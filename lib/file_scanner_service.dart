// lib/services/file_scanner_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; // For kIsWeb check
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart'; // Import metadata retriever
import 'package:raaz/song_model.dart'; // Import the Song model

class FileScannerService {
  final List<String> _audioExtensions = const [
    '.mp3',
    '.m4a',
    '.wav',
    '.ogg',
    '.aac',
    '.flac',
    '.opus',
    '.amr'
  ];
  final List<String> _excludedPaths = const [
    'call',
    'callrecorder',
    // Add back others if needed after testing
    'notifications',
    'ringtones',
    'alarms',
  ];

  // --- Changed return type to List<Song> ---
  Future<List<Song>> scanForAudioFiles() async {
    if (kIsWeb) {
      // Metadata retrieval doesn't work on web
      print("[Scanner MD] Skipping scan on web platform.");
      return [];
    }
    print("[Scanner MD] Starting audio file scan with metadata...");
    List<Song> foundSongs = []; // List to hold Song objects
    PermissionStatus status = await Permission.audio.status;

    if (!status.isGranted) {
      print("[Scanner MD] Storage permission not granted. Cannot scan.");
      return [];
    }

    try {
      // Use a Set to avoid adding duplicate directories
      Set<Directory> dirsToScanSet = {};
      String? primaryRootPath; // Store potential primary root path

      // 1. Get ALL external storage directories (includes SD cards etc.)
      List<Directory>? externalDirs =
          await getExternalStorageDirectories(); // Use plural

      if (externalDirs != null && externalDirs.isNotEmpty) {
        print(
            "[Scanner MD] Found external directories: ${externalDirs.map((d) => d.path).toList()}");
        for (Directory dir in externalDirs) {
          // Try to derive the root for each directory found
          List<String> pathSegments = dir.path.split('/');
          int androidIndex = pathSegments.indexOf('Android');
          if (androidIndex > 0) {
            String currentRootPath =
                pathSegments.sublist(0, androidIndex).join('/');
            Directory rootDir = Directory(currentRootPath);
            if (await rootDir.exists()) {
              print(
                  "[Scanner MD] Identified potential root storage path: $currentRootPath");
              dirsToScanSet.add(rootDir);
              if (primaryRootPath == null)
                primaryRootPath =
                    currentRootPath; // Store the first valid root found
            } else {
              print(
                  "[Scanner MD] Derived root path does not exist: $currentRootPath");
            }
          } else {
            print(
                "[Scanner MD] Could not derive root path from external dir: ${dir.path}");
            // Add the directory itself if root derivation fails for it
            if (await dir.exists()) {
              print("[Scanner MD] Adding external dir directly: ${dir.path}");
              dirsToScanSet.add(dir);
            }
          }
        }
      } else {
        print("[Scanner MD] Could not get external storage directories.");
      }

      // 2. Explicitly add common Music and Download directories relative to the *primary* derived root or a common default
      //    This avoids adding /storage/XXXX-XXXX/Music if it doesn't exist, but still scans the root /storage/XXXX-XXXX
      String baseStoragePath = primaryRootPath ??
          "/storage/emulated/0"; // Use primary derived root or common default
      List<String> commonDirs = ['Music', 'Download'];

      for (String commonDirName in commonDirs) {
        Directory dir = Directory('$baseStoragePath/$commonDirName');
        if (await dir.exists()) {
          print(
              "[Scanner MD] Adding common directory based on primary root: ${dir.path}");
          dirsToScanSet.add(dir); // Add to the set
        } else {
          print(
              "[Scanner MD] Common directory not found based on primary root: ${dir.path}");
        }
      }

      // 3. Remove redundant check for primaryExternalDir as it's covered by getExternalStorageDirectories

      if (dirsToScanSet.isEmpty) {
        print(
            "[Scanner MD] No suitable directories found to scan after all checks.");
        return []; // Really can't find where to scan
      }

      print(
          "[Scanner MD] Final directories to scan: ${dirsToScanSet.map((d) => d.path).toList()}");

      // Use a Set to avoid processing duplicate file paths during recursion
      Set<String> processedPaths = {};

      for (Directory dir in dirsToScanSet) {
        // No need to check processedPaths here as the Set handles duplicates

        if (dir.path.contains('/Android/data/com.example.raaz')) {
          print(
              "[Scanner MD] Skipping app-specific data directory: ${dir.path}");
          continue;
        }
        print("[Scanner MD] Scanning root directory: ${dir.path}");
        await _scanDirectory(
            dir, foundSongs, 0, processedPaths); // Pass set down
      }
    } catch (e) {
      print("[Scanner MD] Error during file scan setup: $e");
    }

    print(
        "[Scanner MD] Scan complete. Found ${foundSongs.length} songs with metadata (attempted).");
    return foundSongs;
  }

  // --- Modified to populate List<Song> and read metadata ---
  Future<void> _scanDirectory(Directory directory, List<Song> foundSongs,
      int depth, Set<String> processedPaths) async {
    if (processedPaths.contains(directory.path) && depth > 0)
      return; // Avoid re-entering processed dirs
    processedPaths.add(directory.path);

    String indent = "  " * depth;
    try {
      String lowerCasePath = directory.path.toLowerCase();
      for (String excluded in _excludedPaths) {
        if (lowerCasePath.contains(excluded)) {
          print(
              "${indent}[Scanner MD] >>> Skipping excluded directory branch (contains '$excluded'): ${directory.path}");
          return;
        }
      }
    } catch (e) {
      print(
          "${indent}[Scanner MD] Error checking path exclusion for ${directory.path}: $e");
    }

    print(
        "${indent}[Scanner MD] Entering directory: ${directory.path}"); // Keep this log

    try {
      print(
          "${indent}[Scanner MD] Attempting to list entities in: ${directory.path}");
      Stream<FileSystemEntity> entityStream;
      try {
        entityStream = directory.list(followLinks: false);
      } catch (e) {
        print(
            "${indent}[Scanner MD] ### EXCEPTION when calling directory.list() for ${directory.path}: $e");
        // Exiting this directory scan if listing itself fails
        print(
            "${indent}[Scanner MD] Exiting directory due to list() exception: ${directory.path}");
        return;
      }

      bool entityFound = false; // Flag to check if stream yields anything

      await for (FileSystemEntity entity in entityStream) {
        try {
          entityFound = true; // Mark that we received at least one entity
          // print("${indent}[Scanner MD] Processing entity: ${entity.path}"); // Optional: Log every entity found
          if (entity is File) {
            String filePath = entity.path;
            String filePathLower = filePath.toLowerCase();
            bool isAudio =
                _audioExtensions.any((ext) => filePathLower.endsWith(ext));

            if (isAudio) {
              print(
                  "${indent}[Scanner MD] Potential Audio File Found: $filePath");
              try {
                // --- Read Metadata ---
                print(
                    "${indent}[Scanner MD]   Attempting metadata retrieval for: $filePath");
                var metadata = await MetadataRetriever.fromFile(File(filePath));
                print(
                    "${indent}[Scanner MD]   Metadata retrieved successfully for: $filePath");
                // --- End Read Metadata ---

                // Create Song object
                Song newSong = Song(
                  filePath: filePath,
                  title: metadata.trackName,
                  artist: metadata.trackArtistNames?.isNotEmpty ?? false
                      ? metadata.trackArtistNames!.join(', ')
                      : null, // Join if multiple artists
                  album: metadata.albumName,
                  albumArtist: metadata.albumArtistName,
                  genre: metadata.genre,
                  durationMs: metadata.trackDuration, // Already in milliseconds
                  // artwork: metadata.albumArt, // This is Uint8List (Bytes) - handle later if needed
                );

                // Basic check: add if title exists or if path is unique (fallback)
                if (newSong.title != null ||
                    !foundSongs.any((s) => s.filePath == newSong.filePath)) {
                  print(
                      "${indent}[Scanner MD]   *** Added Song: ${newSong.displayTitle} - ${newSong.displayArtist}");
                  foundSongs.add(newSong);
                } else {
                  print(
                      "${indent}[Scanner MD]   --- Skipping song with null title and duplicate path? Path: ${newSong.filePath}");
                }
              } on Exception catch (e) {
                print(
                    "${indent}[Scanner MD]   ### Error reading metadata for $filePath: $e");
                // ALWAYS add the song on metadata error, using filename as fallback title
                String fallbackTitle =
                    filePath.split('/').last.split('.').first;
                if (!foundSongs.any((s) => s.filePath == filePath)) {
                  // Check uniqueness before adding fallback
                  print(
                      "${indent}[Scanner MD] *** Added Song (fallback after metadata error): $fallbackTitle");
                  foundSongs
                      .add(Song(filePath: filePath, title: fallbackTitle));
                } else {
                  print(
                      "${indent}[Scanner MD] --- Skipping duplicate fallback song: $filePath");
                }
              }
            }
          } else if (entity is Directory) {
            String dirName = entity.path.split('/').last;
            if (!dirName.startsWith('.') &&
                !entity.path.contains(
                    '/Android/data') && // Already checked at higher level, but good for safety
                !entity.path.contains('/Android/obb')) {
              // Already checked at higher level
              // Only recurse if path hasn't been processed to avoid loops/redundancy
              if (!processedPaths.contains(entity.path)) {
                await _scanDirectory(
                    entity, foundSongs, depth + 1, processedPaths);
              } else {
                // print("${indent}[Scanner MD]   - Skipping already processed directory (recursive call): ${entity.path}");
              }
            } else {
              // print("${indent}[Scanner MD]   - Skipping hidden or Android system directory (recursive call): ${entity.path}");
            }
          }
        } catch (e) {
          print(
              "${indent}[Scanner MD] ### EXCEPTION while processing entity ${entity.path} in ${directory.path}: $e");
          // Continue to next entity if possible
        }
      } // end await for

      if (!entityFound) {
        print(
            "${indent}[Scanner MD] ### No entities found OR stream ended prematurely for directory: ${directory.path}");
      }
    } on FileSystemException catch (e) {
      // This catches errors if the stream itself throws a FileSystemException before or during iteration (e.g. permission denied on the directory itself)
      print(
          "${indent}[Scanner MD] ### FileSystemException for directory ${directory.path}: ${e.message} (OS Error: ${e.osError?.message}, Code: ${e.osError?.errorCode})");
    } catch (e) {
      // Catch any other unexpected errors during the scan of this directory
      print(
          "${indent}[Scanner MD] ### UNEXPECTED error for directory ${directory.path}: $e");
    }
    print(
        "${indent}[Scanner MD] Exiting directory: ${directory.path}"); // Log exit
  }
}
