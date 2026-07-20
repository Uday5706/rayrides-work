import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // Initialize Firebase and Hive
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("Firebase Initialized Successfully");
  } catch (e) {
    debugPrint("Firebase Init Failed: $e");
  }

  await Hive.initFlutter();
  await Hive.openBox('offline_bookings');

  final userBox = await Hive.openBox('userBox');
  await userBox.put('userId', 'gcGDAZdibT6Z7Et1kcfi'); // Dummy userId for now

  // Listen for network changes and trigger sync
  Connectivity().onConnectivityChanged.listen((result) {
    if (result != ConnectivityResult.none) {
      syncOfflineBookings();
    }
  });

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // themeMode: ThemeMode.system,
      //
      // // 2. Define the Light Theme (Dark Green Primary)
      // theme: ThemeData(
      //   brightness: Brightness.light,
      //   primaryColor: Colors.green[800], // Dark Green
      //   scaffoldBackgroundColor: Colors.grey[50],
      //   appBarTheme: AppBarTheme(
      //     backgroundColor: Colors.green[800],
      //     foregroundColor: Colors.white, // Text color on AppBar
      //   ),
      //   elevatedButtonTheme: ElevatedButtonThemeData(
      //     style: ElevatedButton.styleFrom(
      //       backgroundColor: Colors.green[800],
      //       foregroundColor: Colors.white,
      //     ),
      //   ),
      // ),
      //
      // // 3. Define the Dark Theme (True Black/Dark Grey with Green accents)
      // darkTheme: ThemeData(
      //   brightness: Brightness.dark,
      //   primaryColor: Colors
      //       .green[600], // Slightly lighter green for contrast in dark mode
      //   scaffoldBackgroundColor:
      //       const Color(0xFF121212), // Material standard dark bg
      //   appBarTheme: const AppBarTheme(
      //     backgroundColor: Color(0xFF1E1E1E),
      //     foregroundColor: Colors.white,
      //   ),
      //   elevatedButtonTheme: ElevatedButtonThemeData(
      //     style: ElevatedButton.styleFrom(
      //       backgroundColor: Colors.green[700],
      //       foregroundColor: Colors.white,
      //     ),
      //   ),
      // ),
      home: loginscreen(),
      // home: LiveRideTrackingScreen(rideId: "TEST_RIDE_001"),
    ),
  );
}

/// Function to sync offline bookings to server
Future<void> syncOfflineBookings() async {
  final offlineBox = Hive.box('offline_bookings');
  final userBox = Hive.box('userBox');
  final userId = userBox.get('userId');

  if (offlineBox.isEmpty || userId == null) return;

  final bookingsList = offlineBox.values.map((booking) {
    return {
      'pickup': booking['pickup'],
      'drop': booking['drop'],
      'fare': booking['fare'],
      'timestamp': booking['timestamp'],
    };
  }).toList();

  final response = await http.post(
    Uri.parse('http://10.0.2.2:3000/sync/bookings'), // Change if not emulator
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'userId': userId, 'bookings': bookingsList}),
  );

  if (response.statusCode == 200) {
    await offlineBox.clear();
    print("✅ Bookings synced successfully and cleared locally.");
  } else {
    print("❌ Sync failed: ${response.statusCode} - ${response.body}");
  }
}
