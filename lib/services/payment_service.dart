import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';

class PaymentService {
  late Razorpay _razorpay;
  final String _backendUrl =
      dotenv.env['BACKEND_URL'] ?? "http://10.0.2.2:3000";

  // 🟢 Callbacks to let the UI know when to stop loading spinners
  VoidCallback? onPaymentSuccess;
  Function(String)? onPaymentError;

  void initialize(String userId,
      {VoidCallback? onSuccess, Function(String)? onError}) {
    _razorpay = Razorpay();
    onPaymentSuccess = onSuccess;
    onPaymentError = onError;

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
  }

  // ==========================================
  // FLOW 1: CLEAR PENALTY
  // ==========================================
  Future<void> initiateClearBalance() async {
    try {
      final String? dynamicUid = FirebaseAuth.instance.currentUser?.uid;
      if (dynamicUid == null) throw Exception("User session expired.");

      final response = await http.post(
        Uri.parse('$_backendUrl/api/payments/create-order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': dynamicUid}),
      );

      if (response.statusCode != 200)
        throw Exception("Server error ${response.statusCode}");
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        var options = {
          'key': data['key'],
          'amount': data['amount'],
          'name': 'RayRides Platform',
          'order_id': data['orderId'],
          'description': 'Negative Balance Settlement',
          'theme': {'color': '#1F5E43'},
        };
        _razorpay.open(options);
      }
    } catch (e) {
      debugPrint('Gateway Dispatch Error: $e');
      if (onPaymentError != null) onPaymentError!(e.toString());
      rethrow;
    }
  }

  // ==========================================
  // FLOW 2: BUY SUBSCRIPTION
  // ==========================================
  Future<void> initiateSubscriptionCheckout(String planId) async {
    try {
      final String? dynamicUid = FirebaseAuth.instance.currentUser?.uid;
      if (dynamicUid == null) throw Exception("User session expired.");

      final response = await http.post(
        Uri.parse('$_backendUrl/api/subscriptions/checkout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'driver_id': dynamicUid,
          'plan_id': planId,
        }),
      );

      if (response.statusCode != 200)
        throw Exception("Server error ${response.statusCode}");
      final data = jsonDecode(response.body);

      // 🟢 INSTANT ACTIVATION (Covered by Wallet or Global Free Tier)
      if (data['requires_payment'] == false) {
        debugPrint("Activated via Wallet or Free Tier!");
        if (onPaymentSuccess != null) onPaymentSuccess!();
        return;
      }

      // 🟢 PARTIAL/FULL PAYMENT REQUIRED (Open Razorpay)
      var options = {
        'key': data['key'],
        'amount': data['amount_due'] * 100, // convert INR to paise
        'name': 'RayRides Captain Pro',
        'order_id': data['order_id'],
        'description': '30-Day Pass',
        'theme': {'color': '#2E7D32'},
      };

      _razorpay.open(options);
    } catch (e) {
      debugPrint('Subscription Dispatch Error: $e');
      if (onPaymentError != null) onPaymentError!(e.toString());
      rethrow;
    }
  }

  // --- INTERNAL HANDLERS ---
  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    debugPrint("✅ Razorpay UI Success. Awaiting Webhook settlement...");
    if (onPaymentSuccess != null) onPaymentSuccess!();
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    debugPrint("Transaction Dropped: ${response.message}");
    if (onPaymentError != null)
      onPaymentError!(response.message ?? "Unknown Error");
  }

  void dispose() {
    _razorpay.clear();
  }
}
