import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class C {
  static const bg = Color(0xFF0D1B2A);
  static const bgCard = Color(0xFF162032);
  static const bgElevated = Color(0xFF1C2B3D);
  static const bgInput = Color(0xFF0D1B2A);
  static const border = Color(0xFF2A3F55);
  static const borderLight = Color(0xFF1F3248);
  static const primary = Color(0xFF00C6FF);
  static const primaryDark = Color(0xFF0099CC);
  static const accent = Color(0xFFFF6B35);
  static const green = Color(0xFF00E676);
  static const yellow = Color(0xFFFFD600);
  static const red = Color(0xFFFF4444);
  static const purple = Color(0xFFB388FF);
  static const text = Color(0xFFE8F4FD);
  static const textMuted = Color(0xFF6B8FAF);
  static const textDim = Color(0xFF3D5A73);
  static const white = Color(0xFFFFFFFF);

  static Color statusColor(String status) {
    const map = {
      'Checked In':       Color(0xFF29B6F6),
      'Diagnosed':        Color(0xFFAB47BC),
      'Awaiting Approval':Color(0xFFFF7043),
      'Waiting for Parts':Color(0xFFFFA726),
      'In Repair':        Color(0xFF00C6FF),
      'Testing':          Color(0xFF26C6DA),
      'QC Passed':        Color(0xFF66BB6A),
      'Ready for Pickup': Color(0xFF00E676),
      'Completed':        Color(0xFF69F0AE),
      'On Hold':          Color(0xFFFFD600),
      'Cancelled':        Color(0xFFFF4444),
      'Warranty Claim':   Color(0xFFEF5350),
    };
    return map[status] ?? const Color(0xFF6B8FAF);
  }

  static String statusIcon(String status) {
    const map = {
      'Checked In':       '📥',
      'Diagnosed':        '🔍',
      'Awaiting Approval':'⏳',
      'Waiting for Parts':'📦',
      'In Repair':        '🔧',
      'Testing':          '🧪',
      'QC Passed':        '✅',
      'Ready for Pickup': '🎉',
      'Completed':        '🏁',
      'On Hold':          '⏸️',
      'Cancelled':        '❌',
      'Warranty Claim':   '🛡️',
    };
    return map[status] ?? '•';
  }

  static String? statusNext(String status) {
    const map = {
      'Checked In':       'Diagnosed',
      'Diagnosed':        'Awaiting Approval',
      'Awaiting Approval':'In Repair',
      'Waiting for Parts':'In Repair',
      'In Repair':        'Testing',
      'Testing':          'QC Passed',
      'QC Passed':        'Ready for Pickup',
      'Ready for Pickup': 'Completed',
    };
    return map[status];
  }

  static Color tierColor(String tier) {
    const map = {
      'Gold':     Color(0xFFF59E0B),
      'Silver':   Color(0xFF94A3B8),
      'Platinum': Color(0xFFA78BFA),
      'Bronze':   Color(0xFFB45309),
    };
    return map[tier] ?? const Color(0xFF6B8FAF);
  }

  static Color timelineTypeColor(String type) {
    const map = {
      'flow':   Color(0xFF00C6FF),
      'note':   Color(0xFF6B8FAF),
      'hold':   Color(0xFFFFD600),
      'cancel': Color(0xFFFF4444),
      'reopen': Color(0xFF00E676),
    };
    return map[type] ?? const Color(0xFF6B8FAF);
  }
}

ThemeData buildTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.primary, secondary: C.accent, surface: C.bgCard, error: C.red,
    ),
    textTheme: GoogleFonts.syneTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.white),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bgElevated, foregroundColor: C.white, elevation: 0,
      titleTextStyle: GoogleFonts.syne(fontSize: 18, fontWeight: FontWeight.w800, color: C.white),
      iconTheme: const IconThemeData(color: C.white),
    ),
    cardTheme: const CardThemeData(color: C.bgCard, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: C.bgInput,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.primary, width: 2)),
      labelStyle: const TextStyle(color: C.textMuted, fontSize: 12),
      hintStyle: const TextStyle(color: C.textDim, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    dividerColor: C.border,
    dividerTheme: const DividerThemeData(color: C.border, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : C.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary.withValues(alpha: 0.4) : C.border),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primary : Colors.transparent),
      side: const BorderSide(color: C.border, width: 2),
    ),
  );
}
