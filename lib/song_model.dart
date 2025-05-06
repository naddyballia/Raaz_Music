// lib/song_model.dart

import 'package:isar/isar.dart';

part 'song_model.g.dart';

@collection // Annotate the class for Isar
class Song {
  Id id = Isar.autoIncrement; // Isar requires an Id field

  @Index(
      unique: true,
      replace: true) // Index filePath for quick lookups and updates
  final String filePath;

  String? title;
  String? artist;
  String? album;
  String? albumArtist; // Sometimes different from track artist
  int? durationMs; // Store duration in milliseconds for easier handling
  String? genre;

  @Index() // Index for sorting by recently played
  DateTime? lastPlayed; // Track when the song was last played

  @Index() // Index for filtering favorites
  bool isFavorite = false; // Track favorite status

  // We might add: artwork (as bytes or path), track number, year etc. later

  // Default constructor (needed by Isar)
  Song({
    required this.filePath,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.durationMs,
    this.genre,
    this.lastPlayed, // Add to constructor (optional, can be updated later)
    this.isFavorite = false, // Default to false
  });

  // You could add helper methods here later, e.g., formattedDuration
  String get displayTitle => title ?? filePath.split('/').last.split('.').first;
  String get displayArtist => artist ?? "Unknown Artist";
}
