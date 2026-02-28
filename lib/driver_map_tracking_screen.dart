import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rayride/nav_bar.dart';
import 'package:rayride/services/driver_socket_service.dart';

class DriverMapTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;
  const DriverMapTrackingScreen({super.key, required this.rideData});

  @override
  State<DriverMapTrackingScreen> createState() =>
      _DriverMapTrackingScreenState();
}

class _DriverMapTrackingScreenState extends State<DriverMapTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  final DriverSocketService _socketService = DriverSocketService();
  final String googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  LatLng? _lastRouteUpdatePos;

  // --- SAFE VARIABLES ---
  late String _rideId;
  late LatLng _pickupPos;
  late LatLng _dropPos;

  // --- LOGIC VARIABLES ---
  StreamSubscription<DocumentSnapshot>? _rideStatusSubscription;
  String _rideStatus = "accepted";
  double _carbonSaved = 0.0;
  late LatLng _driverStartPos;
  bool _isStartPosSet = false;

  // --- ANIMATION VARIABLES ---
  late AnimationController _animController;
  LatLng _currentVisualPos = const LatLng(0, 0);
  double _currentVisualHeading = 0.0;
  LatLng _oldPos = const LatLng(0, 0);
  LatLng _newPos = const LatLng(0, 0);
  double _oldHeading = 0.0;
  double _newHeading = 0.0;

  @override
  void initState() {
    super.initState();

    // 1. SAFE ID EXTRACTION
    _rideId = widget.rideData['rideId'] ?? widget.rideData['id'] ?? "";

    // 2. SAFE COORDINATE EXTRACTION (Fixes 'Null is not subtype of double')
    _pickupPos = LatLng(
      _parseDouble(widget.rideData['pickup_lat']),
      _parseDouble(widget.rideData['pickup_lng']),
    );
    _dropPos = LatLng(
      _parseDouble(widget.rideData['drop_lat']),
      _parseDouble(widget.rideData['drop_lng']),
    );

    if (_rideId.isEmpty) {
      debugPrint("❌ ERROR: Ride ID is missing!");
    }

    _loadMarkerIcon();

    if (_rideId.isNotEmpty) {
      _socketService.connect(_rideId);
      _listenForRideStatusChanges();
    }

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..addListener(() {
        final t = _animController.value;
        if (mounted) {
          setState(() {
            _currentVisualPos = LatLng(
              ui.lerpDouble(_oldPos.latitude, _newPos.latitude, t)!,
              ui.lerpDouble(_oldPos.longitude, _newPos.longitude, t)!,
            );
            _currentVisualHeading = ui.lerpDouble(_oldHeading, _newHeading, t)!;
            _updateMarkers();
          });
        }
      });

    _startLocationTracking();
  }

  // --- HELPER: Safely convert any value to double ---
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void dispose() {
    _rideStatusSubscription?.cancel();
    _socketService.disconnect();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveCarbonEmission() async {
    try {
      await FirebaseFirestore.instance.collection('rides').doc(_rideId).update({
        'carbon_saved_kg': _carbonSaved,
        'completed_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Carbon save error: $e");
    }
  }

  void _startLocationTracking() async {
    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      _driverStartPos =
          LatLng(initialPosition.latitude, initialPosition.longitude);
      _isStartPosSet = true;

      if (mounted) {
        setState(() {
          _currentVisualPos = _driverStartPos;
          _currentVisualHeading = initialPosition.heading;
          _oldPos = _currentVisualPos;
          _newPos = _currentVisualPos;

          _updateMarkers();
          _updateRoutesAndCarbon(_currentVisualPos);
        });
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (!mounted) return;
      if (_rideId.isEmpty) return;

      LatLng newPos = LatLng(position.latitude, position.longitude);

      _socketService.sendLocation(
        position.latitude,
        position.longitude,
        position.heading,
        _rideId,
      );

      _animateCar(newPos, position.heading);
      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
      _throttledRouteUpdate(newPos);
    });
  }

  void _animateCar(LatLng destPos, double destHeading) {
    _oldPos = _currentVisualPos;
    _oldHeading = _currentVisualHeading;
    _newPos = destPos;
    _newHeading = destHeading;

    if ((_newHeading - _oldHeading).abs() > 180) {
      if (_newHeading > _oldHeading)
        _oldHeading += 360;
      else
        _newHeading += 360;
    }
    _animController.forward(from: 0.0);
  }

  void _throttledRouteUpdate(LatLng currentPos) {
    if (_lastRouteUpdatePos == null) {
      _lastRouteUpdatePos = currentPos;
      _updateRoutesAndCarbon(currentPos);
      return;
    }
    double distance = Geolocator.distanceBetween(
      _lastRouteUpdatePos!.latitude,
      _lastRouteUpdatePos!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    _calculateCarbon(currentPos);

    if (distance > 50) {
      _lastRouteUpdatePos = currentPos;
      _updateRoutesAndCarbon(currentPos);
    }
  }

  void _calculateCarbon(LatLng currentPos) {
    if (!_isStartPosSet) return;

    double totalDist = 0.0;
    if (_rideStatus == "accepted") {
      totalDist = Geolocator.distanceBetween(
        _driverStartPos.latitude,
        _driverStartPos.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
    } else {
      double approach = Geolocator.distanceBetween(
        _driverStartPos.latitude,
        _driverStartPos.longitude,
        _pickupPos.latitude,
        _pickupPos.longitude,
      );
      double trip = Geolocator.distanceBetween(
        _pickupPos.latitude,
        _pickupPos.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
      totalDist = approach + trip;
    }

    if (mounted) {
      setState(() {
        _carbonSaved = (totalDist / 1000) * 0.4;
      });
    }
  }

  void _listenForRideStatusChanges() {
    if (_rideId.isEmpty) return;

    _rideStatusSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(_rideId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data() as Map<String, dynamic>;
      final status = data['status'];

      /// 🚨 RIDE CANCELLED BEFORE START
      if (status == 'cancelled' && _rideStatus == "accepted") {
        await _showCancelledScreen();
        Navigator.pop(context);
      }

      /// 🏁 RIDE ENDED
      if (status == 'ended') {
        await _saveCarbonEmission();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Ride Completed Successfully"),
              backgroundColor: Colors.blue),
        );
        mainNavController.index = 1;
      }
    });
  }

  Future<void> _updateRoutesAndCarbon(LatLng driverPos) async {
    // If coordinates are invalid (0.0), don't fetch route
    if (_pickupPos.latitude == 0 || _dropPos.latitude == 0) return;

    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    Set<Polyline> newPolylines = {};

    if (_rideStatus == "accepted") {
      // 1. Red Line (Shrinking): Driver -> Pickup
      PolylineResult toPickup = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(driverPos.latitude, driverPos.longitude),
          destination: PointLatLng(_pickupPos.latitude, _pickupPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      // 2. Blue Line (Static): Pickup -> Drop
      PolylineResult toDrop = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(_pickupPos.latitude, _pickupPos.longitude),
          destination: PointLatLng(_dropPos.latitude, _dropPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (toPickup.points.isNotEmpty) {
        newPolylines.add(Polyline(
          polylineId: const PolylineId("to_pickup"),
          points: toPickup.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.red,
          width: 5,
        ));
      }
      if (toDrop.points.isNotEmpty) {
        newPolylines.add(Polyline(
          polylineId: const PolylineId("to_drop"),
          points: toDrop.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.blue,
          width: 5,
        ));
      }
    } else if (_rideStatus == "in_progress") {
      // 1. Blue Line (Shrinking): Driver -> Drop
      PolylineResult toDrop = await polylinePoints.getRouteBetweenCoordinates(
        request: PolylineRequest(
          origin: PointLatLng(driverPos.latitude, driverPos.longitude),
          destination: PointLatLng(_dropPos.latitude, _dropPos.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (toDrop.points.isNotEmpty) {
        newPolylines.add(Polyline(
          polylineId: const PolylineId("to_drop"),
          points: toDrop.points
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList(),
          color: Colors.blue,
          width: 5,
        ));
      }
    }

    if (mounted) {
      setState(() {
        _polylines = newPolylines;
      });
    }
  }

  void _updateMarkers() {
    // Only show markers if they have valid coordinates
    if (_pickupPos.latitude == 0 || _dropPos.latitude == 0) return;

    _markers = {
      Marker(
        markerId: const MarkerId("pickup"),
        position: _pickupPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      Marker(
        markerId: const MarkerId("drop"),
        position: _dropPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId("driver"),
        position: _currentVisualPos,
        rotation: _currentVisualHeading,
        icon: _carIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        flat: true,
      ),
    };
  }

  Future<void> _loadMarkerIcon() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double size = 120.0;
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.directions_car_filled.codePoint),
      style: TextStyle(
          fontSize: size,
          fontFamily: Icons.directions_car_filled.fontFamily,
          color: Colors.blue),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 0));
    final image = await pictureRecorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    setState(() =>
        _carIcon = BitmapDescriptor.fromBytes(data!.buffer.asUint8List()));
  }

  void _showOtpDialog() {
    final TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enter Start OTP"),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(hintText: "Enter 4-digit code"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => _verifyOtp(otpController.text),
            child: const Text("Verify & Start"),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyOtp(String enteredOtp) async {
    if (enteredOtp == widget.rideData['otp'].toString()) {
      try {
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(_rideId)
            .update({'status': 'in_progress'});

        if (!mounted) return;
        Navigator.pop(context);

        setState(() {
          _rideStatus = "in_progress";
        });

        _updateRoutesAndCarbon(_currentVisualPos);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Trip Started! Drive safely."),
              backgroundColor: Colors.green),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Invalid OTP"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(_rideStatus == "accepted"
              ? "Navigate to Pickup"
              : "Navigate to Drop")),
      body: _currentVisualPos.latitude == 0
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _currentVisualPos, zoom: 16),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) => _mapController = controller,
                ),

                // Carbon Emission Display
                Positioned(
                  top: 20,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.green[800],
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      "🌱 Saved: ${_carbonSaved.toStringAsFixed(2)} kg",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _rideStatus == "accepted"
          ? FloatingActionButton.extended(
              onPressed: _showOtpBottomSheet,
              label: const Text("START TRIP",
                  style: TextStyle(color: Colors.white)),
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              backgroundColor: Colors.green,
            )
          : null,
    );
  }

  void _showOtpBottomSheet() {
    final TextEditingController otpController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 30,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enter Ride OTP",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              /// OTP BOXES
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: "",
                  filled: true,
                  fillColor: Colors.grey[200],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => _verifyOtp(otpController.text),
                  child: const Text(
                    "START TRIP",
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCancelledScreen() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.cancel, color: Colors.red, size: 70),
              SizedBox(height: 20),
              Text(
                "OOPS!",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text(
                "The ride was cancelled by the rider.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
