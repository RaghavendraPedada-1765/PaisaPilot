import 'package:flutter/material.dart';

/// Shared palette for the dashboard, activity ledger and import controls.
const teal = Color(0xFF82E5CA);
const _ink = Color(0xFF101816);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: Brightness.dark,
    primary: teal,
    surface: _ink,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF17211E),
      indicatorColor: teal.withValues(alpha: 0.18),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: teal, foregroundColor: _ink, elevation: 2,
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06), space: 1),
  );
}

/// Full-screen backdrop the glass cards sit on.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -1),
            radius: 1.6,
            colors: [Color(0xFF203830), _ink],
          ),
        ),
        child: child,
      );
}

/// Translucent panel with a hairline border.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  // A Material, not a coloured box: list tiles inside paint their tap ripple on
  // the nearest Material, which a coloured box would hide.
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1A2521),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}
