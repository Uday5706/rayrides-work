import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';
import 'package:flutter_google_places_hoc081098/google_maps_webservice_places.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/places.dart' as gm_webservice;
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';

import '../services/payment_service.dart';
import 'driver_map_tracking_screen.dart';

class fareOfferScreen extends StatefulWidget {
  const fareOfferScreen({super.key});

  @override
  State<fareOfferScreen> createState() => _fareOfferScreenState();
}

class _fareOfferScreenState extends State<fareOfferScreen> {
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _farePerKmController =
      TextEditingController(text: "12.0");

  LatLng? _dropLatLng;
  int _totalCapacity = 4;
  bool _isPublishing = false;
  bool _isLoadingCheckoutData = false;

  final PaymentService _paymentService = PaymentService();
  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  // Theming
  final Color primaryGreen = const Color(0xFF2E7D32);
  final Color lightGreen = const Color(0xFFE8F5E9);

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _paymentService.initialize(user.uid, onSuccess: () {
        if (mounted) {
          Navigator.pop(context); // Close any active sheet/dialog if open
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Success! Captain Pass Activated."),
              backgroundColor: Colors.green));
        }
      }, onError: (message) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("Payment Failed: $message"),
              backgroundColor: Colors.red));
        }
      });
    }
  }

  @override
  void dispose() {
    _paymentService.dispose();
    super.dispose();
  }

  Future<void> _handleAutocomplete() async {
    var p = await PlacesAutocomplete.show(
      context: context,
      apiKey: kGoogleApiKey,
      mode: Mode.overlay,
      language: "en",
      components: [Component(Component.country, "in")],
    );

    if (p != null) {
      final places = gm_webservice.GoogleMapsPlaces(apiKey: kGoogleApiKey);
      final detail = await places.getDetailsByPlaceId(p.placeId!);
      final lat = detail.result.geometry!.location.lat;
      final lng = detail.result.geometry!.location.lng;

      setState(() {
        _dropController.text = p.description!;
        _dropLatLng = LatLng(lat, lng);
      });
    }
  }

  Future<void> _publishSharedRoute() async {
    if (_dropLatLng == null || _dropController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Please select a destination drop-off location.")));
      return;
    }
    setState(() => _isPublishing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String driverUid = user?.uid ?? "demo_driver_uid";

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      double farePerKm = double.tryParse(_farePerKmController.text) ?? 12.0;

      DocumentReference tripRef =
          await FirebaseFirestore.instance.collection('shared_trips').add({
        'driver_id': driverUid,
        'driver_name': user?.displayName ?? "Captain",
        'vehicle_number': "DL 1CA 1234",
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error publishing route: $e")));
    }
  }

  // 🟢 STEP 1: PRE-FETCH BREAKDOWN FOR THE MODAL UX
  Future<void> _showTransactionSummaryModal() async {
    setState(() => _isLoadingCheckoutData = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Fetch Plan price and Driver Wallet concurrently from backend/Firestore
      // For precision, we fetch live values to show exact math in the modal
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

      // 🟢 POP UP THE FINTECH SUMMARY SHEET
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              Text("Transaction Summary",
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("Review your breakdown before activating Captain Pro.",
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey[600])),

              const SizedBox(height: 25),

              // Ledger breakdown box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow("30-Day Pass Price",
                        "₹${basePrice.toStringAsFixed(0)}"),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider()),
                    _buildSummaryRow("Wallet Deducted",
                        "- ₹${walletUsed.toStringAsFixed(0)}",
                        color: Colors.green),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider()),
                    _buildSummaryRow(
                        "Gateway Payable", "₹${gatewayDue.toStringAsFixed(0)}",
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
                    backgroundColor: primaryGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    Navigator.pop(context); // Close sheet
                    _executeSubscriptionCheckout(); // Fire backend + razorpay securely
                  },
                  child: Text(
                    gatewayDue == 0
                        ? "ACTIVATE FOR FREE"
                        : "PROCEED TO PAY ₹${gatewayDue.toStringAsFixed(0)}",
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
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

  Widget _buildSummaryRow(String title, String value,
      {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 14,
                color: isBold ? Colors.black : Colors.grey[700],
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 15,
                color: color ?? (isBold ? Colors.black : Colors.black87),
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  // 🟢 STEP 2: HANDOFF ENTIRELY TO BACKEND LOGIC VIA PAYMENT SERVICE
  Future<void> _executeSubscriptionCheckout() async {
    try {
      await _paymentService.initiateSubscriptionCheckout('plan_monthly');
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return const Scaffold(body: Center(child: Text("Please log in")));

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
                if (subEnd.isAfter(DateTime.now())) {
                  hasActiveSub = true;
                }
              }
            }

            if (hasActiveSub || isGlobalFree) {
              return _buildPublishRouteUI(isGlobalFree);
            } else {
              return _buildSubscriptionPaywallUI();
            }
          },
        );
      },
    );
  }

  Widget _buildPublishRouteUI(bool isGlobalFree) {
    return ColoredBox(
      color: primaryGreen,
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: Text("Publish Route",
                style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: primaryGreen,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isGlobalFree)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: lightGreen,
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(Icons.star, color: primaryGreen),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                              "Early Adopter Bonus: Subscriptions are currently FREE!",
                              style: GoogleFonts.poppins(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.w600)),
                        )
                      ],
                    ),
                  ),
                Text("Where are you driving to?",
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text(
                    "Publish your route and let riders along the way book your empty seats.",
                    style: GoogleFonts.poppins(color: Colors.grey[700])),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10)
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildStaticOriginField(),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Divider()),
                      _buildDestinationField(),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: _buildSettingCard(
                          title: "Available Seats",
                          icon: Icons.airline_seat_recline_normal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: Icon(Icons.remove_circle_outline,
                                    color: primaryGreen),
                                onPressed: () => setState(() {
                                  if (_totalCapacity > 1) _totalCapacity--;
                                }),
                              ),
                              Text("$_totalCapacity",
                                  style: GoogleFonts.poppins(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                icon: Icon(Icons.add_circle_outline,
                                    color: primaryGreen),
                                onPressed: () => setState(() {
                                  if (_totalCapacity < 6) _totalCapacity++;
                                }),
                              ),
                            ],
                          )),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildSettingCard(
                          title: "Fare per Km (₹)",
                          icon: Icons.currency_rupee,
                          child: TextField(
                            controller: _farePerKmController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                fontSize: 20, fontWeight: FontWeight.bold),
                            decoration:
                                const InputDecoration(border: InputBorder.none),
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    onPressed: _isPublishing ? null : _publishSharedRoute,
                    child: _isPublishing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text("PUBLISH ROUTE & GO ONLINE",
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionPaywallUI() {
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text("Captain Pro",
                style: GoogleFonts.poppins(color: Colors.black)),
            backgroundColor: Colors.white,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.black),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium, size: 80, color: primaryGreen),
                  const SizedBox(height: 20),
                  Text("Unlock Captain Mode",
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  const SizedBox(height: 10),
                  Text(
                      "Your subscription has expired. Renew your pass to publish routes and start earning.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 14, color: Colors.grey[600])),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: lightGreen,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: primaryGreen, width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("30-Day Pass",
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryGreen)),
                            Text("Zero commission on rides",
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: primaryGreen.withOpacity(0.8))),
                          ],
                        ),
                        Text("₹499",
                            style: GoogleFonts.poppins(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: primaryGreen)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 5),
                      Text(
                          "Wallet balance will be automatically applied at checkout.",
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      // 🟢 TRiggers the clean modal summary sheet instead of direct raw loading
                      onPressed: _isLoadingCheckoutData
                          ? null
                          : _showTransactionSummaryModal,
                      child: _isLoadingCheckoutData
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text("SUBSCRIBE NOW",
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
        ),
      ),
    );
  }

  Widget _buildStaticOriginField() {
    return Row(
      children: [
        Icon(Icons.my_location, color: primaryGreen),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Starting Point",
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
              Text("Current Location",
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDestinationField() {
    return GestureDetector(
      onTap: _handleAutocomplete,
      child: Container(
        color: Colors.transparent,
        child: Row(
          children: [
            const Icon(Icons.flag, color: Colors.redAccent),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Drop-off Location",
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey)),
                  Text(
                    _dropController.text.isEmpty
                        ? "Tap to search destination"
                        : _dropController.text,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _dropController.text.isEmpty
                            ? Colors.grey
                            : Colors.black),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(height: 5),
          Text(title,
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
