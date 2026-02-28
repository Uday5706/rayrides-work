import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
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
  bool _isCancelling = false;

  final RiderSocketService _socketService = RiderSocketService();
  LatLng? _lastPathUpdatePos;

  String _pickupEta = "Calculating...";
  String _tripTime = "Calculating...";
  Timer? _etaDebounce;

  String _rideStatus = "accepted"; // initial status
  bool _hasDriverArrived = false;
  double _carbonSaved = 0.0;
  bool _isNearDrop = false;
  late LatLng _driverStartPos;

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
    _driverStartPos = LatLng(startLat, startLng);

    _currentVisualPos = LatLng(startLat, startLng);
    _currentVisualHeading = startHeading;

    // 2. INITIAL PATH
    // Draw the grey line (Driver -> Pickup) IMMEDIATELY
    _updateLiveRoute(_currentVisualPos);
    _calculateAllETAs(_currentVisualPos);

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
    FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;

      final newStatus = doc['status'];

      if (newStatus != _rideStatus) {
        setState(() {
          _rideStatus = newStatus;
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

  // Function to handle ride cancellation
  Future<void> _cancelRideWithDelay() async {
    if (_isCancelling) return;

    setState(() => _isCancelling = true);

    try {
      // 1️⃣ Immediately mark cancelled
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .update({'status': 'cancelled'});

      // 2️⃣ Wait 5 seconds (loader visible)
      await Future.delayed(const Duration(seconds: 5));

      // 3️⃣ Delete ride document
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .delete();

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Cancel error: $e");
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _endRide() async {
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideId)
          .update({'status': 'ended'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ride completed successfully")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("End ride error: $e");
    }
  }

  void _updateRideProximity(LatLng currentPos) {
    double distanceToDrop = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      widget.rideData['drop_lat'],
      widget.rideData['drop_lng'],
    );

    double distanceToPickup = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      widget.rideData['pickup_lat'],
      widget.rideData['pickup_lng'],
    );

    // --- UPDATED CARBON LOGIC ---
    double totalDistanceMeters = 0.0;

    if (_rideStatus == "accepted") {
      // Phase 1: Driver moving towards Pickup
      totalDistanceMeters = Geolocator.distanceBetween(
        _driverStartPos.latitude,
        _driverStartPos.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
    } else if (_rideStatus == "in_progress") {
      // Phase 2: Approach Distance (Fixed) + Trip Distance (Dynamic)
      double approachDist = Geolocator.distanceBetween(
        _driverStartPos.latitude,
        _driverStartPos.longitude,
        widget.rideData['pickup_lat'],
        widget.rideData['pickup_lng'],
      );

      double tripDist = Geolocator.distanceBetween(
        widget.rideData['pickup_lat'],
        widget.rideData['pickup_lng'],
        currentPos.latitude,
        currentPos.longitude,
      );

      totalDistanceMeters = approachDist + tripDist;
    }

    _carbonSaved = (totalDistanceMeters / 1000) * 0.4; // 0.4kg per km
    // ----------------------------

    setState(() {
      // FIX: The critical bug is resolved here
      if (_rideStatus == "accepted") {
        if (distanceToPickup < 50 && !_hasDriverArrived) {
          setState(() {
            _hasDriverArrived = true;
          });
          _throttledPathUpdate(currentPos);
        }
      }

      _isNearDrop = distanceToDrop < 100;
    });
  }

  Future<void> _calculateAllETAs(LatLng driverPos) async {
    final String status = _rideStatus;

    // Pickup ETA: Always Driver -> Pickup
    final pickupDuration = await _getDuration(driverPos,
        LatLng(widget.rideData['pickup_lat'], widget.rideData['pickup_lng']));

    // Trip Time Logic
    LatLng tripOrigin;
    LatLng tripDest =
        LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng']);

    if (status == "in_progress") {
      // If ride started: Driver -> Drop
      tripOrigin = driverPos;
    } else {
      // If accepted/not started: Pickup -> Drop
      tripOrigin =
          LatLng(widget.rideData['pickup_lat'], widget.rideData['pickup_lng']);
    }

    final tripDuration = await _getDuration(tripOrigin, tripDest);

    if (mounted) {
      setState(() {
        _pickupEta = "$pickupDuration mins";
        _tripTime = "$tripDuration mins";
      });
    }
  }

  // Helper to fetch duration from Google Distance Matrix
  Future<int> _getDuration(LatLng origin, LatLng dest) async {
    try {
      final url = "https://maps.googleapis.com/maps/api/distancematrix/json"
          "?origins=${origin.latitude},${origin.longitude}"
          "&destinations=${dest.latitude},${dest.longitude}"
          "&key=$_googleMapsKey";

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['rows'][0]['elements'][0]['status'] == 'OK') {
          // Duration value is in seconds, convert to minutes
          int seconds = data['rows'][0]['elements'][0]['duration']['value'];
          return (seconds / 60).ceil();
        }
      }
    } catch (e) {
      print("ETA Error: $e");
    }
    return 0;
  }

  void _connectSocket() {
    print("🔵 Connecting to Rider Socket...");

    _socketService.connect(
      widget.rideId,
      onLocation: ({required position, required heading}) {
        if (!mounted) return;

        // Trigger smooth animation to new point
        _animateCar(position, heading);
        _updateRideProximity(position);

        // Update path (logic remains same)
        _throttledPathUpdate(position);

        _etaDebounce?.cancel();
        _etaDebounce = Timer(const Duration(seconds: 5), () {
          _calculateAllETAs(position);
        });
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
      _updateLiveRoute(currentPos);
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
      _updateLiveRoute(currentPos);
    }
  }

  Future<void> _updateLiveRoute(LatLng driverLocation) async {
    bool isLiveTrip = _rideStatus == "in_progress";

    LatLng destination = isLiveTrip
        ? LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng'])
        : LatLng(widget.rideData['pickup_lat'], widget.rideData['pickup_lng']);

    PolylineResult result = await _polylineHelper.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(driverLocation.latitude, driverLocation.longitude),
        destination: PointLatLng(destination.latitude, destination.longitude),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty && mounted) {
      List<LatLng> points =
          result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      setState(() {
        if (isLiveTrip) {
          // FIX 1: Remove BOTH the grey line AND the static blue trip line
          _trackPolylines.removeWhere((p) =>
                  p.polylineId.value == "approach_live" ||
                  p.polylineId.value == "trip_main" // Static line must go
              );

          // Add the shrinking live line
          _trackPolylines.add(Polyline(
            polylineId: const PolylineId("trip_live"),
            points: points,
            color: Colors.blueAccent,
            width: 6,
          ));
        } else {
          _trackPolylines.add(Polyline(
            polylineId: const PolylineId("approach_live"),
            points: points,
            color: Colors.grey.withOpacity(0.7),
            width: 5,
          ));
        }
      });
    }
  }

  // Future<void> _updateLiveApproachPath(LatLng driverLocation) async {
  //   PolylineResult result = await _polylineHelper.getRouteBetweenCoordinates(
  //     request: PolylineRequest(
  //       origin: PointLatLng(driverLocation.latitude, driverLocation.longitude),
  //       destination: PointLatLng(
  //           widget.rideData['pickup_lat'], widget.rideData['pickup_lng']),
  //       mode: TravelMode.driving,
  //     ),
  //   );
  //
  //   if (result.points.isNotEmpty && mounted) {
  //     List<LatLng> approachPoints =
  //         result.points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  //     setState(() {
  //       _trackPolylines
  //           .removeWhere((p) => p.polylineId.value == "approach_live");
  //       _trackPolylines.add(Polyline(
  //           polylineId: const PolylineId("approach_live"),
  //           points: approachPoints,
  //           color: Colors.grey.withOpacity(0.7),
  //           width: 5));
  //     });
  //   }
  // }

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
    if (_rideStatus == "in_progress") return;
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
          Positioned(
            top: 60,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.green[800],
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                  "🌱 Carbon Saved: ${_carbonSaved.toStringAsFixed(2)} kg",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ),
          SlidingUpPanel(
            minHeight: 280,
            maxHeight: 500,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            color: Colors.black87,
            panel: _buildInformationPanel(),
          ),
        ],
      ),
    );
  }

  // Helper for consistent metric styling
  Widget _buildMetricColumn(String label, String value,
      {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.grey, fontSize: 10, letterSpacing: 1.1)),
        Text(value,
            style: TextStyle(
                color: isHighlight ? Colors.greenAccent : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInformationPanel() {
    final bool showCancelButton = _rideStatus == "accepted";

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      child: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// DRAG HANDLE
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              _buildHeaderSection(),
              const SizedBox(height: 20),

              /// DRIVER INFO
              Row(
                children: [
                  const CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.blueGrey,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.rideData['driver_name'] ?? "Captain",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.rideData['vehicle_number'] ?? "DL 1CA 1234",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      children: const [
                        Icon(Icons.star, color: Colors.orange, size: 16),
                        SizedBox(width: 4),
                        Text("4.7")
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 25),

              _buildOtpCard(),

              const SizedBox(height: 25),

              /// PICKUP
              _locationRow(
                Icons.circle,
                Colors.green,
                widget.rideData['pickup_name'] ?? "Pickup location",
              ),

              const SizedBox(height: 10),

              /// DROP
              _locationRow(
                Icons.location_on,
                Colors.red,
                widget.rideData['drop_name'] ?? "Drop location",
              ),

              const SizedBox(height: 25),

              /// FARE SECTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Total Fare",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    "₹${widget.rideData['fare'] ?? '0'}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.black),
                  )
                ],
              ),

              const SizedBox(height: 30),

              /// CANCEL BUTTON (ONLY IN ACCEPTED PHASE)
              if (showCancelButton)
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isCancelling ? null : _cancelRideWithDelay,
                    child: _isCancelling
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : const Text(
                            "Cancel",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpCard() {
    if (_rideStatus != "accepted") return const SizedBox();

    final otp = widget.rideData['otp'].toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Start ride with PIN",
          style: TextStyle(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: otp.split('').map((digit) {
            return Container(
              margin: const EdgeInsets.only(right: 10),
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                digit,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeaderSection() {
    String title;
    String subtitle;

    if (_rideStatus == "accepted") {
      if (_hasDriverArrived) {
        title = "Driver has arrived";
        subtitle = "Please share OTP to start ride";
      } else {
        title = "Captain on the way";
        subtitle = "Pickup ETA";
      }
    } else if (_rideStatus == "in_progress") {
      title = "Trip in progress";
      subtitle = "Time remaining";
    } else if (_rideStatus == "ended") {
      title = "Ride Completed";
      subtitle = "Thank you for riding";
    } else {
      title = "Ride Status";
      subtitle = "";
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ],
        ),

        /// 🔥 RIGHT SIDE DYNAMIC WIDGET
        _buildHeaderRightWidget(),
      ],
    );
  }

  Widget _buildHeaderRightWidget() {
    /// 🔴 END RIDE BUTTON
    if (_rideStatus == "in_progress" && _isNearDrop) {
      return GestureDetector(
        onTap: _endRide,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.4),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: const Text(
            "END RIDE",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      );
    }

    /// 🟢 ARRIVED STATE
    if (_rideStatus == "accepted" && _hasDriverArrived) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          "Arrived",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    /// 🔵 NORMAL ETA
    if (_rideStatus == "accepted") {
      return _buildEtaPill(_pickupEta);
    }

    if (_rideStatus == "in_progress") {
      return _buildEtaPill(_tripTime);
    }

    return const SizedBox();
  }

  Widget _buildEtaPill(String value) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[800],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
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

Widget _locationRow(IconData icon, Color color, String text) {
  return Row(
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(color: Colors.black87),
          overflow: TextOverflow.ellipsis,
        ),
      )
    ],
  );
}
