// lib/widgets/wallet_balance_card.dart
import 'package:flutter/material.dart';

import '../services/payment_service.dart';
import '../services/user_service.dart';

class WalletBalanceCard extends StatelessWidget {
  final String userId;
  final UserService _userService = UserService();
  final PaymentService _paymentService = PaymentService();

  WalletBalanceCard({Key? key, required this.userId}) : super(key: key) {
    // Initialize Razorpay listeners
    _paymentService.initialize(userId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: _userService.streamNegativeBalance(userId),
      builder: (context, snapshot) {
        // 1. Handle Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator(color: Color(0xFF1F5E43));
        }

        // 2. Handle Error State
        if (snapshot.hasError) {
          return Text('Error loading balance');
        }

        final double negativeBalance = snapshot.data ?? 0.0;

        // 3. Build the UI reactively
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1710), // RayRides Dark Theme
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "PENDING DUES",
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "₹${negativeBalance.toStringAsFixed(2)}",
                style: TextStyle(
                  color: negativeBalance > 0 ? Colors.redAccent : Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              // Only show the pay button if they actually owe money
              if (negativeBalance > 0) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF10B981), // RayRides Green
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      // Trigger the backend order creation and Razorpay UI
                      _paymentService.initiateClearBalance();
                    },
                    child: const Text(
                      "Clear Balance Now",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text("Account is clear. Ready to ride!",
                        style: TextStyle(color: Color(0xFF10B981))),
                  ],
                )
              ]
            ],
          ),
        );
      },
    );
  }
}
