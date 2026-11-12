// lib/core/auth/business_membership_lookup.dart
//
// "Does this account belong to a business, and as what?" Local database
// first, then the cloud when it is configured. Moved out of
// CustomerCommerceService: these are account questions, not commerce ones.

import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

class BusinessMembershipLookup {
  BusinessMembershipLookup(this.db, {SupabaseClient? client})
    : _client = client;

  final AppDatabase db;
  final SupabaseClient? _client;

  Future<bool> hasBusinessMembership(String userId) async {
    final local =
        await (db.select(db.businessMembers)..where(
              (member) =>
                  member.userId.equals(userId) & member.status.equals('active'),
            ))
            .get();
    if (local.isNotEmpty) return true;
    final owned = await (db.select(
      db.businesses,
    )..where((business) => business.ownerUserId.equals(userId))).get();
    if (owned.isNotEmpty) return true;
    final client = _client;
    if (client == null) return false;

    final memberships = await client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', userId)
        .eq('status', 'active')
        .limit(1);
    return memberships.isNotEmpty;
  }

  Future<bool> hasOwnerBusinessMembership(String userId) async {
    final owned = await (db.select(
      db.businesses,
    )..where((business) => business.ownerUserId.equals(userId))).get();
    if (owned.isNotEmpty) return true;

    final localOwner =
        await (db.select(db.businessMembers)..where(
              (member) =>
                  member.userId.equals(userId) &
                  member.role.equals('owner') &
                  member.status.equals('active'),
            ))
            .getSingleOrNull();
    if (localOwner != null) return true;
    final client = _client;
    if (client == null) return false;

    final memberships = await client
        .from('business_memberships')
        .select('business_id')
        .eq('user_id', userId)
        .eq('role', 'owner')
        .eq('status', 'active')
        .limit(1);
    return memberships.isNotEmpty;
  }

  Future<bool> hasTeamBusinessMembership(String userId) async {
    if (!await hasBusinessMembership(userId)) return false;
    if (await hasOwnerBusinessMembership(userId)) return false;
    return true;
  }
}

final businessMembershipLookupProvider = Provider<BusinessMembershipLookup>((
  ref,
) {
  final available = ref.watch(supabaseAvailableProvider);
  return BusinessMembershipLookup(
    ref.watch(databaseProvider),
    client: available ? ref.watch(supabaseClientProvider) : null,
  );
});