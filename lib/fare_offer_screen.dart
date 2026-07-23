import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import '../services/payment_service.dart';
import 'core/app_theme.dart'; // 🟢 Premium Theme
import 'driver_map_tracking_screen.dart';

class fareOfferScreen extends StatefulWidget {
  const fareOfferScreen({super.key});

  @override
  State<fareOfferScreen> createState() => _fareOfferScreenState();
}

class _fareOfferScreenState extends State<fareOfferScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _farePerKmController =
      TextEditingController(text: "12.0");

  LatLng? _dropLatLng;
  int _totalCapacity = 4;
  bool _isPublishing = false;
  bool _isLoadingCheckoutData = false;

  final PaymentService _paymentService = PaymentService();
  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  // 🟢 Animations
  late AnimationController _animController;
  late Animation<Offset> _slideUp;
  late Animation<double> _scaleIn;

  @override
  void initState() {
    super.initState();

    // Animation Setup
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _slideUp =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _scaleIn = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _paymentService.initialize(user.uid, onSuccess: () {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Success! Captain Pass Activated."),
            backgroundColor: AppTheme.mutedPine,
          ));
        }
      }, onError: (message) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Payment Failed: $message"),
            backgroundColor: Colors.redAccent,
          ));
        }
      });
    }
  }

  @override
  void dispose() {
    _paymentService.dispose();
    _animController.dispose();
    _dropController.dispose();
    _farePerKmController.dispose();
    super.dispose();
  }

  // 🟢 LAUNCH PREMIUM SEARCH MODAL
  Future<void> _handleCustomSearch() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FareLocationSearchModal(apiKey: kGoogleApiKey),
    );

    if (result != null) {
      setState(() {
        _dropController.text = result['address'];
        _dropLatLng = result['latlng'];
      });
    }
  }

  Future<void> _publishSharedRoute() async {
    if (_dropLatLng == null || _dropController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please select a drop-off destination."),
        backgroundColor: Colors.orangeAccent,
      ));
      return;
    }
    setState(() => _isPublishing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String driverUid = user?.uid ?? "demo_driver_uid";

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw Exception('Permissions denied');
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double farePerKm = double.tryParse(_farePerKmController.text) ?? 12.0;

      DocumentReference tripRef =
          await FirebaseFirestore.instance.collection('shared_trips').add({
        'driver_id': driverUid,
        'driver_name': user?.displayName ?? "Captain",
        'vehicle_number': "DL 1CA 1234", // Ideally fetched from driver profile
        'status': 'active',
        'start_name': 'Current Location',
        'start_latitude': position.latitude,
        'start_longitude': position.longitude,
        'drop_name': _dropController.text,
        'drop_lat': _dropLatLng!.latitude,
        'drop_lng': _dropLatLng!.longitude,
        'current_lat': position.latitude,
        'current_lng': position.longitude,
        'current_heading': position.heading,
        'total_capacity': _totalCapacity,
        'available_seats': _totalCapacity,
        'per_seat_fare_per_km': farePerKm,
        'published_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Map<String, dynamic> tripData = {
        'tripId': tripRef.id,
        'driver_id': driverUid
      };
      setState(() => _isPublishing = false);

      PersistentNavBarNavigator.pushNewScreen(
        context,
        screen: DriverMapTrackingScreen(rideData: tripData),
        withNavBar: false,
        pageTransitionAnimation: PageTransitionAnimation.cupertino,
      );
    } catch (e) {
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: $e"), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _showTransactionSummaryModal() async {
    setState(() => _isLoadingCheckoutData = true);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final planDoc = await FirebaseFirestore.instance
          .collection('subscription_plans')
          .doc('plan_monthly')
          .get();
      final walletDoc = await FirebaseFirestore.instance
          .collection('wallets')
          .doc(user.uid)
          .get();
      final configDoc = await FirebaseFirestore.instance
          .collection('system_configs')
          .doc('global')
          .get();

      double basePrice = planDoc.exists
          ? (planDoc.data()?['price_inr'] ?? 499).toDouble()
          : 499.0;
      double walletBalance = walletDoc.exists
          ? (walletDoc.data()?['balance'] ?? 0.0).toDouble()
          : 0.0;
      bool isFreeActive = configDoc.exists
          ? (configDoc.data()?['is_free_subs_active'] ?? false)
          : false;

      double walletUsed = 0.0;
      double gatewayDue = basePrice;

      if (isFreeActive) {
        gatewayDue = 0.0;
      } else {
        if (walletBalance >= basePrice) {
          walletUsed = basePrice;
          gatewayDue = 0.0;
        } else {
          walletUsed = walletBalance;
          gatewayDue = basePrice - walletBalance;
        }
      }

      if (!mounted) return;
      setState(() => _isLoadingCheckoutData = false);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.deepForest : AppTheme.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
                color: isDark
                    ? AppTheme.mutedPine.withOpacity(0.3)
                    : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: isDark ? AppTheme.dustySage : Colors.grey[300],
                          borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 20),
              Text("Transaction Summary",
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.white : AppTheme.deepForest)),
              const SizedBox(height: 5),
              Text("Review your breakdown before activating Captain Pro.",
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppTheme.dustySage)),
              const SizedBox(height: 25),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A5240)
                      : AppTheme.softMint.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.dustySage.withOpacity(0.2)
                          : Colors.transparent),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow("30-Day Pass Price",
                        "₹${basePrice.toStringAsFixed(0)}", isDark),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(
                            color: isDark
                                ? AppTheme.dustySage.withOpacity(0.3)
                                : Colors.grey[300])),
                    _buildSummaryRow("Wallet Deducted",
                        "- ₹${walletUsed.toStringAsFixed(0)}", isDark,
                        color: AppTheme.mutedPine),
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Divider(
                            color: isDark
                                ? AppTheme.dustySage.withOpacity(0.3)
                                : Colors.grey[300])),
                    _buildSummaryRow("Gateway Payable",
                        "₹${gatewayDue.toStringAsFixed(0)}", isDark,
                        isBold: true),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.mutedPine,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _paymentService
                        .initiateSubscriptionCheckout('plan_monthly');
                  },
                  child: Text(
                    gatewayDue == 0
                        ? "ACTIVATE FOR FREE"
                        : "PROCEED TO PAY ₹${gatewayDue.toStringAsFixed(0)}",
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } catch (e) {
      setState(() => _isLoadingCheckoutData = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error fetching summary: $e")));
    }
  }

  Widget _buildSummaryRow(String title, String value, bool isDark,
      {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 14,
                color: isBold
                    ? (isDark ? AppTheme.white : AppTheme.deepForest)
                    : AppTheme.dustySage,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 16,
                color: color ?? (isDark ? AppTheme.white : AppTheme.deepForest),
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return Scaffold(
          backgroundColor: AppTheme.deepForest,
          body: const Center(
              child: CircularProgressIndicator(color: AppTheme.softMint)));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('system_configs')
          .doc('global')
          .snapshots(),
      builder: (context, configSnapshot) {
        bool isGlobalFree = true;
        if (configSnapshot.hasData && configSnapshot.data!.exists) {
          isGlobalFree = (configSnapshot.data!.data()
                  as Map<String, dynamic>)['is_free_subs_active'] ??
              false;
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            bool hasActiveSub = false;
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData =
                  userSnapshot.data!.data() as Map<String, dynamic>;
              if (userData['sub_end'] != null) {
                DateTime subEnd = (userData['sub_end'] as Timestamp).toDate();
                if (subEnd.isAfter(DateTime.now())) hasActiveSub = true;
              }
            }

            return Scaffold(
              backgroundColor:
                  isDark ? AppTheme.deepForest : const Color(0xFFF5F7F5),
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                    hasActiveSub || isGlobalFree
                        ? "Publish Route"
                        : "Captain Pro",
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.white : AppTheme.deepForest)),
                centerTitle: true,
                actions: [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeNotifier,
                    builder: (context, currentMode, child) {
                      return IconButton(
                        icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                            color: isDark
                                ? AppTheme.softMint
                                : AppTheme.deepForest),
                        onPressed: () => themeNotifier.value =
                            isDark ? ThemeMode.light : ThemeMode.dark,
                      );
                    },
                  ),
                ],
              ),
              body: hasActiveSub || isGlobalFree
                  ? _buildPublishRouteUI(isGlobalFree, isDark)
                  : _buildSubscriptionPaywallUI(isDark),
            );
          },
        );
      },
    );
  }

  Widget _buildPublishRouteUI(bool isGlobalFree, bool isDark) {
    return SlideTransition(
      position: _slideUp,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isGlobalFree)
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppTheme.mutedPine.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: AppTheme.mutedPine.withOpacity(0.3))),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppTheme.mutedPine),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            "Early Adopter Bonus: Subscriptions are currently FREE!",
                            style: GoogleFonts.poppins(
                                color: isDark
                                    ? AppTheme.softMint
                                    : AppTheme.mutedPine,
                                fontWeight: FontWeight.bold,
                                fontSize: 13))),
                  ],
                ),
              ),
            Text("Where are you driving to?",
                style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.white : AppTheme.deepForest,
                    letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(
                "Publish your route and let riders along the way book your empty seats.",
                style: GoogleFonts.poppins(
                    color: AppTheme.dustySage, fontSize: 14)),
            const SizedBox(height: 32),

            ScaleTransition(
              scale: _scaleIn,
              child: Container(
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
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trip_origin,
                            color: AppTheme.mutedPine, size: 20),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Starting Point",
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: AppTheme.dustySage,
                                      fontWeight: FontWeight.w500)),
                              Text("Current Location",
                                  style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppTheme.white
                                          : AppTheme.deepForest)),
                            ],
                          ),
                        )
                      ],
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 9.0, top: 4, bottom: 4),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                              height: 24,
                              width: 2,
                              color: AppTheme.dustySage.withOpacity(0.3))),
                    ),
                    GestureDetector(
                      onTap: _handleCustomSearch,
                      child: Container(
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.blueAccent, size: 20),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Drop-off Location",
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: AppTheme.dustySage,
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                    _dropController.text.isEmpty
                                        ? "Tap to search destination"
                                        : _dropController.text,
                                    style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _dropController.text.isEmpty
                                            ? AppTheme.dustySage
                                            : (isDark
                                                ? AppTheme.white
                                                : AppTheme.deepForest)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildSettingCard(
                    title: "Available Seats",
                    icon: Icons.airline_seat_recline_normal_rounded,
                    isDark: isDark,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppTheme.mutedPine),
                            onPressed: () => setState(() {
                                  if (_totalCapacity > 1) _totalCapacity--;
                                })),
                        Text("$_totalCapacity",
                            style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppTheme.white
                                    : AppTheme.deepForest)),
                        IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: AppTheme.mutedPine),
                            onPressed: () => setState(() {
                                  if (_totalCapacity < 6) _totalCapacity++;
                                })),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSettingCard(
                    title: "Fare per Km",
                    icon: Icons.currency_rupee_rounded,
                    isDark: isDark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextField(
                        controller: _farePerKmController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color:
                                isDark ? AppTheme.white : AppTheme.deepForest),
                        decoration: const InputDecoration(
                            border: InputBorder.none, isDense: true),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.mutedPine,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                onPressed: _isPublishing ? null : _publishSharedRoute,
                child: _isPublishing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text("PUBLISH & GO ONLINE",
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2)),
              ),
            ),
            const SizedBox(height: 100), // Nav bar padding
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionPaywallUI(bool isDark) {
    return SlideTransition(
      position: _slideUp,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: AppTheme.softMint.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium_rounded,
                    size: 80, color: AppTheme.mutedPine),
              ),
              const SizedBox(height: 24),
              Text("Unlock Captain Mode",
                  style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.white : AppTheme.deepForest,
                      letterSpacing: -0.5)),
              const SizedBox(height: 12),
              Text(
                  "Your pass has expired. Renew to publish routes, accept riders, and keep 100% of your earnings.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppTheme.dustySage, height: 1.5)),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: isDark
                          ? [
                              AppTheme.mutedPine.withOpacity(0.8),
                              const Color(0xFF2A5240)
                            ]
                          : [AppTheme.mutedPine, const Color(0xFF759C8C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.mutedPine.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("30-Day Pass",
                            style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.white)),
                        const SizedBox(height: 4),
                        Text("Zero commission forever.",
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppTheme.softMint)),
                      ],
                    ),
                    Text("₹499",
                        style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.white)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTheme.dustySage),
                  const SizedBox(width: 8),
                  Text("Wallet balance automatically applies at checkout.",
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppTheme.dustySage,
                          fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.mutedPine,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16))),
                  onPressed: _isLoadingCheckoutData
                      ? null
                      : _showTransactionSummaryModal,
                  child: _isLoadingCheckoutData
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text("RENEW PASS NOW",
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingCard(
      {required String title,
      required IconData icon,
      required Widget child,
      required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
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
        children: [
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppTheme.softMint.withOpacity(0.3),
                  shape: BoxShape.circle),
              child: Icon(icon, color: AppTheme.mutedPine, size: 20)),
          const SizedBox(height: 12),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppTheme.dustySage,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// 🟢 REUSABLE PREMIUM SEARCH MODAL FOR DROP LOCATION
class FareLocationSearchModal extends StatefulWidget {
  final String apiKey;
  const FareLocationSearchModal({super.key, required this.apiKey});

  @override
  State<FareLocationSearchModal> createState() =>
      _FareLocationSearchModalState();
}

class _FareLocationSearchModalState extends State<FareLocationSearchModal> {
  List<dynamic> _predictions = [];
  bool _isFetching = false;
  Timer? _debounce;

  void _searchPlaces(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.isEmpty) {
      setState(() {
        _predictions.clear();
        _isFetching = false;
      });
      return;
    }
    setState(() => _isFetching = true);

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final url = Uri.parse(
            'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=${widget.apiKey}&components=country:in');
        final response = await http.get(url);
        final data = json.decode(response.body);

        if (data['status'] == 'OK' && mounted) {
          setState(() {
            _predictions = data['predictions'];
            _isFetching = false;
          });
        } else {
          if (mounted) setState(() => _isFetching = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isFetching = false);
      }
    });
  }

  Future<void> _fetchPlaceDetails(String placeId, String description) async {
    setState(() => _isFetching = true);
    try {
      final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=${widget.apiKey}');
      final response = await http.get(url);
      final data = json.decode(response.body);

      if (data['status'] == 'OK' && mounted) {
        final lat = data['result']['geometry']['location']['lat'];
        final lng = data['result']['geometry']['location']['lng'];
        Navigator.pop(
            context, {'latlng': LatLng(lat, lng), 'address': description});
      }
    } catch (e) {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.deepForest : AppTheme.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                  color: isDark ? AppTheme.dustySage : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text("Set Drop-off Location",
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.white : AppTheme.deepForest)),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              autofocus: true,
              onChanged: _searchPlaces,
              style: GoogleFonts.poppins(
                  color: isDark ? AppTheme.white : AppTheme.deepForest,
                  fontSize: 16),
              decoration: InputDecoration(
                hintText: "Search area, street, or landmark...",
                hintStyle: GoogleFonts.poppins(
                    color: isDark ? AppTheme.dustySage : Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, color: AppTheme.mutedPine),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2A5240)
                    : AppTheme.softMint.withOpacity(0.3),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_isFetching)
            const LinearProgressIndicator(
                color: AppTheme.mutedPine, backgroundColor: Colors.transparent),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final prediction = _predictions[index];
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.deepForest
                            : AppTheme.softMint.withOpacity(0.5),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.location_on,
                        color: AppTheme.mutedPine, size: 20),
                  ),
                  title: Text(
                      prediction['structured_formatting']['main_text'] ?? "",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? AppTheme.white : AppTheme.deepForest)),
                  subtitle: Text(
                      prediction['structured_formatting']['secondary_text'] ??
                          "",
                      style: GoogleFonts.poppins(
                          color: AppTheme.dustySage, fontSize: 12)),
                  onTap: () => _fetchPlaceDetails(
                      prediction['place_id'], prediction['description']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
