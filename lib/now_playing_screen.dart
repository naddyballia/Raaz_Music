// lib/now_playing_screen.dart

import 'dart:ui'; // For ImageFilter backdrop blur
import 'package:flutter/material.dart';
import 'package:raaz/song_model.dart'; // To use the Song class
// Import home_screen but hide potentially conflicting widget names
import 'package:raaz/home_screen.dart' hide Text, TextStyle, SizedBox;
import 'package:raaz/services/audio_player_service.dart'; // Import the service

class NowPlayingScreen extends StatefulWidget {
  // We need to know which song to display on this screen
  final Song song;

  const NowPlayingScreen({super.key, required this.song});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  // Get the audio service instance
  final AudioPlayerService _audioService = AudioPlayerService();

  // Remove placeholder state variables that will come from the stream
  // bool _isPlaying = true;
  // bool _isFavorite = false;
  // double _currentSliderValue = 90;
  // double _maxSliderValue = 240;

  // Keep local state for buttons not yet fully implemented
  bool _isFavoriteLocal = false; // TODO: Replace with actual state later
  bool _isShuffleLocal = false; // TODO: Replace with actual state later
  bool _isRepeatLocal = false; // TODO: Replace with actual state later

  // Helper to format duration (e.g., 125 seconds -> "2:05")
  String _formatDuration(double seconds) {
    Duration duration = Duration(seconds: seconds.toInt());
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    // Optional: Add hours if needed ${twoDigits(duration.inHours)}:
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
  // --- End of State variables ---

  @override
  Widget build(BuildContext context) {
    // Use the same theme colors defined in home_screen.dart
    const Color themeColor = themeBackgroundColor;
    const Color accentColor = themeAccentColor;

    return Scaffold(
      backgroundColor: themeColor,
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        // Button to go back to the home screen
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
          onPressed: () => Navigator.pop(context), // Closes this screen
        ),
        title: const Text(
          'Now Playing',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        // actions: [ // Optional: Add action buttons to AppBar if needed
        //   IconButton(icon: Icon(Icons.more_vert), onPressed: () {}),
        // ],
      ),
      // Wrap body content with StreamBuilder
      body: StreamBuilder<PlaybackState>(
        stream: _audioService.playbackStateStream,
        builder: (context, snapshot) {
          final playbackState = snapshot.data ??
              PlaybackState(); // Use default state if no data yet
          final currentSong = playbackState.currentSong ??
              widget.song; // Fallback to initial song
          final isPlaying = playbackState.playing;
          final position = playbackState.position;
          final duration = playbackState.duration ?? Duration.zero;
          final bufferedPosition = playbackState.bufferedPosition;

          // Calculate values for UI
          double sliderValue = position.inMilliseconds.toDouble();
          double maxSliderValue = duration.inMilliseconds.toDouble();
          if (maxSliderValue <= 0)
            maxSliderValue = 1.0; // Avoid division by zero

          // Return the main UI structure using stream data
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const Spacer(flex: 1),
                _buildVinylRecordWithGrooves(),
                const Spacer(flex: 1),
                _buildSongInfo(currentSong), // Pass currentSong from stream
                const SizedBox(height: 20),
                _buildProgressBar(sliderValue, maxSliderValue, position,
                    duration), // Pass stream values
                const Spacer(flex: 1),
                _buildPlaybackControls(isPlaying), // Pass stream value
                const Spacer(flex: 1),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Helper methods to build parts of the UI ---

  Widget _buildVinylRecordWithGrooves() {
    // Simple representation, could be enhanced with gradients or images later
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87, // Vinyl color
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white, // Label color
          ),
          child: const Center(
            child: Icon(
              Icons.music_note,
              color: themeAccentColor, // Use accent color for note
              size: 40,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo(Song song) {
    return Column(
      children: [
        Text(
          song.displayTitle, // Use song from stream
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          song.displayArtist, // Use song from stream
          style: const TextStyle(fontSize: 15, color: Colors.black54),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildProgressBar(double sliderValue, double maxSliderValue,
      Duration position, Duration duration) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: themeAccentColor, // Active part color
            inactiveTrackColor: themeAccentColor.withOpacity(
              0.3,
            ), // Inactive part color
            trackHeight: 3.0,
            thumbColor: themeAccentColor, // Thumb color
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
            overlayColor: themeAccentColor.withAlpha(0x29),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
          ),
          child: Slider(
            value:
                sliderValue.clamp(0.0, maxSliderValue), // Use value from stream
            min: 0,
            max: maxSliderValue,
            onChanged: (value) {
              // Seek when slider interaction ends
              _audioService.seek(Duration(milliseconds: value.round()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(
                    position.inSeconds.toDouble()), // Use position from stream
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                _formatDuration(
                    duration.inSeconds.toDouble()), // Use duration from stream
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 38),
          color: Colors.black54,
          onPressed: _audioService.skipToPrevious,
        ),
        const SizedBox(width: 25),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: themeAccentColor, // Use accent color for background
            boxShadow: [
              BoxShadow(
                color: themeAccentColor.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 50),
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            onPressed: () {
              // Toggle based on stream state
              if (isPlaying) {
                _audioService.pause();
              } else {
                _audioService.resume();
              }
            },
          ),
        ),
        const SizedBox(width: 25),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 38),
          color: Colors.black54,
          onPressed: _audioService.skipToNext,
        ),
      ],
    );
  }
}
