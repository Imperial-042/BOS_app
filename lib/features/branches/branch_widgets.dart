// lib/features/branches/branch_widgets.dart  (NEW FILE)
//
// BranchChip: shows the branch this device works in and lets people with more
// than one branch switch. Hidden when the business has a single branch.

import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BranchChip extends ConsumerWidget {
  const BranchChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(branchesProvider);
    final current = ref.watch(selectedBranchProvider);
    if (all.length < 2 || current == null) return const SizedBox.shrink();

    final businessId = ref.watch(selectedBusinessIdProvider);
    final locked = ref.watch(lockedBranchIdProvider(businessId)) != null;
    final canSwitch = ref.watch(allowedBranchesProvider).length > 1 && !locked;
    final canManage = ref.watch(canProvider(BosPermission.branchManage));

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(
          locked
              ? Icons.lock_outline_rounded
              : Icons.store_mall_directory_outlined,
          size: 16,
        ),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(current.name, overflow: TextOverflow.ellipsis),
        ),
        onPressed: (canSwitch || canManage)
            ? () => showBranchSheet(context)
            : null,
      ),
    );
  }
}

Future<void> showBranchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _BranchSheet(),
  );
}

class _BranchSheet extends ConsumerWidget {
  const _BranchSheet();

  Future<void> _select(BuildContext context, WidgetRef ref, Branch b) async {
    if (ref.read(posOrderProvider).isNotEmpty ||
        ref.read(heldOrdersProvider).isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Finish or discard the open and held orders before switching branch.',
            ),
          ),
        );
      return;
    }
    final businessId = ref.read(selectedBusinessIdProvider);
    await BranchPrefs.save(businessId, b.id);
    ref.read(savedBranchIdProvider(businessId).notifier).state = b.id;
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessId = ref.watch(selectedBusinessIdProvider);
    final allowed = ref.watch(allowedBranchesProvider);
    final currentId = ref.watch(selectedBranchIdProvider);
    final lockedId = ref.watch(lockedBranchIdProvider(businessId));
    final canManage = ref.watch(canProvider(BosPermission.branchManage));
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          const ListTile(
            title: Text(
              'Work in branch',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          for (final b in allowed)
            ListTile(
              leading: Icon(
                b.isHeadquarters
                    ? Icons.home_work_outlined
                    : Icons.store_mall_directory_outlined,
              ),
              title: Text(b.name),
              subtitle: Text(
                [
                  if (b.code != null) b.code!,
                  if (b.isHeadquarters) 'Main branch',
                ].join(' · '),
              ),
              selected: b.id == currentId,
              trailing: b.id == currentId
                  ? const Icon(Icons.check_circle_rounded)
                  : null,
              enabled: lockedId == null,
              onTap: lockedId == null ? () => _select(context, ref, b) : null,
            ),
          if (canManage) ...[
            const Divider(),
            SwitchListTile(
              secondary: Icon(
                Icons.lock_outline_rounded,
                color: scheme.primary,
              ),
              title: const Text('Lock this device to this branch'),
              subtitle: const Text(
                'For a POS tablet: staff can\'t switch to another branch.',
              ),
              value: lockedId != null,
              onChanged: (on) async {
                final value = on ? currentId : null;
                await BranchPrefs.setLock(businessId, value);
                ref.read(lockedBranchIdProvider(businessId).notifier).state =
                    value;
              },
            ),
          ],
        ],
      ),
    );
  }
}
