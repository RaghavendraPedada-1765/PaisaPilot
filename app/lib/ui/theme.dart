import 'package:flutter/material.dart';

/// Dark glass look with a teal accent. Colours are a first pass; the UI
/// details are still to be agreed.
const teal = Color(0xFF2DD4BF);
const _ink = Color(0xFF0B1416);

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
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      indicatorColor: teal.withValues(alpha: 0.18),
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
            colors: [Color(0xFF0F3A3A), _ink],
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
        color: Colors.white.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}
