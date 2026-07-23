import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rayride/role_selection_screen.dart';

// 🟢 Import the global theme controller & palette
import './core/app_theme.dart';

class OTPscreen extends StatefulWidget {
  final String verificationId;

  const OTPscreen({super.key, required this.verificationId});

  @override
  State<OTPscreen> createState() => _OTPscreenState();
}

class _OTPscreenState extends State<OTPscreen> {
  final List<TextEditingController> otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false; // 🟢 Added loading state for the verify button

  @override
  void dispose() {
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var node in otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty && index < 5) {
      FocusScope.of(context).requestFocus(otpFocusNodes[index + 1]);
    } else if (value.isEmpty && index > 0) {
      FocusScope.of(context).requestFocus(otpFocusNodes[index - 1]);
    }
  }

  void _verifyOtp() async {
    String otp = otpControllers.map((controller) => controller.text).join();

    if (otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter all 6 digits"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        final user = userCredential.user!;
        final userRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);

        final docSnapshot = await userRef.get();

        if (!docSnapshot.exists) {
          // NEW USER
          await userRef.set({
            'uid': user.uid,
            'phone': user.phoneNumber,
            'rating': 5.0,
            'negative_balance': 0.0,
            'created_at': FieldValue.serverTimestamp(),
            'last_login_at': FieldValue.serverTimestamp(),
            'is_active': true,
            'role': 'user',
          });
          debugPrint("New user created in Firestore!");
        } else {
          // EXISTING USER
          await userRef.update({
            'last_login_at': FieldValue.serverTimestamp(),
          });
          debugPrint("Existing user logged in!");
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("OTP Verified ✅"),
              backgroundColor: AppTheme.mutedPine),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => roleSelection()),
        );
      }
    } catch (e) {
      debugPrint("OTP Verification Failed ❌: $e");
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Invalid OTP Code"),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  void _resendOtp() {
    debugPrint("Resend OTP not implemented.");
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification'),
        centerTitle: true,
        leading:
            BackButton(color: isDark ? AppTheme.white : AppTheme.deepForest),
        actions: [
          // 🟢 THEME TOGGLE
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              return IconButton(
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
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            // 🟢 ELEGANT ENTRANCE ANIMATION (Slide up & Fade in)
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 50 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark
                        ? AppTheme.mutedPine.withOpacity(0.3)
                        : Colors.transparent,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black45
                          : AppTheme.dustySage.withOpacity(0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Verify OTP',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 32),

                    // 🟢 ANIMATED LOCK ICON
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.8, end: 1.0),
                      duration: const Duration(milliseconds: 1000),
                      curve: Curves.elasticOut,
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.deepForest
                              : AppTheme.softMint.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 40,
                          color:
                              isDark ? AppTheme.softMint : AppTheme.mutedPine,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'Enter the 6-digit code sent to your phone',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 32),

                    // 🟢 PREMIUM OTP INPUT FIELDS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        return SizedBox(
                          width: 42,
                          height: 55,
                          child: TextField(
                            controller: otpControllers[index],
                            focusNode: otpFocusNodes[index],
                            maxLength: 1,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color:
                                  isDark ? AppTheme.white : AppTheme.deepForest,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: isDark
                                  ? AppTheme.deepForest.withOpacity(0.5)
                                  : AppTheme.white,
                              contentPadding: EdgeInsets.zero,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? AppTheme.dustySage.withOpacity(0.3)
                                      : AppTheme.softMint,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppTheme.mutedPine,
                                  width: 2,
                                ),
                              ),
                            ),
                            onChanged: (value) => _onOtpChanged(value, index),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),

                    TextButton(
                      onPressed: _resendOtp,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            isDark ? AppTheme.dustySage : AppTheme.mutedPine,
                      ),
                      child: Text(
                        'Resend OTP',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 🟢 VERIFY BUTTON WITH LOADING SPINNER
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verifyOtp,
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: AppTheme.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'VERIFY',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
