// lib/core/sync/sync_trigger_service.dart
//
// Fires the sync engine at the right moments: startup, session restored,
// network back, app foreground, a local write (debounced), a periodic safety
// net, and a Realtime nudge when another device changes the business.
// Connectivity is only a trigger — sync correctness is proven by the server.

import 'dart:async';

import 'package:bos_application/core/auth/access_revocation.dart';
import 'package:bos_application/core/auth/session_end.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/stock/stock_service.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/core/sync/sync_change_log.dart';
import 'package:bos_application/features/transactions/domain/pos_session_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/pos_order_state.dart';
import 'package:bos_application/features/transactions/presentation/screens/transaction_page.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bos_application/core/business/current_business.dart';
import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        RealtimeChannel;

import '../auth/authorization_providers.dart';
import '../database/database_provider.dart';
import '../device/device_management_service.dart';
import '../device/device_providers.dart';
import '../supabase/supabase_service.dart';
import 'sync_coordinator.dart';

class SyncTriggerService with WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<dynamic>? _localSub;
  ProviderSubscription<dynamic>? _businessSub;
  ProviderSubscription<dynamic>? _authSub;
  Timer? _poll;
  Timer? _debounce;
  RealtimeChannel? _channel;
  RealtimeChannel? _memberChannel;
  Timer? _memberPoll;
  bool _refreshingMembership = false;
  DateTime? _lastMembershipRefresh;
  bool _started = false;

  SyncTriggerService(this._ref);

  /// Call once after sign-in. Idempotent. Only runs when Supabase is
  /// configured; otherwise everything stays purely local.
  void start() {
    if (_started || !_ref.read(supabaseAvailableProvider)) return;
    _started = true;

    // Startup: sync the selected business right away.
    unawaited(_syncCurrent());

    // Network restored -> sync.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(_syncCurrent());
    });

    // Foreground -> sync.
    WidgetsBinding.instance.addObserver(this);

    // Local write -> push soon (debounced). Ignore the sync engine's own
    // bookkeeping tables so a sync doesn't trigger another sync.
    _localSub = _ref.read(databaseProvider).tableUpdates().listen((updates) {
      if (SyncCoordinator.anyActive) return;
      if (!updates.any((u) => !u.table.startsWith('sync_'))) return;
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(seconds: 2),
        () => unawaited(_syncCurrent()),
      );
    });

    // Safety net if Realtime drops or a trigger is missed.
    _poll = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(syncAllPendingNow()),
    );

    // Another device changed this business -> pull soon.
    _subscribeRealtime();
    // Role / status changes for this account arrive through
    // business_memberships, which is not in the change feed.
    _subscribeMemberships();
    _memberPoll = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshMemberships()),
    );
    _businessSub = _ref.listen(selectedBusinessIdProvider, (_, __) {
      _subscribeRealtime();
      unawaited(_syncCurrent());
    });

    _authSub = _ref.listen<String?>(authenticatedUserIdProvider, (_, next) {
      if (next == null) stop();
    });
  }

  void _subscribeRealtime() {
    try {
      final businessId = _ref.read(selectedBusinessIdProvider);
      _channel?.unsubscribe();
      _channel = _ref
          .read(supabaseClientProvider)
          .channel('sync:$businessId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'sync_changes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'business_id',
              value: businessId,
            ),
            callback: (_) => unawaited(_syncCurrent()),
          )
          .subscribe();
    } on Object catch (error) {
      // Realtime is only a nudge; the timer and other triggers still work.
      // ignore: avoid_print
      print('[sync] realtime subscribe failed (${error.runtimeType})');
    }
  }

  void _subscribeMemberships() {
    try {
      final userId = _ref.read(authenticatedUserIdProvider);
      if (userId == null) return;
      _memberChannel?.unsubscribe();
      _memberChannel = _ref
          .read(supabaseClientProvider)
          .channel('members:$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'business_memberships',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) => unawaited(_refreshMemberships(force: true)),
          )
          .subscribe();
    } on Object catch (error) {
      // ignore: avoid_print
      print('[sync] membership realtime failed (${error.runtimeType})');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshMemberships(force: true));
      unawaited(_syncCurrent());
    }
  }

  Future<void> _syncCurrent() async {
    if (!_ref.read(supabaseAvailableProvider)) return;
    final userId = _ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    final businessId = _ref.read(selectedBusinessIdProvider);

    try {
      final registration = await _ref.read(
        currentDeviceRegistrationProvider.future,
      );
      if (registration == null || registration.status != 'active') return;

      if (!await _ensureSessionActive()) return;
      await _refreshMemberships();

      final coordinator = _ref.read(syncCoordinatorProvider);
      final summary = await coordinator.syncNow(businessId, userId: userId);
      if (summary.pulledCount > 0) {
        unawaited(_ref.read(stockProjectionProvider).refresh());
      }
      if (summary.state == SyncState.authorizationRequired) {
        unawaited(_ensureSessionActive(force: true));
      }
    } on DeviceAuthorizationException catch (error) {
      // ignore: avoid_print
      print('[sync] waiting for device authorization: ${error.message}');
    } on DeviceManagementException catch (error) {
      // ignore: avoid_print
      print('[sync] device check failed (${error.code ?? 'unknown'})');
    } on Object catch (error) {
      // ignore: avoid_print
      print('[sync] device check failed (${error.runtimeType})');
    }
  }

  /// A blocked sync can mean this session or device was revoked elsewhere.
  /// Ask the server; sign out only when it says the session is not active.
  DateTime? _lastSessionCheck;
  bool _checkingSession = false;

  /// Returns false (after signing out) when the server says this device
  /// session is no longer active. Must run BEFORE any membership query: a
  /// revoked session just gets empty results from RLS, which would look like
  /// "removed from the business".
  Future<bool> _ensureSessionActive({bool force = false}) async {
    if (_checkingSession) return true;
    final now = DateTime.now();
    final last = _lastSessionCheck;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 10)) {
      return true;
    }
    _checkingSession = true;
    _lastSessionCheck = now;
    try {
      final active = await _ref
          .read(supabaseClientProvider)
          .rpc('is_current_device_session_active');
      if (active == false) {
        await _ref
            .read(deviceManagementServiceProvider)
            .markCurrentSessionRevoked();
        await endSessionLocally(
          _ref,
          notice:
              'This device was signed out from another device. Sign in '
              'again to continue.',
        );
        return false;
      }
      return true;
    } on Object {
      return true; // offline or transient: try again next time
    } finally {
      _checkingSession = false;
    }
  }

  /// Runs a sync right now (for manual Retry buttons).
  Future<void> syncNow() => _syncCurrent();

  /// Pushes pending changes of OTHER businesses (e.g. one just created while
  /// another is selected). _syncCurrent only handles the selected one.
  Future<void> _syncOtherPending() async {
    final userId = _ref.read(authenticatedUserIdProvider);
    if (userId == null || !_ref.read(supabaseAvailableProvider)) return;
    final current = _ref.read(selectedBusinessIdProvider);
    try {
      final rows = await _ref
          .read(databaseProvider)
          .customSelect(
            "SELECT DISTINCT business_id FROM sync_outbox "
            "WHERE status = 'pending'",
          )
          .get();
      for (final r in rows) {
        final id = r.read<String>('business_id');
        if (id == current) continue;
        await _ref.read(syncCoordinatorProvider).syncNow(id, userId: userId);
      }
    } on Object catch (e) {
      // ignore: avoid_print
      print('[sync] other-business sync failed (${e.runtimeType})');
    }
  }

  /// Call right after creating a business so it uploads immediately.
  Future<void> syncAllPendingNow() async {
    await _syncCurrent();
    await _syncOtherPending();
  }

  void stop() {
    _connectivitySub?.cancel();
    _localSub?.cancel();
    _businessSub?.close();
    _poll?.cancel();
    _debounce?.cancel();
    _channel?.unsubscribe();
    _memberChannel?.unsubscribe();
    _memberPoll?.cancel();
    _authSub?.close();
    _authSub = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  /// Moves the app to another business the user belongs to after the
  /// selected one was deleted. Returns false when none is left, so the
  /// caller can route to create/join onboarding.
  Future<bool> moveOffRemovedBusiness(String userId, String removedId) async {
    final db = _ref.read(databaseProvider);
    final rows = await db
        .customSelect(
          'SELECT b.id FROM businesses b '
          'JOIN business_members m ON m.business_id = b.id '
          "WHERE m.user_id = ? AND m.status = 'active' AND b.is_active = 1 "
          'AND b.id <> ? ORDER BY b.name LIMIT 1',
          variables: [
            Variable.withString(userId),
            Variable.withString(removedId),
          ],
        )
        .get();
    if (rows.isEmpty) return false;

    await switchToBusiness(rows.first.read<String>('id'));
    return true;
  }

  /// Makes [businessId] the current business on this device.
  Future<void> switchToBusiness(String businessId) async {
    final db = _ref.read(databaseProvider);
    await SyncChangeLog.suppressed(db, () async {
      await db.customStatement('UPDATE businesses SET is_current = 0');
      await db.customStatement(
        'UPDATE businesses SET is_current = 1 WHERE id = ?',
        [businessId],
      );
    });
       final changed = applyCurrentBusiness(_ref, businessId);
       // Keep the old behaviour: the ledger version always bumps once, even
       // when re-selecting the business that is already open.
       if (!changed) _ref.read(ledgerVersionProvider.notifier).state++;
    _ref.invalidate(currentBusinessMembershipProvider);
    _ref.invalidate(posOrderProvider); // cart
    _ref.invalidate(heldOrdersProvider); // held orders
    _ref.invalidate(currentPosSessionProvider);
  }

  /// Call after BusinessService.createBusiness: makes it the active business
  /// everywhere (kCurrentBusinessId + providers) and uploads it right away.
  Future<void> openNewBusiness(String businessId) async {
    await switchToBusiness(businessId);
    unawaited(syncAllPendingNow());
  }

  /// When history rows exist, an active row wins.
  Map<String, dynamic>? _pickMembership(List<dynamic> rows) {
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;
    return list.firstWhere(
      (r) => r['status'] == 'active',
      orElse: () => list.first,
    );
  }

  /// Detects that this account lost access to [businessId] (membership
  /// removed or deleted) and raises the warning dialog.
  Future<void> _checkAccessRevoked(
    dynamic db,
    dynamic client,
    String userId,
    String businessId,
  ) async {
    if (_ref.read(accessRevocationProvider)?.businessId == businessId) return;

    final localRows =
        await (db.select(db.businessMembers)..where(
              (m) => m.userId.equals(userId) & m.businessId.equals(businessId),
            ))
            .get();
    if (localRows.isEmpty) return; // never a member here; not a removal

    final cloudRows = await client
        .from('business_memberships')
        .select('status')
        .eq('user_id', userId)
        .eq('business_id', businessId);
    final cloud = _pickMembership(cloudRows);
    final status = cloud?['status'] as String?;
    // Row hidden or deleted (null) or explicitly removed.
    if (cloud != null && status != 'removed') return;

    await (db.update(db.businessMembers)..where(
          (m) => m.userId.equals(userId) & m.businessId.equals(businessId),
        ))
        .write(
          BusinessMembersCompanion(
            status: const Value('removed'),
            updatedAt: Value(DateTime.now()),
          ),
        );

    final business = await (db.select(
      db.businesses,
    )..where((b) => b.id.equals(businessId))).getSingleOrNull();

    _ref.read(accessRevocationProvider.notifier).state = AccessRevocation(
      businessId: businessId,
      businessName: (business?.name as String?) ?? 'this business',
    );
  }

  /// Role changes, suspensions and new businesses arrive through
  /// business_memberships, which is not in the change feed.
  /// Pulls this account's membership (role, status) from the cloud into
  /// Drift. A normal check costs one small query and only does the full
  /// refresh when the role or status actually differs.
  Future<void> _refreshMemberships({bool force = false}) async {
    if (!_ref.read(supabaseAvailableProvider)) return;
    final userId = _ref.read(authenticatedUserIdProvider);
    if (userId == null || _refreshingMembership) return;
    if (!await _ensureSessionActive()) return;

    final now = DateTime.now();
    final last = _lastMembershipRefresh;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 15)) {
      return;
    }

    _refreshingMembership = true;
    _lastMembershipRefresh = now;
    try {
      final db = _ref.read(databaseProvider);
      final client = _ref.read(supabaseClientProvider);
      final businessId = _ref.read(selectedBusinessIdProvider);

      if (!force) {
        final cloudRows = await client
            .from('business_memberships')
            .select('role, status')
            .eq('user_id', userId)
            .eq('business_id', businessId);
        final cloud = _pickMembership(cloudRows);
        final localRows =
            await (db.select(db.businessMembers)..where(
                  (m) =>
                      m.userId.equals(userId) & m.businessId.equals(businessId),
                ))
                .get();
        final local = localRows.isEmpty ? null : localRows.first;
        if (cloud != null &&
            local != null &&
            cloud['role'] == local.role &&
            cloud['status'] == local.status) {
          return;
        }
      }

      final result = await adoptCloudAccess(db, client, userId: userId);
      if (result.removedBusinessIds.contains(businessId)) {
        await moveOffRemovedBusiness(userId, businessId);
      } else {
        await _checkAccessRevoked(db, client, userId, businessId);
      }
      // ignore: avoid_print
      print('[membership] refreshed from cloud');
    } on Object catch (error) {
      // ignore: avoid_print
      print('[sync] membership refresh failed ($error)');
    } finally {
      _refreshingMembership = false;
    }
  }
}

final syncTriggerServiceProvider = Provider<SyncTriggerService>((ref) {
  final service = SyncTriggerService(ref);
  ref.onDispose(service.stop);
  return service;
});
