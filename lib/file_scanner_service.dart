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
      List<Directory> dirsToScan = [];
      Directory? primaryExternalDir = await getExternalStorageDirectory();
      if (primaryExternalDir != null) {
        String rootPath = primaryExternalDir.path.split('/Android/')[0];
        if (await Directory(rootPath).exists()) {
          print("[Scanner MD] Identified root storage path: $rootPath");
          dirsToScan.add(Directory(rootPath));
        } else {
          print("[Scanner MD] Could not confirm root storage path: $rootPath");
        }
      } else {
        print("[Scanner MD] Could not get primary external storage directory.");
      }

      if (dirsToScan.isEmpty) {
        print("[Scanner MD] No suitable directories found to scan.");
        // Attempt to scan standard Music directory as a fallback
        Directory? musicDir = await getExternalStorageDirectory();
        if (musicDir != null && await musicDir.exists()) {
          print(
              "[Scanner MD] Trying Music directory as fallback: ${musicDir.path}");
          dirsToScan.add(musicDir);
        } else {
          return []; // Really can't find where to scan
        }
      }

      // Use a Set to avoid processing duplicate paths if roots overlap
      Set<String> processedPaths = {};

      for (Directory dir in dirsToScan) {
        if (processedPaths.contains(dir.path))
          continue; // Skip if already processed
        processedPaths.add(dir.path);

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

    // print("${indent}[Scanner MD] Entering directory: ${directory.path}");

    try {
      Stream<FileSystemEntity> entityStream =
          directory.list(followLinks: false);

      await for (FileSystemEntity entity in entityStream) {
        if (entity is File) {
          String filePath = entity.path;
          String filePathLower = filePath.toLowerCase();
          bool isAudio =
              _audioExtensions.any((ext) => filePathLower.endsWith(ext));

          if (isAudio) {
            // print("${indent}[Scanner MD] Potential Audio File: $filePath");
            try {
              // --- Read Metadata ---
              var metadata = await MetadataRetriever.fromFile(File(filePath));
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
                    "${indent}[Scanner MD] *** Added Song: ${newSong.displayTitle} - ${newSong.displayArtist}");
                foundSongs.add(newSong);
              } else {
                print(
                    "${indent}[Scanner MD] --- Skipping song with null title and duplicate path? Path: ${newSong.filePath}");
              }
            } on Exception catch (e) {
              print(
                  "${indent}[Scanner MD] Error reading metadata for $filePath: $e");
              // Optionally add the song even without metadata, using filename as title
              String fallbackTitle = filePath.split('/').last.split('.').first;
              if (!foundSongs.any((s) => s.filePath == filePath)) {
                print(
                    "${indent}[Scanner MD] *** Added Song (fallback): $fallbackTitle");
                foundSongs.add(Song(filePath: filePath, title: fallbackTitle));
              }
            }
          }
        } else if (entity is Directory) {
          String dirName = entity.path.split('/').last;
          if (!dirName.startsWith('.') &&
              !entity.path.contains('/Android/data') &&
              !entity.path.contains('/Android/obb')) {
            // Only recurse if path hasn't been processed to avoid loops/redundancy
            if (!processedPaths.contains(entity.path)) {
              await _scanDirectory(
                  entity, foundSongs, depth + 1, processedPaths);
            }
          } else {
            // print("${indent}[Scanner MD]   - Skipping hidden or Android system directory: ${entity.path}");
          }
        }
      }
    } on FileSystemException catch (e) {
      print(
          "${indent}[Scanner MD] Could not list directory ${directory.path}: $e");
    } catch (e) {
      print(
          "${indent}[Scanner MD] Error scanning directory ${directory.path}: $e");
    }
  }
}
