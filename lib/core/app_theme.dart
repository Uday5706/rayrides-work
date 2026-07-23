import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// 🟢 GLOBAL THEME CONTROLLER
// You can change this from anywhere in the app to instantly toggle dark/light mode!
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

class AppTheme {
  // --- PALETTE EXTRACTED FROM YOUR IMAGE ---
  static const Color white = Color(0xFFFFFFFF);
  static const Color softMint = Color(0xFFD2E0D5);
  static const Color dustySage = Color(0xFF8FABA0);
  static const Color mutedPine = Color(0xFF5C8B76);
  static const Color deepForest = Color(0xFF1F4332);

  // --- LIGHT THEME ---
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: mutedPine,
    scaffoldBackgroundColor: white,
    cardColor: softMint.withOpacity(0.3),
    appBarTheme: AppBarTheme(
      backgroundColor: white,
      elevation: 0,
      iconTheme: const IconThemeData(color: deepForest),
      titleTextStyle: GoogleFonts.poppins(
        color: deepForest,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: mutedPine,
        foregroundColor: white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: GoogleFonts.poppins(color: deepForest),
      bodyMedium: GoogleFonts.poppins(color: deepForest.withOpacity(0.8)),
    ),
  );

  // --- DARK THEME ---
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: mutedPine,
    scaffoldBackgroundColor:
        deepForest, // 🟢 Deep Forest background for elegance
    cardColor:
        const Color(0xFF2A5240), // Slightly lighter than deep forest for cards
    appBarTheme: AppBarTheme(
      backgroundColor: deepForest,
      elevation: 0,
      iconTheme: const IconThemeData(color: white),
      titleTextStyle: GoogleFonts.poppins(
        color: white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: mutedPine,
        foregroundColor: white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: GoogleFonts.poppins(color: white),
      bodyMedium: GoogleFonts.poppins(color: softMint),
    ),
  );
}
