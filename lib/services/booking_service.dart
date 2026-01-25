import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:rayride/models/booking_model.dart';

const String offlineBookingBox = 'offline_bookings';

/// ------------------------------------------------------------
/// SAVE BOOKING OFFLINE
/// ------------------------------------------------------------
Future<void> saveOfflineBooking(Booking booking) async {
  final box = Hive.box(offlineBookingBox);
  await box.put(booking.id, booking.toMap());

  debugPrint("📦 Booking saved offline: ${booking.pickup} → ${booking.drop}");
}

/// ------------------------------------------------------------
/// CREATE BOOKING (ONLINE / OFFLINE SAFE ENTRY POINT)
/// ------------------------------------------------------------
Future<void> createBooking({
  required BuildContext context,
  required Booking booking,
}) async {
  final connectivity = await Connectivity().checkConnectivity();

  if (connectivity == ConnectivityResult.none) {
    // 📵 No internet
    await saveOfflineBooking(booking);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("📴 No internet. Booking saved offline."),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  // 🌐 Try sending online
  final success = await sendToServer(booking);

  if (!success) {
    // ⚠️ Network failed mid-request
    await saveOfflineBooking(booking);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("⚠️ Network error. Booking saved offline."),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

/// ------------------------------------------------------------
/// SYNC ALL OFFLINE BOOKINGS
/// ------------------------------------------------------------
Future<void> syncOfflineBookings({BuildContext? context}) async {
  final box = Hive.box(offlineBookingBox);
  final keys = box.keys.toList();

  for (final key in keys) {
    final raw = box.get(key);
    if (raw is! Map) continue; // 🛡 Safety

    final booking = Booking.fromMap(Map<String, dynamic>.from(raw));

    if (booking.isSynced) continue;

    final success = await sendToServer(booking);

    if (success) {
      await box.delete(key);

      debugPrint("✅ Synced booking: ${booking.pickup} → ${booking.drop}");

      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Synced booking: ${booking.pickup} → ${booking.drop}",
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

/// ------------------------------------------------------------
/// SEND BOOKING TO BACKEND
/// ------------------------------------------------------------
Future<bool> sendToServer(Booking booking) async {
  try {
    final response = await http.post(
      Uri.parse(
        'http://localhost:3000/api/rides/book',
      ), // ⚠️ Use LAN IP on real device
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'pickup': booking.pickup,
        'drop': booking.drop,
        'fare': booking.fare,
        'commuterId': booking.commuterId,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      debugPrint(
        "🌐 Booking sent to server: ${booking.pickup} → ${booking.drop}",
      );
      return true;
    } else {
      debugPrint("❌ Server error ${response.statusCode}: ${response.body}");
      return false;
    }
  } catch (e) {
    debugPrint("❌ Error sending booking: $e");
    return false;
  }
}
