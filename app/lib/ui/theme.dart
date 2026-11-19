import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';

/// Dark glass on a deep petrol-green canvas, with restrained mint highlights.
/// `teal` is the mint accent (the name predates the palette).
const teal = Color(0xFF82E5CA);
const canvasTop = Color(0xFF0E3533); // petrol green, where the light falls
const canvas = Color(0xFF071716); // the rest of the canvas
const glassFill = Color(0x14FFFFFF); // smoked glass panel tint
const listFill = Color(0x0AFFFFFF); // lighter tint for scrolling lists
const glassEdge = Color(0x1FFFFFFF); // fine translucent border
const textMuted = Color(0xB3E3F1EC); // secondary text, ~70%
const textFaint = Color(0x80E3F1EC); // captions, ~50%
const credit = teal; // money in
const debit = Color(0xFFFFB4A2); // money out: soft coral, never alarm red
const unsortedColor = Color(0xFFF0CB78); // amber for "needs a category"

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: teal,
    brightness: Brightness.dark,
    primary: teal,
    surface: canvas,
  );
  const chipShape = StadiumBorder(side: BorderSide(color: glassEdge));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF20A1F1E),
      indicatorColor: teal.withValues(alpha: 0.18),
      height: 68,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: teal,
      foregroundColor: canvas,
      elevation: 2,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: glassFill,
      selectedColor: teal.withValues(alpha: 0.22),
      side: const BorderSide(color: glassEdge),
      shape: chipShape,
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glassFill,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassEdge)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: glassEdge)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: teal)),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.06), space: 1),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF0C2122), showDragHandle: true),
  );
}

/// Amounts line up in columns: tabular figures on top of [base].
TextStyle? money(TextStyle? base) => base?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// [ms] milliseconds, or none when Android's "remove animations" is on.
Duration motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: ms);

/// Stable per category id, so a category keeps its colour across months.
Color categoryColor(int? id) {
  const colors = [
    Color(0xFF82E5CA), Color(0xFF9BB7FF), Color(0xFFE9A4BC), Color(0xFFD0B0FF),
    Color(0xFF94CBE1), Color(0xFFC8DB8C), Color(0xFFF4B18D), Color(0xFF7FD3E8),
    Color(0xFFB9C3FF), Color(0xFFE6C3A0), Color(0xFFA6E3A1),
  ];
  return id == null ? unsortedColor : colors[id % colors.length];
}

/// Full-screen petrol-green backdrop the glass sits on.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: canvas,
          gradient: RadialGradient(
            center: Alignment(-0.8, -1.1),
            radius: 1.5,
            colors: [canvasTop, canvas],
          ),
        ),
        child: child,
      );
}

/// Smoked-glass panel with a hairline border. A tint, not a blur: these
/// scroll, and real backdrop blur is kept for elevated surfaces.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.fill = glassFill});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color fill;

  // A Material, not a coloured box: list tiles inside paint their tap ripple on
  // the nearest Material, which a coloured box would hide.
  @override
  Widget build(BuildContext context) => Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: glassEdge),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}

/// Frosted surface for elevated sheets: real backdrop blur over the screen
/// behind it.
class FrostedSheet extends StatelessWidget {
  const FrostedSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xD90B2223),
              border: Border(top: BorderSide(color: glassEdge)),
            ),
            // Ripples paint on the nearest Material; keep one above the fill.
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );
}

/// Subtle press feedback: shrinks to 98% while pressed. Taps pass through to
/// the child's own InkWell; nothing moves with reduced motion.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down && !MediaQuery.disableAnimationsOf(context) ? 0.98 : 1,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      );
}

/// Small uppercase-free section label used across screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: textMuted, letterSpacing: 0.2),
      );
}
