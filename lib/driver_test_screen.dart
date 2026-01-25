import 'package:flutter/material.dart';
import 'package:rayride/services/driver_socket_service.dart';

class DriverTestScreen extends StatefulWidget {
  @override
  State<DriverTestScreen> createState() => _DriverTestScreenState();
}

class _DriverTestScreenState extends State<DriverTestScreen> {
  final driverSocket = DriverSocketService();

  @override
  void initState() {
    super.initState();
    driverSocket.connect("TEST_RIDE_001");
  }

  @override
  void dispose() {
    driverSocket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Driver Simulator")),
      body: Center(child: Text("🚗 Sending location...")),
    );
  }
}
