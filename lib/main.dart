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
