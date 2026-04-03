import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🟢 Required for Profile Checks
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';
import 'package:flutter_google_places_hoc081098/google_maps_webservice_places.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart'
    as polyline;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/places.dart' as gm_webservice;

import 'live_ride_tracking_screen.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  _RideBookingScreenState createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  int _requestedSeats = 1;
  List<Map<String, dynamic>> _availableSharedTrips = [];
  double _calculatedDistanceKm = 0.0;

  String _locationStatus = "Detecting current location...";
  Position? _currentPosition;
  Set<Marker> _markers = {};
  LatLng? _dropLatLng;
  Map<PolylineId, Polyline> _polylines = {};
  List<LatLng> _polylineCoordinates = [];
  bool _isSearching = false;

  // 🟢 NEW: Rider Profile State
  double _negativeBalance = 0.0;
  double _riderRating = 5.0;
  bool _isLoadingProfile = true;

  final String _pickupId = "pickup_marker";
  final String _dropId = "drop_marker";

  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  final LatLng _defaultCenter = const LatLng(28.6139, 77.2090);

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _fetchRiderProfile(); // 🟢 Fetch penalties and ratings on load
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 🟢 NEW: Fetch the user's profile to check for penalties
  Future<void> _fetchRiderProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _negativeBalance =
                (doc.data()?['negative_balance'] ?? 0.0).toDouble();
            _riderRating = (doc.data()?['rating'] ?? 5.0).toDouble();
            _isLoadingProfile = false;
          });
        } else {
          if (mounted) setState(() => _isLoadingProfile = false);
        }
      } else {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  // 🟢 NEW: Simulated Payment function to clear penalty
  Future<void> _payPenalty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Simulate calling Razorpay/Stripe here, then clear the database flag
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'negative_balance': 0.0,
      });

      setState(() {
        _negativeBalance = 0.0;
      });

      _showSnackBar("Penalty paid! You can now book rides.", Colors.green);
    } catch (e) {
      _showSnackBar("Payment failed. Please try again.", Colors.red);
    }
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    _currentPosition = position;

    String address =
        await _getAddressFromLatLng(position.latitude, position.longitude);

    setState(() {
      _locationStatus = "Location Detected";
      _pickupController.text = address;
      _moveToPosition(LatLng(position.latitude, position.longitude), "Pickup",
          isPickup: true);
    });
  }

  Future<String> _getAddressFromLatLng(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      Placemark place = placemarks[0];
      return "${place.name}, ${place.subLocality}, ${place.locality}";
    } catch (e) {
      return "Point ($lat, $lng)";
    }
  }

  void _moveToPosition(LatLng target, String title, {required bool isPickup}) {
    String mId = isPickup ? _pickupId : _dropId;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == mId);
      _markers.add(
        Marker(
          markerId: MarkerId(mId),
          position: target,
          infoWindow: InfoWindow(title: title),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isPickup ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed),
        ),
      );
    });

    if (_currentPosition != null && _dropLatLng != null) {
      _getRoute();
    }
  }

  Future<void> _getRoute() async {
    polyline.PolylinePoints polylinePoints =
        polyline.PolylinePoints(apiKey: kGoogleApiKey);
    polyline.PolylineResult result =
        await polylinePoints.getRouteBetweenCoordinates(
      request: polyline.PolylineRequest(
        origin: polyline.PointLatLng(
            _currentPosition!.latitude, _currentPosition!.longitude),
        destination:
            polyline.PointLatLng(_dropLatLng!.latitude, _dropLatLng!.longitude),
        mode: polyline.TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      for (var point in result.points) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }

      _calculatedDistanceKm = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              _dropLatLng!.latitude,
              _dropLatLng!.longitude) /
          1000;

      setState(() {
        _polylines[const PolylineId("ride_route")] = Polyline(
          polylineId: const PolylineId("ride_route"),
          color: Colors.blueAccent,
          points: _polylineCoordinates,
          width: 6,
          jointType: JointType.round,
        );
      });
      _zoomToFit();
    }
  }

  void _zoomToFit() {
    if (_mapController == null ||
        _currentPosition == null ||
        _dropLatLng == null) return;

    LatLng p1 = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    LatLng p2 = _dropLatLng!;
    LatLngBounds bounds;

    if (p1.latitude > p2.latitude && p1.longitude > p2.longitude) {
      bounds = LatLngBounds(southwest: p2, northeast: p1);
    } else if (p1.longitude > p2.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p1.latitude, p2.longitude),
          northeast: LatLng(p2.latitude, p1.longitude));
    } else if (p1.latitude > p2.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p2.latitude, p1.longitude),
          northeast: LatLng(p1.latitude, p2.longitude));
    } else {
      bounds = LatLngBounds(southwest: p1, northeast: p2);
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _onMapTap(LatLng tappedPoint) async {
    setState(() => _dropLatLng = tappedPoint);
    String address = await _getAddressFromLatLng(
        tappedPoint.latitude, tappedPoint.longitude);
    setState(() => _dropController.text = address);
    _moveToPosition(tappedPoint, "Drop Location", isPickup: false);
  }

  Future<void> _handleAutocomplete(
      TextEditingController controller, bool isPickup) async {
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
      LatLng target = LatLng(lat, lng);

      setState(() {
        controller.text = p.description!;
        if (isPickup) {
          _currentPosition = Position(
              latitude: lat,
              longitude: lng,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0);
        } else {
          _dropLatLng = target;
        }
      });
      _moveToPosition(target, p.description!, isPickup: isPickup);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _searchSharedTrips() async {
    if (_dropController.text.isEmpty) {
      _showSnackBar("Please provide drop location", Colors.red);
      return;
    }

    setState(() => _isSearching = true);

    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('shared_trips')
          .where('status', isEqualTo: 'active')
          .where('available_seats', isGreaterThanOrEqualTo: _requestedSeats)
          .get();

      List<Map<String, dynamic>> validTrips = [];

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;

        double driverLat = data['current_lat'];
        double driverLng = data['current_lng'];

        double distanceToDriver = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            driverLat,
            driverLng);

        if (distanceToDriver <= 5000) {
          double perKmRate = data['per_seat_fare_per_km'] ?? 12.0;
          double calculatedFare =
              _calculatedDistanceKm * perKmRate * _requestedSeats;

          data['calculated_fare'] = calculatedFare;
          data['trip_id'] = doc.id;
          data['distance_away'] = (distanceToDriver / 1000).toStringAsFixed(1);

          validTrips.add(data);
        }
      }

      setState(() {
        _isSearching = false;
        _availableSharedTrips = validTrips;
      });

      if (validTrips.isEmpty) {
        _showSnackBar("No shared rides available nearby", Colors.orange);
      } else {
        _showAvailableRidesSheet();
      }
    } catch (e) {
      setState(() => _isSearching = false);
      _showSnackBar("Error finding rides: $e", Colors.red);
    }
  }

  // 🟢 UPDATED: Booking Logic now uses pending_approval and attaches Rating
  Future<void> _bookSelectedTrip(Map<String, dynamic> tripData) async {
    final String tripId = tripData['trip_id'];

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("Please log in first", Colors.red);
      return;
    }
    final String passId = user.uid; // 🟢 We now strictly use the UID

    try {
      // 🟢 1. No atomic transaction deducting seats here!
      // We just push the document with a 'pending_approval' flag.
      DocumentReference tripRef =
          FirebaseFirestore.instance.collection('shared_trips').doc(tripId);
      DocumentReference passengerRef =
          tripRef.collection('passengers').doc(passId);

      await passengerRef.set({
        'passenger_id': passId,
        'pickup_lat': _currentPosition!.latitude,
        'pickup_lng': _currentPosition!.longitude,
        'drop_lat': _dropLatLng!.latitude,
        'drop_lng': _dropLatLng!.longitude,
        'seats_booked': _requestedSeats,
        'fare': tripData['calculated_fare'],
        'status': 'pending_approval', // Driver must accept this
        'rider_rating': _riderRating, // Driver sees this before accepting
        'created_at': FieldValue.serverTimestamp(),
      });

      _showSnackBar(
          "Request sent! Waiting for driver approval...", Colors.green);

      if (mounted) {
        Map<String, dynamic> ridePayload = {
          'trip_id': tripId,
          'passenger_id': passId,
          'driver_name': tripData['driver_name'],
          'vehicle_number': tripData['vehicle_number'] ?? "Carpool Vehicle",
          'pickup_lat': _currentPosition!.latitude,
          'pickup_lng': _currentPosition!.longitude,
          'drop_lat': _dropLatLng!.latitude,
          'drop_lng': _dropLatLng!.longitude,
          'fare': tripData['calculated_fare'],
          'seats_booked': _requestedSeats,
          'current_lat': tripData['current_lat'],
          'current_lng': tripData['current_lng'],
          'current_heading': tripData['current_heading'],
        };

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LiveRideTrackingScreen(rideData: ridePayload),
          ),
        );
      }
    } catch (e) {
      _showSnackBar("Booking failed: $e", Colors.red);
    }
  }

  void _showAvailableRidesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("Available Rides",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _availableSharedTrips.length,
                  itemBuilder: (context, index) {
                    var trip = _availableSharedTrips[index];
                    return ListTile(
                      leading:
                          const CircleAvatar(child: Icon(Icons.directions_car)),
                      title: Text(
                          "${trip['driver_name']} • ${trip['distance_away']} km away"),
                      subtitle: Text("Seats left: ${trip['available_seats']}"),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("₹${trip['calculated_fare'].toStringAsFixed(0)}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.green)),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _bookSelectedTrip(trip);
                            },
                            child: const Text("Book"),
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _defaultCenter, zoom: 13.0),
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers,
            polylines: Set<Polyline>.of(_polylines.values),
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),
          _buildTopOverlay(),

          // 🟢 Conditionally show the booking tools or the penalty block
          _buildBottomOverlay(),

          if (_isSearching)
            const Center(
                child: CircularProgressIndicator(color: Colors.orangeAccent)),
        ],
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Column(
        children: [
          _buildSearchBox(
              "Pickup",
              _pickupController,
              () => _handleAutocomplete(_pickupController, true),
              Icons.circle,
              Colors.blueAccent),
          const SizedBox(height: 10),
          _buildSearchBox(
              "Where to?",
              _dropController,
              () => _handleAutocomplete(_dropController, false),
              Icons.location_on,
              Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 20)
            ]),

        // 🟢 Check if loading, blocked by penalty, or normal
        child: _isLoadingProfile
            ? const SizedBox(
                height: 100, child: Center(child: CircularProgressIndicator()))
            : _negativeBalance > 0
                ? _buildPenaltyUI()
                : _buildNormalBookingUI(),
      ),
    );
  }

  // 🟢 NEW: Penalty UI
  Widget _buildPenaltyUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 40),
        const SizedBox(height: 10),
        const Text("Booking Blocked",
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
        const SizedBox(height: 5),
        Text(
            "You have an unpaid penalty of ₹${_negativeBalance.toStringAsFixed(0)} for making a driver wait.",
            textAlign: TextAlign.center),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: _payPenalty,
            child: Text("Pay ₹${_negativeBalance.toStringAsFixed(0)} to Unlock",
                style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        )
      ],
    );
  }

  Widget _buildNormalBookingUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Seats Required:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                    if (_requestedSeats > 1) _requestedSeats--;
                  }),
                ),
                Text("$_requestedSeats",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() {
                    if (_requestedSeats < 6) _requestedSeats++;
                  }),
                ),
              ],
            )
          ],
        ),
        const SizedBox(height: 15),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: _searchSharedTrips,
            child: const Text("Find Shared Rides",
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ),
        )
      ],
    );
  }

  Widget _buildSearchBox(String hint, TextEditingController controller,
      VoidCallback onTap, IconData prefixIcon, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: TextField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon, color: iconColor, size: 18),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15)),
      ),
    );
  }
}
