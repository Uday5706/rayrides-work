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

import 'driver_map_tracking_screen.dart';

// TEACHING CONCEPT: Paradigm Shift (Reactive -> Proactive)
// We renamed the internal state logic to reflect "Publishing a Route"
// rather than "Accepting Offers". The driver creates the inventory (seats),
// and the riders consume it.
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

  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  @override
  void initState() {
    super.initState();
  }

  // TEACHING CONCEPT: Google Places Autocomplete Integration
  // We need the driver's exact destination coordinates to allow the rider's
  // app to calculate if their route overlaps with the driver's route.
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

  // TEACHING CONCEPT: Creating the 'Shared Trip' Document
  // This function seeds the database with the driver's active state.
  // Riders will query this exact document to book seats.
  Future<void> _publishSharedRoute() async {
    if (_dropLatLng == null || _dropController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please select a destination drop-off location.")),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final String driverUid = user?.uid ?? "demo_driver_uid";

      // Get driver's current starting point
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

      // 1. Create the Master Trip Document
      DocumentReference tripRef =
          await FirebaseFirestore.instance.collection('shared_trips').add({
        'driver_id': driverUid,
        'driver_name': user?.displayName ?? "Captain",
        'vehicle_number':
            "DL 1CA 1234", // Replace with actual driver vehicle data
        'status': 'active',

        // Static route data
        'start_name': 'Current Location',
        'start_lat': position.latitude,
        'start_lng': position.longitude,
        'drop_name': _dropController.text,
        'drop_lat': _dropLatLng!.latitude,
        'drop_lng': _dropLatLng!.longitude,

        // Live tracking data (Updated via Socket/Geolocator later)
        'current_lat': position.latitude,
        'current_lng': position.longitude,
        'current_heading': position.heading,

        // Capacity & Economics
        'total_capacity': _totalCapacity,
        'available_seats': _totalCapacity, // Starts fully empty
        'per_seat_fare_per_km': farePerKm,

        'published_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // Prepare payload for the Tracking Screen
      Map<String, dynamic> tripData = {
        'tripId': tripRef.id,
        'driver_id': driverUid,
      };

      setState(() => _isPublishing = false);

      // 2. Navigate to the manifest tracker
      PersistentNavBarNavigator.pushNewScreen(
        context,
        screen: DriverMapTrackingScreen(rideData: tripData),
        withNavBar: false,
        pageTransitionAnimation: PageTransitionAnimation.cupertino,
      );
    } catch (e) {
      setState(() => _isPublishing = false);
      debugPrint("Publish error: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error publishing route: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("Publish Route",
            style: GoogleFonts.poppins(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Where are you driving to?",
                style: GoogleFonts.poppins(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
                "Publish your route and let riders along the way book your empty seats.",
                style: GoogleFonts.poppins(color: Colors.grey[700])),

            const SizedBox(height: 30),

            // Route Section
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
                    child: Divider(),
                  ),
                  _buildDestinationField(),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Economics & Capacity Section
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
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.blueAccent),
                            onPressed: () => setState(() {
                              if (_totalCapacity > 1) _totalCapacity--;
                            }),
                          ),
                          Text("$_totalCapacity",
                              style: GoogleFonts.poppins(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline,
                                color: Colors.blueAccent),
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

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
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
    );
  }

  Widget _buildStaticOriginField() {
    return Row(
      children: [
        const Icon(Icons.my_location, color: Colors.blueAccent),
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
        color: Colors.transparent, // Ensures the whole row is clickable
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
