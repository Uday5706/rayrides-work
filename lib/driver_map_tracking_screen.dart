import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rayride/nav_bar.dart';
import 'package:rayride/services/driver_socket_service.dart';

// 🟢 Premium Theme
import 'core/app_theme.dart';

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
  bool _isInvalidTrip = false;

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
      _isInvalidTrip = true;
      return;
    }

    _loadMarkerIcon();
    _socketService.connect(_tripId);
    _listenForPassengers();

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

    themeNotifier.addListener(_updateMapStyle);
    _startLocationTracking();
  }

  @override
  void dispose() {
    themeNotifier.removeListener(_updateMapStyle);
    _passengersSubscription?.cancel();
    _socketService.disconnect();
    _animController.dispose();
    super.dispose();
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
          color: AppTheme.mutedPine), // 🟢 Themed Car Icon
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

      setState(() => _passengers = updatedPassengers);
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
              backgroundColor: Colors.orangeAccent));
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
      if (_newHeading > _oldHeading)
        _oldHeading += 360;
      else
        _newHeading += 360;
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
    Color routeColor = AppTheme.mutedPine;

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
          routeColor = Colors.orangeAccent;
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
            jointType: JointType.round,
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
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
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

    setState(() => _markers = newMarkers);
  }

  void _calculateCarbon(LatLng currentPos) {
    if (!_isStartPosSet) return;
    double totalDist = Geolocator.distanceBetween(
      _driverStartPos.latitude,
      _driverStartPos.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );
    if (mounted) setState(() => _carbonSaved = (totalDist / 1000) * 0.4);
  }

  void _showOtpBottomSheet(
      String passengerId, String expectedOtp, double baseFare) {
    final TextEditingController otpController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24,
              right: 24,
              top: 32),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.deepForest : AppTheme.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Enter Rider OTP",
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppTheme.white : AppTheme.deepForest)),
              const SizedBox(height: 8),
              Text("Ask the rider for their 4-digit code.",
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppTheme.dustySage)),
              const SizedBox(height: 32),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 32,
                    letterSpacing: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.white : AppTheme.deepForest),
                decoration: InputDecoration(
                  counterText: "",
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF2A5240)
                      : AppTheme.softMint.withOpacity(0.3),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.mutedPine,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () {
                    _verifyPassengerOtp(passengerId, baseFare);
                    Navigator.pop(context);
                  },
                  child: Text("VERIFY & PICKUP",
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

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
          transaction.update(
              tripRef, {'available_seats': availableSeats - requestedSeats});
          transaction.update(passRef, {'status': 'awaiting_pickup'});
        } else {
          throw Exception("Not enough seats available!");
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Request Accepted!"),
            backgroundColor: AppTheme.mutedPine));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()), backgroundColor: Colors.redAccent));
    }
  }

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

  Future<void> _cancelNoShowPassenger(
      String passengerId, int seatsBooked) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      double penaltyAmount = 0.0, ratingPenalty = 0.0, newRiderRating = 5.0;
      int waitBlockMinutes = 1, feePerBlock = 1, penaltyBlockMinutes = 1;
      double penaltyPerBlock = 0.1;
      DateTime? arrivedAt = _passengerArrivalTimes[passengerId];

      if (arrivedAt != null) {
        int totalWaitMinutes = DateTime.now().difference(arrivedAt).inMinutes;
        penaltyAmount =
            ((totalWaitMinutes / waitBlockMinutes).floor() * feePerBlock)
                .toDouble();
        ratingPenalty =
            (totalWaitMinutes / penaltyBlockMinutes).floor() * penaltyPerBlock;
      }

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentReference tripRef =
            FirebaseFirestore.instance.collection('shared_trips').doc(_tripId);
        DocumentReference passRef =
            tripRef.collection('passengers').doc(passengerId);
        DocumentReference riderRef =
            FirebaseFirestore.instance.collection('users').doc(passengerId);
        DocumentSnapshot tripDoc = await transaction.get(tripRef);
        DocumentSnapshot riderDoc = await transaction.get(riderRef);

        if (riderDoc.exists) {
          double currentRating = _parseDouble(
              (riderDoc.data() as Map<String, dynamic>)['rating'] ?? 5.0);
          newRiderRating = (currentRating - ratingPenalty).clamp(1.0, 5.0);
        }

        int currentSeats = tripDoc['available_seats'] ?? 0;
        transaction
            .update(tripRef, {'available_seats': currentSeats + seatsBooked});
        transaction.update(passRef, {
          'status': 'cancelled_by_driver',
          'penalty_applied': penaltyAmount
        });

        if (penaltyAmount > 0 || ratingPenalty > 0) {
          Map<String, dynamic> riderUpdates = {};
          if (penaltyAmount > 0)
            riderUpdates['negative_balance'] =
                FieldValue.increment(penaltyAmount);
          if (ratingPenalty > 0) riderUpdates['rating'] = newRiderRating;
          transaction.update(riderRef, riderUpdates);
        }

        if (penaltyAmount > 0) {
          DocumentReference ledgerRef =
              FirebaseFirestore.instance.collection('penalty_ledgers').doc();
          transaction.set(ledgerRef, {
            'rider_id': passengerId,
            'driver_id': user.uid,
            'trip_id': _tripId,
            'amount': penaltyAmount,
            'reason': 'driver_cancelled_no_show',
            'status': 'unpaid',
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Passenger Cancelled (No-Show). Seats restored."),
            backgroundColor: Colors.orangeAccent));
    } catch (e) {
      debugPrint("Error cancelling no-show: $e");
    }
  }

  Future<void> _verifyPassengerOtp(String passengerId, double baseFare) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Driver not authenticated!");

      double waitingFee = 0.0, ratingPenalty = 0.0, newRiderRating = 5.0;
      DateTime? arrivedAt = _passengerArrivalTimes[passengerId];

      if (arrivedAt != null) {
        int totalWaitMinutes = DateTime.now().difference(arrivedAt).inMinutes;
        waitingFee = ((totalWaitMinutes / 1).floor() * 1).toDouble();
        ratingPenalty = (totalWaitMinutes / 1).floor() * 0.1;
      }

      DocumentReference riderRef =
          FirebaseFirestore.instance.collection('users').doc(passengerId);
      DocumentSnapshot riderDoc = await riderRef.get();
      if (riderDoc.exists) {
        double currentRating = _parseDouble(
            (riderDoc.data() as Map<String, dynamic>)['rating'] ?? 5.0);
        newRiderRating = (currentRating - ratingPenalty).clamp(1.0, 5.0);
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
        'waiting_fee_applied': waitingFee
      });

      if (ratingPenalty > 0 || waitingFee > 0) {
        Map<String, dynamic> riderUpdates = {};
        if (waitingFee > 0)
          riderUpdates['negative_balance'] = FieldValue.increment(waitingFee);
        if (ratingPenalty > 0) riderUpdates['rating'] = newRiderRating;
        batch.update(riderRef, riderUpdates);
      }

      if (waitingFee > 0) {
        DocumentReference ledgerRef =
            FirebaseFirestore.instance.collection('penalty_ledgers').doc();
        batch.set(ledgerRef, {
          'rider_id': passengerId,
          'driver_id': user.uid,
          'trip_id': _tripId,
          'amount': waitingFee,
          'reason': 'wait_time',
          'status': 'unpaid',
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(waitingFee > 0
                ? "Picked up! Added ₹${waitingFee.toStringAsFixed(0)} fee."
                : "Passenger Picked Up!"),
            backgroundColor: AppTheme.mutedPine));
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

      batch.update(passRef,
          {'status': 'dropped_off', 'drop_time': FieldValue.serverTimestamp()});
      batch.update(tripRef, {
        'available_seats': FieldValue.increment(seatsFreed),
        'total_earned': FieldValue.increment(fareEarned),
        'completed_passengers': FieldValue.arrayUnion([
          {'passenger_id': passengerId, 'fare': fareEarned, 'seats': seatsFreed}
        ])
      });

      await batch.commit();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Dropped off! ₹${fareEarned.toStringAsFixed(0)} added to shift."),
            backgroundColor: Colors.blueAccent));
    } catch (e) {
      debugPrint("Error dropping off: $e");
    }
  }

  Future<void> _endEntireTrip() async {
    try {
      if (_tripId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('shared_trips')
            .doc(_tripId)
            .update({
          'status': 'completed',
          'carbon_saved_kg': _carbonSaved,
          'completed_at': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Shift Completed"),
            backgroundColor: AppTheme.mutedPine));
        mainNavController.index = 0; // Go to dashboard
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("End trip error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInvalidTrip) {
      return Scaffold(
        appBar: AppBar(
            title: const Text("Tracking Error"),
            backgroundColor: AppTheme.deepForest),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 60),
              const SizedBox(height: 16),
              Text("No active route found.",
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.mutedPine),
                onPressed: () => Navigator.pop(context),
                child: const Text("Go Back",
                    style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Active Shift",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.white : AppTheme.deepForest)),
        backgroundColor: isDark
            ? AppTheme.deepForest.withOpacity(0.8)
            : AppTheme.white.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(),
      ),
      body: _currentVisualPos.latitude == 0
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.mutedPine))
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition:
                      CameraPosition(target: _currentVisualPos, zoom: 16),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _updateMapStyle();
                  },
                  zoomControlsEnabled: false,
                  padding: const EdgeInsets.only(bottom: 380),
                ),

                // 🟢 Glassmorphic Carbon Widget
                Positioned(
                  top: 100,
                  left: 20,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.deepForest.withOpacity(0.7)
                              : AppTheme.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isDark
                                  ? AppTheme.dustySage.withOpacity(0.3)
                                  : AppTheme.softMint),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.eco_rounded,
                                color: AppTheme.mutedPine, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Saved: ${_carbonSaved.toStringAsFixed(2)} kg",
                              style: GoogleFonts.poppins(
                                  color: isDark
                                      ? AppTheme.white
                                      : AppTheme.deepForest,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildPassengerPanel(isDark),
                )
              ],
            ),
    );
  }

  Widget _buildPassengerPanel(bool isDark) {
    List<Map<String, dynamic>> pendingPassengers =
        _passengers.where((p) => p['status'] == 'pending_approval').toList();
    List<Map<String, dynamic>> activePassengers = _passengers
        .where((p) =>
            p['status'] == 'awaiting_pickup' || p['status'] == 'in_transit')
        .toList();

    return Container(
      height: 380,
      decoration: BoxDecoration(
          color: isDark ? AppTheme.deepForest : AppTheme.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: isDark
                    ? Colors.black45
                    : AppTheme.dustySage.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, -5))
          ]),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              height: 5,
              width: 40,
              decoration: BoxDecoration(
                  color: isDark ? AppTheme.dustySage : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10))),
          if (pendingPassengers.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text("New Requests",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                          fontSize: 16))),
            ),
            ...pendingPassengers.map((p) => ListTile(
                  leading: const CircleAvatar(
                      backgroundColor: Colors.orangeAccent,
                      child: Icon(Icons.person_add_rounded,
                          color: Colors.white, size: 20)),
                  title: Text("Rider (${p['seats_booked']} seats)",
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          color:
                              isDark ? AppTheme.white : AppTheme.deepForest)),
                  subtitle: Text(
                      "Rating: ⭐ ${(p['rider_rating'] ?? 5.0).toStringAsFixed(1)}",
                      style: GoogleFonts.poppins(
                          color: AppTheme.dustySage, fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.cancel_rounded,
                              color: Colors.redAccent, size: 36),
                          onPressed: () => _rejectPassenger(p['passenger_id'])),
                      IconButton(
                          icon: const Icon(Icons.check_circle_rounded,
                              color: AppTheme.mutedPine, size: 36),
                          onPressed: () => _acceptPassenger(p)),
                    ],
                  ),
                )),
            Divider(
                color: isDark
                    ? AppTheme.dustySage.withOpacity(0.2)
                    : Colors.grey[200]),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Passenger Manifest",
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.white : AppTheme.deepForest))),
          ),
          if (activePassengers.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: AppTheme.softMint.withOpacity(0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.radar_rounded,
                          size: 50, color: AppTheme.mutedPine),
                    ),
                    const SizedBox(height: 16),
                    Text("Route Active",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color:
                                isDark ? AppTheme.white : AppTheme.deepForest)),
                    Text("Searching for riders along your route...",
                        style: GoogleFonts.poppins(
                            color: AppTheme.dustySage, fontSize: 14)),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(
                                color: Colors.redAccent.withOpacity(0.5),
                                width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _endEntireTrip,
                          child: Text("END SHIFT",
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ),
                      ),
                    ),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isAwaiting
                          ? Colors.orangeAccent.withOpacity(0.2)
                          : Colors.blueAccent.withOpacity(0.2),
                      child: Icon(
                          isAwaiting
                              ? Icons.hail_rounded
                              : Icons.local_taxi_rounded,
                          color: isAwaiting
                              ? Colors.orangeAccent
                              : Colors.blueAccent),
                    ),
                    title: Text("Passenger (${p['seats_booked']} seats)",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color:
                                isDark ? AppTheme.white : AppTheme.deepForest)),
                    subtitle: Text(
                        isAwaiting
                            ? "Awaiting Pickup (Hold to cancel)"
                            : "In Transit",
                        style: GoogleFonts.poppins(
                            color: isAwaiting
                                ? Colors.orangeAccent
                                : Colors.blueAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    onLongPress: () {
                      if (isAwaiting)
                        _cancelNoShowPassenger(
                            p['passenger_id'], p['seats_booked']);
                    },
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: isAwaiting
                              ? AppTheme.mutedPine
                              : Colors.redAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: () {
                        if (isAwaiting) {
                          _showOtpBottomSheet(
                              p['passenger_id'],
                              p['otp'] ?? "1234",
                              (p['fare'] ?? 0.0).toDouble());
                        } else {
                          _dropOffPassenger(p);
                        }
                      },
                      child: Text(isAwaiting ? "PICKUP" : "DROP OFF",
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
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
