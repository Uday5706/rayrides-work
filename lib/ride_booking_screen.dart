import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_google_places_hoc081098/flutter_google_places_hoc081098.dart';
import 'package:flutter_google_places_hoc081098/google_maps_webservice_places.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart'
    as polyline;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_webservice/places.dart' as gm_webservice;
import 'package:hive/hive.dart';
import 'package:rayride/offline_Booking_Screen.dart';
import 'package:uuid/uuid.dart';

import 'live_ride_tracking_screen.dart';

class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  _RideBookingScreenState createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _fareController = TextEditingController();

  String _locationStatus = "Detecting current location...";
  Position? _currentPosition;
  Set<Marker> _markers = {};
  LatLng? _dropLatLng;
  Map<PolylineId, Polyline> _polylines = {};
  List<LatLng> _polylineCoordinates = [];
  bool _isSearching = false;
  String? _currentRideId;
  StreamSubscription<DocumentSnapshot>? _rideSubscription;

  final String _pickupId = "pickup_marker";
  final String _dropId = "drop_marker";

  final String kGoogleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
  final LatLng _defaultCenter = const LatLng(28.6139, 77.2090);

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  @override
  void dispose() {
    _rideSubscription?.cancel(); // Cancel listener to prevent memory leaks
    super.dispose();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    _currentPosition = position;

    String address =
        await _getAddressFromLatLng(position.latitude, position.longitude);

    setState(() {
      _locationStatus = "Location Detected";
      _pickupController.text = address;
      _moveToPosition(LatLng(position.latitude, position.longitude), "Pickup",
          isPickup: true);
    });
  }

  Future<String> _getAddressFromLatLng(double lat, double lng) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      Placemark place = placemarks[0];
      return "${place.name}, ${place.subLocality}, ${place.locality}";
    } catch (e) {
      return "Point ($lat, $lng)";
    }
  }

  void _moveToPosition(LatLng target, String title, {required bool isPickup}) {
    String mId = isPickup ? _pickupId : _dropId;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15));

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == mId);
      _markers.add(
        Marker(
          markerId: MarkerId(mId),
          position: target,
          infoWindow: InfoWindow(title: title),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isPickup ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed),
        ),
      );
    });

    if (_currentPosition != null && _dropLatLng != null) {
      _getRoute();
    }
  }

  Future<void> _getRoute() async {
    polyline.PolylinePoints polylinePoints =
        polyline.PolylinePoints(apiKey: kGoogleApiKey);
    polyline.PolylineResult result =
        await polylinePoints.getRouteBetweenCoordinates(
      request: polyline.PolylineRequest(
        origin: polyline.PointLatLng(
            _currentPosition!.latitude, _currentPosition!.longitude),
        destination:
            polyline.PointLatLng(_dropLatLng!.latitude, _dropLatLng!.longitude),
        mode: polyline.TravelMode.driving,
      ),
    );

    if (result.points.isNotEmpty) {
      _polylineCoordinates.clear();
      for (var point in result.points) {
        _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
      }

      setState(() {
        _polylines[const PolylineId("ride_route")] = Polyline(
          polylineId: const PolylineId("ride_route"),
          color: Colors.blueAccent,
          points: _polylineCoordinates,
          width: 6,
          jointType: JointType.round,
        );
      });
      _zoomToFit();
    }
  }

  void _zoomToFit() {
    if (_mapController == null ||
        _currentPosition == null ||
        _dropLatLng == null) return;

    LatLng p1 = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    LatLng p2 = _dropLatLng!;
    LatLngBounds bounds;

    if (p1.latitude > p2.latitude && p1.longitude > p2.longitude) {
      bounds = LatLngBounds(southwest: p2, northeast: p1);
    } else if (p1.longitude > p2.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p1.latitude, p2.longitude),
          northeast: LatLng(p2.latitude, p1.longitude));
    } else if (p1.latitude > p2.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(p2.latitude, p1.longitude),
          northeast: LatLng(p1.latitude, p2.longitude));
    } else {
      bounds = LatLngBounds(southwest: p1, northeast: p2);
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _onMapTap(LatLng tappedPoint) async {
    setState(() => _dropLatLng = tappedPoint);
    String address = await _getAddressFromLatLng(
        tappedPoint.latitude, tappedPoint.longitude);
    setState(() => _dropController.text = address);
    _moveToPosition(tappedPoint, "Drop Location", isPickup: false);
  }

  Future<void> _handleAutocomplete(
      TextEditingController controller, bool isPickup) async {
    var p = await PlacesAutocomplete.show(
      context: context,
      apiKey: kGoogleApiKey,
      mode: Mode.overlay,
      language: "en",
      components: [Component(Component.country, "in")],
    );

    if (p != null) {
      final places = gm_webservice.GoogleMapsPlaces(apiKey: kGoogleApiKey);
      final detail = await places.getDetailsByPlaceId(p.placeId!);
      final lat = detail.result.geometry!.location.lat;
      final lng = detail.result.geometry!.location.lng;
      LatLng target = LatLng(lat, lng);

      setState(() {
        controller.text = p.description!;
        if (isPickup) {
          _currentPosition = Position(
              latitude: lat,
              longitude: lng,
              timestamp: DateTime.now(),
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0);
        } else {
          _dropLatLng = target;
        }
      });
      _moveToPosition(target, p.description!, isPickup: isPickup);
    }
  }

  Future<bool> _isOnline() async {
    try {
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  // UPDATED: Confirm booking now includes real-time handshake logic
  Future<void> _confirmBooking() async {
    if (_dropController.text.isEmpty || _fareController.text.isEmpty) {
      _showSnackBar("Please provide all details", Colors.red);
      return;
    }

    bool online = await _isOnline();
    final String rideId = const Uuid().v4();
    _currentRideId = rideId;
    final double fare = double.tryParse(_fareController.text) ?? 100.0;
    final String otp =
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    if (online) {
      setState(() => _isSearching = true);
      try {
        await FirebaseFirestore.instance.collection('rides').doc(rideId).set({
          'rideId': rideId,
          'pickup_name': _pickupController.text,
          'drop_name': _dropController.text,
          'pickup_lat': _currentPosition!.latitude,
          'pickup_lng': _currentPosition!.longitude,
          'drop_lat': _dropLatLng!.latitude,
          'drop_lng': _dropLatLng!.longitude,
          'fare': fare,
          'status': 'searching', //change to searching to work properly
          'otp': otp,
          'timestamp': FieldValue.serverTimestamp(),
        });

        // HANDSHAKE LISTENER: Triggers when driver clicks "Accept"
        _rideSubscription = FirebaseFirestore.instance
            .collection('rides')
            .doc(rideId)
            .snapshots()
            .listen((snapshot) {
          if (snapshot.exists) {
            var data = snapshot.data() as Map<String, dynamic>;
            if (data['status'] == 'accepted') {
              _rideSubscription?.cancel(); // Stop listening
              if (!mounted) return;

              setState(() => _isSearching = false);

              // Move to Tracking Screen immediately
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => LiveRideTrackingScreen(
                    rideId: rideId,
                    rideData: data,
                  ),
                ),
              );
            }
          }
        });
      } catch (e) {
        setState(() => _isSearching = false);
        _showSnackBar(
            "Booking failed: Please check Firebase Rules", Colors.red);
      }
    } else {
      final box = await Hive.openBox('offline_bookings');
      await box.put(rideId, {
        'pickup': _pickupController.text,
        'drop': _dropController.text,
        'fare': fare
      });
      _showSnackBar("Saved to Offline Logs", Colors.orange);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: _defaultCenter, zoom: 13.0),
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers,
            polylines: Set<Polyline>.of(_polylines.values),
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),
          _buildTopOverlay(),
          _buildBottomOverlay(),
          if (_isSearching) _buildSearchingLoader(),
        ],
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Column(
        children: [
          _buildSearchBox(
              "Pickup",
              _pickupController,
              () => _handleAutocomplete(_pickupController, true),
              Icons.circle,
              Colors.blueAccent),
          const SizedBox(height: 10),
          _buildSearchBox(
              "Where to?",
              _dropController,
              () => _handleAutocomplete(_dropController, false),
              Icons.location_on,
              Colors.redAccent),
        ],
      ),
    );
  }

  Widget _buildBottomOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _glassContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location, color: Colors.blueAccent),
              title: const Text("Current Location"),
              subtitle: Text(_locationStatus),
              trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _determinePosition),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _fareController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "Proposed Fare (₹)"),
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        padding: const EdgeInsets.symmetric(vertical: 15)),
                    onPressed: _confirmBooking,
                    child: const Text("Confirm Ride",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Colors.orangeAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const OfflineBookingsScreen()));
                    },
                    child: const Icon(Icons.access_time,
                        color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingLoader() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        color: Colors.black26,
        child: Center(
          child: _glassContainer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.orangeAccent),
                const SizedBox(height: 20),
                const Text("Finding nearby drivers...",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text("Drivers within 500m are being notified"),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    _rideSubscription?.cancel();
                    FirebaseFirestore.instance
                        .collection('rides')
                        .doc(_currentRideId)
                        .delete();
                    setState(() => _isSearching = false);
                  },
                  child: const Text("Cancel Search",
                      style: TextStyle(color: Colors.red)),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox(String hint, TextEditingController controller,
      VoidCallback onTap, IconData prefixIcon, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: TextField(
        controller: controller,
        readOnly: true,
        onTap: onTap,
        decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon, color: iconColor, size: 18),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15)),
      ),
    );
  }

  Widget _glassContainer({required Widget child}) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)]),
      child: child,
    );
  }
}
