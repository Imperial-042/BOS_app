// lib/core/navigation/shell/module_body.dart
//
// Screen area: optional page switcher above a lazily-built, kept-alive stack of views.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bos_application/core/navigation/bos_registry.dart';
import 'package:bos_application/core/navigation/shell/module_hub.dart';

/// Builds a view the first time it is opened, then keeps it alive.
class _LazyStack extends StatefulWidget {
  const _LazyStack({required this.selectedKey, required this.onOpen});

  final String selectedKey;
  final ValueChanged<String> onOpen;

  @override
  State<_LazyStack> createState() => _LazyStackState();
}

class _LazyStackState extends State<_LazyStack>
    with SingleTickerProviderStateMixin {
  final Set<String> _visited = {};
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(covariant _LazyStack old) {
    super.didUpdateWidget(old);
    if (old.selectedKey != widget.selectedKey) _fade.forward(from: 0.15);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Widget _buildView(BuildContext context, String key) {
    final destination = bosDestById[key];

    // Not a destination, so it is a module landing page.
    if (destination == null) {
      final module = BosModule.values.firstWhere((m) => bosHubKey(m) == key);
      return BosModuleHub(info: bosModuleInfo[module]!, onOpen: widget.onOpen);
    }

    final builder = destination.builder;
    return builder != null
        ? builder(context)
        : BosComingSoonView(destination: destination);
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.selectedKey);
    final index = bosViewKeys.indexOf(widget.selectedKey);

    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(
        index: index < 0 ? 0 : index,
        children: [
          for (final key in bosViewKeys)
            _visited.contains(key)
                ? _buildView(context, key)
                : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// Screen area: an optional module page switcher above the current view.
/// On very wide screens the content is centred and capped in width.
class BosModuleBody extends StatelessWidget {
  const BosModuleBody({super.key, 
    required this.module,
    required this.destinationId,
    required this.viewKey,
    required this.showSwitcher,
    required this.onOpenModule,
    required this.onOpenDestination,
  });

  final BosModule module;
  final String? destinationId;
  final String viewKey;

  /// Rail-less layouts have no sub-menu, so a page switcher is shown here.
  final bool showSwitcher;
  final ValueChanged<BosModule> onOpenModule;
  final ValueChanged<String> onOpenDestination;

  @override
  Widget build(BuildContext context) {
    final info = bosModuleInfo[module]!;
    final inModulePage = info.homeId == null && destinationId != null;

    return Column(
      children: [
        if (showSwitcher && inModulePage)
          BosModuleSwitcher(
            info: info,
            destinationId: destinationId,
            onBack: () => onOpenModule(module),
            onOpen: onOpenDestination,
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(
                constraints.maxWidth,
                Breakpoints.maxContent,
              );
              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: _LazyStack(
                    selectedKey: viewKey,
                    onOpen: onOpenDestination,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
