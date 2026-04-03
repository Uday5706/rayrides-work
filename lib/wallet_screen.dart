import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double balance = 0.0;
  bool isLoading = true;

  final Color primaryGreen = const Color(0xFF2E7D32); // Elegant dark green
  final Color lightGreen = const Color(0xFFE8F5E9);
  final Color accentGreen = const Color(0xFF4CAF50);

  @override
  void initState() {
    super.initState();
    _fetchOnlyWalletBalance();
  }

  // 🟢 ULTRA-SIMPLIFIED LOGIC: Just gets the balance.
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
      // 🟢 GUARANTEE THE LOADER STOPS SPINNING
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: primaryGreen))
            : Column(
                children: [
                  _buildHeader(),
                  _buildSummaryCards(),
                  _buildTransactionTitle(),
                  _buildTransactionList(),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryGreen,
        child: const Icon(Icons.account_balance, color: Colors.white),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Withdrawal system coming soon!")));
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primaryGreen,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('My Wallet',
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w500)),
              const Icon(Icons.settings, color: Colors.white),
            ],
          ),
          const SizedBox(height: 25),
          Text('₹${balance.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              )),
          const SizedBox(height: 4),
          Text('Available Balance (Penalties & Extras)',
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.white.withOpacity(0.9))),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildGlassCard(Icons.calendar_today, 'Today',
              '₹0'), // Hardcoded for now to prevent loader freeze
          _buildGlassCard(Icons.bar_chart, 'Weekly',
              '₹0'), // Hardcoded for now to prevent loader freeze
          _buildGlassCard(Icons.download, 'Withdraw', 'Cash Out'),
        ],
      ),
    );
  }

  Widget _buildGlassCard(IconData icon, String title, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: lightGreen, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 26, color: accentGreen),
            const SizedBox(height: 10),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent Activity',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87)),
          Icon(Icons.filter_list, color: primaryGreen),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text("No recent transactions",
                style:
                    GoogleFonts.poppins(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
