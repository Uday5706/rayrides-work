import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// 🟢 Premium Theme Import
import 'core/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  double balance = 0.0;
  bool isLoading = true;

  // 🟢 Animations
  late AnimationController _animController;
  late Animation<Offset> _slideHeader;
  late Animation<double> _scaleCards;
  late Animation<Offset> _slideList;

  @override
  void initState() {
    super.initState();

    // Animation Setup
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _slideHeader =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic)),
    );

    _scaleCards = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.2, 0.8, curve: Curves.elasticOut)),
    );

    _slideList =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(
          parent: _animController,
          curve: const Interval(0.4, 1.0, curve: Curves.easeOutCubic)),
    );

    _fetchOnlyWalletBalance();
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchOnlyWalletBalance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final walletDoc = await FirebaseFirestore.instance
            .collection('wallets')
            .doc(user.uid)
            .get();
        if (walletDoc.exists && mounted) {
          setState(() {
            balance = (walletDoc.data()?['balance'] ?? 0.0).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Wallet Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.deepForest : const Color(0xFFF5F7F5),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.mutedPine))
          : Column(
              children: [
                _buildHeader(isDark),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        _buildSummaryCards(isDark),
                        const SizedBox(height: 10),
                        SlideTransition(
                          position: _slideList,
                          child: Column(
                            children: [
                              _buildTransactionTitle(isDark),
                              _buildTransactionEmptyState(isDark),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: ScaleTransition(
        scale: _scaleCards,
        child: FloatingActionButton.extended(
          backgroundColor: AppTheme.mutedPine,
          elevation: 8,
          icon: const Icon(Icons.account_balance_wallet_rounded,
              color: AppTheme.white),
          label: Text("Withdraw",
              style: GoogleFonts.poppins(
                  color: AppTheme.white, fontWeight: FontWeight.bold)),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Withdrawal system coming soon!"),
                backgroundColor: AppTheme.mutedPine,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final user = FirebaseAuth.instance.currentUser;

    return SlideTransition(
      position: _slideHeader,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [AppTheme.deepForest, const Color(0xFF142C21)]
                : [AppTheme.mutedPine, AppTheme.deepForest],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(40)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.deepForest.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Wallet',
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      color: AppTheme.white,
                      fontWeight: FontWeight.bold),
                ),
                _buildThemeToggle(isDark),
              ],
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  size: 40, color: AppTheme.softMint),
            ),
            const SizedBox(height: 16),
            if (user != null)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('wallets')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  double liveBalance = 0.0;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    liveBalance = (snapshot.data!.data()
                                as Map<String, dynamic>?)?['balance']
                            ?.toDouble() ??
                        0.0;
                  }

                  return Text(
                    '₹${liveBalance.toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.white,
                        letterSpacing: -1),
                  );
                },
              ),
            const SizedBox(height: 4),
            Text(
              'Available Balance (Penalties & Extras)',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppTheme.softMint,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeToggle(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.white.withOpacity(0.2),
            shape: BoxShape.circle,
            border:
                Border.all(color: AppTheme.softMint.withOpacity(0.3), width: 1),
          ),
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              return IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: AppTheme.white,
                  size: 20,
                ),
                onPressed: () {
                  themeNotifier.value =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(bool isDark) {
    return ScaleTransition(
      scale: _scaleCards,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGlassCard(Icons.today_rounded, 'Today', '₹0', isDark),
            _buildGlassCard(Icons.bar_chart_rounded, 'Weekly', '₹0', isDark),
            _buildGlassCard(
                Icons.download_rounded, 'Withdraw', 'Cash Out', isDark,
                isHighlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassCard(IconData icon, String title, String value, bool isDark,
      {bool isHighlight = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: isHighlight
              ? (isDark
                  ? AppTheme.mutedPine.withOpacity(0.8)
                  : AppTheme.mutedPine)
              : (isDark ? const Color(0xFF2A5240) : AppTheme.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isHighlight
                  ? Colors.transparent
                  : (isDark
                      ? AppTheme.dustySage.withOpacity(0.2)
                      : AppTheme.softMint)),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black26
                  : AppTheme.dustySage.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: isHighlight
                      ? AppTheme.white.withOpacity(0.2)
                      : AppTheme.softMint.withOpacity(0.3),
                  shape: BoxShape.circle),
              child: Icon(icon,
                  size: 22,
                  color: isHighlight
                      ? AppTheme.white
                      : (isDark ? AppTheme.softMint : AppTheme.mutedPine)),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: isHighlight ? AppTheme.softMint : AppTheme.dustySage,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isHighlight
                      ? AppTheme.white
                      : (isDark ? AppTheme.white : AppTheme.deepForest)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTitle(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent Activity',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.white : AppTheme.deepForest)),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2A5240)
                  : AppTheme.softMint.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune_rounded,
                color: isDark ? AppTheme.softMint : AppTheme.mutedPine,
                size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 80,
              color: isDark
                  ? AppTheme.dustySage.withOpacity(0.5)
                  : Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No recent transactions",
              style: GoogleFonts.poppins(
                  color: isDark ? AppTheme.dustySage : Colors.grey[500],
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 80), // Padding for the bottom nav bar
        ],
      ),
    );
  }
}
