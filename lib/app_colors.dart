import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors (matching the logo)
  static const Color background = Color(0xFF0A0F1D); // Deep dark navy blue
  static const Color surface = Color(0xFF161F33);    // Slightly lighter navy for cards/containers
  static const Color surfaceLight = Color(0xFF1F2B47); // Even lighter navy for active/hover states
  
  static const Color primary = Color(0xFF39D353);    // Vibrant neon battery green
  static const Color secondary = Color(0xFFFFB800);  // Golden yellow (matching the bell)
  static const Color accent = Color(0xFF00D2FF);     // Cyan blue for charging effects
  
  // Status Colors
  static const Color alert = Color(0xFFEF4444);      // Red for error/high battery alerts
  static const Color success = Color(0xFF10B981);    // Green for success/done states
  
  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF); // White text
  static const Color textSecondary = Color(0xFF94A3B8); // Slate gray text
  static const Color textMuted = Color(0xFF64748B);     // Muted gray text
  
  // Border & Divider Colors
  static const Color border = Color(0xFF23314F);      // Border color for cards
  
  // Gradient Colors
  static const List<Color> batteryGradient = [
    Color(0xFF10B981),
    Color(0xFF39D353),
  ];
  
  static const List<Color> alertGradient = [
    Color(0xFFFFB800),
    Color(0xFFFF7A00),
  ];

  static const List<Color> backgroundGradient = [
    Color(0xFF0A0F1D),
    Color(0xFF050810),
  ];
}
