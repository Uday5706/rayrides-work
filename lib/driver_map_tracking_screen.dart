import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rayride/services/driver_socket_service.dart'; // Import your socket service

class DriverMapTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> rideData;
  const DriverMapTrackingScreen({super.key, required this.rideData});

  @override
  State<DriverMapTrackingScreen> createState() =>
      _DriverMapTrackingScreenState();
}

class _DriverMapTrackingScreenState extends State<DriverMapTrackingScreen> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _carIcon;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  LatLng? _driverLatLng;

  // 1. Initialize Socket Service
  final DriverSocketService _socketService = DriverSocketService();

  final String googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  @override
  void initState() {
    super.initState();
    _loadMarkerIcon();

    // 2. Connect to the socket room immediately
    // ensure 'rideId' exists in your rideData map
    _socketService.connect(widget.rideData['rideId']);

    _startLocationTracking();
  }

  @override
  void dispose() {
    // 3. Clean up connection when leaving screen
    _socketService.disconnect();
    super.dispose();
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
    // Check type consistency (String vs Int)
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

  void _startLocationTracking() async {
    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        _driverLatLng =
            LatLng(initialPosition.latitude, initialPosition.longitude);
        _updateMarkers(initialPosition);
        _drawRoutes(_driverLatLng!);
      });
    } catch (e) {
      debugPrint("Could not get initial position: $e");
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (!mounted) return;

      LatLng newPos = LatLng(position.latitude, position.longitude);

      // --- CRITICAL CHANGE: Socket Emit instead of Firestore Write ---
      _socketService.sendLocation(
        position.latitude,
        position.longitude,
        position.heading,
        widget.rideData['rideId'], // Ensure this matches the joinRide ID
      );
      // -------------------------------------------------------------

      setState(() {
        _driverLatLng = newPos;
        _updateMarkers(position);
        // Only redraw routes if really necessary (Optional optimization)
        _drawRoutes(newPos);
      });

      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
    });
  }

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

  void _updateMarkers(Position currentPos) {
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
        position: LatLng(currentPos.latitude, currentPos.longitude),
        icon: _carIcon ?? BitmapDescriptor.defaultMarker,
        rotation: currentPos.heading,
        anchor: const Offset(0.5, 0.5),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Navigate to Pickup")),
      body: _driverLatLng == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _driverLatLng!, zoom: 16),
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
