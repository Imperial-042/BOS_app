// lib/core/auth/permission_gate.dart
//
// UI convenience only. Hiding a control is NOT security — every sensitive
// operation is also enforced in the service layer via
// AuthorizationService.require().

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'authorization_providers.dart';
import 'bos_access.dart';

class PermissionGate extends ConsumerWidget {
  /// Shown when the user has [permission] (or any of [anyOf]).
  final BosPermission? permission;
  final List<BosPermission> anyOf;
  final Widget child;

  /// Shown instead when access is denied. Defaults to nothing.
  final Widget? fallback;

  const PermissionGate({
    super.key,
    this.permission,
    this.anyOf = const [],
    required this.child,
    this.fallback,
  }) : assert(permission != null || anyOf.length > 0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authorizationServiceProvider);
    final allowed = permission != null
        ? auth.can(permission!)
        : auth.canAny(anyOf);
    return allowed ? child : (fallback ?? const SizedBox.shrink());
  }
}
