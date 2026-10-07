import 'package:flutter/material.dart';

/// Deadzone's visual identity: think "signal bleeding through static."
/// Near-black background, a single hot signal-orange accent for anything
/// "live" (connected peers, active relay), and a cold teal for anything
/// "stored/secure" (encrypted, saved locally). The contrast between the
/// two colors is doing a lot of the storytelling: orange = radio signal
/// right now, teal = the locked box nobody else can open.
class AppColors {
  static const Color void_ = Color(0xFF0A0B0D); // near-black background
  static const Color surface = Color(0xFF14161A); // card/sheet background
  static const Color surfaceRaised = Color(0xFF1C1F24);
  static const Color signal = Color(0xFFFF6B35); // live/active accent (orange)
  static const Color secure = Color(0xFF2DD4BF); // encrypted/local accent (teal)
  static const Color danger = Color(0xFFFF3B5C); // SOS / broadcast
  static const Color textPrimary = Color(0xFFF4F4F5);
  static const Color textMuted = Color(0xFF8B8D98);
  static const Color divider = Color(0xFF26292F);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.void_,
      primaryColor: AppColors.signal,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: AppColors.signal,
        secondary: AppColors.secure,
        error: AppColors.danger,
        surface: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.void_,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 12),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: AppColors.divider,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.signal,
        foregroundColor: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.signal,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceRaised,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

/// Signal strength → color, used anywhere we show connection quality
/// (peer list, radar blips, message hop indicators).
Color signalStrengthColor(int strength) {
  if (strength >= 3) return AppColors.signal;
  if (strength >= 1) return AppColors.secure;
  return AppColors.textMuted;
}