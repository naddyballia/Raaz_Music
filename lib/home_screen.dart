// lib/home_screen.dart

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:raaz/now_playing_screen.dart';
import 'package:raaz/song_model.dart'; // Use the full Song model
import 'package:raaz/file_scanner_service.dart';
import 'package:raaz/services/database_service.dart'; // Import Database service
import 'package:raaz/services/audio_player_service.dart'; // Corrected Import AudioPlayerService

// Theme constants (could be moved to a theme file later)
const Color themeBackgroundColor = Color(0xFFFFF0F0);
const Color themeAccentColor = Color(0xFFE91E63);

// Enum for Sort Order
enum SortOrder { alphabetical, recent }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FileScannerService _scannerService = FileScannerService();
  final DatabaseService _dbService = DatabaseService();
  final AudioPlayerService _audioService = AudioPlayerService();

  // State for search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // State for sorting
  SortOrder _currentSortOrder = SortOrder.alphabetical;

  List<Song> _songs = [];
  bool _isScanning = false;
  bool _isLoadingFromDb = true;
  Song? _currentlyPlayingSong; // State for the mini-player

  @override
  void initState() {
    super.initState();
    _loadSongsFromDb();
    // Listener for search query changes
    _searchController.addListener(() {
      if (mounted) {
        // Check if widget is still mounted
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose(); // Dispose controller
    super.dispose();
  }

  Future<void> _loadSongsFromDb() async {
    if (!mounted) return;
    setState(() {
      _isLoadingFromDb = true;
    });
    print("[Home Screen] Loading songs from database...");
    try {
      final dbSongs = await _dbService.loadSongs();
      if (!mounted) return;
      setState(() {
        _songs = dbSongs;
        _isLoadingFromDb = false;
        print("[Home Screen] Loaded ${_songs.length} songs from DB.");
        // Optionally set initial mini-player song
        if (_songs.isNotEmpty) {
          _currentlyPlayingSong ??= _songs[0]; // Set only if null
        }
      });
    } catch (e) {
      print("[Home Screen] Error loading songs from DB: $e");
      if (!mounted) return;
      setState(() {
        _isLoadingFromDb = false;
      });
    }
  }

  Future<void> _requestPermissionAndScan() async {
    if (_isScanning) return;
    PermissionStatus status = await Permission.audio.request();
    if (status.isGranted) {
      _scanMusicAndSave();
    } else if (status.isPermanentlyDenied) {
      _showSnackBar(context, 'Permission permanently denied. Open settings.');
      await openAppSettings();
    } else {
      _showSnackBar(context, 'Permission required to scan for music.');
    }
  }

  Future<void> _scanMusicAndSave() async {
    if (_isScanning) return;
    PermissionStatus status = await Permission.audio.status;
    if (!status.isGranted) {
      _showSnackBar(context, 'Permission denied. Cannot scan.');
      return;
    }
    setState(() {
      _isScanning = true;
    });
    _showSnackBar(context, 'Scanning for music...');
    try {
      final List<Song> scannedSongs = await _scannerService.scanForAudioFiles();
      await _dbService.saveSongs(scannedSongs);
      if (!mounted) return;
      setState(() {
        _songs = scannedSongs;
        _isScanning = false;
        // Update mini player if nothing was playing or list was empty
        if (_songs.isNotEmpty && _currentlyPlayingSong == null) {
          _currentlyPlayingSong = _songs[0];
        } else if (_songs.isEmpty) {
          _currentlyPlayingSong = null; // Clear mini player if no songs
        }
      });
      _showSnackBar(context, 'Scan complete! Found ${_songs.length} files.');
    } catch (e) {
      print("[Home Screen] Error during scan/save: $e");
      if (!mounted) return;
      setState(() {
        _isScanning = false;
      });
      _showSnackBar(context, 'Error during scan.');
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.removeCurrentSnackBar(); // Remove previous snackbar
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: themeAccentColor.withOpacity(0.9),
        behavior: SnackBarBehavior.floating, // Make it float
        margin: const EdgeInsets.all(10), // Add margin
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)), // Rounded corners
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Allow body to draw behind bottom bar
      appBar: AppBar(
        title: Expanded(child: _buildSearchField()), // Expanded search field
        toolbarHeight: 80,
        // No actions needed per target UI
      ),
      body: Column(
        children: [
          _buildQuickAccessIcons(context), // Icons row
          const SizedBox(height: 10), // Reduced spacing
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _currentSortOrder == SortOrder.recent
                    ? 'Recently Played'
                    : 'Play The Songs..',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<PlaybackState>(
              stream: _audioService.playbackStateStream,
              builder: (context, snapshot) {
                final currentPlayingSongId = snapshot.data?.currentSong?.id;

                if (_isLoadingFromDb) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: themeAccentColor));
                } else if (_songs.isEmpty) {
                  return _buildEmptyListMessage();
                } else {
                  // --- Apply Sorting ---
                  List<Song> sortedSongs =
                      List.from(_songs); // Create a modifiable copy
                  if (_currentSortOrder == SortOrder.recent) {
                    sortedSongs.sort((a, b) {
                      // Sort descending: songs without lastPlayed go to the end
                      if (a.lastPlayed == null && b.lastPlayed == null)
                        return 0;
                      if (a.lastPlayed == null) return 1;
                      if (b.lastPlayed == null) return -1;
                      return b.lastPlayed!.compareTo(a.lastPlayed!);
                    });
                  } else {
                    // Default to alphabetical
                    sortedSongs.sort((a, b) => a.displayTitle
                        .toLowerCase()
                        .compareTo(b.displayTitle.toLowerCase()));
                  }
                  // --- End Sorting ---

                  // Filter sorted songs based on search query
                  final filteredSongs = sortedSongs.where((song) {
                    final query = _searchQuery.toLowerCase();
                    final title = song.displayTitle.toLowerCase();
                    final artist = song.displayArtist.toLowerCase();
                    // Add album later if needed: final album = song.album?.toLowerCase() ?? '';
                    return title.contains(query) || artist.contains(query);
                  }).toList();

                  // Pass the sorted and filtered list to the list builder
                  return _buildSongMetadataList(
                      currentPlayingSongId, filteredSongs);
                }
              },
            ),
          ),
        ],
      ),
      // Mini Player at the bottom
      bottomNavigationBar: _currentlyPlayingSong != null
          ? Padding(
              // Wrap the mini-player in padding
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom),
              child: _buildMiniPlayer(context),
            )
          : null, // Show nothing if no song selected
    );
  }

  // --- UI Building Methods ---

  Widget _buildSearchField() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(
          vertical: 15, horizontal: 16), // Added horizontal margin
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search songs, artists, albums...',
          prefixIcon: Icon(Icons.search, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 15),
        ),
        style: TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildQuickAccessIcons(BuildContext context) {
    // Wrap the Row in a Container with a specific height
    return Container(
      height: 70, // Give the row a fixed height
      padding: const EdgeInsets.symmetric(
          vertical: 10.0), // Adjust padding as needed
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center items vertically
        children: [
          // New Order: Home, Recent, Favorite, Download
          _buildIconColumn(Icons.home_outlined, 'Home', () {
            // Set sort order to alphabetical
            setState(() {
              _currentSortOrder = SortOrder.alphabetical;
            });
            _showSnackBar(context, 'Sorted alphabetically');
          }),
          _buildIconColumn(Icons.history, 'Recent', () {
            // Set sort order to recent
            setState(() {
              _currentSortOrder = SortOrder.recent;
            });
            _showSnackBar(context, 'Sorted by recently played');
          }),
          _buildIconColumn(Icons.favorite_border, 'Favorite', () {
            _showSnackBar(context, 'Favorite feature coming soon!');
          }),
          _buildIconColumn(Icons.download_outlined, 'Download', () {
            _showSnackBar(context, 'Download feature coming soon!');
          }),
          // Removed Playback Icon
        ],
      ),
    );
  }

  Widget _buildIconColumn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // Make sure the whole area is tappable
      child: Padding(
        // Add padding around each icon column for better spacing
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black54, size: 28),
            const SizedBox(height: 5),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildSongMetadataList(
      int? currentPlayingSongId, List<Song> songsToDisplay) {
    // Handle empty filtered list specifically
    if (songsToDisplay.isEmpty && _searchQuery.isNotEmpty) {
      // Show only if searching resulted in empty
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            'No songs found matching "$_searchQuery"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ),
      );
    } else if (songsToDisplay.isEmpty && _searchQuery.isEmpty) {
      // If not searching and list is empty, show the generic empty message
      return _buildEmptyListMessage();
    }

    // If we have songs to display (filtered or not)
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: songsToDisplay.length, // Use filtered list length
      itemBuilder: (context, index) {
        final song = songsToDisplay[index]; // Use song from filtered list
        bool isSelected = currentPlayingSongId == song.id;

        return ListTile(
          leading: Icon(
            Icons.music_note,
            color: isSelected ? themeAccentColor : Colors.grey[600],
            size: 26,
          ),
          title: Text(
            song.displayTitle,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 15,
              color: isSelected ? themeAccentColor : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.displayArtist,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black54),
            onPressed: () {
              _showSnackBar(context, 'Options for ${song.displayTitle}');
              // TODO: Show options menu (add to playlist, etc.)
            },
          ),
          onTap: () {
            // Pass the ORIGINAL unfiltered list to setPlaylist
            _audioService.setPlaylist(_songs, song);
          },
          selected: isSelected,
          selectedTileColor: themeAccentColor.withOpacity(0.05),
        );
      },
    );
  }

  Widget _buildEmptyListMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize:
              MainAxisSize.min, // Important for Column in Center/Expanded
          children: [
            Icon(Icons.music_off_outlined, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _isScanning ? 'Scanning...' : 'No music files found.',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (!_isScanning && !_isLoadingFromDb && _songs.isEmpty)
              Text(
                'Tap the refresh icon to scan your device for music.',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniPlayer(BuildContext context) {
    // Use StreamBuilder to listen to playback state
    return StreamBuilder<PlaybackState>(
      stream: _audioService.playbackStateStream, // Listen to the service stream
      builder: (context, snapshot) {
        final playbackState = snapshot.data; // Get the latest state
        final song =
            playbackState?.currentSong; // Get the current song from the state
        final isPlaying = playbackState?.playing ?? false;
        final position = playbackState?.position ?? Duration.zero;
        final duration = playbackState?.duration ?? Duration.zero;

        // Show nothing if no song is loaded/playing
        if (song == null) {
          return const SizedBox.shrink(); // Return an empty widget
        }

        // Calculate progress for the LinearProgressIndicator
        double progress = (duration.inMilliseconds > 0)
            ? (position.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0;

        // Build the actual mini-player UI based on the state
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => NowPlayingScreen(song: song)),
            );
          },
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color:
                  Colors.white.withOpacity(0.98), // Slightly less transparent
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2)),
              ],
              border:
                  Border(top: BorderSide(color: Colors.grey[300]!, width: 0.5)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Progress Bar - Updated value
                Padding(
                  padding: EdgeInsets.zero,
                  child: LinearProgressIndicator(
                    value: progress, // Use calculated progress
                    backgroundColor: Colors.grey[300],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(themeAccentColor),
                    minHeight: 2.5,
                  ),
                ),
                // Song Info and Play Button Row
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundColor: Color(0xFFFCE4EC),
                          child: Icon(Icons.music_note,
                              color: themeAccentColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.displayTitle, // Use song from state
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.displayArtist, // Use song from state
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Play/Pause Button - Updated icon and action
                        IconButton(
                          icon: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 32,
                          ),
                          padding: EdgeInsets.zero,
                          color: themeAccentColor,
                          onPressed: () {
                            // Call the service to toggle playback
                            if (isPlaying) {
                              _audioService.pause();
                            } else {
                              _audioService.resume();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- REMOVE RECENT SONGS DIALOG METHOD ---
  // Future<void> _showRecentSongsDialog() async {
  // ... (entire method content)
  // }
  // --- END OF REMOVAL ---
} // End of _HomeScreenState class
