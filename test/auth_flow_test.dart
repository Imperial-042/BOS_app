// test/auth_flow_test.dart
//
// Authentication, session, and account-switching coverage for the BOS auth
// layer. Cloud (Supabase) calls are mocked out of scope here — these tests
// exercise the local AuthService credential store, SessionStore
// persistence, and the multi-user data-isolation rules that decide what an
// account can see after switching.

import 'package:bos_application/core/auth/auth_service.dart';
import 'package:bos_application/core/auth/authorization_service.dart';
import 'package:bos_application/core/auth/session_store.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppDatabase> _newDb() async =>
    AppDatabase.forTesting(NativeDatabase.memory());

AuthorizationService _asUser(String userId) =>
    AuthorizationService(userId: userId, businessId: null, membership: null);

Future<List<BusinessMember>> _membershipsOf(AppDatabase db, String userId) {
  return (db.select(
    db.businessMembers,
  )..where((m) => m.userId.equals(userId) & m.status.equals('active'))).get();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthService auth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await _newDb();
    auth = AuthService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('local auth service', () {
    test('registration stores a salted hash, never the plaintext', () async {
      final user = await auth.register(
        email: 'Owner@Example.com',
        password: 'secret123',
        displayName: 'Owner One',
      );

      expect(user.email, 'owner@example.com');
      expect(user.displayName, 'Owner One');
      expect(user.passwordHash, isNot(contains('secret123')));
      expect(user.passwordSalt, isNotEmpty);
      expect(user.passwordHash, isNotEmpty);
    });

    test('rejects duplicate emails and invalid input', () async {
      await auth.register(
        email: 'taken@example.com',
        password: 'secret123',
        displayName: 'First',
      );

      await expectLater(
        auth.register(
          email: 'taken@example.com',
          password: 'other999',
          displayName: 'Second',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.register(
          email: 'not-an-email',
          password: 'secret123',
          displayName: 'X',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.register(
          email: 'short@example.com',
          password: '123',
          displayName: 'X',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        auth.register(
          email: 'nameless@example.com',
          password: 'secret123',
          displayName: '  ',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test(
      'login verifies credentials without leaking which part failed',
      () async {
        await auth.register(
          email: 'user@example.com',
          password: 'secret123',
          displayName: 'User',
        );

        final loggedIn = await auth.login(
          email: '  USER@example.com ',
          password: 'secret123',
        );
        expect(loggedIn.email, 'user@example.com');

        // login() stamps lastLoginAt on the persisted row (the returned
        // object is read before the update, so verify against the database).
        final persisted = await (db.select(
          db.users,
        )..where((u) => u.id.equals(loggedIn.id))).getSingle();
        expect(persisted.lastLoginAt, isNotNull);

        await expectLater(
          auth.login(email: 'user@example.com', password: 'wrong'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Incorrect email or password.',
            ),
          ),
        );
        await expectLater(
          auth.login(email: 'ghost@example.com', password: 'secret123'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Incorrect email or password.',
            ),
          ),
        );
      },
    );

    test('changePassword rotates the credential', () async {
      final user = await auth.register(
        email: 'user@example.com',
        password: 'secret123',
        displayName: 'User',
      );

      await auth.changePassword(
        userId: user.id,
        currentPassword: 'secret123',
        newPassword: 'new-secret456',
      );

      await expectLater(
        auth.login(email: 'user@example.com', password: 'secret123'),
        throwsA(isA<AuthException>()),
      );
      final relogged = await auth.login(
        email: 'user@example.com',
        password: 'new-secret456',
      );
      expect(relogged.id, user.id);
    });

    test('ensureLocalUser creates an identity shell exactly once', () async {
      await auth.ensureLocalUser(
        id: 'cloud-uuid-1',
        email: 'Cloud@Example.com',
        displayName: 'Cloud User',
      );
      await auth.ensureLocalUser(
        id: 'cloud-uuid-1',
        email: 'cloud@example.com',
        displayName: 'Renamed',
      );

      final users = await (db.select(
        db.users,
      )..where((u) => u.id.equals('cloud-uuid-1'))).get();
      expect(users, hasLength(1));
      expect(users.single.displayName, 'Cloud User');
      expect(users.single.email, 'cloud@example.com');

      // A shell must never accept a password login.
      await expectLater(
        auth.login(email: 'cloud@example.com', password: 'anything'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('session store', () {
    test('save / read / clear round-trips the signed-in user id', () async {
      expect(await SessionStore.readUserId(), isNull);

      await SessionStore.saveUserId('user-a');
      expect(await SessionStore.readUserId(), 'user-a');

      // Logging out must not leave the previous account restorable.
      await SessionStore.clear();
      expect(await SessionStore.readUserId(), isNull);
    });

    test('biometric unlock flag persists independently', () async {
      expect(await SessionStore.isBiometricEnabled(), isFalse);
      await SessionStore.setBiometricEnabled(true);
      expect(await SessionStore.isBiometricEnabled(), isTrue);
      await SessionStore.clear();
      expect(await SessionStore.isBiometricEnabled(), isTrue);
    });
  });

  group('account switching', () {
    test('user B never sees user A\'s business after a switch', () async {
      final userA = await auth.register(
        email: 'a@example.com',
        password: 'secret123',
        displayName: 'User A',
      );
      final userB = await auth.register(
        email: 'b@example.com',
        password: 'secret123',
        displayName: 'User B',
      );

      final businessA = await BusinessService(
        db,
        _asUser(userA.id),
      ).createBusiness(name: 'A Store', setAsCurrent: false);

      // Simulate the switch: A's session is cleared, B signs in.
      await SessionStore.saveUserId(userA.id);
      await SessionStore.clear();
      await auth.login(email: 'b@example.com', password: 'secret123');
      await SessionStore.saveUserId(userB.id);

      final membershipsB = await _membershipsOf(db, userB.id);
      expect(membershipsB, isEmpty, reason: 'B has not joined any business');

      // B creates their own business; A's stays out of B's scope.
      await BusinessService(
        db,
        _asUser(userB.id),
      ).createBusiness(name: 'B Store', setAsCurrent: false);

      final bMembershipsAfter = await _membershipsOf(db, userB.id);
      expect(bMembershipsAfter, hasLength(1));
      expect(bMembershipsAfter.single.businessId, isNot(businessA.id));

      final aMemberships = await _membershipsOf(db, userA.id);
      expect(aMemberships.single.businessId, businessA.id);

      // B signs out; A signs back in and still sees exactly their own.
      await SessionStore.clear();
      await auth.login(email: 'a@example.com', password: 'secret123');
      await SessionStore.saveUserId(userA.id);
      final aRestored = await _membershipsOf(db, userA.id);
      expect(aRestored, hasLength(1));
      expect(aRestored.single.businessId, businessA.id);
    });

    test('an unauthenticated identity owns nothing', () async {
      final userA = await auth.register(
        email: 'a@example.com',
        password: 'secret123',
        displayName: 'User A',
      );
      await BusinessService(
        db,
        _asUser(userA.id),
      ).createBusiness(name: 'A Store', setAsCurrent: false);

      // Signed-out queries (no user id) resolve to nothing.
      final anonymous = await _membershipsOf(db, 'nobody');
      expect(anonymous, isEmpty);
    });
  });
}
