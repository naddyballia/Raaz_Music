import 'package:just_audio/just_audio.dart';
import 'package:raaz/song_model.dart';
import 'package:rxdart/rxdart.dart'; // For combining streams
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'package:raaz/services/database_service.dart'; // Import DatabaseService

// Data class to hold playback state information
class PlaybackState {
  final ProcessingState processingState;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;
  final Song? currentSong; // Track the currently loaded song

  PlaybackState({
    this.processingState = ProcessingState.idle,
    this.playing = false,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration,
    this.currentSong,
  });
}

class AudioPlayerService {
  // Singleton pattern
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final DatabaseService _dbService =
      DatabaseService(); // Get DB service instance
  // Store the current playlist
  List<Song> _currentPlaylist = [];
  int _currentIndex = -1;

  // Keep track of the actual Song object being played
  // This needs updating when the sequence changes
  Song? _currentSong;

  // StreamController to broadcast playback state changes
  // Using BehaviorSubject to provide the latest value to new listeners
  final _playbackStateSubject =
      BehaviorSubject<PlaybackState>.seeded(PlaybackState());

  // Public stream for widgets to listen to
  Stream<PlaybackState> get playbackStateStream => _playbackStateSubject.stream;

  void initialize() {
    print("[AudioService] Initializing...");

    // Listen to the player's sequence state changes to update our _currentSong
    _audioPlayer.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _currentPlaylist.length) {
        _currentIndex = index;
        _currentSong = _currentPlaylist[index];
        // Don't push full state here, let combineLatest handle it
        // to avoid race conditions
      } else {
        _currentIndex = -1;
        _currentSong = null;
      }
      // Force combineLatest to re-emit with the updated song
      _playbackStateSubject
          .add(_playbackStateSubject.value.copyWith(currentSong: _currentSong));
    });

    // Combine streams
    Rx.combineLatest6<ProcessingState, bool, Duration, Duration, Duration?,
            int?, PlaybackState>(
        _audioPlayer.processingStateStream,
        _audioPlayer.playingStream,
        _audioPlayer.positionStream,
        _audioPlayer.bufferedPositionStream,
        _audioPlayer.durationStream,
        _audioPlayer.currentIndexStream, // Use index stream directly
        (processingState, playing, position, bufferedPosition, duration,
            index) {
      // Use the locally updated _currentSong which is synced with currentIndexStream
      return PlaybackState(
          processingState: processingState,
          playing: playing,
          position: position,
          bufferedPosition: bufferedPosition,
          duration: duration,
          currentSong: _currentSong);
    }).listen((state) {
      _playbackStateSubject.add(state); // Broadcast the combined state
    }, onError: (error) {
      print("[AudioService] Error in playback stream: $error");
      _playbackStateSubject.addError(error);
    });

    _audioPlayer.playbackEventStream.listen((event) {
      // Can listen to specific events here if needed
    }, onError: (Object e, StackTrace stackTrace) {
      print('[AudioService] A playback error occurred: $e');
    });

    print("[AudioService] Initialization complete.");
  }

  // --- Playlist Management ---
  Future<void> setPlaylist(List<Song> playlist, Song startSong) async {
    _currentPlaylist = playlist;
    _currentIndex =
        _currentPlaylist.indexWhere((s) => s.filePath == startSong.filePath);
    if (_currentIndex == -1) _currentIndex = 0; // Fallback to first song

    _currentSong = _currentIndex >= 0 ? _currentPlaylist[_currentIndex] : null;

    // Immediately update state with the new potential song
    _playbackStateSubject
        .add(_playbackStateSubject.value.copyWith(currentSong: _currentSong));

    print(
        "[AudioService] Setting playlist with ${_currentPlaylist.length} songs, starting with: ${startSong.displayTitle}");

    final audioSources = _currentPlaylist.map((song) {
      return AudioSource.uri(Uri.file(song.filePath),
          tag: song.id); // Use song ID or path as tag
    }).toList();

    try {
      await _audioPlayer.setAudioSource(
        ConcatenatingAudioSource(children: audioSources),
        initialIndex: _currentIndex,
        initialPosition: Duration.zero,
      );
      // Update last played timestamp for the starting song
      if (_currentSong != null) {
        await _dbService.updateLastPlayed(_currentSong!); // Call DB service
      }
      await _audioPlayer.play();
    } catch (e) {
      print("[AudioService] Error setting playlist: $e");
      _currentPlaylist = [];
      _currentIndex = -1;
      _currentSong = null;
      _playbackStateSubject.add(PlaybackState()); // Reset state on error
    }
  }

  Future<void> skipToNext() async {
    await _audioPlayer.seekToNext();
    if (_audioPlayer.playing == false) {
      // Keep playing if skipping while paused
      // _audioPlayer.play(); // Optional: decide if skip should auto-play
    }
  }

  Future<void> skipToPrevious() async {
    await _audioPlayer.seekToPrevious();
    if (_audioPlayer.playing == false) {
      // _audioPlayer.play(); // Optional: decide if skip should auto-play
    }
  }

  // --- Basic Controls (pause, resume, seek, stop) ---
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.play();
  }

  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentPlaylist = []; // Clear playlist on stop
    _currentIndex = -1;
    _currentSong = null;
    _playbackStateSubject.add(PlaybackState());
  }

  // Dispose the player when the service is no longer needed (e.g., app close)
  void dispose() {
    print("[AudioService] Disposing player.");
    _audioPlayer.dispose();
    _playbackStateSubject.close(); // Close the stream controller
  }

  // Getter to check if currently playing (based on player state)
  bool get isPlaying => _audioPlayer.playing;

  // Getter for the currently loaded song model
  Song? get currentSong => _currentSong;
}

// Helper extension for PlaybackState to easily update parts of it
extension PlaybackStateCopyWith on PlaybackState {
  PlaybackState copyWith({
    ProcessingState? processingState,
    bool? playing,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    Song? currentSong,
  }) {
    return PlaybackState(
      processingState: processingState ?? this.processingState,
      playing: playing ?? this.playing,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      currentSong: currentSong ?? this.currentSong,
    );
  }
}
