// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'live_ride_tracking_screen.dart';
// import 'package:rayride/booking_service.dart'; // Add this to access syncOfflineBookings()

// class SharedRideDashboardScreen extends StatefulWidget {
//   final String dropLocation;
//   final String fare;

//   const SharedRideDashboardScreen({
//     super.key,
//     required this.dropLocation,
//     required this.fare,
//   });

//   @override
//   _SharedRideDashboardScreenState createState() =>
//       _SharedRideDashboardScreenState();
// }

// class _SharedRideDashboardScreenState
//     extends State<SharedRideDashboardScreen> {
//   int totalSeats = 4;
//   int currentOccupancy = 1;
//   List<String> pickups = ["Sector 10", "Mall Gate", "School"];
//   List<String> drops = ["Metro", "Market", "Park"];
//   int index = 0;
//   late Timer _timer;

//   @override
//   void initState() {
//     super.initState();
//     _timer = Timer.periodic(Duration(seconds: 5), (timer) {
//       setState(() {
//         currentOccupancy = (currentOccupancy + 1) % (totalSeats + 1);
//         index = (index + 1) % pickups.length;
//       });
//     });
//   }

//   @override
//   void dispose() {
//     _timer.cancel();
//     super.dispose();
//   }

//   Widget buildInfoTile(
//       String label, String value, IconData icon, Color color) {
//     return Card(
//       child: ListTile(
//         leading: Icon(icon, color: color),
//         title: Text(label),
//         subtitle: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     double progress = currentOccupancy / totalSeats;

//     return Scaffold(
//       backgroundColor: Colors.grey[100],
//       appBar: AppBar(
//         title: Text('Ride Dashboard'),
//       ),
//       body: SafeArea(
//         child: ListView(
//           padding: EdgeInsets.all(16),
//           children: [
//             Text("Live Ride Status",
//                 style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
//             SizedBox(height: 20),
//             Card(
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12)),
//               elevation: 5,
//               child: Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Column(
//                   children: [
//                     Text("Seats Occupied", style: TextStyle(fontSize: 18)),
//                     SizedBox(height: 10),
//                     LinearProgressIndicator(
//                       value: progress,
//                       minHeight: 10,
//                       backgroundColor: Colors.grey[300],
//                       color: Colors.deepPurple,
//                     ),
//                     SizedBox(height: 10),
//                     Text("$currentOccupancy / $totalSeats Occupied"),
//                   ],
//                 ),
//               ),
//             ),
//             SizedBox(height: 20),
//             buildInfoTile(
//                 "Next Pickup", pickups[index], Icons.location_on, Colors.green),
//             buildInfoTile("Next Drop-off", drops[index], Icons.flag, Colors.red),
//             buildInfoTile("Drop Location", widget.dropLocation,
//                 Icons.location_pin, Colors.blue),
//             buildInfoTile("Estimated Fare", widget.fare, Icons.attach_money,
//                 Colors.orange),
//             SizedBox(height: 20),

//             // Start Ride Tracking Button
//             ElevatedButton(
//               onPressed: () {
//                 Navigator.push(
//                   context,
//                   MaterialPageRoute(
//                       builder: (context) => LiveRideTrackingScreen()),
//                 );
//               },
//               style: ElevatedButton.styleFrom(
//                 padding: EdgeInsets.symmetric(vertical: 16),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//               child: Text('Start Ride Tracking'),
//             ),

//             SizedBox(height: 10),

//             // 🔄 Sync Now Button
//             ElevatedButton(
//               onPressed: () {
//                 syncOfflineBookings(context: context);
//               },
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Colors.blueGrey,
//                 padding: EdgeInsets.symmetric(vertical: 16),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//               child: Text('🔄 Sync Offline Bookings'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rayride/services/booking_service.dart'; // Access syncOfflineBookings()

import 'live_ride_tracking_screen.dart';

class SharedRideDashboardScreen extends StatefulWidget {
  final String dropLocation;
  final String fare;

  const SharedRideDashboardScreen({
    super.key,
    required this.dropLocation,
    required this.fare,
  });

  @override
  _SharedRideDashboardScreenState createState() =>
      _SharedRideDashboardScreenState();
}

class _SharedRideDashboardScreenState extends State<SharedRideDashboardScreen> {
  int totalSeats = 4;
  int currentOccupancy = 1;
  List<String> pickups = ["Sector 10", "Mall Gate", "School"];
  List<String> drops = ["Metro", "Market", "Park"];
  int index = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      setState(() {
        currentOccupancy = (currentOccupancy + 1) % (totalSeats + 1);
        index = (index + 1) % pickups.length;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Widget buildInfoTile(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        subtitle: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = totalSeats > 0 ? currentOccupancy / totalSeats : 0;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('Ride Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Live Ride Status",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Occupancy Progress
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      "Seats Occupied",
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.grey[300],
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(height: 10),
                    Text("$currentOccupancy / $totalSeats Occupied"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Ride Info Cards
            buildInfoTile(
              "Next Pickup",
              pickups[index],
              Icons.location_on,
              Colors.green,
            ),
            buildInfoTile(
              "Next Drop-off",
              drops[index],
              Icons.flag,
              Colors.red,
            ),
            buildInfoTile(
              "Drop Location",
              widget.dropLocation,
              Icons.location_pin,
              Colors.blue,
            ),
            buildInfoTile(
              "Estimated Fare",
              widget.fare,
              Icons.attach_money,
              Colors.orange,
            ),

            const SizedBox(height: 25),

            // Start Ride Tracking Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        LiveRideTrackingScreen(rideId: "TEST_RIDE_001"),
                  ),
                );
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Start Ride Tracking'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 10),

            // Sync Offline Bookings Button
            ElevatedButton.icon(
              onPressed: () {
                syncOfflineBookings(context: context);
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync Offline Bookings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
