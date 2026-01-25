import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rayride/services/driver_socket_service.dart';

class DriverMapTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;
  const DriverMapTrackingScreen({super.key, required this.rideData});

  @override
  State<DriverMapTrackingScreen> createState() =>
      _DriverMapTrackingScreenState();
}

// 1. Add Mixin for Animation
class _DriverMapTrackingScreenState extends State<DriverMapTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // Logic variables
  final DriverSocketService _socketService = DriverSocketService();
  final String googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  LatLng? _lastRouteUpdatePos; // To throttle API calls

  // --- SMOOTH ANIMATION VARIABLES ---
  late AnimationController _animController;
  LatLng _currentVisualPos = const LatLng(0, 0);
  double _currentVisualHeading = 0.0;

  LatLng _oldPos = const LatLng(0, 0);
  LatLng _newPos = const LatLng(0, 0);
  double _oldHeading = 0.0;
  double _newHeading = 0.0;
  // ----------------------------------

  @override
  void initState() {
    super.initState();
    _loadMarkerIcon();
    _socketService.connect(widget.rideData['rideId']);

    // 2. Setup Animation Controller
    // Duration matches typical GPS update interval (approx 1-2 sec)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..addListener(() {
        final t = _animController.value;
        if (mounted) {
          setState(() {
            // Interpolate Position
            _currentVisualPos = LatLng(
              ui.lerpDouble(_oldPos.latitude, _newPos.latitude, t)!,
              ui.lerpDouble(_oldPos.longitude, _newPos.longitude, t)!,
            );
            // Interpolate Heading
            _currentVisualHeading = ui.lerpDouble(_oldHeading, _newHeading, t)!;

            // Update markers continuously as animation plays
            _updateMarkers();
          });
        }
      });

    _startLocationTracking();
  }

  @override
  void dispose() {
    _socketService.disconnect();
    _animController.dispose();
    super.dispose();
  }

  void _startLocationTracking() async {
    // A. Get First Fix Immediately (No Animation)
    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      if (mounted) {
        setState(() {
          _currentVisualPos =
              LatLng(initialPosition.latitude, initialPosition.longitude);
          _currentVisualHeading = initialPosition.heading;

          // Set animation start/end to current to avoid jumps
          _oldPos = _currentVisualPos;
          _newPos = _currentVisualPos;

          _updateMarkers();
          _drawRoutes(_currentVisualPos);
        });
      }
    } catch (e) {
      debugPrint("Could not get initial position: $e");
    }

    // B. Listen for Updates
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (!mounted) return;

      LatLng newPos = LatLng(position.latitude, position.longitude);

      // 1. Send to Socket (Rider sees this)
      _socketService.sendLocation(
        position.latitude,
        position.longitude,
        position.heading,
        widget.rideData['rideId'],
      );

      // 2. Animate Driver's Own Map (Driver sees this)
      _animateCar(newPos, position.heading);

      // 3. Move Camera smoothly
      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));

      // 4. Update Route (Throttled)
      _throttledRouteUpdate(newPos);
    });
  }

  void _animateCar(LatLng destPos, double destHeading) {
    _oldPos = _currentVisualPos;
    _oldHeading = _currentVisualHeading;

    _newPos = destPos;
    _newHeading = destHeading;

    // Fix Rotation Wrapping
    if ((_newHeading - _oldHeading).abs() > 180) {
      if (_newHeading > _oldHeading)
        _oldHeading += 360;
      else
        _newHeading += 360;
    }

    _animController.forward(from: 0.0);
  }

  // --- Optimization: Don't call Google API every 2 seconds ---
  void _throttledRouteUpdate(LatLng currentPos) {
    if (_lastRouteUpdatePos == null) {
      _lastRouteUpdatePos = currentPos;
      _drawRoutes(currentPos);
      return;
    }
    double distance = Geolocator.distanceBetween(
      _lastRouteUpdatePos!.latitude,
      _lastRouteUpdatePos!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );
    // Only redraw route if moved 50 meters
    if (distance > 50) {
      _lastRouteUpdatePos = currentPos;
      _drawRoutes(currentPos);
    }
  }

  // Task 2: Paint the two routes
  Future<void> _drawRoutes(LatLng driverPos) async {
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    LatLng pickup =
        LatLng(widget.rideData['pickup_lat'], widget.rideData['pickup_lng']);
    LatLng drop =
        LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng']);

    // 1. Driver to Pickup (RED)
    PolylineResult toPickup = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(driverPos.latitude, driverPos.longitude),
        destination: PointLatLng(pickup.latitude, pickup.longitude),
        mode: TravelMode.driving,
      ),
    );

    // 2. Pickup to Drop (BLUE)
    PolylineResult toDrop = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(pickup.latitude, pickup.longitude),
        destination: PointLatLng(drop.latitude, drop.longitude),
        mode: TravelMode.driving,
      ),
    );

    if (mounted) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("to_pickup"),
            points: toPickup.points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            color: Colors.red,
            width: 5,
          ),
          Polyline(
            polylineId: const PolylineId("to_drop"),
            points: toDrop.points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            color: Colors.blue,
            width: 5,
          ),
        };
      });
    }
  }

  // Use the animated position for the marker
  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId("pickup"),
        position: LatLng(
            widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      Marker(
        markerId: const MarkerId("drop"),
        position:
            LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng']),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId("driver"),
        // VISUAL POS used here
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
        color: Colors.blue,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0, 0));

    final image = await pictureRecorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    setState(() {
      _carIcon = BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
    });
  }

  // ... [Keep _showOtpDialog, _verifyOtp, _showSnackBar same as before] ...
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
          decoration:
              const InputDecoration(hintText: "Enter 4-digit code from rider"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
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
            .doc(widget.rideData['id'])
            .update({'status': 'in_progress'});
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        _showSnackBar("Trip Started! Drive safely.", Colors.green);
        setState(() {
          _polylines
              .removeWhere((p) => p.polylineId.value == "driver_to_pickup");
        });
      } catch (e) {
        if (!mounted) return;
        _showSnackBar("Error: $e", Colors.red);
      }
    } else {
      if (!mounted) return;
      _showSnackBar("Invalid OTP", Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Navigate to Pickup")),
      body: _currentVisualPos.latitude == 0
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  // Use visual pos for camera target too if you want it to follow smoothly
                  initialCameraPosition:
                      CameraPosition(target: _currentVisualPos, zoom: 16),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) => _mapController = controller,
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showOtpDialog,
        label: const Text("START TRIP"),
        icon: const Icon(Icons.play_arrow),
        backgroundColor: Colors.green,
      ),
    );
  }
}
