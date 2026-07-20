import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String phone;
  final List<String> roles; // ['rider', 'driver']

  // Rider fields
  final double negativeBalance;
  final double riderRating;

  // Driver fields
  final bool isDriverVerified;
  final DateTime? subEnd; // Null if no active subscription

  UserModel({
    required this.uid,
    required this.name,
    required this.phone,
    required this.roles,
    required this.negativeBalance,
    required this.riderRating,
    required this.isDriverVerified,
    this.subEnd,
  });

  // 🟢 READ FROM FIRESTORE
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      roles: List<String>.from(data['roles'] ?? ['rider']), // Default to rider
      negativeBalance: (data['negative_balance'] ?? 0.0).toDouble(),
      riderRating: (data['rating'] ?? 5.0).toDouble(),
      isDriverVerified: data['is_driver_verified'] ?? false,
      subEnd: data['sub_end'] != null
          ? (data['sub_end'] as Timestamp).toDate()
          : null,
    );
  }

  // 🟢 WRITE TO FIRESTORE
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'roles': roles,
      'negative_balance': negativeBalance,
      'rating': riderRating,
      'is_driver_verified': isDriverVerified,
      'sub_end': subEnd != null ? Timestamp.fromDate(subEnd!) : null,
    };
  }

  // Helper method for UI logic
  bool get isDriverActive => subEnd != null && subEnd!.isAfter(DateTime.now());
}
