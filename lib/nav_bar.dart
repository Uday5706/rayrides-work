import 'package:flutter/material.dart';
import 'package:persistent_bottom_nav_bar/persistent_bottom_nav_bar.dart';
import 'package:rayride/Notification_screen.dart';
import 'package:rayride/dashboard_screen.dart';
import 'package:rayride/fare_offer_screen.dart';
import 'package:rayride/wallet_screen.dart';

// 🟢 Import your global theme palette
import 'core/app_theme.dart';

/// ✅ GLOBAL CONTROLLER
final PersistentTabController mainNavController =
    PersistentTabController(initialIndex: 0);

class mainnavbar extends StatefulWidget {
  const mainnavbar({super.key});

  @override
  State<StatefulWidget> createState() => _MainnavbarState();
}

class _MainnavbarState extends State<mainnavbar> {
  List<Widget> _buildscreen() {
    return [
      const DashboardScreen(),
      const fareOfferScreen(),
      const WalletScreen(),
      const Notificationscreen(),
    ];
  }

  List<PersistentBottomNavBarItem> _navbaritems(bool isDark) {
    final Color activeColor = isDark ? AppTheme.softMint : AppTheme.mutedPine;
    final Color inactiveColor =
        isDark ? AppTheme.dustySage.withOpacity(0.6) : AppTheme.dustySage;

    return [
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.dashboard_rounded),
        title: "Dashboard",
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.local_fire_department_rounded),
        title: "Offers",
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      // 🟢 MAP TAB REMOVED - NOW A 4-TAB LAYOUT
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.account_balance_wallet_rounded),
        title: "Wallet",
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
      PersistentBottomNavBarItem(
        icon: const Icon(Icons.notifications_rounded),
        title: "Alerts",
        activeColorPrimary: activeColor,
        inactiveColorPrimary: inactiveColor,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PersistentTabView(
      context,
      controller: mainNavController,
      screens: _buildscreen(),
      items: _navbaritems(isDark),
      navBarHeight: 70,
      padding: const EdgeInsets.only(
        left: 10,
        right: 10,
      ),
      confineToSafeArea: true,
      handleAndroidBackButtonPress: true,
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? AppTheme.deepForest : AppTheme.white,
      decoration: NavBarDecoration(
        colorBehindNavBar: isDark ? AppTheme.deepForest : AppTheme.white,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.4)
                : AppTheme.dustySage.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      navBarStyle: NavBarStyle.style12,
    );
  }
}
