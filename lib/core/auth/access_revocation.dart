// lib/core/auth/access_revocation.dart
//
// Set by SyncTriggerService when the cloud says the signed-in user no longer
// has access to the selected business. AccessRevokedListener shows the
// warning dialog while this is non-null.

import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccessRevocation {
  const AccessRevocation({
    required this.businessId,
    required this.businessName,
  });

  final String businessId;
  final String businessName;
}

final accessRevocationProvider = StateProvider<AccessRevocation?>(
  (ref) => null,
);
