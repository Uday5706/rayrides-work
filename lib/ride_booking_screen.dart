import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart'
    as polyline;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/payment_service.dart';
import '../services/user_service.dart';
import 'core/app_theme.dart';
import 'live_ride_tracking_screen.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  _RideBookingScreenState createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  int _requestedSeats = 1;
  List<Map<String, dynamic>> _availableSharedTrips = [];
  double _calculatedDistanceKm = 0.0;

  Position? _currentPosition;
  Set<Marker> _markers = {};
  LatLng? _dropLatLng;
  Map<PolylineId, Polyline> _polylines = {};
  List<LatLng> _polylineCoordinates = [];
  bool _isSearching = false;

  // 🟢 NEW: Tracks which field the map taps should update (Defaults to drop-off)
  bool _isSettingPickup = false;

  final PaymentService _paymentService = PaymentService();
  final UserService _userService = UserService();
  String? _currentUserId;
  double _riderRating = 5.0;
  bool _isLoadingProfile = true;

  final String _pickupId = "pickup_marker";
  final String _dropId = "drop_marker";

  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  final LatLng _defaultCenter = const LatLng(28.6139, 77.2090);

  late AnimationController _animController;
  late Animation<Offset> _slideTop;
  late Animation<Offset> _slideBottom;

  @override
  void initState() {
    super.initState();
    _determinePosition();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _slideTop =
        Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _slideBottom =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutExpo),
    );
    _animController.forward();

    themeNotifier.addListener(_updateMapStyle);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUserId = user.uid;
      _paymentService.initialize(_currentUserId!);
      _fetchRiderRating();
    } else {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_updateMapStyle);
    _animController.dispose();
    _paymentService.dispose();
    _pickupController.dispose();
    _dropController.dispose();
    super.dispose();
  }

  void _updateMapStyle() {
    if (_mapController == null) return;
    if (themeNotifier.value == ThemeMode.dark) {
      _mapController!.setMapStyle(
          '[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}]');
    } else {
      _mapController!.setMapStyle(null);
    }
  }

  Future<void> _fetchRiderRating() async {
    try {
      if (_currentUserId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            _riderRating = (doc.data()?['rating'] ?? 5.0).toDouble();
            _isLoadingProfile = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingProfile = false);
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
            isPickup ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
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
          color: AppTheme.deepForest,
          points: _polylineCoordinates,
          width: 5,
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

  // 🟢 NEW: Dynamically handles both Pickup and Drop taps based on the active state
  void _onMapTap(LatLng tappedPoint) async {
    String address = await _getAddressFromLatLng(
        tappedPoint.latitude, tappedPoint.longitude);

    setState(() {
      if (_isSettingPickup) {
        _pickupController.text = address;
        _currentPosition = Position(
            latitude: tappedPoint.latitude,
            longitude: tappedPoint.longitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0);
        _moveToPosition(tappedPoint, "Pickup Location", isPickup: true);
      } else {
        _dropLatLng = tappedPoint;
        _dropController.text = address;
        _moveToPosition(tappedPoint, "Drop Location", isPickup: false);
      }
    });
  }

  Future<void> _openCustomSearch(
      TextEditingController controller, bool isPickup) async {
    // Sync the active tap state with whichever modal was just opened
    setState(() => _isSettingPickup = isPickup);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          LocationSearchModal(isPickup: isPickup, apiKey: kGoogleApiKey),
    );

    if (result != null) {
      LatLng target = result['latlng'];
      String address = result['address'];

      setState(() {
        controller.text = address;
        if (isPickup) {
          _currentPosition = Position(
              latitude: target.latitude,
              longitude: target.longitude,
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
      _moveToPosition(target, address, isPickup: isPickup);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _searchSharedTrips() async {
    if (_dropController.text.isEmpty) {
      _showSnackBar("Please provide a drop location", Colors.orangeAccent);
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
        double distanceToDriver = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            data['current_lat'],
            data['current_lng']);

        if (distanceToDriver <= 5000) {
          double perKmRate = data['per_seat_fare_per_km'] ?? 12.0;
          data['calculated_fare'] =
              _calculatedDistanceKm * perKmRate * _requestedSeats;
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
        _showSnackBar("No shared rides available nearby", AppTheme.dustySage);
      } else {
        _showAvailableRidesSheet();
      }
    } catch (e) {
      setState(() => _isSearching = false);
      _showSnackBar("Error finding rides: $e", Colors.redAccent);
    }
  }

  Future<void> _bookSelectedTrip(Map<String, dynamic> tripData) async {
    final String tripId = tripData['trip_id'];
    if (_currentUserId == null) return;

    try {
      DocumentReference tripRef =
          FirebaseFirestore.instance.collection('shared_trips').doc(tripId);
      await tripRef.collection('passengers').doc(_currentUserId).set({
        'passenger_id': _currentUserId,
        'pickup_lat': _currentPosition!.latitude,
        'pickup_lng': _currentPosition!.longitude,
        'drop_lat': _dropLatLng!.latitude,
        'drop_lng': _dropLatLng!.longitude,
        'seats_booked': _requestedSeats,
        'fare': tripData['calculated_fare'],
        'status': 'pending_approval',
        'rider_rating': _riderRating,
        'created_at': FieldValue.serverTimestamp(),
      });

      _showSnackBar(
          "Request sent! Waiting for driver approval...", AppTheme.mutedPine);

      if (mounted) {
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (context) => LiveRideTrackingScreen(rideData: {
                      'trip_id': tripId,
                      'passenger_id': _currentUserId,
                      'driver_name': tripData['driver_name'],
                      'vehicle_number':
                          tripData['vehicle_number'] ?? "Carpool Vehicle",
                      'pickup_lat': _currentPosition!.latitude,
                      'pickup_lng': _currentPosition!.longitude,
                      'drop_lat': _dropLatLng!.latitude,
                      'drop_lng': _dropLatLng!.longitude,
                      'fare': tripData['calculated_fare'],
                      'seats_booked': _requestedSeats,
                      'current_lat': tripData['current_lat'],
                      'current_lng': tripData['current_lng'],
                    })));
      }
    } catch (e) {
      _showSnackBar("Booking failed: $e", Colors.redAccent);
    }
  }

  void _showAvailableRidesSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.deepForest : AppTheme.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text("Available Rides",
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.white : AppTheme.deepForest)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _availableSharedTrips.length,
                  itemBuilder: (context, index) {
                    var trip = _availableSharedTrips[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A5240)
                            : AppTheme.softMint.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isDark ? AppTheme.deepForest : AppTheme.white,
                          child: const Icon(Icons.directions_car,
                              color: AppTheme.mutedPine),
                        ),
                        title: Text("${trip['driver_name']}",
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            "${trip['distance_away']} km away • Seats left: ${trip['available_seats']}"),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                "₹${trip['calculated_fare'].toStringAsFixed(0)}",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppTheme.mutedPine)),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _bookSelectedTrip(trip);
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.mutedPine),
                              child: const Text("Book"),
                            )
                          ],
                        ),
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
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _defaultCenter, zoom: 13.0),
            onMapCreated: (controller) {
              _mapController = controller;
              _updateMapStyle();
            },
            markers: _markers,
            polylines: Set<Polyline>.of(_polylines.values),
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          _buildFloatingControls(),
          _buildBottomOverlay(),
          if (_isSearching)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.mutedPine)),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingControls() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: SlideTransition(
        position: _slideTop,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGlassButton(
                Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, child) {
                final isDark = currentMode == ThemeMode.dark;
                return _buildGlassButton(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    () => themeNotifier.value =
                        isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassButton(IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.deepForest.withOpacity(0.7)
                : AppTheme.white.withOpacity(0.8),
            shape: BoxShape.circle,
            border: Border.all(
                color: isDark
                    ? AppTheme.dustySage.withOpacity(0.3)
                    : AppTheme.softMint,
                width: 1),
          ),
          child: IconButton(
            icon: Icon(icon,
                color: isDark ? AppTheme.softMint : AppTheme.deepForest),
            onPressed: onTap,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    if (_currentUserId == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideBottom,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.deepForest.withOpacity(0.95)
                : AppTheme.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: isDark
                    ? AppTheme.mutedPine.withOpacity(0.3)
                    : Colors.transparent,
                width: 1),
            boxShadow: [
              BoxShadow(
                  color: isDark
                      ? Colors.black45
                      : AppTheme.dustySage.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 10))
            ],
          ),
          child: _isLoadingProfile
              ? const SizedBox(
                  height: 100,
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.mutedPine)))
              : StreamBuilder<double>(
                  stream: _userService.streamNegativeBalance(_currentUserId!),
                  builder: (context, snapshot) {
                    final double currentNegativeBalance = snapshot.data ?? 0.0;
                    return currentNegativeBalance > 0
                        ? _buildPenaltyUI(currentNegativeBalance, isDark)
                        : _buildNormalBookingUI(isDark);
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildPenaltyUI(double balance, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 48),
        const SizedBox(height: 12),
        Text("Account Restricted",
            style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent)),
        const SizedBox(height: 8),
        Text("You have an unpaid penalty of ₹${balance.toStringAsFixed(0)}.",
            style: GoogleFonts.poppins(
                color: isDark ? AppTheme.white : AppTheme.deepForest)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            onPressed: () => _paymentService.initiateClearBalance(),
            child: Text("PAY ₹${balance.toStringAsFixed(0)} TO UNLOCK",
                style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  // 🟢 NEW: Reusable row builder for selecting locations with active state
  Widget _buildLocationRow(bool isPickup, String title, String value,
      IconData icon, Color iconColor, bool isDark) {
    bool isActive = _isSettingPickup == isPickup;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? (isDark
                ? AppTheme.white.withOpacity(0.1)
                : AppTheme.white.withOpacity(0.6))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? (isDark
                  ? AppTheme.softMint.withOpacity(0.3)
                  : AppTheme.mutedPine.withOpacity(0.3))
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _isSettingPickup = isPickup);
                _openCustomSearch(
                    isPickup ? _pickupController : _dropController, isPickup);
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value.isEmpty ? title : value,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: isActive || value.isNotEmpty
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: value.isEmpty
                              ? AppTheme.dustySage
                              : (isDark ? AppTheme.white : AppTheme.deepForest),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.touch_app_rounded,
              color: isActive
                  ? AppTheme.mutedPine
                  : AppTheme.dustySage.withOpacity(0.5),
              size: 20,
            ),
            tooltip: "Select on Map",
            onPressed: () {
              setState(() => _isSettingPickup = isPickup);
              _showSnackBar(
                  "Tap on the map to set ${isPickup ? 'Pickup' : 'Drop-off'} location",
                  AppTheme.mutedPine);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBookingUI(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2A5240)
                : AppTheme.softMint.withOpacity(0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isDark
                    ? AppTheme.dustySage.withOpacity(0.2)
                    : Colors.transparent),
          ),
          child: Column(
            children: [
              // 🟢 Uses the new active-state rows!
              _buildLocationRow(
                  true,
                  "Current Location",
                  _pickupController.text,
                  Icons.trip_origin,
                  AppTheme.mutedPine,
                  isDark),

              Padding(
                padding: const EdgeInsets.only(left: 19.0),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                        height: 16,
                        width: 2,
                        color: AppTheme.dustySage.withOpacity(0.5))),
              ),

              _buildLocationRow(false, "Where to?", _dropController.text,
                  Icons.location_on, Colors.blueAccent, isDark),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Seats Required",
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.white : AppTheme.deepForest)),
            Container(
              decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A5240)
                      : AppTheme.softMint.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(30)),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.remove,
                        color: isDark ? AppTheme.white : AppTheme.deepForest,
                        size: 20),
                    onPressed: () => setState(() {
                      if (_requestedSeats > 1) _requestedSeats--;
                    }),
                  ),
                  Text("$_requestedSeats",
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? AppTheme.white : AppTheme.deepForest)),
                  IconButton(
                    icon: Icon(Icons.add,
                        color: isDark ? AppTheme.white : AppTheme.deepForest,
                        size: 20),
                    onPressed: () => setState(() {
                      if (_requestedSeats < 6) _requestedSeats++;
                    }),
                  ),
                ],
              ),
            )
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.mutedPine,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
            onPressed: _searchSharedTrips,
            child: Text("FIND SHARED RIDES",
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
        )
      ],
    );
  }
}

// 🟢 BULLETPROOF, STATE-PRESERVING SEARCH MODAL WIDGET
class LocationSearchModal extends StatefulWidget {
  final bool isPickup;
  final String apiKey;

  const LocationSearchModal(
      {super.key, required this.isPickup, required this.apiKey});

  @override
  State<LocationSearchModal> createState() => _LocationSearchModalState();
}

class _LocationSearchModalState extends State<LocationSearchModal> {
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

      if (data['status'] == 'OK') {
        final lat = data['result']['geometry']['location']['lat'];
        final lng = data['result']['geometry']['location']['lng'];
        if (mounted) {
          Navigator.pop(context, {
            'latlng': LatLng(lat, lng),
            'address': description,
          });
        }
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
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
            child: Text(widget.isPickup ? "Set Pickup Location" : "Where to?",
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
