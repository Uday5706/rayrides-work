import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tcard/tcard.dart';

import 'driver_map_tracking_screen.dart';

class fareOfferScreen extends StatefulWidget {
  const fareOfferScreen({super.key});

  @override
  State<fareOfferScreen> createState() => _fareOfferScreenState();
}

class _fareOfferScreenState extends State<fareOfferScreen> {
  final TCardController _controller = TCardController();
  List<Map<String, dynamic>> rideOffers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOffers(); // Initial scan on load
  }

  /// Task: Fetch all 'searching' rides directly from Firestore
  /// We have removed the 500m proximity filter per your request.
  Future<void> fetchOffers() async {
    setState(() => isLoading = true);
    try {
      // Fetching all rides with 'searching' status
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('rides')
          .where('status', isEqualTo: 'searching')
          .get();

      setState(() {
        rideOffers = snapshot.docs.map((doc) {
          var data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id; // Map document ID for acceptance
          return data;
        }).toList();
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Scan complete: ${rideOffers.length} rides found")),
      );
    } catch (e) {
      debugPrint("❌ Scan failed: $e");
      setState(() => isLoading = false);
    }
  }

  /// Logic to accept a ride and move to the map
  // Inside _fareOfferScreenState
  Future<void> acceptRide(Map<String, dynamic> offer) async {
    try {
      // 1. Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return Future.error('Location services are disabled.');
      }

      // 2. Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // 3. Request permission if it was previously denied
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Permissions are denied, next time you could try requesting permissions again
          return Future.error('Location permissions are denied');
        }
      }

      // 4. Handle permanent denial (User must go to settings manually)
      if (permission == LocationPermission.deniedForever) {
        return Future.error(
            'Location permissions are permanently denied, we cannot request permissions.');
      }

      // 5. If permissions are granted, proceed with fetching position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      await FirebaseFirestore.instance
          .collection('rides')
          .doc(offer['id'])
          .update({
        'status': 'accepted',
        'driver_id': 'driver_demo_123',
        'driver_lat': position.latitude, // Initialize coordinates
        'driver_lng': position.longitude,
        'driver_heading': position.heading,
      });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DriverMapTrackingScreen(rideData: offer),
        ),
      );
    } catch (e) {
      debugPrint("Accept error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Available Rides", style: GoogleFonts.poppins()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchOffers, // Manual scan button
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : rideOffers.isEmpty
              ? _buildEmptyState()
              : Center(
                  child: TCard(
                    cards: _buildCards(),
                    controller: _controller,
                    size: const Size(360, 420),
                  ),
                ),
      // Task: Primary "Scan Again" button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: fetchOffers,
        label: const Text("Scan Again"),
        icon: const Icon(Icons.search),
        backgroundColor: Colors.orangeAccent,
      ),
    );
  }

  /// Creates the swipeable card widgets
  List<Widget> _buildCards() {
    return rideOffers.map((offer) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          children: [
            Text("Ride Request",
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 30),

            // Null-safe address tiles
            _infoTile(Icons.pin_drop, "Pickup",
                offer['pickup_name'] ?? "No pickup address"),
            _infoTile(
                Icons.flag, "Drop", offer['drop_name'] ?? "No drop address"),
            _infoTile(Icons.currency_rupee, "Fare", "₹${offer['fare'] ?? '0'}"),

            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => acceptRide(offer),
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text("Accept",
                      style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  onPressed: () =>
                      _controller.forward(direction: SwipDirection.Left),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text("Reject",
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            )
          ],
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_transfer, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          Text("No active rides found.",
              style: GoogleFonts.poppins(color: Colors.grey)),
          TextButton(
              onPressed: fetchOffers, child: const Text("Tap to refresh")),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          // Expanded prevents horizontal RenderFlex overflow
          Expanded(
            child: Text(
              "$label: $value",
              style: GoogleFonts.poppins(fontSize: 14),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
