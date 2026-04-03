import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 🟢 Required for Profile Checks
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:rayride/services/rider_socket_service.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

class LiveRideTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> rideData; // Contains trip_id and passenger_id

  const LiveRideTrackingScreen({
    super.key,
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

  StreamSubscription<DocumentSnapshot>? _passengerSub;
  StreamSubscription<DocumentSnapshot>? _tripSub;

  final RiderSocketService _socketService = RiderSocketService();
  LatLng? _lastPathUpdatePos;

  String _pickupEta = "Calculating...";
  String _tripTime = "Calculating...";
  Timer? _etaDebounce;

  // 🟢 DEFAULT STATE
  String _passengerStatus = "pending_approval";
  bool _hasDriverArrived = false;
  double _carbonSaved = 0.0;
  bool _isNearDrop = false;
  late LatLng _driverStartPos;

  // 🟢 NEW: Capture arrival time to calculate cancellation penalty
  DateTime? _driverArrivalTime;

  late String _tripId;
  late String _passengerId;

  late AnimationController _animController;
  LatLng _currentVisualPos = const LatLng(0, 0);
  double _currentVisualHeading = 0.0;

  LatLng _oldPos = const LatLng(0, 0);
  LatLng _newPos = const LatLng(0, 0);
  double _oldHeading = 0.0;
  double _newHeading = 0.0;

  final String _googleMapsKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  late final PolylinePoints _polylineHelper =
      PolylinePoints(apiKey: _googleMapsKey);

  @override
  void initState() {
    super.initState();

    _tripId = widget.rideData['trip_id'] ?? "";
    _passengerId = widget.rideData['passenger_id'] ?? "";

    double startLat =
        widget.rideData['current_lat'] ?? widget.rideData['pickup_lat'];
    double startLng =
        widget.rideData['current_lng'] ?? widget.rideData['pickup_lng'];
    double startHeading =
        (widget.rideData['current_heading'] ?? 0.0).toDouble();
    _driverStartPos = LatLng(startLat, startLng);

    _currentVisualPos = LatLng(startLat, startLng);
    _currentVisualHeading = startHeading;

    _updateLiveRoute(_currentVisualPos);
    _calculateAllETAs(_currentVisualPos);

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

    // --- LISTENER 1: PASSENGER STATUS ---
    _passengerSub = FirebaseFirestore.instance
        .collection('shared_trips')
        .doc(_tripId)
        .collection('passengers')
        .doc(_passengerId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;

      final newStatus = doc['status'];

      // 🟢 NEW: Capture arrival time if driver cancelled on us
      if (newStatus == 'cancelled_by_driver') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Driver cancelled the ride (No-Show). Penalties may apply."),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ));
        Navigator.pop(context);
        return;
      }

      if (newStatus != _passengerStatus) {
        setState(() => _passengerStatus = newStatus);

        if (newStatus == 'rejected') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Driver rejected the request or car is full."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ));
          Navigator.pop(context);
        } else if (newStatus == 'dropped_off') {
          _handleDropOff();
        }
      }
    });

    // --- LISTENER 2: DRIVER LIVE LOCATION ---
    _tripSub = FirebaseFirestore.instance
        .collection('shared_trips')
        .doc(_tripId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;

      final data = doc.data() as Map<String, dynamic>;

      if (data.containsKey('current_lat') && data.containsKey('current_lng')) {
        LatLng newDriverPos = LatLng(data['current_lat'], data['current_lng']);
        double newHeading = (data['current_heading'] ?? 0.0).toDouble();

        _handleDriverMovement(newDriverPos, newHeading);
      }
    });

    _initAssets();
  }

  @override
  void dispose() {
    _passengerSub?.cancel();
    _tripSub?.cancel();
    _etaDebounce?.cancel();

    _animController.dispose();
    _socketService.disconnect();
    super.dispose();
  }

  Future<void> _handleDriverMovement(LatLng newPos, double heading) async {
    _animateCar(newPos, heading);
    _updateRideProximity(newPos);
    _throttledPathUpdate(newPos);

    _etaDebounce?.cancel();
    _etaDebounce = Timer(const Duration(seconds: 5), () {
      _calculateAllETAs(newPos);
    });

    if (_mapCompleter.isCompleted) {
      final GoogleMapController controller = await _mapCompleter.future;
      controller.animateCamera(CameraUpdate.newLatLng(newPos));
    }
  }

  void _handleDropOff() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("You have been dropped off! Trip complete.")),
    );
    Navigator.pop(context);
  }

  // 🟢 UPDATED: Penalty logic for Rider Cancellation
  Future<void> _cancelRideWithDelay() async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("User not authenticated.");

      double penaltyAmount = 0.0;
      double ratingPenalty = 0.0;

      // 1. Calculate penalties if the driver had already arrived
      if (_hasDriverArrived && _driverArrivalTime != null) {
        int waitBlockMinutes = 1;
        int feePerBlock = 1;
        int penaltyBlockMinutes = 1;
        double penaltyPerBlock = 0.1;

        int totalWaitMinutes =
            DateTime.now().difference(_driverArrivalTime!).inMinutes;

        int feeBlocks = (totalWaitMinutes / waitBlockMinutes).floor();
        penaltyAmount = (feeBlocks * feePerBlock).toDouble();

        int penaltyBlocks = (totalWaitMinutes / penaltyBlockMinutes).floor();
        ratingPenalty = penaltyBlocks * penaltyPerBlock;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference tripRef =
            FirebaseFirestore.instance.collection('shared_trips').doc(_tripId);
        DocumentReference passRef =
            tripRef.collection('passengers').doc(_passengerId);
        DocumentReference riderRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        // Fetch Driver's UID from the trip to pay them the penalty
        DocumentSnapshot tripDoc = await transaction.get(tripRef);
        DocumentSnapshot passDoc = await transaction.get(passRef);
        DocumentSnapshot riderDoc = await transaction.get(riderRef);

        if (passDoc.exists) {
          int seatsBooked = passDoc['seats_booked'] ?? 1;
          int currentSeats = tripDoc['available_seats'] ?? 0;
          String currentStatus = passDoc['status'];
          String driverId = tripDoc['driver_id'];

          // Restore seats to carpool (only if they were actually taken)
          if (currentStatus != 'pending_approval') {
            transaction.update(
                tripRef, {'available_seats': currentSeats + seatsBooked});
          }

          transaction.update(passRef,
              {'status': 'cancelled', 'penalty_applied': penaltyAmount});

          // Apply Penalities to Rider
          if (penaltyAmount > 0 || ratingPenalty > 0) {
            double currentRating =
                (riderDoc.data() as Map<String, dynamic>)['rating'] ?? 5.0;
            double newRating = currentRating - ratingPenalty;
            if (newRating < 1.0) newRating = 1.0;

            Map<String, dynamic> riderUpdates = {};
            if (penaltyAmount > 0)
              riderUpdates['negative_balance'] =
                  FieldValue.increment(penaltyAmount);
            if (ratingPenalty > 0) riderUpdates['rating'] = newRating;

            transaction.update(riderRef, riderUpdates);

            // Compensate the Driver instantly
            if (penaltyAmount > 0 && driverId.isNotEmpty) {
              DocumentReference driverWalletRef = FirebaseFirestore.instance
                  .collection('wallets')
                  .doc(driverId);
              transaction.set(
                  driverWalletRef,
                  {
                    'balance': FieldValue.increment(penaltyAmount),
                    'last_updated': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true));
            }
          }
        }
      });

      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        if (penaltyAmount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "Ride Cancelled. A ₹${penaltyAmount.toStringAsFixed(0)} penalty was applied for making the driver wait."),
              backgroundColor: Colors.red));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Ride Cancelled successfully."),
              backgroundColor: Colors.green));
        }
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Cancel error: $e");
      setState(() => _isCancelling = false);
    }
  }

  void _updateRideProximity(LatLng currentPos) {
    if (!mounted) return;
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

    double totalDistanceMeters = 0.0;

    if (_passengerStatus == "awaiting_pickup") {
      totalDistanceMeters = Geolocator.distanceBetween(
        _driverStartPos.latitude,
        _driverStartPos.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
    } else if (_passengerStatus == "in_transit") {
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

    _carbonSaved = (totalDistanceMeters / 1000) * 0.4;

    setState(() {
      if (_passengerStatus == "awaiting_pickup") {
        if (distanceToPickup < 50 && !_hasDriverArrived) {
          setState(() {
            _hasDriverArrived = true;
            _driverArrivalTime = DateTime.now(); // 🟢 CAPTURE ARRIVAL TIME
          });
          _throttledPathUpdate(currentPos);
        }
      }
      _isNearDrop = distanceToDrop < 100;
    });
  }

  Future<void> _calculateAllETAs(LatLng driverPos) async {
    final String status = _passengerStatus;

    final pickupDuration = await _getDuration(driverPos,
        LatLng(widget.rideData['pickup_lat'], widget.rideData['pickup_lng']));

    LatLng tripOrigin;
    LatLng tripDest =
        LatLng(widget.rideData['drop_lat'], widget.rideData['drop_lng']);

    if (status == "in_transit") {
      tripOrigin = driverPos;
    } else {
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
          int seconds = data['rows'][0]['elements'][0]['duration']['value'];
          return (seconds / 60).ceil();
        }
      }
    } catch (e) {
      print("ETA Error: $e");
    }
    return 0;
  }

  void _animateCar(LatLng destPos, double destHeading) {
    _oldPos = _currentVisualPos;
    _oldHeading = _currentVisualHeading;
    _newPos = destPos;
    _newHeading = destHeading;

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
    bool isLiveTrip = _passengerStatus == "in_transit";

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
          _trackPolylines.removeWhere((p) =>
              p.polylineId.value == "approach_live" ||
              p.polylineId.value == "trip_main");

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
    if (_passengerStatus == "in_transit") return;
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

  Widget _buildInformationPanel() {
    final bool showCancelButton = _passengerStatus == "awaiting_pickup" ||
        _passengerStatus == "pending_approval";

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),
              _buildHeaderSection(),
              const SizedBox(height: 20),
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
                          widget.rideData['driver_name'] ?? "Shared Captain",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.rideData['vehicle_number'] ??
                              "Carpool Vehicle",
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
              _locationRow(Icons.circle, Colors.green,
                  widget.rideData['pickup_name'] ?? "Pickup location"),
              const SizedBox(height: 10),
              _locationRow(Icons.location_on, Colors.red,
                  widget.rideData['drop_name'] ?? "Drop location"),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      "Total Fare (${widget.rideData['seats_booked'] ?? 1} seats)",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(
                      "₹${(double.tryParse(widget.rideData['fare'].toString()) ?? 0.0).toStringAsFixed(0)}",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.black))
                ],
              ),
              const SizedBox(height: 30),
              if (showCancelButton)
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isCancelling ? null : _cancelRideWithDelay,
                    child: _isCancelling
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.red))
                        : const Text("Cancel Ride",
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpCard() {
    if (_passengerStatus != "awaiting_pickup") return const SizedBox();

    final otp = widget.rideData['otp']?.toString() ?? "1234";

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Share PIN with driver",
            style: TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: FontWeight.w500)),
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
                  borderRadius: BorderRadius.circular(8)),
              child: Text(digit,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHeaderSection() {
    String title;
    String subtitle;

    if (_passengerStatus == "pending_approval") {
      title = "Request Sent";
      subtitle = "Waiting for driver to accept...";
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.orange)),
            ],
          ),
          const SizedBox(
            height: 24,
            width: 24,
            child:
                CircularProgressIndicator(color: Colors.orange, strokeWidth: 3),
          )
        ],
      );
    } else if (_passengerStatus == "awaiting_pickup") {
      if (_hasDriverArrived) {
        title = "Driver has arrived";
        subtitle = "Please share OTP to enter carpool";
      } else {
        title = "Carpool on the way";
        subtitle = "Pickup ETA";
      }
    } else if (_passengerStatus == "in_transit") {
      title = "Trip in progress";
      subtitle = "Time remaining";
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
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
        _buildHeaderRightWidget(),
      ],
    );
  }

  Widget _buildHeaderRightWidget() {
    if (_passengerStatus == "awaiting_pickup" && _hasDriverArrived) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
            color: Colors.green, borderRadius: BorderRadius.circular(20)),
        child: const Text("Arrived",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );
    }

    if (_passengerStatus == "awaiting_pickup") return _buildEtaPill(_pickupEta);
    if (_passengerStatus == "in_transit") return _buildEtaPill(_tripTime);

    return const SizedBox();
  }

  Widget _buildEtaPill(String value) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.blue[800], borderRadius: BorderRadius.circular(20)),
      child: Text(value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}

Widget _locationRow(IconData icon, Color color, String text) {
  return Row(
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text,
            style: const TextStyle(color: Colors.black87),
            overflow: TextOverflow.ellipsis),
      )
    ],
  );
}
