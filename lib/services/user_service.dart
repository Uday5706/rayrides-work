// lib/services/user_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns a real-time stream of the user's negative balance.
  Stream<double> streamNegativeBalance(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data()!.containsKey('negative_balance')) {
        // Convert to double safely, handling both int and double types from Firestore
        return (snapshot.data()!['negative_balance'] as num).toDouble();
      }
      return 0.0; // Default if field doesn't exist
    });
  }
}
