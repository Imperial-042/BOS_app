// lib/app/access_gate.dart
//
// Waits for the membership to resolve, then opens the shell. The shell is
// KEYED by business + branch + user + role, so switching any of them
// rebuilds it from scratch and no page state (or cached data) from the
// previous business can leak into the next one.

import 'package:bos_application/core/auth/access_revoked_listener.dart';
import 'package:bos_application/core/branch/branch_providers.dart';
import 'package:bos_application/core/device/device_session_watcher.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/app/startup/startup_screens.dart';
import 'package:bos_application/app/startup/no_access_screen.dart';
import 'package:bos_application/core/navigation/shell/navigation_shell.dart';

/// Session side effects that used to run inside BosAccessGate.build().
///
/// Runs when the membership resolves (and again whenever it changes), never
/// from a widget rebuild: starts sync once the member has a usable role.
final accessSessionEffectsProvider = Provider.autoDispose<void>((ref) {
  ref.listen(currentBusinessMembershipProvider, (previous, next) {
    final m = next.asData?.value;
    if (m == null) return;
    final custom = m.role.startsWith(kCustomRolePrefix);
    if (!custom && BosRole.fromId(m.role) == null) return;

    ref.read(syncTriggerServiceProvider).start();
    if (ref.read(supabaseAvailableProvider)) {
      ref.read(deviceSessionWatcherProvider);
    }
  }, fireImmediately: true);
});

class BosAccessGate extends ConsumerWidget {
  const BosAccessGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(accessSessionEffectsProvider);
    final membership = ref.watch(currentBusinessMembershipProvider);

    // The listener wraps BOTH the shell and the "no access" screen, so the
    // removed-access dialog survives the swap between them.
    return AccessRevokedListener(
      child: membership.when(
        loading: () => const BosStartupLoading(),
        error: (e, _) => BosStartupError(
          error: e,
          onRetry: () => ref.invalidate(currentBusinessMembershipProvider),
        ),
        data: (m) {
          final custom = m != null && m.role.startsWith(kCustomRolePrefix);
          if (m == null || (!custom && BosRole.fromId(m.role) == null)) {
            return BosNoAccessScreen(
              onRetry: () => ref.invalidate(currentBusinessMembershipProvider),
            );
          }
          ref.watch(stockProjectionProvider);
          // A custom role's definition arrives with the first sync.
          if (ref.watch(currentRoleProvider) == null) {
            return const BosStartupLoading();
          }
          final assignments = ref.watch(branchMembershipsProvider);
          if (assignments.isLoading && !assignments.hasValue) {
            return const BosStartupLoading();
          }
          return NavigationShell(
            key: ValueKey(
              '${m.businessId}:${ref.watch(selectedBranchIdProvider)}:'
              '${m.userId}:${m.role}',
            ),
          );
        },
      ),
    );
  }
}
