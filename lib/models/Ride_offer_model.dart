class Rideoffer{
Rideoffer({
  required this.rideId,
    required this.pickup,
    required this.drop,
    required this.fare,
    required this.distance,
    required this.status,
    required this.expirytime,
  });

  String rideId; // Unique identifier for the ride offer
  String pickup;
  String drop;
  double fare;
  double distance;
  String status;
  DateTime expirytime;

  factory Rideoffer.fromJson(Map<String, dynamic> json){
    return Rideoffer( rideId: json['rideId'] ?? '',
      pickup: json['pickup'],
     drop: json['drop'],
      fare: json['fare'],
     distance: json['distance'],
    status: json['status'],
   expirytime: DateTime.parse(json['expirytime']),
    );
  }

  Map<String,dynamic> toJson(){
    return {
      'rideId': rideId,
      'pickup': pickup,
      'drop': drop,
      'fare': fare,
      'distance': distance,
      'status': status,
      'expirytime': expirytime.toIso8601String(),
    };
  }
}