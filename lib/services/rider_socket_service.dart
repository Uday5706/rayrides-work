import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class RiderSocketService {
  late IO.Socket socket;

  void connect(
    String rideId, {
    required Future<void> Function({
      required LatLng position,
      required double heading,
    }) onLocation,
  }) {
    socket = IO.io(
      'http://10.0.2.2:3000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      socket.emit("joinRide", rideId);
    });

    socket.on("driverLocation", (data) async {
      await onLocation(
        position: LatLng(
          (data['lat'] as num).toDouble(),
          (data['lng'] as num).toDouble(),
        ),
        heading: (data['heading'] ?? 0).toDouble(),
      );
    });
  }

  void disconnect() {
    socket.disconnect();
  }
}
