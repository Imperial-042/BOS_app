import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Pending-change counts that cannot upload as the signed-in account.
class HeldOutboxSummary {
  const HeldOutboxSummary({
    required this.recoverable,
    required this.otherAccounts,
    required this.otherBusinesses,
  });

  /// Unattributed (legacy) changes in businesses the account belongs to.
  final int recoverable;

  /// Changes recorded under a different account. Never reassigned.
  final int otherAccounts;

  /// Unattributed changes in businesses this account is not a member of.
  final int otherBusinesses;

  int get total => recoverable + otherAccounts + otherBusinesses;
}

/// Explicit, account-initiated recovery of outbox rows created before change
/// ownership was recorded.
///
/// Only unattributed rows in businesses where the account has an active local
/// membership can be adopted. Rows owned by another account are never
/// reassigned, and the server's row-level security still decides whether the
/// account may write each change.
class OutboxRecoveryService {
  OutboxRecoveryService(this._db);

  final AppDatabase _db;

  static const _unattributed =
      'NOT EXISTS (SELECT 1 FROM sync_outbox_owners own WHERE own.outbox_id = o.id)';
  static const _isMember =
      'EXISTS (SELECT 1 FROM business_members m WHERE m.business_id = o.business_id '
      "AND m.user_id = ? AND m.status = 'active')";

  Future<HeldOutboxSummary> summarize(String userId) async {
    final row = await _db
        .customSelect(
          'SELECT '
          "COALESCE(SUM(CASE WHEN $_unattributed AND $_isMember THEN 1 ELSE 0 END), 0) AS recoverable, "
          'COALESCE(SUM(CASE WHEN NOT $_unattributed AND NOT EXISTS ('
          'SELECT 1 FROM sync_outbox_owners own WHERE own.outbox_id = o.id AND own.owner_user_id = ?'
          ') THEN 1 ELSE 0 END), 0) AS other_accounts, '
          "COALESCE(SUM(CASE WHEN $_unattributed AND NOT $_isMember THEN 1 ELSE 0 END), 0) AS other_businesses "
          "FROM sync_outbox o WHERE o.status <> 'synced'",
          variables: [
            Variable.withString(userId),
            Variable.withString(userId),
            Variable.withString(userId),
          ],
        )
        .getSingle();

    return HeldOutboxSummary(
      recoverable: row.read<int>('recoverable'),
      otherAccounts: row.read<int>('other_accounts'),
      otherBusinesses: row.read<int>('other_businesses'),
    );
  }

  /// Attributes recoverable rows to [userId]. Returns how many were adopted.
  Future<int> adoptUnattributed(String userId) {
    return _db.transaction(() async {
      final adoptable = (await summarize(userId)).recoverable;
      await _db.customStatement(
        'INSERT INTO sync_outbox_owners (outbox_id, owner_user_id) '
        'SELECT o.id, ? FROM sync_outbox o '
        "WHERE o.status <> 'synced' AND $_unattributed AND $_isMember",
        [userId, userId],
      );
      return adoptable;
    });
  }
}
