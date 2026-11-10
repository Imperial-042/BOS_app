import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Shared visual building blocks for every customer screen.

const kCustomerGood = Color(0xFF1F9D74);
const kCustomerWarn = Color(0xFFE08A1E);

/// Brand gradient used by every hero surface in the customer app.
BoxDecoration customerHeroDecoration(ColorScheme scheme, {double radius = 28}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary,
        Color.alphaBlend(
          scheme.tertiary.withValues(alpha: 0.55),
          scheme.primary,
        ),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: scheme.primary.withValues(alpha: 0.25),
        blurRadius: 26,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

class CustomerRing extends StatelessWidget {
  const CustomerRing({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.12), width: 18),
      ),
    ),
  );
}

/// Tonal rounded-square avatar tinted from the store name, so the same
/// store always looks the same.
class CustomerStoreAvatar extends StatelessWidget {
  const CustomerStoreAvatar({super.key, required this.name, this.size = 52});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palettes = <(Color, Color)>[
      (scheme.primaryContainer, scheme.onPrimaryContainer),
      (scheme.secondaryContainer, scheme.onSecondaryContainer),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    ];
    final trimmed = name.trim();
    final (bg, fg) = trimmed.isEmpty
        ? (scheme.surfaceContainerHighest, scheme.onSurfaceVariant)
        : palettes[trimmed.toLowerCase().codeUnits.fold<int>(
                0,
                (a, b) => a + b,
              ) %
              palettes.length];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: trimmed.isEmpty
          ? Icon(Icons.storefront_rounded, color: fg, size: size * 0.5)
          : Text(
              trimmed[0].toUpperCase(),
              style: TextStyle(
                color: fg,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Nudges [color] lighter or darker until it is readable on [background].
Color customerReadableOn(
  Color color,
  Color background, {
  double minRatio = 4.5,
}) {
  if (_contrastRatio(color, background) >= minRatio) return color;
  final hsl = HSLColor.fromColor(color);
  final lighten = background.computeLuminance() < 0.5;
  var l = hsl.lightness;
  for (var i = 0; i < 20; i++) {
    final candidate = hsl.withLightness(l).toColor();
    if (_contrastRatio(candidate, background) >= minRatio) return candidate;
    l = (lighten ? l + 0.05 : l - 0.05).clamp(0.0, 1.0);
  }
  return hsl.withLightness(l).toColor();
}

/// Small rounded label.
///
/// By default it is a soft tint of [color] and its text is adjusted so it
/// stays readable in light and dark themes. Use [solid] on busy or gradient
/// backgrounds (like the store banner): it gets an opaque surface-coloured
/// background so it is visible whatever sits behind it.
class CustomerPill extends StatelessWidget {
  const CustomerPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = solid
        ? scheme.surface
        : color.withValues(alpha: 0.16);
    // What the text really sits on, for the contrast check.
    final effectiveBg = solid
        ? scheme.surface
        : Color.alphaBlend(background, scheme.surface);
    final fg = customerReadableOn(
      solid ? color : Color.lerp(color, scheme.onSurface, 0.25)!,
      effectiveBg,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: solid
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget customerOpenPill(bool open, {bool solid = false}) => CustomerPill(
  label: open ? 'Open now' : 'Closed',
  color: open ? kCustomerGood : const Color(0xFFE5484D),
  icon: open ? Icons.circle : Icons.circle_outlined,
  solid: solid,
);

Color customerStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'pending' => kCustomerWarn,
    'accepted' || 'preparing' => scheme.primary,
    'ready' || 'completed' => kCustomerGood,
    'rejected' || 'cancelled' => scheme.error,
    _ => scheme.onSurfaceVariant,
  };
}

String customerStatusLabel(String status) => switch (status) {
  'pending' => 'Awaiting store',
  'accepted' => 'Accepted',
  'rejected' => 'Declined',
  'preparing' => 'Preparing',
  'ready' => 'Ready for pickup',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => status,
};

String formatCustomerPrice(int cents, String currency) =>
    NumberFormat.currency(
      name: currency,
      symbol: NumberFormat.simpleCurrency(name: currency).currencySymbol,
      decimalDigits: 2,
    ).format(cents / 100);

/// Centered icon + title + message (+ optional action) for empty/error states.
class CustomerStateMessage extends StatelessWidget {
  const CustomerStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// Sliver wrapper so a message can sit inside a CustomScrollView.
Widget customerSliverMessage(Widget message) =>
    SliverFillRemaining(hasScrollBody: false, child: message);