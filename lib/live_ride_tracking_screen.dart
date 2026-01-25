import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rayride/services/rider_socket_service.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

class LiveRideTrackingScreen extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic> rideData;

  const LiveRideTrackingScreen({
    super.key,
    required this.rideId,
    required this.rideData,
  });

  @override
  State<LiveRideTrackingScreen> createState() => _LiveRideTrackingScreenState();
}

class _LiveRideTrackingScreenState extends State<LiveRideTrackingScreen>
    with SingleTickerProviderStateMixin {
  final Completer<GoogleMapController> _mapCompleter = Completer();

  Set<Polyline> _trackPolylines = {};
  BitmapDescriptor? _customCarIcon;

  final RiderSocketService _socketService = RiderSocketService();
  LatLng? _lastPathUpdatePos;

  // --- SMOOTH ANIMATION VARIABLES ---
  late AnimationController _animController;
  LatLng _currentVisualPos = const LatLng(0, 0);
  double _currentVisualHeading = 0.0;

  LatLng _oldPos = const LatLng(0, 0);
  LatLng _newPos = const LatLng(0, 0);
  double _oldHeading = 0.0;
  double _newHeading = 0.0;
  // ----------------------------------

  final String _googleMapsKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  late final PolylinePoints _polylineHelper =
      PolylinePoints(apiKey: _googleMapsKey);

  @override
  void initState() {
    super.initState();

    // 1. CORRECT INITIALIZATION
    // Check if Firestore already has driver location.
    // If yes, use it. If no, fallback to pickup.
    double startLat =
        widget.rideData['driver_lat'] ?? widget.rideData['pickup_lat'];
    double startLng =
        widget.rideData['driver_lng'] ?? widget.rideData['pickup_lng'];
    double startHeading = (widget.rideData['driver_heading'] ?? 0.0).toDouble();

    _currentVisualPos = LatLng(startLat, startLng);
    _currentVisualHeading = startHeading;

    // 2. INITIAL PATH
    // Draw the grey line (Driver -> Pickup) IMMEDIATELY
    _updateLiveApproachPath(_currentVisualPos);

    // Setup Animation Controller (Duration = typical socket update interval)
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
          });
        }
      });

    _initAssets();
    _connectSocket();
  }

  @override
  void dispose() {
    _socketService.disconnect();
    _animController.dispose();
    super.dispose();
  }

  void _connectSocket() {
    print("🔵 Connecting to Rider Socket...");

    _socketService.connect(
      widget.rideId,
      onLocation: ({required position, required heading}) {
        if (!mounted) return;

        // Trigger smooth animation to new point
        _animateCar(position, heading);

        // Update path (logic remains same)
        _throttledPathUpdate(position);
      },
    );
  }

  void _animateCar(LatLng destPos, double destHeading) {
    _oldPos = _currentVisualPos;
    _oldHeading = _currentVisualHeading;

    _newPos = destPos;
    _newHeading = destHeading;

    // Fix Rotation Wrapping
    if ((_newHeading - _oldHeading).abs() > 180) {
      if (_newHeading > _oldHeading) {
        _oldHeading += 360;
      } else {
        _newHeading += 360;
      }
    }

    _animController.forward(from: 0.0);
  }

  void _throttledPathUpdate(LatLng currentPos) {
    if (_lastPathUpdatePos == null) {
      _lastPathUpdatePos = currentPos;
      _updateLiveApproachPath(currentPos);
      return;
    }

    double distance = Geolocator.distanceBetween(
      _lastPathUpdatePos!.latitude,
      _lastPathUpdatePos!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    if (distance > 50) {
      _lastPathUpdatePos = currentPos;
      _updateLiveApproachPath(currentPos);
    }
  }

  Future<void> _updateLiveApproachPath(LatLng driverLocation) async {
    PolylineResult result = await _polylineHelper.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(driverLocation.latitude, driverLocation.longitude),
        destination: PointLatLng(
            widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty && mounted) {
      List<LatLng> approachPoints =
          result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      setState(() {
        _trackPolylines
            .removeWhere((p) => p.polylineId.value == "approach_live");
        _trackPolylines.add(Polyline(
            polylineId: const PolylineId("approach_live"),
            points: approachPoints,
            color: Colors.grey.withOpacity(0.7),
            width: 5));
      });
    }
  }

  Future<void> _initAssets() async {
    await _renderCarIcon();
    await _fetchInitialTripRoute();
  }

  Future<void> _renderCarIcon() async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    const double iconSize = 110.0;
    TextPainter painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: String.fromCharCode(Icons.directions_car_filled.codePoint),
      style: TextStyle(
          fontSize: iconSize,
          fontFamily: Icons.directions_car_filled.fontFamily,
          color: Colors.blueAccent),
    );
    painter.layout();
    painter.paint(canvas, const Offset(0, 0));
    final img = await recorder
        .endRecording()
        .toImage(iconSize.toInt(), iconSize.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (mounted && byteData != null) {
      setState(() => _customCarIcon =
          BitmapDescriptor.fromBytes(byteData.buffer.asUint8List()));
    }
  }

  Future<void> _fetchInitialTripRoute() async {
    PolylineResult result = await _polylineHelper.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(
            widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
        destination: PointLatLng(
            widget.rideData['drop_lat'], widget.rideData['drop_lng']),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty && mounted) {
      List<LatLng> tripPoints =
          result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
      setState(() {
        _trackPolylines.add(Polyline(
            polylineId: const PolylineId("trip_main"),
            points: tripPoints,
            color: Colors.blueAccent,
            width: 6));
      });
    }
  }

  Set<Marker> _buildMapMarkers() {
    return {
      Marker(
          markerId: const MarkerId("driver_marker"),
          position: _currentVisualPos,
          rotation: _currentVisualHeading,
          icon: _customCarIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
          flat: true),
      Marker(
          markerId: const MarkerId("pickup_marker"),
          position: LatLng(
              widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
      Marker(
          markerId: const MarkerId("drop_marker"),
          position:
              LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng']),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GoogleMap(
            // 3. Initial Camera respects Driver Location
            initialCameraPosition:
                CameraPosition(target: _currentVisualPos, zoom: 15),
            markers: _buildMapMarkers(),
            polylines: _trackPolylines,
            onMapCreated: (ctrl) {
              if (!_mapCompleter.isCompleted) _mapCompleter.complete(ctrl);
            },
            myLocationEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
          ),
          Positioned(top: 60, right: 20, child: _buildOtpDisplay()),
          SlidingUpPanel(
            minHeight: 280,
            maxHeight: 450,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            color: Colors.black87,
            panel: _buildInformationPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.orange, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        const Text("START OTP",
            style: TextStyle(color: Colors.white, fontSize: 10)),
        Text(widget.rideData['otp'].toString(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildInformationPanel() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Center(child: Container(width: 40, height: 4, color: Colors.grey[700])),
        const SizedBox(height: 20),
        ListTile(
          leading: const CircleAvatar(
              radius: 25,
              backgroundColor: Colors.blueGrey,
              child: Icon(Icons.person, color: Colors.white)),
          title: Text(widget.rideData['driver_name'] ?? "Raj Singh",
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text("Swift Dzire • DL 1CA 1234",
              style: TextStyle(color: Colors.grey)),
          trailing: const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.call, color: Colors.white)),
        ),
        const Divider(height: 40, color: Colors.white12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          RideInfoItem(title: "PICKUP ETA", detail: "3 mins"),
          RideInfoItem(title: "TRIP TIME", detail: "14 mins"),
        ]),
        const SizedBox(height: 25),
        RideLocationRow(
            icon: Icons.my_location,
            iconColor: Colors.green,
            title: "Pickup",
            desc: widget.rideData['pickup_name'] ?? ""),
        RideLocationRow(
            icon: Icons.flag,
            iconColor: Colors.blueAccent,
            title: "Drop",
            desc: widget.rideData['drop_name'] ?? ""),
      ]),
    );
  }
}

// Helpers
class RideInfoItem extends StatelessWidget {
  final String title;
  final String detail;
  const RideInfoItem({super.key, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        Text(detail,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ]);
}

class RideLocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String desc;
  const RideLocationRow(
      {super.key,
      required this.icon,
      required this.iconColor,
      required this.title,
      required this.desc});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
            child: Text("$title: $desc",
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis)),
      ]));
}
