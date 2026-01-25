import 'dart:async';
import 'dart:math' as math; // Import math for bearing calculation
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  LatLng? _previousPos;

  // --- SIMULATION VARIABLES ---
  Timer? _demoTimer;
  LatLng? _simulatedPos; // If not null, map uses this instead of Firestore
  double? _simulatedHeading; // If not null, map uses this

  final String _googleMapsKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  late final PolylinePoints _polylineHelper =
      PolylinePoints(apiKey: _googleMapsKey);

  @override
  void initState() {
    super.initState();
    _initAssets();
  }

  @override
  void dispose() {
    _demoTimer?.cancel(); // Cleanup timer
    super.dispose();
  }

  Future<void> _initAssets() async {
    await _renderCarIcon();
    await _fetchInitialTripRoute();
  }

  // ... [Keep _renderCarIcon and _fetchInitialTripRoute same as before] ...
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

    if (result.points.isNotEmpty) {
      List<LatLng> tripPoints =
          result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      // CRITICAL FIX: Add 'if (mounted)' before every setState in async functions
      if (mounted) {
        setState(() {
          _trackPolylines.add(Polyline(
              polylineId: const PolylineId("trip_main"),
              points: tripPoints,
              color: Colors.blueAccent,
              width: 6));
        });
      }
    }
  }
  // ... ---------------------------------------------------------------- ...

  // --- 🚗 DUMMY SIMULATION LOGIC START ---

  // Helper: Calculate bearing (rotation) between two points
  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = start.latitude * (math.pi / 180.0);
    double lon1 = start.longitude * (math.pi / 180.0);
    double lat2 = end.latitude * (math.pi / 180.0);
    double lon2 = end.longitude * (math.pi / 180.0);

    double dLon = lon2 - lon1;
    double y = math.sin(dLon) * math.cos(lat2);
    double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    double brng = math.atan2(y, x);
    return (brng * (180.0 / math.pi) + 360.0) % 360.0;
  }

  void _startDummyDrive(LatLng currentDriverPos) async {
    if (_demoTimer != null && _demoTimer!.isActive) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("🚗 Simulation Started!")));

    // 1. Fetch Leg 1: Driver -> Pickup
    PolylineResult leg1 = await _polylineHelper.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin:
            PointLatLng(currentDriverPos.latitude, currentDriverPos.longitude),
        destination: PointLatLng(
            widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
        mode: TravelMode.driving,
      ),
    );

    // 2. Fetch Leg 2: Pickup -> Drop
    PolylineResult leg2 = await _polylineHelper.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(
            widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
        destination: PointLatLng(
            widget.rideData['drop_lat'], widget.rideData['drop_lng']),
        mode: TravelMode.driving,
      ),
    );

    if (leg1.points.isEmpty && leg2.points.isEmpty) return;

    List<LatLng> driverToPickup =
        leg1.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    List<LatLng> pickupToDrop =
        leg2.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    int index = 0;
    bool reachedPickup = false;

    setState(() => _trackPolylines.clear());

    _demoTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      List<LatLng> currentActivePath =
          reachedPickup ? pickupToDrop : driverToPickup;

      if (index >= currentActivePath.length - 1) {
        if (!reachedPickup) {
          reachedPickup = true;
          index = 0;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("📍 Driver reached Pickup!")));
        } else {
          timer.cancel();
          setState(() {
            _simulatedPos = null;
            _simulatedHeading = null;
            _trackPolylines.clear();
          });
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("🏁 Ride Completed")));
          return;
        }
      }

      LatLng start = currentActivePath[index];
      LatLng end = currentActivePath[index + 1];

      setState(() {
        _simulatedPos = start;
        _simulatedHeading = _calculateBearing(start, end);

        // --- DYNAMIC PATH SHORTENING ---
        // We only draw from the current 'index' to the end of the list
        // This makes the path "disappear" behind the car
        _trackPolylines = {
          Polyline(
            polylineId: PolylineId(
                reachedPickup ? "trip_to_drop" : "approach_to_pickup"),
            points: currentActivePath.sublist(index), // This is the secret
            color: Colors.blueAccent,
            width: 6,
            jointType: JointType.round,
          )
        };
      });

      _moveCameraToPosition(start);
      index++;
    });
  }
  // --- 🚗 DUMMY SIMULATION LOGIC END ---

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

  Future<void> _moveCameraToPosition(LatLng pos) async {
    final controller = await _mapCompleter.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 16, tilt: 40)));
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

  // Fuzzy Finder (Keep this from previous step)
  dynamic _fuzzyGet(Map<String, dynamic> data, String targetKey) {
    if (data.containsKey(targetKey)) return data[targetKey];
    for (String key in data.keys) {
      if (key.trim() == targetKey) return data[key];
    }
    return null;
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
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: CircularProgressIndicator());
              }

              final remoteData = snapshot.data!.data() as Map<String, dynamic>;

              final rawLat = _fuzzyGet(remoteData, 'driver_lat');
              final rawLng = _fuzzyGet(remoteData, 'driver_lng');
              final rawHeading = _fuzzyGet(remoteData, 'driver_heading');

              // Firestore data (Fallbacks)
              final double fsLat = (rawLat is num
                      ? rawLat.toDouble()
                      : double.tryParse(rawLat.toString())) ??
                  widget.rideData['pickup_lat'] - 0.001;
              final double fsLng = (rawLng is num
                      ? rawLng.toDouble()
                      : double.tryParse(rawLng.toString())) ??
                  widget.rideData['pickup_lng'] - 0.001;
              final LatLng fsPos = LatLng(fsLat, fsLng);
              final double fsHeading = (rawHeading is num
                      ? rawHeading.toDouble()
                      : double.tryParse(rawHeading?.toString() ?? "0")) ??
                  0.0;

              // 🔥 OVERRIDE: If simulation is running, use _simulatedPos, otherwise use Firestore
              final LatLng effectivePos = _simulatedPos ?? fsPos;
              final double effectiveHeading = _simulatedHeading ?? fsHeading;

              // Only auto-update camera if NOT simulating (Simulation handles its own camera)
              if (_simulatedPos == null && _previousPos != effectivePos) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _previousPos = effectivePos;
                  _updateLiveApproachPath(effectivePos);
                  _moveCameraToPosition(effectivePos);
                });
              }

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

      // 🕹️ TEST BUTTON
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.white,
        onPressed: () {
          // Start simulation from current pickup or a known default
          // For robustness, we just assume driver starts somewhat near pickup or just use pickup for demo
          _startDummyDrive(LatLng(widget.rideData['pickup_lat'] - 0.001,
              widget.rideData['pickup_lng'] - 0.001));
        },
        child: const Icon(Icons.play_arrow, color: Colors.black),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
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
