// test/business_membership_lookup_test.dart
//
// BusinessMembershipLookup against an in-memory database, no cloud client.

import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/business_membership_lookup.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/sync/sync_tracker.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 'u_owner';
const _stranger = 'u_stranger';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BusinessMembershipLookup lookup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    lookup = BusinessMembershipLookup(db);
    SyncTracker.currentUserId = _owner;
  });

  tearDown(() async {
    SyncTracker.currentUserId = null;
    await db.close();
  });

  Future<void> createBusinessFor(String userId) async {
    await BusinessService(
      db,
      AuthorizationService(userId: userId, businessId: null, membership: null),
    ).createBusiness(name: 'Alpha', setAsCurrent: false);
  }

  test('someone with no business belongs to nothing', () async {
    expect(await lookup.hasBusinessMembership(_stranger), isFalse);
    expect(await lookup.hasOwnerBusinessMembership(_stranger), isFalse);
    expect(await lookup.hasTeamBusinessMembership(_stranger), isFalse);
  });

  test('a business owner is an owner, not a team member', () async {
    await createBusinessFor(_owner);

    expect(await lookup.hasBusinessMembership(_owner), isTrue);
    expect(await lookup.hasOwnerBusinessMembership(_owner), isTrue);
    expect(await lookup.hasTeamBusinessMembership(_owner), isFalse);
  });

  test("someone else's business does not make you a member", () async {
    await createBusinessFor(_owner);

    expect(await lookup.hasBusinessMembership(_stranger), isFalse);
    expect(await lookup.hasOwnerBusinessMembership(_stranger), isFalse);
    expect(await lookup.hasTeamBusinessMembership(_stranger), isFalse);
  });
}
