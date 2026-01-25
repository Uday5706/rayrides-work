import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class RiderSocketService {
  late IO.Socket socket;

  // Change this IP if testing on a Real Device (use 192.168.x.x)
  // 10.0.2.2 only works if you are on the Android Emulator
  final String _serverUrl = 'http://10.0.2.2:3000';

  void connect(
    String rideId, {
    required Function({
      required LatLng position,
      required double heading,
    }) onLocation,
  }) {
    print("🔌 Attempting to connect to $_serverUrl for ride: $rideId");

    socket = IO.io(
      _serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket']) // Forces WebSocket only (no polling)
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print("✅ Rider Socket Connected! ID: ${socket.id}");
      // CRITICAL: We must emit 'joinRide' to receive updates for this specific ride
      socket.emit("joinRide", rideId);
    });

    socket.onConnectError((data) => print("❌ Socket Connection Error: $data"));
    socket.onDisconnect((_) => print("⚠️ Rider Socket Disconnected"));

    // Listen for driver location
    socket.on("driverLocation", (data) {
      // Debug print to confirm data reached the phone
      print("📥 RECEIVED SOCKET DATA: $data");

      try {
        if (data == null) return;

        // Robust parsing to handle String/Double/Int differences
        double lat = double.parse(data['lat'].toString());
        double lng = double.parse(data['lng'].toString());
        double heading = double.parse((data['heading'] ?? 0).toString());

        onLocation(
          position: LatLng(lat, lng),
          heading: heading,
        );
      } catch (e) {
        print("💥 Error parsing driver location: $e");
      }
    });
  }

  void disconnect() {
    if (socket.connected) {
      socket.disconnect();
    }
  }
}
