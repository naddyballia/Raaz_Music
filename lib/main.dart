// lib/main.dart

import 'package:flutter/material.dart';
import 'package:raaz/home_screen.dart';
import 'package:raaz/services/database_service.dart'; // Import DatabaseService
import 'package:raaz/services/audio_player_service.dart'; // Import AudioPlayerService
// Permission handler is no longer directly needed here, moved to HomeScreen logic
// import 'package:permission_handler/permission_handler.dart';

// Removed Isar/path_provider imports and global variable
// import 'package:isar/isar.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:raaz/song_model.dart';
// late Isar isarDatabase;

Future<void> main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize DatabaseService (which handles Isar internally)
  await DatabaseService().initialize();

  // Initialize AudioPlayerService
  AudioPlayerService()
      .initialize(); // No need to await if init is synchronous internally

  // Removed manual Isar initialization
  // final dir = await getApplicationDocumentsDirectory();
  // isarDatabase = await Isar.open(
  //   [SongSchema], // Pass the generated Schema
  //   directory: dir.path,
  //   name: 'raazMusicDb', // Name for the database file
  // );

  // Run the app
  runApp(const MyApp());
}

// MyApp remains largely the same, just doesn't need to be StatefulWidget anymore
// as permission/initial load logic moves to HomeScreen
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Raaz Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          primarySwatch: Colors.pink,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          // Consistent background color (can be defined globally)
          scaffoldBackgroundColor: const Color(0xFFFFF0F0),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFFF0F0),
            elevation: 0,
            iconTheme:
                IconThemeData(color: Colors.black54), // For back buttons etc.
          )),
      home: const HomeScreen(), // Start with HomeScreen
    );
  }
}
