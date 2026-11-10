// lib/app/startup/startup_service.dart
//
// Decides which business BOS opens at startup. Offline-first: it looks in the
// local database FIRST and never contacts Supabase just to find out whether
// BOS can open. Cloud verification runs afterwards, in the background.
//
// The UI (BosStartupGate) owns only the widgets; everything here takes plain
// dependencies, so it can be unit-tested without pumping a widget tree.

import 'dart:async';
import 'package:bos_application/core/audit/audit_log_service.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/core/sync/legacy_data_bootstrap.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:bos_application/core/sync/transfer_repair.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/membership_service.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:bos_application/core/business/current_business.dart';
import 'package:bos_application/app/startup/startup_repairs.dart';

/// Callbacks into the widget that started the flow.
class StartupHooks {
  const StartupHooks({required this.isActive, required this.restart});

  /// False once the widget that started startup has been disposed.
  final bool Function() isActive;

  /// Re-runs the whole startup flow.
  final VoidCallback restart;
}

/// Thrown by startup when the account has no membership and no pending
/// invite, so the UI can ask "join or create?" instead of silently
/// creating a business.
class NoBusinessYet implements Exception {
  const NoBusinessYet();
}

final startupServiceProvider = Provider<StartupService>(
  (ref) => StartupService(ref),
);

class StartupService {
  StartupService(this._ref);

  final Ref _ref;

  Future<String> _createFirstBusiness(AppDatabase db, String userId) async {
    String newId;

    if (_ref.read(supabaseAvailableProvider)) {
      newId = await _ref
          .read(cloudBusinessServiceProvider)
          .createBusiness(name: 'My Business');
    } else {
      newId = 'biz_${DateTime.now().microsecondsSinceEpoch}';
    }

    await db.transaction(() async {
      await db
          .into(db.businesses)
          .insert(
            BusinessesCompanion.insert(
              id: newId,
              name: 'My Business',
              ownerUserId: userId,
              isCurrent: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      await db.seedDefaultsForBusiness(newId);

      await MembershipService.insertOwnerMembership(
        db,
        businessId: newId,
        userId: userId,
      );
    });

    return newId;
  }

  // ============================================================
  // LOCAL BUSINESS DISCOVERY
  //
  // THIS IS THE IMPORTANT OFFLINE-FIRST PART.
  //
  // We look in Drift FIRST.
  // We do not contact Supabase just to determine whether BOS can open.
  // ============================================================

  Future<List<BusinessesData>> _findLocalBusinessesForUser(
    AppDatabase db,
    String userId,
  ) async {
    final memberships = await (db.select(
      db.businessMembers,
    )..where((m) => m.userId.equals(userId) & m.status.equals('active'))).get();

    final businessIds = memberships.map((m) => m.businessId).toSet();

    if (businessIds.isNotEmpty) {
      final businesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.isIn(businessIds))).get();

      final active = businesses.where((business) => business.isActive).toList();

      if (active.isNotEmpty) {
        return active;
      }
    }

    // Compatibility fallback for older local databases where the owner
    // relationship may exist but the local membership row was not present.
    final owned = await (db.select(
      db.businesses,
    )..where((b) => b.ownerUserId.equals(userId))).get();

    return owned.where((business) => business.isActive).toList();
  }

  // ============================================================
  // LOCAL DEVICE AUTHORIZATION
  // ============================================================

  Future<void> _throwIfLocallyRevoked(String userId) async {
    if (!_ref.read(supabaseAvailableProvider)) {
      return;
    }

    final deviceService = _ref.read(deviceManagementServiceProvider);

    final cached = await deviceService.getCachedAuthorization(userId: userId);

    if (cached == null) {
      // Existing installations created before this offline authorization
      // cache existed have no cached state yet. They are allowed to use
      // their already-existing local business and will be reconciled online.
      return;
    }

    if (!cached.authorized) {
      throw DeviceAuthorizationException(
        _deviceAuthorizationMessage(cached.status, cached.requiresFreshLogin),
        status: cached.status,
        requiresFreshLogin: cached.requiresFreshLogin,
      );
    }
  }

  String _deviceAuthorizationMessage(String status, bool requiresFreshLogin) {
    return switch (status) {
      'revoked' when requiresFreshLogin =>
        'This device was revoked. Sign out, sign in again, then '
            'explicitly reactivate it to resume cloud access.',
      'revoked' =>
        'This device was revoked. Explicitly reactivate it to resume '
            'cloud access.',
      'blocked' =>
        'This device is blocked. Contact your organization administrator '
            'to restore cloud access.',
      _ => 'This device is not authorized for cloud access.',
    };
  }

  // ============================================================
  // SELECT / PREPARE CURRENT BUSINESS
  // ============================================================

  Future<BusinessesData> _selectCurrentBusiness(
    AppDatabase db,
    List<BusinessesData> myBusinesses,
  ) async {
    final active = myBusinesses.where((business) => business.isActive).toList();

    if (active.isEmpty) {
      throw StateError('You do not currently belong to an active business.');
    }

    final current = active.firstWhere(
      (business) => business.isCurrent,
      orElse: () => active.first,
    );

    await SyncChangeLog.suppressed(db, () {
      return db.transaction(() async {
        await (db.update(
          db.businesses,
        )).write(const BusinessesCompanion(isCurrent: Value(false)));

        await (db.update(db.businesses)..where((b) => b.id.equals(current.id)))
            .write(const BusinessesCompanion(isCurrent: Value(true)));
      });
    });

    applyCurrentBusiness(_ref, current.id);

    return current;
  }

  // ============================================================
  // ONLINE RECONCILIATION
  //
  // IMPORTANT:
  // This does NOT block the initial offline startup.
  //
  // It verifies the installation against Supabase after the local
  // business has already been allowed to open.
  // ============================================================

  Future<void> _reconcileCloudState({
    required AppDatabase db,
    required String userId,
    required String currentBusinessId,
    required StartupHooks hooks,
  }) async {
    if (!_ref.read(supabaseAvailableProvider)) {
      return;
    }

    try {
      final deviceService = _ref.read(deviceManagementServiceProvider);

      final device = await deviceService.registerCurrentDevice().timeout(
        const Duration(seconds: 5),
      );

      debugPrint(
        '[device] background reconciliation '
        'status=${device.status} '
        'requiresFreshLogin=${device.requiresFreshLogin}',
      );

      await AuditDeviceId.remember(device.deviceUuid);

      if (device.status != 'active') {
        debugPrint(
          '[device] current device is no longer active '
          'after online reconciliation',
        );

        if (hooks.isActive()) {
          _ref.invalidate(currentBusinessMembershipProvider);
        }

        return;
      }

      final client = _ref.read(supabaseClientProvider);

      // Drop businesses the owner deleted elsewhere BEFORE anything else
      // (claim_owner_membership, bootstrap) can act on them.
      try {
        final removed = await purgeDeletedBusinesses(db, client);
        if (removed.contains(currentBusinessId)) {
          if (!hooks.isActive()) return;
          final moved = await _ref
              .read(syncTriggerServiceProvider)
              .moveOffRemovedBusiness(userId, currentBusinessId);
          if (!moved) {
            // No business left: startup shows "Create or join".
            hooks.restart();
          }
          return;
        }
      } catch (e) {
        debugPrint('[business] deleted-business check skipped: $e');
      }

      final cloudMemberships = await client
          .from('business_memberships')
          .select('business_id, status, role')
          .eq('user_id', userId)
          .eq('status', 'active')
          .timeout(const Duration(seconds: 5));

      debugPrint(
        '[business] background membership '
        'reconciliation count=${cloudMemberships.length}',
      );
      if (cloudMemberships.isEmpty) {
        // Never invent a status the cloud doesn't hold. Heal owners whose
        // membership was never uploaded, then apply whatever the cloud says.
        final localBiz = await (db.select(
          db.businesses,
        )..where((b) => b.id.equals(currentBusinessId))).getSingleOrNull();
        if (localBiz != null && localBiz.ownerUserId == userId) {
          try {
            await client.rpc(
              'claim_owner_membership',
              params: {'p_business_id': currentBusinessId},
            );
          } catch (e) {
            debugPrint('[business] claim_owner_membership failed: $e');
          }
        }
        await adoptCloudAccess(db, client, userId: userId);
        if (hooks.isActive()) _ref.invalidate(currentBusinessMembershipProvider);
        return;
      }

      // Bring any cloud membership/business changes into Drift.
      await adoptCloudAccess(db, client, userId: userId);

      // Legacy bootstrap is now NON-FATAL and NON-BLOCKING at startup.
      try {
        final biz = await (db.select(
          db.businesses,
        )..where((b) => b.id.equals(currentBusinessId))).getSingleOrNull();
        final bootstrapped = biz?.ownerUserId == userId
            ? await _ref
                  .read(legacyCloudBootstrapServiceProvider)
                  .bootstrapIfNeeded(currentBusinessId)
            : false;

        if (bootstrapped) {
          debugPrint('[bootstrap] legacy local data uploaded to cloud');
        }
      } catch (error, stack) {
        debugPrint('[bootstrap] background bootstrap skipped: $error');
        debugPrint(stack.toString());
      }

      // Profile upload is also best-effort.
      try {
        await queueLocalProfileIfCloudBlank(
          db,
          client,
          businessId: currentBusinessId,
        );
      } catch (error) {
        debugPrint('[bootstrap] background profile upload skipped: $error');
      }
    } on DeviceAuthorizationException catch (error) {
      debugPrint('[device] background reconciliation rejected device: $error');

      if (hooks.isActive()) {
        _ref.invalidate(currentBusinessMembershipProvider);
      }
    } on TimeoutException catch (error) {
      // No network / unreachable Supabase:
      // local BOS continues running normally.
      debugPrint('[offline] cloud reconciliation timed out: $error');
    } on Object catch (error, stack) {
      // Cloud failure must NOT destroy offline usability.
      debugPrint('[offline] cloud reconciliation skipped: $error');
      debugPrint(stack.toString());
    }
  }

  // ============================================================
  // CLOUD-FIRST INITIALIZATION
  //
  // Used only when there is NO local business.
  //
  // A brand-new installation still needs internet once to:
  // - load membership
  // - redeem invitation
  // - or create the cloud business
  //
  // Existing installations do NOT come through this path when offline.
  // ============================================================

  Future<List<BusinessesData>> _initializeCloudBusiness(
    AppDatabase db,
    SupabaseClient client,
    String userId, {
    required bool allowCreateFirstBusiness,
  }) async {
    final deviceService = _ref.read(deviceManagementServiceProvider);

    final device = await deviceService.registerCurrentDevice();

    debugPrint(
      '[device] initial registration '
      'status=${device.status} '
      'requiresFreshLogin=${device.requiresFreshLogin} '
      'uuid=${device.deviceUuid}',
    );

    await AuditDeviceId.remember(device.deviceUuid);

    if (device.status != 'active') {
      throw DeviceAuthorizationException(
        _deviceAuthorizationMessage(device.status, device.requiresFreshLogin),
        status: device.status,
        requiresFreshLogin: device.requiresFreshLogin,
      );
    }

    debugPrint('[business] querying cloud memberships for user=$userId');

    List<dynamic> cloudMemberships;

    try {
      cloudMemberships = await client
          .from('business_memberships')
          .select('business_id, status, role')
          .eq('user_id', userId)
          .eq('status', 'active')
          .timeout(const Duration(seconds: 8));

      debugPrint(
        '[business] cloud membership query '
        'SUCCESS count=${cloudMemberships.length}',
      );
    } on TimeoutException {
      throw StateError(
        'BOS could not reach the cloud. '
        'Your local session is still intact, but this device has '
        'no local business available for offline startup. '
        'Connect to the internet once and try again.',
      );
    } catch (e, st) {
      debugPrint('[business] cloud membership query FAILED: $e');
      debugPrint(st.toString());

      throw StateError(
        'Could not check your business membership in the cloud. ($e)',
      );
    }

    // ==========================================================
    // EXISTING CLOUD BUSINESS
    // ==========================================================

    if (cloudMemberships.isNotEmpty) {
      debugPrint('[business] existing cloud membership found');

      try {
        await adoptCloudAccess(db, client, userId: userId);
      } catch (e, st) {
        debugPrint('[business] adoptCloudAccess FAILED: $e');
        debugPrint(st.toString());

        throw StateError(
          'Could not load your existing business from the cloud. '
          'Check your connection and tap Try again. ($e)',
        );
      }

      final localMemberships =
          await (db.select(db.businessMembers)..where(
                (m) => m.userId.equals(userId) & m.status.equals('active'),
              ))
              .get();

      if (localMemberships.isEmpty) {
        throw StateError(
          'Your cloud account has an active business membership, '
          'but it could not be imported into the local database.',
        );
      }

      final businessIds = localMemberships.map((m) => m.businessId).toSet();

      final myBusinesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.isIn(businessIds))).get();

      if (myBusinesses.isEmpty) {
        throw StateError(
          'Your business membership was found in the cloud, '
          'but the business record could not be loaded.',
        );
      }

      return myBusinesses;
    }

    // ==========================================================
    // NO CLOUD BUSINESS
    // ==========================================================

    final authUser = client.auth.currentUser;

    final prefs = await SharedPreferences.getInstance();

    final inviteKey = pendingInviteKey(authUser?.email ?? '');

    final pendingCode = prefs.getString(inviteKey);

    if (pendingCode != null && pendingCode.isNotEmpty) {
      debugPrint('[business] redeeming saved invite code');

      try {
        await _ref
            .read(cloudBusinessServiceProvider)
            .redeemInviteCode(pendingCode);

        await prefs.remove(inviteKey);
      } on CloudBusinessException catch (e) {
        if (e.code == 'database_error') {
          await prefs.remove(inviteKey);
        }

        rethrow;
      } finally {
        await prefs.remove(inviteKey);
      }

      return _initializeCloudBusiness(
        db,
        client,
        userId,
        allowCreateFirstBusiness: allowCreateFirstBusiness,
      );
    }

    final intentKey = createBusinessIntentKey(authUser?.email ?? '');
    final wantsOwnBusiness = prefs.getBool(intentKey) ?? false;

    if (!allowCreateFirstBusiness && !wantsOwnBusiness) {
      throw const NoBusinessYet();
    }

    debugPrint('[business] creating first cloud business');

    final newId = await _createFirstBusiness(db, userId);
    await prefs.remove(intentKey);

    final created = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(newId))).get();

    if (created.isEmpty) {
      throw StateError(
        'The new business was created but could not be loaded locally.',
      );
    }

    return created;
  }

  // ============================================================
  // MAIN STARTUP
  // ============================================================

  /// Opens the local business if there is one (offline-first), otherwise
  /// initializes from the cloud. Never blocks local startup on the network.
  Future<BusinessesData> ensureBusinessExists({
    required bool allowCreateFirstBusiness,
    required StartupHooks hooks,
  }) async {
    final db = _ref.read(databaseProvider);

    final cloudEnabled = _ref.read(supabaseAvailableProvider);

    // ------------------------------------------------------------
    // CLOUD SESSION
    // ------------------------------------------------------------

    if (cloudEnabled) {
      final client = _ref.read(supabaseClientProvider);

      final authUser = client.auth.currentUser;

      debugPrint('[business] Supabase current user = ${authUser?.id}');

      debugPrint('[business] Supabase current email = ${authUser?.email}');

      if (authUser == null) {
        throw StateError('Signed out during startup.');
      }

      final userId = authUser.id;

      // ----------------------------------------------------------
      // FIRST: USE THE LOCAL AUTHORIZATION CACHE
      //
      // If the server previously told us this device was revoked,
      // do not grant access even while offline.
      //
      // If there is no cached decision yet, legacy installations
      // can still use their existing local business.
      // ----------------------------------------------------------

      await _throwIfLocallyRevoked(userId);

      // ----------------------------------------------------------
      // FIRST: LOOK FOR LOCAL BUSINESS
      //
      // This is what makes an already-configured BOS installation
      // genuinely usable without internet.
      // ----------------------------------------------------------

      final localBusinesses = await _findLocalBusinessesForUser(db, userId);

      if (localBusinesses.isNotEmpty) {
        debugPrint(
          '[offline] local business found; '
          'startup does not require Supabase',
        );

        final current = await _selectCurrentBusiness(db, localBusinesses);

        // Cloud verification/reconciliation happens AFTER local
        // startup. It must never block this path.
        unawaited(
          _reconcileCloudState(
            db: db,
            userId: userId,
            currentBusinessId: current.id,
            hooks: hooks,
          ),
        );

        _ref.read(authenticatedUserIdProvider.notifier).state = userId;

        await repairTextTimestamps(db);
        unawaited(
          repairBranchTransfers(
            db,
          ).then((_) => _ref.read(syncTriggerServiceProvider).syncNow()),
        );

        if (current.ownerUserId == userId) {
          unawaited(backfillCashiers(db, userId));
        }

        debugPrint('[business] business name=${current.name}');

        return current;
      }

      // ----------------------------------------------------------
      // NO LOCAL BUSINESS
      //
      // Therefore this is a first-time / not-yet-downloaded
      // installation. Cloud initialization is required.
      // ----------------------------------------------------------

      final myBusinesses = await _initializeCloudBusiness(
        db,
        client,
        userId,
        allowCreateFirstBusiness: allowCreateFirstBusiness,
      );

      _ref.read(authenticatedUserIdProvider.notifier).state = userId;

      final current = await _selectCurrentBusiness(db, myBusinesses);

      // Initial cloud load succeeded. Any bootstrap/profile work
      // is now safely background work.
      unawaited(
        _reconcileCloudState(
          db: db,
          userId: userId,
          currentBusinessId: current.id,
            hooks: hooks,
        ),
      );

      debugPrint('[business] selected business = ${current.id}');

      debugPrint('[business] business name = ${current.name}');

      return current;
    }

    // ------------------------------------------------------------
    // LOCAL-ONLY MODE
    // ------------------------------------------------------------

    final userId = _ref.read(authenticatedUserIdProvider);

    debugPrint('[auth] local user id = $userId');

    if (userId == null) {
      throw StateError('Signed out during startup.');
    }

    var myBusinesses = await _findLocalBusinessesForUser(db, userId);

    if (myBusinesses.isEmpty) {
      final newId = await _createFirstBusiness(db, userId);

      myBusinesses = await (db.select(
        db.businesses,
      )..where((b) => b.id.equals(newId))).get();
    }

    return _selectCurrentBusiness(db, myBusinesses);
  }
}
