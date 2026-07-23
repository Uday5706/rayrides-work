import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rayride/Otp_verify_screen.dart';

// 🟢 Import the global theme controller & palette
import './core/app_theme.dart';

class loginscreen extends StatefulWidget {
  const loginscreen({super.key});

  @override
  State<StatefulWidget> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<loginscreen> {
  final TextEditingController phonenumber = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false; // 🟢 Added loading state for elegant UX

  String formatPhoneNumber(String input) {
    input = input.replaceAll(RegExp(r'\D'), '');
    if (input.startsWith('91') && input.length == 12) {
      return '+$input';
    } else if (input.length == 10) {
      return '+91$input';
    }
    return '+$input';
  }

  void sendotp() async {
    if (phonenumber.text.isEmpty) return;

    setState(() => _isLoading = true);
    String phone = formatPhoneNumber(phonenumber.text);

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        debugPrint("Auto verification completed!");
        try {
          UserCredential userCredential =
              await _auth.signInWithCredential(credential);
          if (userCredential.user != null) {
            final user = userCredential.user!;
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              'uid': user.uid,
              'phone': user.phoneNumber,
              'created_at': FieldValue.serverTimestamp(),
              'is_active': true,
            }, SetOptions(merge: true));

            debugPrint("User saved to Firestore!");
            // Navigator.pushReplacement(...);
          }
        } catch (e) {
          debugPrint("Auto sign-in failed: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Verification failed: ${e.message}"),
            backgroundColor: Colors.redAccent,
          ),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPscreen(verificationId: verificationId),
          ),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        debugPrint("Timeout: $verificationId");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
        centerTitle: true,
        actions: [
          // 🟢 THEME TOGGLE: Instantly switches the entire app's theme
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
                  offset: Offset(0, 50 * (1 - value)), // Slides up
                  child: Opacity(
                    opacity: value, // Fades in
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
                      'Create Account',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 32),

                    // 🟢 ANIMATED ICON CONTAINER
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
                          Icons.smartphone_rounded,
                          size: 40,
                          color:
                              isDark ? AppTheme.softMint : AppTheme.mutedPine,
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'Enter your phone number',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We will send you a verification code to this number.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 32),

                    // 🟢 THEMED TEXT FIELD
                    TextField(
                      controller: phonenumber,
                      keyboardType: TextInputType.phone,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                          ),
                      decoration: InputDecoration(
                        hintText: 'Mobile Number',
                        hintStyle: TextStyle(
                          color: isDark ? AppTheme.dustySage : Colors.grey[400],
                          fontSize: 16,
                          letterSpacing: 0,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppTheme.deepForest.withOpacity(0.5)
                            : AppTheme.white,
                        prefixIcon: Icon(
                          Icons.phone_outlined,
                          color: AppTheme.mutedPine,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppTheme.dustySage.withOpacity(0.3)
                                : Colors.transparent,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppTheme.mutedPine,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // 🟢 THEMED ELEVATED BUTTON WITH LOADING STATE
                    SizedBox(
                      width: double.infinity,
                      height: 55, // Taller, premium feel
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : sendotp,
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
                                'SEND OTP',
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
