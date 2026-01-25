import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:rayride/models/booking_model.dart'; // Ensure this path is correct

class OfflineBookingsScreen extends StatefulWidget {
  const OfflineBookingsScreen({super.key});

  @override
  _OfflineBookingsScreenState createState() => _OfflineBookingsScreenState();
}

class _OfflineBookingsScreenState extends State<OfflineBookingsScreen> {
  // We use a Future to ensure the box is open before we build the listenable
  late Future<Box> _openBoxFuture;

  @override
  void initState() {
    super.initState();
    // Pre-opening the box to avoid late initialization crashes
    _openBoxFuture = Hive.openBox('offline_bookings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        centerTitle: true,
        elevation: 0,
        title: const Text(
          "Offline Booking Logs",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: FutureBuilder<Box>(
        future: _openBoxFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.deepOrange));
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error opening logs: ${snapshot.error}"));
          }

          // ValueListenableBuilder listens to Hive changes in real-time
          return ValueListenableBuilder(
            valueListenable: snapshot.data!.listenable(),
            builder: (context, Box box, _) {
              final bookings = box.values.toList();

              if (bookings.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: bookings.length,
                itemBuilder: (context, index) {
                  // Map the Hive data to your Booking Model
                  final rawData = bookings[index];
                  final Booking booking =
                      Booking.fromMap(Map<String, dynamic>.from(rawData));

                  return _buildBookingCard(booking, box);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBookingCard(Booking booking, Box box) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 3,
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: const CircleAvatar(
          backgroundColor: Colors.orangeAccent,
          child: Icon(Icons.cloud_off, color: Colors.white),
        ),
        title: Text(
          "${booking.pickup} ➔ ${booking.drop}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.fromLTRB(0, 8.0, 0, 0),
          child: Text(
            "Fare: ₹${booking.fare.toStringAsFixed(2)}",
            style: const TextStyle(
                color: Colors.green, fontWeight: FontWeight.w600),
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: () async {
            // Delete using the ID stored in the model
            await box.delete(booking.id);
            _showSnackBar("Log deleted");
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text("No offline bookings found",
              style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
