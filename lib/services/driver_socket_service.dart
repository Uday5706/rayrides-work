import 'package:socket_io_client/socket_io_client.dart' as IO;

class DriverSocketService {
  late IO.Socket socket;

  void connect(String rideId) {
    socket = IO.io(
      'http://10.0.2.2:3000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print("🟢 Driver socket connected");
      socket.emit("joinRide", rideId);
    });

    socket.onDisconnect((_) {
      print("🔴 Driver socket disconnected");
    });
  }

  void sendLocation(double lat, double lng, double heading, String rideId) {
    if (!socket.connected) return;

    socket.emit("driverLocation", {
      "rideId": rideId,
      "lat": lat,
      "lng": lng,
      "heading": heading,
    });
  }

  void disconnect() {
    if (socket.connected) {
      socket.disconnect();
    }
  }
}
