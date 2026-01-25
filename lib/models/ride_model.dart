class Ride {
  final String rideId;
  final String bookingId;
  final String driverId;
  final String commuterId;

  final String pickup;
  final String drop;

  final String
  status; // requested | accepted | arrived | ongoing | completed | cancelled
  final DateTime startedAt;

  Ride({
    required this.rideId,
    required this.bookingId,
    required this.driverId,
    required this.commuterId,
    required this.pickup,
    required this.drop,
    required this.status,
    required this.startedAt,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      rideId: json['rideId'],
      bookingId: json['bookingId'],
      driverId: json['driverId'],
      commuterId: json['commuterId'],
      pickup: json['pickup'],
      drop: json['drop'],
      status: json['status'],
      startedAt: DateTime.parse(json['startedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rideId': rideId,
      'bookingId': bookingId,
      'driverId': driverId,
      'commuterId': commuterId,
      'pickup': pickup,
      'drop': drop,
      'status': status,
      'startedAt': startedAt.toIso8601String(),
    };
  }
}
