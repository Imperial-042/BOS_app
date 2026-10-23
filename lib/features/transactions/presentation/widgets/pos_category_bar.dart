// lib/features/production/presentation/widgets/pos_category_bar.dart
//
// One continuous, horizontally scrollable "track" holding every category as a
// tappable segment. The selected segment is a filled pill that stays scrolled
// into view. Replaces the row of loose ChoiceChips.

import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';

class PosCategoryBar extends StatefulWidget {
  final List<ProductCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  const PosCategoryBar({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<PosCategoryBar> createState() => _PosCategoryBarState();
}

class _PosCategoryBarState extends State<PosCategoryBar> {
  final Map<String, GlobalKey> _keys = {};

  GlobalKey _keyFor(String? id) =>
      _keys.putIfAbsent(id ?? '__all__', () => GlobalKey());

  @override
  void didUpdateWidget(covariant PosCategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keyFor(widget.selectedId).currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final segments = <({String? id, String label})>[
      (id: null, label: 'All'),
      for (final c in widget.categories) (id: c.id, label: c.name),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final s in segments)
                _Segment(
                  key: _keyFor(s.id),
                  label: s.label,
                  selected: widget.selectedId == s.id,
                  onTap: () => widget.onSelected(s.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            child: Text(label, maxLines: 1),
          ),
        ),
      ),
    );
  }
}
