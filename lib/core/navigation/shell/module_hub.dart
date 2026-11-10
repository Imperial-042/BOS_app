// lib/core/navigation/shell/module_hub.dart
//
// Module landing page ("hub"), page switcher and the "coming soon" placeholder.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/navigation/bos_registry.dart';
import 'package:bos_application/core/navigation/bos_permissions.dart';

/// A module's landing page: what it offers, and what is still to come.
class BosModuleHub extends ConsumerWidget {
  const BosModuleHub({super.key, required this.info, required this.onOpen});

  final BosModuleInfo info;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = ref.watch(authorizationServiceProvider);
    final all = visibleDestinations(auth, info.module);
    final ready = all.where((d) => d.isAvailable).toList();
    final soon = all.where((d) => !d.isAvailable).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(16.0, (constraints.maxWidth - 1000) / 2);

        return ListView(
          padding: EdgeInsets.fromLTRB(side, 20, side, 32),
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    info.selectedIcon,
                    size: 26,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        info.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (ready.isNotEmpty) _HubGrid(items: ready, onOpen: onOpen),
            if (soon.isNotEmpty) ...[
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Coming soon',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _HubGrid(items: soon, onOpen: onOpen),
            ],
          ],
        );
      },
    );
  }
}

/// Responsive card grid. Cards size to their content, so nothing can overflow
/// at large text sizes.
class _HubGrid extends StatelessWidget {
  const _HubGrid({required this.items, required this.onOpen});

  final List<BosDestination> items;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const minCardWidth = 300.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = math.min(
          3,
          math.max(1, ((available + gap) / (minCardWidth + gap)).floor()),
        );
        final cardWidth = (available - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in items)
              SizedBox(
                width: cardWidth,
                child: _HubCard(destination: d, onTap: () => onOpen(d.id)),
              ),
          ],
        );
      },
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.destination, required this.onTap});

  final BosDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = destination.isAvailable;
    final opensAsRoute = destination.presentation == BosPresentation.route;

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: available
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  destination.icon,
                  size: 22,
                  color: available
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: available ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!available)
                const _SoonPill()
              else
                Icon(
                  opensAsRoute
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: opensAsRoute ? 18 : 22,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonPill extends StatelessWidget {
  const _SoonPill();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Soon',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Back-to-module button plus quick switching between the module's pages.
/// Shown when there is no extended rail to nest them in.
class BosModuleSwitcher extends ConsumerWidget {
  const BosModuleSwitcher({super.key, 
    required this.info,
    required this.destinationId,
    required this.onBack,
    required this.onOpen,
  });

  final BosModuleInfo info;
  final String? destinationId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authorizationServiceProvider);
    final pages = visibleAvailable(
      auth,
      info.module,
    ).where((d) => d.presentation == BosPresentation.embedded).toList();

    return Material(
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'All of ${info.label}',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    for (final d in pages)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: ChoiceChip(
                          label: Text(d.label),
                          showCheckmark: false,
                          selected: d.id == destinationId,
                          onSelected: (_) => onOpen(d.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for destinations that are planned but not built. Deliberately
/// does nothing except say so.
class BosComingSoonView extends StatelessWidget {
  const BosComingSoonView({super.key, required this.destination});

  final BosDestination destination;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  destination.icon,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const _SoonPill(),
              const SizedBox(height: 12),
              Text(
                destination.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'This part of BOS isn\'t available yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
