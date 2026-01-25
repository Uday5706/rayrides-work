import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:rayride/nav_bar.dart';

import 'ride_booking_screen.dart';

class roleSelection extends StatelessWidget {
  final Color primaryBlue = const Color(0xFF0288D1);
  final Color lightBackgroundStart = const Color(0xFFE0F7FA);
  final Color lightBackgroundEnd = const Color(0xFFB2EBF2);

  const roleSelection({super.key});

  Future<bool> checkConnection() async {
    var result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [lightBackgroundStart, lightBackgroundEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Choose Your Role',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 40),

                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RideBookingScreen(),
                          // builder: (context) =>
                          //     LiveRideTrackingScreen(rideId: "TEST_RIDE_001"),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.directions_walk,
                      color: Color(0xFF0288D1),
                    ),
                    label: const Text(
                      'I am a Commuter',
                      style: TextStyle(fontSize: 18, color: Color(0xFF0288D1)),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 4,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(
                          color: Color(0xFF0288D1),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Driver Button
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => DriverApp()),
                      );
                    },
                    icon: const Icon(Icons.drive_eta, color: Colors.white),
                    label: const Text(
                      'I am a Driver',
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 4,
                      backgroundColor: primaryBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RayRide"),
        backgroundColor: const Color(0xFF0288D1),
      ),
      body: const Center(
        child: Text("Welcome to RayRide!", style: TextStyle(fontSize: 20)),
      ),
      bottomNavigationBar: mainnavbar(),
    );
  }
}
