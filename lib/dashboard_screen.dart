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
  double todayEarnings = 0.0; // Changed to Today's Earnings
  List<Map<String, dynamic>> rideHistory = [];
  double todayCO2 = 0.0;
  Map<String, dynamic>? activeRide;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchDashboardData();
  }

  void _backToRoleSelection(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const roleSelection()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> fetchDashboardData() async {
    setState(() => isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => isLoading = false);
        return;
      }

      final driverUid = user.uid;

      final rideSnapshot = await FirebaseFirestore.instance
          .collection('shared_trips')
          .where('driver_id', isEqualTo: driverUid)
          .orderBy('published_at', descending: true)
          .get();

      List<Map<String, dynamic>> tempHistory = [];
      todayCO2 = 0.0;
      todayEarnings = 0.0;
      activeRide = null;
      int completedCount = 0;

      final DateTime now = DateTime.now();

      for (var doc in rideSnapshot.docs) {
        Map<String, dynamic> rideData = {
          ...doc.data(),
          'tripId': doc.id,
        };

        // 🟢 INSTANT MATH: No subcollection reads needed anymore!
        double shiftEarnings = (rideData['total_earned'] ?? 0.0).toDouble();

        tempHistory.add(rideData);

        if (rideData['status'] == 'active') {
          activeRide = rideData;
        } else if (rideData['status'] == 'completed') {
          completedCount++;

          if (rideData['completed_at'] != null) {
            DateTime completedDate =
                (rideData['completed_at'] as Timestamp).toDate();
            if (completedDate.year == now.year &&
                completedDate.month == now.month &&
                completedDate.day == now.day) {
              todayCO2 += (rideData['carbon_saved_kg'] ?? 0.0);
              todayEarnings += shiftEarnings;
            }
          }
        }
      }

      setState(() {
        rideHistory = tempHistory;
        totalCompletedRides = completedCount;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error fetching dashboard data: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batteryPercentText = '${(batteryLevel * 100).toInt()}%';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: fetchDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
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
                            style:
                                TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          SizedBox(height: 5),
                          Text(
                            "Shared Driver Dashboard",
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
                    _buildCO2Card(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCardModern(
                            title: "₹${todayEarnings.toStringAsFixed(0)}",
                            subtitle: "Today's Earnings",
                            icon: Icons.currency_rupee,
                            color: Colors.green,
                          ),
                        ),
                        Expanded(
                          child: _buildStatCardModern(
                            title: "$totalCompletedRides",
                            subtitle: "Total Shifts",
                            icon: Icons.directions_car,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildBatteryCard(batteryPercentText),
                    const SizedBox(height: 25),
                    _buildResumeRideButton(),
                    const SizedBox(height: 20),
                    _buildRideHistorySection(),
                    const SizedBox(height: 30),
                    _buildButton(
                        "Log Out", () => _backToRoleSelection(context)),
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
          Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
            backgroundColor: Colors.orangeAccent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          icon: const Icon(Icons.map, color: Colors.white),
          label: const Text(
            "Resume Active Route",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        child: Text("No shared routes published yet."),
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
            "Carpool Shift History",
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
    // 🟢 Read directly from the array we created during the ride
    List<dynamic> passengers = ride['completed_passengers'] ?? [];
    double shiftEarnings = (ride['total_earned'] ?? 0.0).toDouble();
    bool isCompleted = ride['status'] == 'completed';

    return ExpansionTile(
      leading: const Icon(Icons.route, color: Colors.blueAccent),
      title: Text(ride['drop_name'] ?? 'Custom Route',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
          isCompleted
              ? 'Shift Ended • ₹${shiftEarnings.toStringAsFixed(0)}'
              : 'Driving Now • ₹${shiftEarnings.toStringAsFixed(0)} earned so far',
          style: TextStyle(
              color: isCompleted ? Colors.grey[700] : Colors.green,
              fontWeight: FontWeight.w600)),
      children: [
        ListTile(
          dense: true,
          leading: const Icon(Icons.eco, color: Colors.green, size: 20),
          title: Text(
              "CO₂ Saved: ${(ride['carbon_saved_kg'] ?? 0).toStringAsFixed(2)} kg"),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.my_location, color: Colors.blue, size: 20),
          title:
              Text("Shift Start: ${ride['start_name'] ?? 'Current Location'}"),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Completed Journeys:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey))),
        ),
        if (passengers.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No passengers dropped off yet."),
          )
        else
          ...passengers.map((p) {
            return ListTile(
              dense: true,
              leading:
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
              title: Text("Passenger (${p['seats']} seats)"),
              subtitle: const Text("Successfully Dropped Off"),
              trailing: Text("+ ₹${(p['fare'] ?? 0).toStringAsFixed(0)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            );
          }).toList(),
        const SizedBox(height: 10),
      ],
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
            backgroundColor: Colors.black,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onPressed,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    );
  }
}
