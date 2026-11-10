// lib/features/customer/presentation/customer_menu_drawer.dart
//
// End-drawer for the customer app: profile, discovery area, QR scan,
// business-mode switch and a confirmed sign out.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Asks for confirmation before signing out. Returns true when confirmed.
Future<bool> confirmCustomerSignOut(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      icon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.logout_rounded,
          color: scheme.onErrorContainer,
          size: 28,
        ),
      ),
      title: const Text(
        'Sign out?',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: const Text(
        'You can sign back in any time. Your followed stores, orders and '
        'points stay safe on your account.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return ok == true;
}

class CustomerMenuDrawer extends StatelessWidget {
  const CustomerMenuDrawer({
    super.key,
    required this.city,
    required this.onProfile,
    required this.onLocation,
    required this.onScan,
    required this.onSignOut,
    this.onAddresses,
    this.onSwitchToBusiness,
    this.displayName,
    this.activeOrders = 0,
    this.onOrders,
    this.onHelp,
    this.onPrivacy,
  });

  /// Current discovery city (empty when not set).
  final String city;
  final VoidCallback onProfile;
  final VoidCallback onLocation;
  final VoidCallback onScan;
  final VoidCallback onSignOut;
  final VoidCallback? onAddresses;
  final VoidCallback? onSwitchToBusiness;

  /// Customer's name (null/empty shows "Welcome back").
  final String? displayName;

  /// Orders still in progress; shown as a badge on "My orders".
  final int activeOrders;

  /// Optional entries: each is hidden when its callback is null.
  final VoidCallback? onOrders;
  final VoidCallback? onHelp;
  final VoidCallback? onPrivacy;

  /// Closes the drawer first, then runs [action] so navigation is clean.
  void _go(BuildContext context, VoidCallback action) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCity = city.isNotEmpty;

    return Drawer(
      width: math.min(340, MediaQuery.sizeOf(context).width * 0.86),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            name: displayName,
            city: city,
            onClose: () => Navigator.of(context).pop(),
            onLocation: () => _go(context, onLocation),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
              children: [
                const _Reveal(index: 0, child: _SectionLabel('Account')),
                _Reveal(
                  index: 1,
                  child: _MenuTile(
                    icon: Icons.person_rounded,
                    color: scheme.primary,
                    title: 'My profile',
                    subtitle: 'Name, contact and personal details',
                    onTap: () => _go(context, onProfile),
                  ),
                ),
                _Reveal(
                  index: 2,
                  child: _MenuTile(
                    icon: Icons.location_on_rounded,
                    color: const Color(0xFFE08A1E),
                    title: 'Discovery area',
                    subtitle: hasCity
                        ? 'Showing stores near $city'
                        : 'Set your city to find stores',
                    badge: hasCity ? null : 'Set up',
                    onTap: () => _go(context, onLocation),
                  ),
                ),
                if (onAddresses != null)
                  _Reveal(
                    index: 3,
                    child: _MenuTile(
                      icon: Icons.bookmark_border_rounded,
                      color: const Color(0xFF0F766E),
                      title: 'Saved addresses',
                      subtitle: 'Manage delivery locations',
                      onTap: () => _go(context, onAddresses!),
                    ),
                  ),
                const SizedBox(height: 14),
                const _Reveal(index: 3, child: _SectionLabel('Shortcuts')),
                if (onOrders != null)
                  _Reveal(
                    index: 4,
                    child: _MenuTile(
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF8B5CF6),
                      title: 'My orders',
                      subtitle: activeOrders > 0
                          ? '$activeOrders in progress'
                          : 'Track and review your orders',
                      badge: activeOrders > 0 ? '$activeOrders active' : null,
                      onTap: () => _go(context, onOrders!),
                    ),
                  ),
                _Reveal(
                  index: 4,
                  child: _MenuTile(
                    icon: Icons.qr_code_scanner_rounded,
                    color: const Color(0xFF1F9D74),
                    title: 'Scan store QR',
                    subtitle: 'Open a store from its invitation code',
                    onTap: () => _go(context, onScan),
                  ),
                ),
                if (onHelp != null || onPrivacy != null) ...[
                  const SizedBox(height: 14),
                  const _Reveal(index: 5, child: _SectionLabel('Support')),
                  if (onHelp != null)
                    _Reveal(
                      index: 6,
                      child: _MenuTile(
                        icon: Icons.support_agent_rounded,
                        color: const Color(0xFF3B82F6),
                        title: 'Help & support',
                        subtitle: 'Get answers or contact the team',
                        onTap: () => _go(context, onHelp!),
                      ),
                    ),
                  if (onPrivacy != null)
                    _Reveal(
                      index: 6,
                      child: _MenuTile(
                        icon: Icons.privacy_tip_rounded,
                        color: const Color(0xFF14B8A6),
                        title: 'Privacy & terms',
                        subtitle: 'How your data is used',
                        onTap: () => _go(context, onPrivacy!),
                      ),
                    ),
                ],
                if (onSwitchToBusiness != null) ...[
                  const SizedBox(height: 14),
                  const _Reveal(index: 5, child: _SectionLabel('Mode')),
                  _Reveal(
                    index: 6,
                    child: _BusinessCard(
                      onTap: () => _go(context, onSwitchToBusiness!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Reveal(
            index: 7,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: scheme.errorContainer.withValues(
                          alpha: 0.6,
                        ),
                        foregroundColor: scheme.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: () => _go(context, onSignOut),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Sign out',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'BOS Customer',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- header --

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.city,
    required this.onClose,
    required this.onLocation,
  });

  final String? name;
  final String city;
  final VoidCallback onClose;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final hasCity = city.isNotEmpty;
    final hasName = (name ?? '').trim().isNotEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
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
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -70,
            child: _Ring(size: 210, color: scheme.onPrimary),
          ),
          Positioned(
            left: -50,
            bottom: -80,
            child: _Ring(size: 150, color: scheme.onPrimary),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 10, 12, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close menu',
                    onPressed: onClose,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.onPrimary.withValues(alpha: 0.16),
                      foregroundColor: scheme.onPrimary,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Avatar with soft halo.
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.onPrimary.withValues(alpha: 0.45),
                          width: 2,
                        ),
                      ),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.onPrimary.withValues(alpha: 0.2),
                        ),
                        child: Center(
                          child: hasName
                              ? Text(
                                  customerInitials(name),
                                  style: TextStyle(
                                    color: scheme.onPrimary,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  size: 36,
                                  color: scheme.onPrimary,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasName ? name!.trim() : 'Welcome back',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your BOS customer account',
                            style: TextStyle(
                              color: scheme.onPrimary.withValues(alpha: 0.82),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                InkWell(
                  onTap: onLocation,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.onPrimary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: scheme.onPrimary.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasCity
                              ? Icons.location_on_rounded
                              : Icons.add_location_alt_outlined,
                          size: 16,
                          color: scheme.onPrimary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            hasCity ? city : 'Set your city',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.1), width: 20),
      ),
    ),
  );
}

// ----------------------------------------------------------------- items --

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary,
                      Color.alphaBlend(
                        scheme.tertiary.withValues(alpha: 0.55),
                        scheme.primary,
                      ),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: scheme.onPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch to business mode',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Manage sales, stock and your team',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.swap_horiz_rounded, color: scheme.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft staggered entrance: fades and slides in from the right.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset((1 - v) * 24, 0), child: c),
      ),
      child: child,
    );
  }
}

/// "Maria Santos" -> "MS", "Maria" -> "M", empty -> "?".
String customerInitials(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
