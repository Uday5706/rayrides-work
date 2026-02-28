import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rayride/role_selection_screen.dart';

import 'driver_map_tracking_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double batteryLevel = 0.0;
  int totalCompletedRides = 0;
  double totalEarnings = 0.0;
  List<Map<String, dynamic>> rideHistory = [];
  double todayCO2 = 0.0;
  Map<String, dynamic>? activeRide;

  @override
  void initState() {
    super.initState();
    fetchDashboardData();
  }

  void _backToRoleSelection(BuildContext context) {
    // Use pushAndRemoveUntil to clear the entire navigation history
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) =>
              const roleSelection() // Replace with your actual class name
          ),
      (Route<dynamic> route) =>
          false, // This condition removes all previous routes
    );
  }

  Future<void> fetchDashboardData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final driverUid = user.uid;

      final rideSnapshot = await FirebaseFirestore.instance
          .collection('rides')
          .where('driver_id', isEqualTo: driverUid)
          .orderBy('accepted_at', descending: true)
          .get();

      rideHistory = rideSnapshot.docs.map((doc) {
        return {
          ...doc.data(),
          'id': doc.id,
        };
      }).toList();

      /// 🔥 Detect Active Ride
      activeRide = null;

      for (var ride in rideHistory) {
        if (ride['status'] == 'accepted' || ride['status'] == 'in_progress') {
          activeRide = ride;
          break;
        }
      }

      if (activeRide != null && activeRide!.isEmpty) {
        activeRide = null;
      }

      final completedRides =
          rideHistory.where((ride) => ride['status'] == 'ended').toList();

      totalCompletedRides = completedRides.length;

      totalEarnings =
          completedRides.fold(0.0, (sum, ride) => sum + (ride['fare'] ?? 0));

      todayCO2 = completedRides.fold(
          0.0, (sum, ride) => sum + (ride['carbon_saved_kg'] ?? 0));

      setState(() {});
    } catch (e) {
      debugPrint("❌ Error fetching dashboard data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final batteryPercentText = '${(batteryLevel * 100).toInt()}%';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: RefreshIndicator(
        onRefresh: fetchDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              /// 🔥 HEADER SECTION
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F2027), Color(0xFF2C5364)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Welcome Back 👋",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    SizedBox(height: 5),
                    Text(
                      "Driver Dashboard",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              /// 🌱 CO2 SAVED TODAY CARD
              _buildCO2Card(),

              const SizedBox(height: 20),

              /// 📊 STATS CARDS
              Row(
                children: [
                  Expanded(
                    child: _buildStatCardModern(
                      title: "₹${totalEarnings.toStringAsFixed(2)}",
                      subtitle: "Total Earnings",
                      icon: Icons.currency_rupee,
                      color: Colors.green,
                    ),
                  ),
                  Expanded(
                    child: _buildStatCardModern(
                      title: "$totalCompletedRides",
                      subtitle: "Completed Rides",
                      icon: Icons.directions_car,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// 🔋 BATTERY CARD
              _buildBatteryCard(batteryPercentText),

              const SizedBox(height: 25),

              /// 🚗 Resume Ride Button
              _buildResumeRideButton(),

              const SizedBox(height: 20),

              /// 📜 Ride History Preview
              _buildRideHistorySection(),

              const SizedBox(height: 30),

              _buildButton("Log Out", () => _backToRoleSelection(context)),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCO2Card() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C853), Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.3),
            blurRadius: 12,
          )
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.eco, color: Colors.white, size: 40),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "CO₂ Saved Today",
                style: TextStyle(color: Colors.white70),
              ),
              Text(
                "${todayCO2.toStringAsFixed(2)} kg",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatCardModern({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
          )
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 10),
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBatteryCard(String percentText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.battery_charging_full,
              size: 40, color: Colors.green),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Battery Level"),
              Text(
                percentText,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResumeRideButton() {
    if (activeRide == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: activeRide!['status'] == 'accepted'
                ? Colors.blue
                : Colors.green,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          icon: const Icon(Icons.map, color: Colors.white),
          label: const Text(
            "Resume Current Ride",
            style: TextStyle(color: Colors.white),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverMapTrackingScreen(rideData: activeRide!),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRideHistorySection() {
    if (rideHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text("No ride history yet."),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ride History",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          ...rideHistory.map((ride) {
            return _buildRideTile(ride);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRideTile(dynamic ride) {
    return ExpansionTile(
      leading: const Icon(Icons.directions_car, color: Colors.blue),
      title: Text("₹${ride['fare'] ?? 0}"),
      subtitle: Text("${ride['status']}"),
      children: [
        ListTile(
          title: Text("Pickup: ${ride['pickup_name'] ?? ''}"),
        ),
        ListTile(
          title: Text("Drop: ${ride['drop_name'] ?? ''}"),
        ),
        ListTile(
          title: Text(
            "CO₂ Saved: ${(ride['co2_saved'] ?? 0).toStringAsFixed(2)} kg",
          ),
        ),
      ],
    );
  }

  Widget buildAlertTile(String title) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber),
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.amber.shade200],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ElevatedButton(onPressed: () {}, child: Text('View')),
          SizedBox(width: 5),
          Icon(Icons.cancel_outlined, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onPressed,
          child: Text(label,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    );
  }
}
