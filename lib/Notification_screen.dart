import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// 🟢 Premium Theme Import
import 'core/app_theme.dart';

class Notificationscreen extends StatefulWidget {
  const Notificationscreen({super.key});

  @override
  State<Notificationscreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<Notificationscreen> {
  List<Map<String, dynamic>> allNotifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    final userBox = await Hive.openBox('userBox');
    final userId = userBox.get('userId') ?? 'demoDriver';

    try {
      final response = await http
          .get(Uri.parse('http://10.0.2.2:3000/api/notifications/$userId'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final List<Map<String, dynamic>> formatted =
            data.map<Map<String, dynamic>>((item) {
          return {
            "icon": _mapStringToIcon(item["icon"]),
            "title": item["title"],
            "subtitle": item["subtitle"],
            "time": DateTime.fromMillisecondsSinceEpoch(item["time"]),
            "read": item["read"],
          };
        }).toList();

        if (mounted) {
          setState(() {
            allNotifications = formatted;
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching notifications: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 🟢 Upgraded to rounded premium icons
  IconData _mapStringToIcon(String iconName) {
    switch (iconName) {
      case 'taxi':
        return Icons.local_taxi_rounded;
      case 'battery':
        return Icons.battery_charging_full_rounded;
      case 'money':
        return Icons.account_balance_wallet_rounded;
      case 'message':
        return Icons.message_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  void markAsRead(Map<String, dynamic> item) {
    setState(() {
      item["read"] = true;
    });
  }

  void removeNotification(Map<String, dynamic> item) {
    setState(() {
      allNotifications.remove(item);
    });
  }

  bool isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    List<Map<String, dynamic>> todayList = allNotifications.where((n) {
      final t = n["time"] as DateTime;
      return isSameDate(t, today);
    }).toList();

    List<Map<String, dynamic>> yesterdayList = allNotifications.where((n) {
      final t = n["time"] as DateTime;
      return isSameDate(t, yesterday);
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppTheme.deepForest : const Color(0xFFF5F7F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("Alerts",
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.white : AppTheme.deepForest)),
        centerTitle: true,
        actions: [
          _buildThemeToggle(isDark),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.mutedPine))
          : allNotifications.isEmpty
              ? _buildEmptyState(isDark)
              : ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  children: [
                    if (todayList.isNotEmpty)
                      SectionHeader(title: "Today", isDark: isDark),
                    ...todayList.map((item) => AnimatedNotificationCard(
                          data: item,
                          onTap: () => markAsRead(item),
                          onDismissed: () => removeNotification(item),
                        )),
                    if (yesterdayList.isNotEmpty) const SizedBox(height: 16),
                    if (yesterdayList.isNotEmpty)
                      SectionHeader(title: "Yesterday", isDark: isDark),
                    ...yesterdayList.map((item) => AnimatedNotificationCard(
                          data: item,
                          onTap: () => markAsRead(item),
                          onDismissed: () => removeNotification(item),
                        )),
                    const SizedBox(height: 100), // Spacing for bottom nav bar
                  ],
                ),
    );
  }

  Widget _buildThemeToggle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, currentMode, child) {
          return IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? AppTheme.softMint : AppTheme.deepForest,
            ),
            onPressed: () {
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded,
              size: 80,
              color: isDark
                  ? AppTheme.dustySage.withOpacity(0.5)
                  : Colors.grey[300]),
          const SizedBox(height: 16),
          Text("You're all caught up!",
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.white : AppTheme.deepForest)),
          const SizedBox(height: 8),
          Text("No new alerts at the moment.",
              style: GoogleFonts.poppins(color: AppTheme.dustySage)),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const SectionHeader({super.key, required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Text(
        title,
        style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.softMint : AppTheme.mutedPine),
      ),
    );
  }
}

class AnimatedNotificationCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const AnimatedNotificationCard({
    super.key,
    required this.data,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  _AnimatedNotificationCardState createState() =>
      _AnimatedNotificationCardState();
}

class _AnimatedNotificationCardState extends State<AnimatedNotificationCard>
    with SingleTickerProviderStateMixin {
  bool isExpanded = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String getFormattedTime(DateTime time) {
    return DateFormat('hh:mm a').format(time);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dismissible(
          key: Key(data["title"] + data["time"].toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 28),
          ),
          onDismissed: (_) {
            widget.onDismissed();
          },
          child: GestureDetector(
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
              widget.onTap();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A5240) : AppTheme.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isDark
                        ? AppTheme.dustySage.withOpacity(0.2)
                        : Colors.transparent),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black26
                        : AppTheme.dustySage.withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.softMint.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(data["icon"],
                            size: 24,
                            color: isDark
                                ? AppTheme.softMint
                                : AppTheme.mutedPine),
                      ),
                      if (!data["read"])
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            height: 14,
                            width: 14,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF2A5240)
                                      : AppTheme.white,
                                  width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data["title"],
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: data["read"]
                                  ? FontWeight.w500
                                  : FontWeight.bold,
                              color: isDark
                                  ? AppTheme.white
                                  : AppTheme.deepForest),
                        ),
                        if (isExpanded)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                              data["subtitle"],
                              style: GoogleFonts.poppins(
                                  color: AppTheme.dustySage,
                                  fontSize: 13,
                                  height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    getFormattedTime(data["time"]),
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: AppTheme.dustySage,
                        fontWeight: FontWeight.w500),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
