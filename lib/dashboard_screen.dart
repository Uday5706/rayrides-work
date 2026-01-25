// import 'package:flutter/material.dart';
// import 'package:percent_indicator/percent_indicator.dart';
// import 'package:rayride/driver_ride_history_screen.dart';

// class DashboardScreen extends StatelessWidget {
//   const DashboardScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         backgroundColor: Colors.grey[350],
//         title: Container(
//           padding: EdgeInsets.all(7),
//           child: Row(
//             children: [
//               Text('Rayrides dashboard',
//                   style: TextStyle(fontWeight: FontWeight.bold)),
//               Spacer(),
//               CircleAvatar(
//                 radius: 25,
//                 backgroundColor: Colors.grey[300],
//                 child: Icon(
//                   Icons.person,
//                   size: 30,
//                   color: Colors.black,
//                 ),
//               ),
//               SizedBox(width: 7),
//               Icon(Icons.settings, size: 25, color: Colors.black),
//             ],
//           ),
//         ),
//       ),
//       body: SingleChildScrollView(
//         child: Column(
//           children: [
//             // Battery status
//             Container(
//               height: MediaQuery.of(context).size.height * 0.27,
//               width: double.infinity,
//               margin: EdgeInsets.fromLTRB(4, 0, 4, 0),
//               padding: EdgeInsets.all(10),
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [
//                     Colors.lightBlue.shade50,
//                     Colors.lightBlue.shade100
//                   ],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 boxShadow: [
//                   BoxShadow(
//                     color:
//                         const Color.fromARGB(255, 93, 90, 90).withOpacity(0.5),
//                     spreadRadius: 2,
//                     blurRadius: 10,
//                     offset: Offset(0, 3),
//                   ),
//                 ],
//               ),
//               child: Column(
//                 children: [
//                   Row(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(Icons.battery_charging_full,
//                           size: 25, color: Colors.green),
//                       SizedBox(width: 10),
//                       Text(
//                         'Battery Status: ',
//                         style: TextStyle(
//                             fontWeight: FontWeight.bold, fontSize: 20),
//                       ),
//                       SizedBox(width: 7),
//                       Text(
//                         '76%',
//                         style: TextStyle(fontSize: 20),
//                       ),
//                     ],
//                   ),
//                   SizedBox(height: 19),
//                   CircularPercentIndicator(
//                     radius: 50.0,
//                     lineWidth: 15,
//                     animation: true,
//                     percent: 0.76,
//                     center: Text(
//                       '76%',
//                       style:
//                           TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
//                     ),
//                     footer: Text(
//                       'Battery Status:Good',
//                       style:
//                           TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
//                     ),
//                     circularStrokeCap: CircularStrokeCap.round,
//                     progressColor: Colors.green,
//                     backgroundColor: Colors.grey[300]!,
//                   )
//                 ],
//               ),
//             ),

//             SizedBox(
//               height: MediaQuery.of(context).size.height * 0.25,
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Expanded(
//                     child: Card(
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(15),
//                       ),
//                       shadowColor:
//                           const Color.fromARGB(255, 62, 61, 61).withOpacity(0.5),
//                       child: Container(
//                         padding: EdgeInsets.all(10),
//                         child: Column(
//                           children: [
//                             Row(
//                               children: [
//                                 Image.asset(
//                                   'images/1.jpeg',
//                                   width: 60,
//                                   height: 60,
//                                 ),
//                                 SizedBox(width: 10),
//                                 Expanded(
//                                   child: Text(
//                                     '₹520 Earned today',
//                                     style: TextStyle(
//                                       fontSize: 18,
//                                       fontWeight: FontWeight.bold,
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                             SizedBox(height: 10),
//                             Text(
//                               '5 Rides Completed',
//                               style: TextStyle(
//                                 fontSize: 16,
//                                 color: Colors.grey[600],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                   Expanded(
//                     child: Card(
//                       margin: EdgeInsets.all(10),
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(15),
//                       ),
//                       shadowColor:
//                           const Color.fromARGB(255, 62, 61, 61).withOpacity(0.5),
//                       child: Container(
//                         padding: EdgeInsets.all(10),
//                         child: Column(
//                           children: [
//                             Row(
//                               children: [
//                                 Image.asset(
//                                   'images/2.png',
//                                   width: 60,
//                                   height: 60,
//                                 ),
//                                 SizedBox(width: 10),
//                                 Expanded(
//                                   child: Text(
//                                     '23.4 km Driven today',
//                                     style: TextStyle(
//                                       fontSize: 18,
//                                       fontWeight: FontWeight.bold,
//                                     ),
//                                   ),
//                                 ),
//                               ],
//                             ),
//                             SizedBox(height: 10),
//                             Text(
//                               'Today\'s Distance',
//                               style: TextStyle(
//                                 fontSize: 16,
//                                 color: Colors.grey[600],
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             Container(
//               padding: EdgeInsets.all(10),
//               child: Column(
//                 children: [
//                   Text(
//                     'Alerts!',
//                     style: TextStyle(
//                       fontSize: 25,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   SizedBox(height: 15),
//                   buildAlertTile('Check Tire pressure'),
//                   SizedBox(height: 15),
//                   buildAlertTile('Battery Below 25%'),
//                 ],
//               ),
//             ),

//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10),
//               child: SizedBox(
//                 width: double.infinity,
//                 height: 55,
//                 child: ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.blue,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                   onPressed: () {

//                     print("View Full Report Pressed");
//                   },
//                   child: Text(
//                     'View Full Report',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                 ),
//               ),
//             ),

//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10),
//               child: SizedBox(
//                 width: double.infinity,
//                 height: 55,
//                 child: ElevatedButton(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.blue,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                   onPressed: () {
//                     Navigator.push(context, MaterialPageRoute(builder:  (context) => DriverRideHistoryScreen()));

//                   },
//                   child: Text(
//                     'View Ride History',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                       color: Colors.white,
//                     ),
//                   ),
//                 ),
//               ),
//             )
//           ],
//         ),
//       ),
//     );
//   }

//   Widget buildAlertTile(String title) {
//     return Container(
//       decoration: BoxDecoration(
//         border: Border.all(color: Colors.amber),
//         gradient: LinearGradient(
//           colors: [Colors.amber.shade100, Colors.amber.shade200],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(10),
//       ),
//       padding: EdgeInsets.all(10),
//       child: Row(
//         children: [
//           Icon(Icons.warning_amber_outlined, color: Colors.amber),
//           SizedBox(width: 10),
//           Expanded(
//             child: Text(
//               title,
//               style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//             ),
//           ),
//           ElevatedButton(onPressed: () {}, child: Text('View')),
//           SizedBox(width: 5),
//           Icon(Icons.cancel_outlined, color: Colors.white),
//         ],
//       ),
//     );
//   }
// }

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:percent_indicator/percent_indicator.dart';
import 'package:rayride/driver_ride_history_screen.dart';
import 'package:rayride/role_selection_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double batteryLevel = 0.0;
  int totalCompletedRides = 0;
  double totalEarnings = 0.0;

  @override
  void initState() {
    super.initState();
    fetchDashboardData();
  }

  void _backToRoleSelection(BuildContext context) {
    // Use pushAndRemoveUntil to clear the entire navigation history
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (context) =>
              const roleSelection() // Replace with your actual class name
          ),
      (Route<dynamic> route) =>
          false, // This condition removes all previous routes
    );
  }

  Future<void> fetchDashboardData() async {
    final userBox = await Hive.openBox('userBox');
    final userId = userBox.get('userId') ?? 'demoDriver';

    try {
      // 🔋 Fetch battery level
      final userResponse =
          await http.get(Uri.parse('http://localhost:3000/api/users/$userId'));
      if (userResponse.statusCode == 200) {
        final user = jsonDecode(userResponse.body);
        batteryLevel = (user['batteryLevel'] ?? 0) / 100;
      }

      // 🚗 Fetch driver rides
      final ridesResponse = await http.get(Uri.parse(
          'http://localhost:3000/api/users/$userId/rides?role=driver'));
      if (ridesResponse.statusCode == 200) {
        final rides = jsonDecode(ridesResponse.body);
        final completedRides =
            rides.where((ride) => ride['status'] == 'accepted').toList();
        totalCompletedRides = completedRides.length;
        totalEarnings =
            completedRides.fold(0.0, (sum, ride) => sum + (ride['fare'] ?? 0));
      }

      setState(() {});
    } catch (e) {
      print("❌ Error fetching dashboard data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final batteryPercentText = '${(batteryLevel * 100).toInt()}%';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey[350],
        title: Row(
          children: [
            Text('Rayrides dashboard',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Spacer(),
            CircleAvatar(
              radius: 25,
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.person, size: 30, color: Colors.black),
            ),
            SizedBox(width: 7),
            Icon(Icons.settings, size: 25, color: Colors.black),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🔋 Battery status
            Container(
              height: MediaQuery.of(context).size.height * 0.27,
              width: double.infinity,
              margin: EdgeInsets.fromLTRB(4, 0, 4, 0),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.lightBlue.shade50, Colors.lightBlue.shade100],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        const Color.fromARGB(255, 93, 90, 90).withOpacity(0.5),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.battery_charging_full,
                          size: 25, color: Colors.green),
                      SizedBox(width: 10),
                      Text('Battery Status: ',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(width: 7),
                      Text(batteryPercentText, style: TextStyle(fontSize: 20)),
                    ],
                  ),
                  SizedBox(height: 19),
                  CircularPercentIndicator(
                    radius: 50.0,
                    lineWidth: 15,
                    animation: true,
                    percent: batteryLevel,
                    center: Text(batteryPercentText,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 20)),
                    footer: Text('Battery Status: Good',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    circularStrokeCap: CircularStrokeCap.round,
                    progressColor: Colors.green,
                    backgroundColor: Colors.grey[300]!,
                  )
                ],
              ),
            ),

            // 💰 Earnings and Rides
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.25,
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                        '₹${totalEarnings.toStringAsFixed(2)} Earned',
                        '$totalCompletedRides Rides Completed',
                        'images/1.jpeg'),
                  ),
                  Expanded(
                    child: _buildStatCard('23.4 km Driven Today',
                        'Today\'s Distance', 'images/2.png'),
                  ),
                ],
              ),
            ),

            // ⚠️ Alerts
            Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                children: [
                  Text('Alerts!',
                      style:
                          TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                  SizedBox(height: 15),
                  buildAlertTile('Check Tire pressure'),
                  SizedBox(height: 15),
                  buildAlertTile('Battery Below 25%'),
                ],
              ),
            ),

            // 🔘 Buttons
            _buildButton('Log Out', () => _backToRoleSelection(context)),
            _buildButton('View Ride History', () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => DriverRideHistoryScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String subtitle, String imagePath) {
    return Card(
      margin: EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      shadowColor: Colors.grey.withOpacity(0.5),
      child: Container(
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Image.asset(imagePath, width: 60, height: 60),
                SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(subtitle,
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget buildAlertTile(String title) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber),
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.amber.shade200],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: EdgeInsets.all(10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ElevatedButton(onPressed: () {}, child: Text('View')),
          SizedBox(width: 5),
          Icon(Icons.cancel_outlined, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onPressed,
          child: Text(label,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ),
      ),
    );
  }
}
