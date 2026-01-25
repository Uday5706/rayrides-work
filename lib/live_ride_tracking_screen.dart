import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
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

class _LiveRideTrackingScreenState extends State<LiveRideTrackingScreen> {
  final Completer<GoogleMapController> _mapCompleter = Completer();

  Set<Polyline> _trackPolylines = {};
  BitmapDescriptor? _customCarIcon;

  // Socket State
  final RiderSocketService _socketService = RiderSocketService();
  LatLng? _liveSocketPos;
  double _liveSocketHeading = 0.0;
  LatLng? _lastPathUpdatePos;

  final String _googleMapsKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  late final PolylinePoints _polylineHelper =
      PolylinePoints(apiKey: _googleMapsKey);

  @override
  void initState() {
    super.initState();
    _initAssets();
    _connectSocket();
  }

  @override
  void dispose() {
    _socketService.disconnect();
    super.dispose();
  }

  void _connectSocket() {
    _socketService.connect(
      widget.rideId,
      onLocation: ({required position, required heading}) {
        // Run inside setState to update the UI
        if (mounted) {
          setState(() {
            _liveSocketPos = position;
            _liveSocketHeading = heading;
          });

          // Move camera to follow car
          _moveCameraToPosition(position);

          // Update path (throttled)
          _throttledPathUpdate(position);
        }
      },
    );
  }

  // --- Map Helpers ---
  Future<void> _moveCameraToPosition(LatLng pos) async {
    if (_mapCompleter.isCompleted) {
      final controller = await _mapCompleter.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: pos, zoom: 16, tilt: 40)));
    }
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
    // Only fetch new route if driver moved > 50 meters
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
            color:
                Colors.grey, // Grey path indicates "Driver approaching pickup"
            width: 5));
      });
    }
  }

  // --- Assets ---
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
            color: Colors.blueAccent, // Blue path is the ride itself
            width: 6));
      });
    }
  }

  Set<Marker> _buildMapMarkers(LatLng driver, double heading) {
    return {
      Marker(
          markerId: const MarkerId("driver_marker"),
          position: driver,
          rotation: heading,
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
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('rides')
                .doc(widget.rideId)
                .snapshots(),
            builder: (context, snapshot) {
              // 1. Initial / Fallback Data (Firestore)
              double driverLat = widget.rideData['pickup_lat'];
              double driverLng = widget.rideData['pickup_lng'];
              double driverHeading = 0.0;

              if (snapshot.hasData && snapshot.data!.exists) {
                final remoteData =
                    snapshot.data!.data() as Map<String, dynamic>;
                if (remoteData['driver_lat'] != null) {
                  driverLat = (remoteData['driver_lat'] as num).toDouble();
                  driverLng = (remoteData['driver_lng'] as num).toDouble();
                  driverHeading =
                      (remoteData['driver_heading'] as num).toDouble();
                }
              }

              // 2. Determine Effective Location
              // PRIORITY: Live Socket > Firestore > Static
              final LatLng effectivePos =
                  _liveSocketPos ?? LatLng(driverLat, driverLng);
              final double effectiveHeading =
                  _liveSocketPos != null ? _liveSocketHeading : driverHeading;

              return GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: effectivePos, zoom: 15),
                markers: _buildMapMarkers(effectivePos, effectiveHeading),
                polylines: _trackPolylines,
                onMapCreated: (ctrl) {
                  if (!_mapCompleter.isCompleted) _mapCompleter.complete(ctrl);
                },
                myLocationEnabled: false,
                zoomControlsEnabled: false,
                // Disable rotate gestures to keep heading visualization clear
                rotateGesturesEnabled: false,
              );
            },
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

  // --- UI Components ---
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
    // ... [Same as your previous code] ...
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
