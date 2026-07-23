import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:rayride/role_selection_screen.dart';

import 'core/app_theme.dart';
import 'driver_map_tracking_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  double batteryLevel = 0.0;
  int totalCompletedRides = 0;
  double todayEarnings = 0.0;
  List<Map<String, dynamic>> rideHistory = [];
  double todayCO2 = 0.0;
  Map<String, dynamic>? activeRide;
  bool isLoading = true;

  // 🟢 ANIMATIONS
  late AnimationController _animController;
  late Animation<Offset> _slideHeader;
  late Animation<double> _scaleCards;
  late Animation<Offset> _slideHistory;

  @override
  void initState() {
    super.initState();

    // Setup Staggered Animations
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _slideHeader =
        Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic)),
    );

    _scaleCards = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.2, 0.7, curve: Curves.elasticOut)),
    );

    _slideHistory =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)),
    );

    fetchDashboardData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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

      _animController.forward(from: 0.0); // Trigger animation on load
    } catch (e) {
      debugPrint("❌ Error fetching dashboard data: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final batteryPercentText = '${(batteryLevel * 100).toInt()}%';

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? AppTheme.deepForest : const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _buildThemeToggle(isDark),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.mutedPine))
          : RefreshIndicator(
              onRefresh: fetchDashboardData,
              color: AppTheme.mutedPine,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildHeader(isDark),
                    const SizedBox(height: 24),

                    // Staggered Cards
                    ScaleTransition(
                      scale: _scaleCards,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            _buildCO2Card(isDark),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCardModern(
                                    title:
                                        "₹${todayEarnings.toStringAsFixed(0)}",
                                    subtitle: "Today's Earnings",
                                    icon: Icons.account_balance_wallet_rounded,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildStatCardModern(
                                    title: "$totalCompletedRides",
                                    subtitle: "Total Shifts",
                                    icon: Icons.directions_car_rounded,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildBatteryCard(batteryPercentText, isDark),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (activeRide != null)
                      ScaleTransition(
                        scale: _scaleCards,
                        child: _buildResumeRideButton(),
                      ),

                    const SizedBox(height: 10),

                    SlideTransition(
                      position: _slideHistory,
                      child: _buildRideHistorySection(isDark),
                    ),

                    const SizedBox(height: 30),
                    SlideTransition(
                      position: _slideHistory,
                      child: _buildLogoutButton(isDark),
                    ),
                    const SizedBox(height: 100), // Padding for bottom nav bar
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildThemeToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0, top: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.deepForest.withOpacity(0.5)
                  : AppTheme.white.withOpacity(0.5),
              shape: BoxShape.circle,
              border: Border.all(
                  color: isDark
                      ? AppTheme.dustySage.withOpacity(0.3)
                      : AppTheme.softMint,
                  width: 1),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, child) {
                return IconButton(
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    color: isDark ? AppTheme.softMint : AppTheme.deepForest,
                  ),
                  onPressed: () {
                    themeNotifier.value =
                        isDark ? ThemeMode.light : ThemeMode.dark;
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return SlideTransition(
      position: _slideHeader,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [AppTheme.deepForest, const Color(0xFF142C21)]
                : [AppTheme.mutedPine, AppTheme.deepForest],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.deepForest.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Welcome Back 👋",
              style: GoogleFonts.poppins(
                  color: AppTheme.softMint,
                  fontSize: 16,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              "Driver Dashboard",
              style: GoogleFonts.poppins(
                color: AppTheme.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCO2Card(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppTheme.mutedPine.withOpacity(0.8), const Color(0xFF2A5240)]
              : [AppTheme.mutedPine, const Color(0xFF759C8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: AppTheme.mutedPine.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.white.withOpacity(0.2), shape: BoxShape.circle),
            child:
                const Icon(Icons.eco_rounded, color: AppTheme.white, size: 32),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("CO₂ Saved Today",
                  style: GoogleFonts.poppins(
                      color: AppTheme.softMint,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                "${todayCO2.toStringAsFixed(2)} kg",
                style: GoogleFonts.poppins(
                    color: AppTheme.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildStatCardModern(
      {required String title,
      required String subtitle,
      required IconData icon,
      required bool isDark}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A5240) : AppTheme.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark
                ? AppTheme.dustySage.withOpacity(0.2)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Colors.black26
                  : AppTheme.dustySage.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppTheme.softMint.withOpacity(0.3),
                shape: BoxShape.circle),
            child: Icon(icon,
                size: 24,
                color: isDark ? AppTheme.softMint : AppTheme.mutedPine),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.white : AppTheme.deepForest)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.poppins(
                  color: AppTheme.dustySage,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildBatteryCard(String percentText, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A5240) : AppTheme.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark
                ? AppTheme.dustySage.withOpacity(0.2)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Colors.black26
                  : AppTheme.dustySage.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.softMint.withOpacity(0.3),
                shape: BoxShape.circle),
            child: Icon(Icons.battery_charging_full_rounded,
                size: 28,
                color: isDark ? AppTheme.softMint : AppTheme.mutedPine),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Battery Level",
                  style: GoogleFonts.poppins(
                      color: AppTheme.dustySage,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
              Text(percentText,
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.white : AppTheme.deepForest)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildResumeRideButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orangeAccent.shade700,
            elevation: 8,
            shadowColor: Colors.orangeAccent.withOpacity(0.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.map_rounded, color: Colors.white),
          label: Text("RESUME ACTIVE ROUTE",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          onPressed: () {
            // 🟢 UPDATED: Uses PersistentNavBarNavigator to push full screen
            PersistentNavBarNavigator.pushNewScreen(
              context,
              screen: DriverMapTrackingScreen(rideData: activeRide!),
              withNavBar: false, // Hides the bottom navigation bar
              pageTransitionAnimation: PageTransitionAnimation.cupertino,
            );
          },
        ),
      ),
    );
  }

  Widget _buildRideHistorySection(bool isDark) {
    if (rideHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Center(
          child: Text("No shared routes published yet.",
              style:
                  GoogleFonts.poppins(color: AppTheme.dustySage, fontSize: 16)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 16.0),
            child: Text("Carpool Shift History",
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.white : AppTheme.deepForest)),
          ),
          ...rideHistory.map((ride) => _buildRideTile(ride, isDark)).toList(),
        ],
      ),
    );
  }

  Widget _buildRideTile(dynamic ride, bool isDark) {
    List<dynamic> passengers = ride['completed_passengers'] ?? [];
    double shiftEarnings = (ride['total_earned'] ?? 0.0).toDouble();
    bool isCompleted = ride['status'] == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A5240) : AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark
                ? AppTheme.dustySage.withOpacity(0.2)
                : Colors.transparent),
        boxShadow: [
          BoxShadow(
              color:
                  isDark ? Colors.black26 : AppTheme.dustySage.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
            dividerColor:
                Colors.transparent), // Removes default ExpansionTile borders
        child: ExpansionTile(
          iconColor: AppTheme.mutedPine,
          collapsedIconColor: AppTheme.dustySage,
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: isCompleted
                    ? AppTheme.softMint.withOpacity(0.3)
                    : Colors.orange.withOpacity(0.2),
                shape: BoxShape.circle),
            child: Icon(Icons.route_rounded,
                color: isCompleted ? AppTheme.mutedPine : Colors.orangeAccent),
          ),
          title: Text(ride['drop_name'] ?? 'Custom Route',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.white : AppTheme.deepForest)),
          subtitle: Text(
            isCompleted
                ? 'Shift Ended • ₹${shiftEarnings.toStringAsFixed(0)}'
                : 'Driving Now • ₹${shiftEarnings.toStringAsFixed(0)}',
            style: GoogleFonts.poppins(
                color: isCompleted ? AppTheme.dustySage : Colors.orangeAccent,
                fontWeight: FontWeight.w600,
                fontSize: 13),
          ),
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                children: [
                  Container(
                      height: 1,
                      color: isDark
                          ? AppTheme.dustySage.withOpacity(0.2)
                          : Colors.grey[200]),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.eco_rounded,
                        color: AppTheme.mutedPine, size: 22),
                    title: Text(
                        "CO₂ Saved: ${(ride['carbon_saved_kg'] ?? 0).toStringAsFixed(2)} kg",
                        style: GoogleFonts.poppins(
                            color: isDark
                                ? AppTheme.softMint
                                : AppTheme.deepForest)),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.my_location_rounded,
                        color: isDark ? AppTheme.softMint : AppTheme.mutedPine,
                        size: 22),
                    title: Text(
                        "Shift Start: ${ride['start_name'] ?? 'Current Location'}",
                        style: GoogleFonts.poppins(
                            color:
                                isDark ? AppTheme.white : AppTheme.deepForest)),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Completed Journeys",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.dustySage,
                            fontSize: 12,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(height: 8),
                  if (passengers.isEmpty)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text("No passengers dropped off yet.",
                            style: GoogleFonts.poppins(
                                color:
                                    isDark ? AppTheme.white : Colors.grey[600],
                                fontSize: 13)))
                  else
                    ...passengers.map((p) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: AppTheme.mutedPine, size: 16),
                            const SizedBox(width: 8),
                            Text("Passenger (${p['seats']} seats)",
                                style: GoogleFonts.poppins(
                                    color: isDark
                                        ? AppTheme.white
                                        : AppTheme.deepForest,
                                    fontSize: 13)),
                            const Spacer(),
                            Text("+ ₹${(p['fare'] ?? 0).toStringAsFixed(0)}",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.mutedPine)),
                          ],
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: BorderSide(
                color: Colors.redAccent.withOpacity(0.5), width: 1.5),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => _backToRoleSelection(context),
          child: Text("LOG OUT",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ),
      ),
    );
  }
}
