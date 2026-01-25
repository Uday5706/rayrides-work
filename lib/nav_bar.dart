import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:rayride/Notification_screen.dart';
import 'package:rayride/dashboard_screen.dart';
import 'package:rayride/driver_map_tracking_screen.dart';
import 'package:rayride/fare_offer_screen.dart';
import 'package:rayride/wallet_screen.dart';

class mainnavbar extends StatefulWidget {
  const mainnavbar({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MainnavbarState();
  }
}

class _MainnavbarState extends State<mainnavbar> {
  List<Widget> _buildscreen() {
    return [
      DashboardScreen(),
      fareOfferScreen(),
      DriverMapTrackingScreen(
        rideData: {},
      ),
      WalletScreen(),
      Notificationscreen(),
    ];
  }

  List<PersistentBottomNavBarItem> _navbaritems() {
    return [
      PersistentBottomNavBarItem(
        icon: Icon(Icons.dashboard),
        title: "Dashboard",
        activeColorPrimary: Colors.blue,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.whatshot, color: Colors.redAccent),
        title: "Fare Offers",
        activeColorPrimary: Colors.redAccent,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.map, color: Colors.green),
        title: "Map",
        activeColorPrimary: Colors.green,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.account_balance_wallet, color: Colors.orange),
        title: "Wallet",
        activeColorPrimary: Colors.orange,
        inactiveColorPrimary: Colors.grey,
      ),
      PersistentBottomNavBarItem(
        icon: Icon(Icons.notifications, color: Colors.purple),
        title: "Notifications",
        activeColorPrimary: Colors.purple,
        inactiveColorPrimary: Colors.grey,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PersistentTabView(
      context,
      controller: PersistentTabController(initialIndex: 0),
      screens: _buildscreen(),
      items: _navbaritems(),
      navBarHeight: 70,
      confineToSafeArea: true,
      backgroundColor: Colors.white70,
      navBarStyle: NavBarStyle.style6,
    );
  }
}
