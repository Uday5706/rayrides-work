import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rayride/nav_bar.dart';

// 🟢 Updated import path as requested
import 'core/app_theme.dart';
import 'ride_booking_screen.dart';

class roleSelection extends StatefulWidget {
  const roleSelection({super.key});

  @override
  State<roleSelection> createState() => _RoleSelectionState();
}

class _RoleSelectionState extends State<roleSelection>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeTitle;
  late Animation<Offset> _slideTitle;
  late Animation<Offset> _slideCommuter;
  late Animation<Offset> _slideDriver;

  @override
  void initState() {
    super.initState();
    // 🟢 Staggered Entrance Animations Setup
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeTitle = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    _slideTitle =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic)),
    );

    _slideCommuter =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic)),
    );

    _slideDriver =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animationController,
          curve: const Interval(0.4, 0.9, curve: Curves.easeOutCubic)),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<bool> checkConnection() async {
    var result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 🟢 THEME TOGGLE
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: Icon(
                    currentMode == ThemeMode.light
                        ? Icons.dark_mode
                        : Icons.light_mode,
                    color: isDark ? AppTheme.softMint : AppTheme.deepForest,
                  ),
                  onPressed: () {
                    themeNotifier.value = currentMode == ThemeMode.light
                        ? ThemeMode.dark
                        : ThemeMode.light;
                  },
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        // 🟢 Theme-aware subtle gradient background
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [AppTheme.deepForest, const Color(0xFF2A5240)]
                : [AppTheme.white, AppTheme.softMint.withOpacity(0.5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _fadeTitle,
                    child: SlideTransition(
                      position: _slideTitle,
                      child: Column(
                        children: [
                          Icon(Icons.route_rounded,
                              size: 64, color: AppTheme.mutedPine),
                          const SizedBox(height: 16),
                          Text(
                            'Choose Your Path',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'How would you like to use RayRide today?',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // 🟢 ANIMATED COMMUTER CARD
                  SlideTransition(
                    position: _slideCommuter,
                    child: FadeTransition(
                      opacity: _fadeTitle,
                      child: _RoleCard(
                        title: 'I am a Commuter',
                        subtitle: 'Find rides and travel comfortably',
                        icon: Icons.directions_walk_rounded,
                        isPrimary: false,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RideBookingScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 🟢 ANIMATED DRIVER CARD
                  SlideTransition(
                    position: _slideDriver,
                    child: FadeTransition(
                      opacity: _fadeTitle,
                      child: _RoleCard(
                        title: 'I am a Driver',
                        subtitle: 'Publish routes and share your journey',
                        icon: Icons.drive_eta_rounded,
                        isPrimary: true, // Highlights this card slightly more
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const DriverApp()),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 🟢 CUSTOM ANIMATED PRESSABLE CARD WIDGET
class _RoleCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Styling based on primary/secondary and theme
    final bgColor = widget.isPrimary
        ? AppTheme.mutedPine
        : (isDark ? AppTheme.deepForest : AppTheme.white);

    final borderColor =
        widget.isPrimary ? Colors.transparent : AppTheme.mutedPine;

    final textColor = widget.isPrimary
        ? AppTheme.white
        : (isDark ? AppTheme.white : AppTheme.deepForest);

    final subtitleColor = widget.isPrimary
        ? AppTheme.white.withOpacity(0.8)
        : (isDark ? AppTheme.dustySage : AppTheme.dustySage);

    return GestureDetector(
      onTapDown: (_) => _scaleController.reverse(),
      onTapUp: (_) {
        _scaleController.forward();
        widget.onTap();
      },
      onTapCancel: () => _scaleController.forward(),
      child: ScaleTransition(
        scale: _scaleController,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black26
                    : AppTheme.dustySage.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.isPrimary
                      ? AppTheme.white.withOpacity(0.2)
                      : AppTheme.softMint.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 32, color: textColor),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: textColor.withOpacity(0.5), size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const mainnavbar();
  }
}
