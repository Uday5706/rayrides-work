import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  late String _tripId;

  List<Map<String, dynamic>> _passengers = [];
  StreamSubscription<QuerySnapshot>? _passengersSubscription;
  double _carbonSaved = 0.0;
  late LatLng _driverStartPos;
  bool _isStartPosSet = false;

  final Map<String, DateTime> _passengerArrivalTimes = {};

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

    _tripId = widget.rideData['tripId'] ?? widget.rideData['id'] ?? "";

    if (_tripId.isEmpty) {
      debugPrint("❌ ERROR: Trip ID is missing!");
    }

    _loadMarkerIcon();

    if (_tripId.isNotEmpty) {
      _socketService.connect(_tripId);
      _listenForPassengers();
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

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  void dispose() {
    _passengersSubscription?.cancel();
    _socketService.disconnect();
    _animController.dispose();
    super.dispose();
  }

  void _listenForPassengers() {
    _passengersSubscription = FirebaseFirestore.instance
        .collection('shared_trips')
        .doc(_tripId)
        .collection('passengers')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      List<Map<String, dynamic>> updatedPassengers = [];
      for (var doc in snapshot.docs) {
        var data = doc.data();
        data['passenger_id'] = doc.id;
        updatedPassengers.add(data);
      }

      setState(() {
        _passengers = updatedPassengers;
      });

      _updateMarkers();
      _throttledRouteUpdate(_currentVisualPos, force: true);
    });
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
          _throttledRouteUpdate(_currentVisualPos, force: true);
        });
      }
    } catch (e) {
      debugPrint("Location Error: $e");
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((Position position) {
      if (!mounted || _tripId.isEmpty) return;

      LatLng newPos = LatLng(position.latitude, position.longitude);

      FirebaseFirestore.instance
          .collection('shared_trips')
          .doc(_tripId)
          .update({
        'current_lat': position.latitude,
        'current_lng': position.longitude,
        'current_heading': position.heading,
      });

      _animateCar(newPos, position.heading);
      _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
      _throttledRouteUpdate(newPos);
      _calculateCarbon(newPos);
      _checkPassengerArrivals(newPos);
    });
  }

  void _checkPassengerArrivals(LatLng driverPos) {
    for (var p in _passengers) {
      if (p['status'] == 'awaiting_pickup') {
        double dist = Geolocator.distanceBetween(
            driverPos.latitude,
            driverPos.longitude,
            _parseDouble(p['pickup_lat']),
            _parseDouble(p['pickup_lng']));

        if (dist <= 100 &&
            !_passengerArrivalTimes.containsKey(p['passenger_id'])) {
          _passengerArrivalTimes[p['passenger_id']] = DateTime.now();

          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Arrived at pickup. Wait timer started."),
              backgroundColor: Colors.orange));
        }
      }
    }
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

  void _throttledRouteUpdate(LatLng currentPos, {bool force = false}) {
    if (_lastRouteUpdatePos == null || force) {
      _lastRouteUpdatePos = currentPos;
      _updateDynamicRoute(currentPos);
      return;
    }

    double distance = Geolocator.distanceBetween(
      _lastRouteUpdatePos!.latitude,
      _lastRouteUpdatePos!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    if (distance > 50) {
      _lastRouteUpdatePos = currentPos;
      _updateDynamicRoute(currentPos);
    }
  }

  Future<void> _updateDynamicRoute(LatLng driverPos) async {
    LatLng? nextTarget;
    double shortestDistance = double.infinity;
    Color routeColor = Colors.blue;

    for (var p in _passengers) {
      if (p['status'] == 'awaiting_pickup') {
        double dist = Geolocator.distanceBetween(
            driverPos.latitude,
            driverPos.longitude,
            _parseDouble(p['pickup_lat']),
            _parseDouble(p['pickup_lng']));
        if (dist < shortestDistance) {
          shortestDistance = dist;
          nextTarget = LatLng(
              _parseDouble(p['pickup_lat']), _parseDouble(p['pickup_lng']));
          routeColor = Colors.redAccent;
        }
      } else if (p['status'] == 'in_transit') {
        double dist = Geolocator.distanceBetween(
            driverPos.latitude,
            driverPos.longitude,
            _parseDouble(p['drop_lat']),
            _parseDouble(p['drop_lng']));
        if (dist < shortestDistance) {
          shortestDistance = dist;
          nextTarget =
              LatLng(_parseDouble(p['drop_lat']), _parseDouble(p['drop_lng']));
          routeColor = Colors.blueAccent;
        }
      }
    }

    if (nextTarget == null) return;

    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(driverPos.latitude, driverPos.longitude),
        destination: PointLatLng(nextTarget.latitude, nextTarget.longitude),
        mode: TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty && mounted) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId("dynamic_route"),
            points: result.points
                .map((p) => LatLng(p.latitude, p.longitude))
                .toList(),
            color: routeColor,
            width: 6,
          )
        };
      });
    }
  }

  void _updateMarkers() {
    Set<Marker> newMarkers = {
      Marker(
        markerId: const MarkerId("driver"),
        position: _currentVisualPos,
        rotation: _currentVisualHeading,
        icon: _carIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 0.5),
        flat: true,
      ),
    };

    for (var p in _passengers) {
      if (p['status'] == 'awaiting_pickup') {
        newMarkers.add(Marker(
          markerId: MarkerId("pickup_${p['passenger_id']}"),
          position: LatLng(
              _parseDouble(p['pickup_lat']), _parseDouble(p['pickup_lng'])),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: "Pickup: ${p['seats_booked']} seats"),
        ));
      } else if (p['status'] == 'in_transit') {
        newMarkers.add(Marker(
          markerId: MarkerId("drop_${p['passenger_id']}"),
          position:
              LatLng(_parseDouble(p['drop_lat']), _parseDouble(p['drop_lng'])),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: "Drop: ${p['seats_booked']} seats"),
        ));
      }
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  void _calculateCarbon(LatLng currentPos) {
    if (!_isStartPosSet) return;
    double totalDist = Geolocator.distanceBetween(
      _driverStartPos.latitude,
      _driverStartPos.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );
    if (mounted) {
      setState(() {
        _carbonSaved = (totalDist / 1000) * 0.4;
      });
    }
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

  void _showOtpBottomSheet(
      String passengerId, String expectedOtp, double baseFare) {
    final TextEditingController otpController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
              const Text("Enter Rider OTP",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
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
                      borderSide: BorderSide.none),
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
                  onPressed: () {
                    _verifyPassengerOtp(passengerId, baseFare);
                    Navigator.pop(context);
                  },
                  child: const Text("VERIFY & PICKUP",
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // 🟢 TEACHING CONCEPT: Atomic Acceptance
  // We use a transaction here. If two riders book the last seat at the exact same
  // millisecond, the transaction prevents double-booking.
  Future<void> _acceptPassenger(Map<String, dynamic> p) async {
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference tripRef =
            FirebaseFirestore.instance.collection('shared_trips').doc(_tripId);
        DocumentReference passRef =
            tripRef.collection('passengers').doc(p['passenger_id']);

        DocumentSnapshot tripDoc = await transaction.get(tripRef);
        int availableSeats = tripDoc['available_seats'] ?? 0;
        int requestedSeats = p['seats_booked'] ?? 1;

        if (availableSeats >= requestedSeats) {
          // 1. Deduct seats from the carpool capacity
          transaction.update(
              tripRef, {'available_seats': availableSeats - requestedSeats});
          // 2. Mark passenger as officially booked
          transaction.update(passRef, {'status': 'awaiting_pickup'});
        } else {
          throw Exception("Not enough seats available in your car!");
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Request Accepted!"), backgroundColor: Colors.green));
    } catch (e) {
      debugPrint("Error accepting: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  // 🟢 NEW: Reject Passenger Logic
  Future<void> _rejectPassenger(String passengerId) async {
    try {
      await FirebaseFirestore.instance
          .collection('shared_trips')
          .doc(_tripId)
          .collection('passengers')
          .doc(passengerId)
          .update({'status': 'rejected'});
    } catch (e) {
      debugPrint("Error rejecting: $e");
    }
  }

  // 🟢 NEW: Driver actively cancelling a no-show rider
  Future<void> _cancelNoShowPassenger(
      String passengerId, int seatsBooked) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      double penaltyAmount = 0.0;
      double ratingPenalty = 0.0;
      double newRiderRating = 5.0;

      int waitBlockMinutes = 1;
      int feePerBlock = 1;
      int penaltyBlockMinutes = 1;
      double penaltyPerBlock = 0.1;

      DateTime? arrivedAt = _passengerArrivalTimes[passengerId];

      if (arrivedAt != null) {
        int totalWaitMinutes = DateTime.now().difference(arrivedAt).inMinutes;
        int feeBlocks = (totalWaitMinutes / waitBlockMinutes).floor();
        penaltyAmount = (feeBlocks * feePerBlock).toDouble();

        int penaltyBlocks = (totalWaitMinutes / penaltyBlockMinutes).floor();
        ratingPenalty = penaltyBlocks * penaltyPerBlock;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference tripRef =
            FirebaseFirestore.instance.collection('shared_trips').doc(_tripId);
        DocumentReference passRef =
            tripRef.collection('passengers').doc(passengerId);
        DocumentReference riderRef =
            FirebaseFirestore.instance.collection('users').doc(passengerId);
        DocumentReference driverWalletRef =
            FirebaseFirestore.instance.collection('wallets').doc(user.uid);

        DocumentSnapshot tripDoc = await transaction.get(tripRef);
        DocumentSnapshot riderDoc = await transaction.get(riderRef);

        if (riderDoc.exists) {
          double currentRating = _parseDouble(
              (riderDoc.data() as Map<String, dynamic>)['rating'] ?? 5.0);
          newRiderRating = (currentRating - ratingPenalty);
          if (newRiderRating < 1.0) newRiderRating = 1.0;
        }

        // Restore seats
        int currentSeats = tripDoc['available_seats'] ?? 0;
        transaction
            .update(tripRef, {'available_seats': currentSeats + seatsBooked});

        // Mark as cancelled by driver
        transaction.update(passRef, {
          'status': 'cancelled_by_driver',
          'penalty_applied': penaltyAmount
        });

        // Apply penalty to Rider profile
        if (penaltyAmount > 0 || ratingPenalty > 0) {
          Map<String, dynamic> riderUpdates = {};
          if (penaltyAmount > 0)
            riderUpdates['negative_balance'] =
                FieldValue.increment(penaltyAmount);
          if (ratingPenalty > 0) riderUpdates['rating'] = newRiderRating;
          transaction.update(riderRef, riderUpdates);
        }

        // Compensate Driver Wallet immediately
        if (penaltyAmount > 0) {
          transaction.set(
              driverWalletRef,
              {
                'balance': FieldValue.increment(penaltyAmount),
                'last_updated': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Passenger Cancelled (No-Show). Seats restored."),
            backgroundColor: Colors.orange));
      }
    } catch (e) {
      debugPrint("Error cancelling no-show: $e");
    }
  }

  Future<void> _verifyPassengerOtp(String passengerId, double baseFare) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Driver not authenticated!");

      double waitingFee = 0.0;
      double ratingPenalty = 0.0;
      double newRiderRating = 5.0;

      int waitBlockMinutes = 1;
      int feePerBlock = 1;
      int penaltyBlockMinutes = 1;
      double penaltyPerBlock = 0.1;

      DateTime? arrivedAt = _passengerArrivalTimes[passengerId];

      if (arrivedAt != null) {
        int totalWaitMinutes = DateTime.now().difference(arrivedAt).inMinutes;
        int feeBlocks = (totalWaitMinutes / waitBlockMinutes).floor();
        waitingFee = (feeBlocks * feePerBlock).toDouble();

        int penaltyBlocks = (totalWaitMinutes / penaltyBlockMinutes).floor();
        ratingPenalty = penaltyBlocks * penaltyPerBlock;
      }

      DocumentReference riderRef =
          FirebaseFirestore.instance.collection('users').doc(passengerId);
      DocumentSnapshot riderDoc = await riderRef.get();

      if (riderDoc.exists) {
        double currentRating = _parseDouble(
            (riderDoc.data() as Map<String, dynamic>)['rating'] ?? 5.0);
        newRiderRating = (currentRating - ratingPenalty);
        if (newRiderRating < 1.0) newRiderRating = 1.0;
      }

      double newTotalFare = baseFare + waitingFee;
      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference passRef = FirebaseFirestore.instance
          .collection('shared_trips')
          .doc(_tripId)
          .collection('passengers')
          .doc(passengerId);

      batch.update(passRef, {
        'status': 'in_transit',
        'fare': newTotalFare,
        'waiting_fee_applied': waitingFee,
      });

      if (ratingPenalty > 0 || waitingFee > 0) {
        // 🟢 Applying negative balance to rider
        Map<String, dynamic> riderUpdates = {};
        if (waitingFee > 0)
          riderUpdates['negative_balance'] = FieldValue.increment(waitingFee);
        if (ratingPenalty > 0) riderUpdates['rating'] = newRiderRating;
        batch.update(riderRef, riderUpdates);
      }

      if (waitingFee > 0) {
        DocumentReference walletRef =
            FirebaseFirestore.instance.collection('wallets').doc(user.uid);
        batch.set(
            walletRef,
            {
              'balance': FieldValue.increment(waitingFee),
              'last_updated': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }

      await batch.commit();

      if (waitingFee > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Picked up! Added ₹${waitingFee.toStringAsFixed(0)} fee. Rider lost ${ratingPenalty.toStringAsFixed(2)} stars."),
            backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Passenger Picked Up!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint("Error updating passenger: $e");
    }
  }

  Future<void> _dropOffPassenger(Map<String, dynamic> p) async {
    String passengerId = p['passenger_id'];
    int seatsFreed = p['seats_booked'];
    double fareEarned = (p['fare'] ?? 0.0).toDouble();

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference tripRef =
          FirebaseFirestore.instance.collection('shared_trips').doc(_tripId);
      DocumentReference passRef =
          tripRef.collection('passengers').doc(passengerId);

      batch.update(passRef, {
        'status': 'dropped_off',
        'drop_time': FieldValue.serverTimestamp(),
      });

      batch.update(tripRef, {
        'available_seats': FieldValue.increment(seatsFreed),
        'total_earned': FieldValue.increment(fareEarned),
        'completed_passengers': FieldValue.arrayUnion([
          {
            'passenger_id': passengerId,
            'fare': fareEarned,
            'seats': seatsFreed,
          }
        ])
      });

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Dropped off! ₹${fareEarned.toStringAsFixed(0)} added to shift."),
          backgroundColor: Colors.blue));
    } catch (e) {
      debugPrint("Error dropping off: $e");
    }
  }

  Future<void> _endEntireTrip() async {
    try {
      await FirebaseFirestore.instance
          .collection('shared_trips')
          .doc(_tripId)
          .update({
        'status': 'completed',
        'carbon_saved_kg': _carbonSaved,
        'completed_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Shared Trip Completed"),
            backgroundColor: Colors.blue));
        mainNavController.index = 1;
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("End trip error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Shared Route Navigation")),
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
                  padding: const EdgeInsets.only(
                      bottom: 350), // Adjust padding for taller panel
                ),
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
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildPassengerPanel(),
                )
              ],
            ),
    );
  }

  // 🟢 UPDATED: Added a Long-Press to Cancel a No-Show rider
  Widget _buildPassengerPanel() {
    List<Map<String, dynamic>> pendingPassengers =
        _passengers.where((p) => p['status'] == 'pending_approval').toList();
    List<Map<String, dynamic>> activePassengers = _passengers
        .where((p) =>
            p['status'] == 'awaiting_pickup' || p['status'] == 'in_transit')
        .toList();

    return Container(
      height: 380, // Taller to fit new requests
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 15, spreadRadius: 5)
          ]),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            height: 5,
            width: 40,
            decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(10)),
          ),

          // --- PENDING REQUESTS SECTION ---
          if (pendingPassengers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("New Requests",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                          fontSize: 16))),
            ),
            ...pendingPassengers.map((p) => ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                      backgroundColor: Colors.orange,
                      child: Icon(Icons.person_add,
                          color: Colors.white, size: 20)),
                  title: Text("Rider (${p['seats_booked']} seats)"),
                  subtitle: Text(
                      "Rating: ⭐ ${(p['rider_rating'] ?? 5.0).toStringAsFixed(1)}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.cancel,
                            color: Colors.red, size: 32),
                        onPressed: () => _rejectPassenger(p['passenger_id']),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_circle,
                            color: Colors.green, size: 32),
                        onPressed: () => _acceptPassenger(p),
                      ),
                    ],
                  ),
                )),
            const Divider(),
          ],

          // --- ACTIVE MANIFEST SECTION ---
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Passenger Manifest",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ),
          if (activePassengers.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("No active passengers.",
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent),
                      onPressed: _endEntireTrip,
                      child: const Text("END SHIFT",
                          style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: activePassengers.length,
                itemBuilder: (context, index) {
                  var p = activePassengers[index];
                  bool isAwaiting = p['status'] == 'awaiting_pickup';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isAwaiting ? Colors.redAccent : Colors.blueAccent,
                      child: Icon(isAwaiting ? Icons.hail : Icons.flag,
                          color: Colors.white),
                    ),
                    title: Text("Passenger (${p['seats_booked']} seats)"),
                    subtitle: Text(
                        isAwaiting
                            ? "Awaiting Pickup (Hold to cancel)"
                            : "In Transit",
                        style: TextStyle(
                            color: isAwaiting ? Colors.orange : Colors.green,
                            fontSize: 12)),
                    onLongPress: () {
                      if (isAwaiting) {
                        // 🟢 Allow driver to manually cancel a no-show rider
                        _cancelNoShowPassenger(
                            p['passenger_id'], p['seats_booked']);
                      }
                    },
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAwaiting ? Colors.green : Colors.red,
                      ),
                      onPressed: () {
                        if (isAwaiting) {
                          double baseFare = (p['fare'] ?? 0.0).toDouble();
                          _showOtpBottomSheet(
                              p['passenger_id'], p['otp'] ?? "1234", baseFare);
                        } else {
                          _dropOffPassenger(p);
                        }
                      },
                      child: Text(isAwaiting ? "PICKUP" : "DROP OFF",
                          style: const TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            )
        ],
      ),
    );
  }
}
