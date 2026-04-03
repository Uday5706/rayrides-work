import 'package:cloud_firestore/cloud_firestore.dart'; // Add Firestore import
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:rayride/Otp_verify_screen.dart';
// Import your next screen so you can navigate after auto-login
// import 'package:rayride/role_selection_screen.dart';

class loginscreen extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _LoginScreenState();
  }
}

class _LoginScreenState extends State<loginscreen> {
  TextEditingController phonenumber = TextEditingController();
  FirebaseAuth _auth = FirebaseAuth.instance;

  String formatPhoneNumber(String input) {
    input = input.replaceAll(RegExp(r'\D'), ''); // Remove all non-digits
    if (input.startsWith('91') && input.length == 12) {
      return '+$input';
    } else if (input.length == 10) {
      return '+91$input'; // Default to India
    }
    return '+$input'; // Fallback, use at own risk
  }

  void sendotp() async {
    String phone = formatPhoneNumber(phonenumber.text);

    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (PhoneAuthCredential credential) async {
        print("Auto verification completed!");

        try {
          // 1. Sign the user in
          UserCredential userCredential =
              await _auth.signInWithCredential(credential);

          // 2. Save user to Firestore
          if (userCredential.user != null) {
            final user = userCredential.user!;

            // Use SetOptions(merge: true) so you don't overwrite existing data
            // if an older user logs in again.
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              'uid': user.uid,
              'phone': user.phoneNumber,
              'created_at': FieldValue.serverTimestamp(),
              'is_active': true,
              // Add any other default fields here
            }, SetOptions(merge: true));

            print("User saved to Firestore!");

            // 3. Navigate to your main dashboard or role selection screen
            // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const roleSelection()));
          }
        } catch (e) {
          print("Auto sign-in failed: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        print("Verification failed: ${e.message}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Verification failed: ${e.message}")),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        print("Code sent: $verificationId");
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OTPscreen(verificationId: verificationId),
          ),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        print("Timeout: $verificationId");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Login Screen'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                SizedBox(height: 32),
                Container(
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 32),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.smartphone,
                                size: 40, color: Colors.grey[600]),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 24,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(Icons.message,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 32),
                      Text(
                        'Enter your phone number',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'We will send you a verification code to this number.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 32),
                      TextField(
                        controller: phonenumber,
                        decoration: InputDecoration(
                          hintText: 'Mobile Number',
                          hintStyle:
                              TextStyle(color: Colors.grey[400], fontSize: 16),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                        keyboardType: TextInputType.phone,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            sendotp();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFF7043),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            'Send',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
