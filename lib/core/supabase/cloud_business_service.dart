// lib/core/supabase/cloud_business_service.dart
//
// Cloud-side profile + business + membership operations against Supabase.
// These hit PostgreSQL directly (protected by RLS) — the client never trusts
// its own business_id; the database enforces membership.
//
// Invite creation always records the authenticated creator so the server-side
// redeem_invite_code() RPC can preserve the inviter in
// business_memberships.invited_by.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class CloudBusinessException implements Exception {
  final String code;
  final String message;

  const CloudBusinessException(this.code, this.message);

  @override
  String toString() => message;
}

CloudBusinessException _mapError(Object error) {
  if (error is PostgrestException) {
    if (error.code == '42501' || error.code == 'PGRST301') {
      return const CloudBusinessException(
        'not_authorized',
        'You don\'t have access to that business.',
      );
    }

    if (error.code == '23505') {
      return const CloudBusinessException(
        'conflict',
        'That record already exists.',
      );
    }

    if (error.code == '23503') {
      return const CloudBusinessException(
        'constraint_error',
        'That record references something that doesn\'t exist here.',
      );
    }

    return CloudBusinessException('database_error', error.message);
  }

  return const CloudBusinessException(
    'network_error',
    'Could not reach the server. Check your connection and try again.',
  );
}

class CloudProfile {
  final String id;
  final String displayName;
  final String? avatarPath;

  const CloudProfile({
    required this.id,
    required this.displayName,
    this.avatarPath,
  });

  factory CloudProfile.fromMap(Map<String, dynamic> map) {
    return CloudProfile(
      id: map['id'] as String,
      displayName: (map['display_name'] as String?) ?? '',
      avatarPath: map['avatar_path'] as String?,
    );
  }
}

class CloudMembership {
  final String id;
  final String businessId;
  final String userId;
  final String role;
  final String status;
  final String? invitedBy;

  const CloudMembership({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.role,
    required this.status,
    this.invitedBy,
  });

  factory CloudMembership.fromMap(Map<String, dynamic> map) {
    return CloudMembership(
      id: map['id'] as String,
      businessId: map['business_id'] as String,
      userId: map['user_id'] as String,
      role: map['role'] as String,
      status: map['status'] as String,
      invitedBy: map['invited_by'] as String?,
    );
  }
}

class CloudBusinessService {
  final SupabaseClient _client;

  CloudBusinessService(this._client);

  String _requireUserId() {
    final uid = _client.auth.currentUser?.id;

    if (uid == null) {
      throw const CloudBusinessException(
        'not_signed_in',
        'Your cloud session has expired. Sign out and sign in again.',
      );
    }

    return uid;
  }

  /// The signed-in user's own profile row (id == auth UUID).
  Future<CloudProfile?> getMyProfile() async {
    final uid = _client.auth.currentUser?.id;

    if (uid == null) return null;

    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      return row == null ? null : CloudProfile.fromMap(row);
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> updateMyProfile({
    String? displayName,
    String? avatarPath,
  }) async {
    final uid = _requireUserId();

    try {
      await _client
          .from('profiles')
          .update({
            if (displayName != null) 'display_name': displayName,
            if (avatarPath != null) 'avatar_path': avatarPath,
          })
          .eq('id', uid);
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Every business the signed-in user actively belongs to.
  ///
  /// RLS remains the authoritative security boundary.
  Future<List<Map<String, dynamic>>> listMyBusinesses() async {
    try {
      final rows = await _client
          .from('businesses')
          .select()
          .eq('is_active', true)
          .order('name');

      return List<Map<String, dynamic>>.from(rows);
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Atomic business creation via the server-side function:
  /// business row + owner membership are created together.
  Future<String> createBusiness({
    required String name,
    String? businessType,
    String? industry,
    String currencyCode = 'PHP',
    String timezone = 'Asia/Manila',
  }) async {
    try {
      final id = await _client.rpc(
        'create_business_with_owner',
        params: {
          'p_name': name,
          'p_business_type': businessType,
          'p_industry': industry,
          'p_currency_code': currencyCode,
          'p_timezone': timezone,
        },
      );

      return id as String;
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// The signed-in user's active memberships.
  ///
  /// RLS remains the authoritative filter. The explicit user filter also
  /// makes the intent clear and avoids returning irrelevant rows if policies
  /// ever become broader.
  Future<List<CloudMembership>> listMyMemberships() async {
    final uid = _requireUserId();

    try {
      final rows = await _client
          .from('business_memberships')
          .select()
          .eq('user_id', uid)
          .eq('status', 'active');

      return [
        for (final row in rows as List)
          CloudMembership.fromMap(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (error) {
      throw _mapError(error);
    }
  }

  // -------------------------------------------------------------------------
  // INVITE CODES
  // -------------------------------------------------------------------------

  /// Creates a redeemable invite code in Supabase.
  ///
  /// IMPORTANT:
  /// created_by is explicitly populated with the authenticated user's UUID.
  /// This value becomes the source for business_memberships.invited_by when
  /// the invite is redeemed by the server-side RPC.
  Future<String> createInviteCode({
    required String businessId,
    required String role,
  }) async {
    final uid = _requireUserId();

    try {
      final code = _generateCode();

      await _client.from('business_invites').insert({
        'business_id': businessId,
        'code': code,
        'role': role,
        'created_by': uid,
      });

      return code;
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Validates a code without consuming it.
  Future<String?> validateInviteCode(String code) async {
    try {
      final result = await _client.rpc(
        'validate_invite_code',
        params: {'p_code': code.trim().toUpperCase()},
      );

      return result as String?;
    } catch (error) {
      throw _mapError(error);
    }
  }

  /// Redeems a code for the signed-in user.
  ///
  /// The server-side RPC must derive invited_by from
  /// business_invites.created_by. The client intentionally does not send an
  /// invited_by value.
  Future<void> redeemInviteCode(String code) async {
    _requireUserId();

    try {
      await _client.rpc(
        'redeem_invite_code',
        params: {'p_code': code.trim().toUpperCase()},
      );
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    _requireUserId();
    try {
      await _client.rpc(fn, params: params);
    } catch (error) {
      throw _mapError(error);
    }
  }

  Future<void> setMemberRole({
    required String businessId,
    required String userId,
    required String role,
  }) => _rpc('set_member_role', {
    'p_business_id': businessId,
    'p_user_id': userId,
    'p_role': role,
  });

  Future<void> setMemberSuspended({
    required String businessId,
    required String userId,
    required bool suspended,
  }) => _rpc('set_member_suspended', {
    'p_business_id': businessId,
    'p_user_id': userId,
    'p_suspended': suspended,
  });

  Future<void> removeMember({
    required String businessId,
    required String userId,
  }) =>
      _rpc('remove_member', {'p_business_id': businessId, 'p_user_id': userId});

  Future<void> transferOwnership({
    required String businessId,
    required String newOwnerUserId,
  }) => _rpc('transfer_ownership', {
    'p_business_id': businessId,
    'p_new_owner': newOwnerUserId,
  });

  Future<void> revokeInviteCode({
    required String businessId,
    required String code,
  }) =>
      _rpc('revoke_invite_code', {'p_business_id': businessId, 'p_code': code});

  Future<void> deleteBusiness(String businessId) =>
      _rpc('delete_business', {'p_business_id': businessId});

  /// Pushes a locally-generated code to Supabase so it can be redeemed on any
  /// device.
  ///
  /// created_by is always taken from the authenticated cloud session.
  Future<void> pushInviteCode({
    required String businessId,
    required String code,
    required String role,
  }) async {
    final uid = _requireUserId();

    try {
      await _client.from('business_invites').upsert({
        'business_id': businessId,
        'code': code.trim().toUpperCase(),
        'role': role,
        'created_by': uid,
      }, onConflict: 'code');
    } on PostgrestException catch (e) {
      throw CloudBusinessException('database_error', '${e.code}: ${e.message}');
    } catch (_) {
      throw const CloudBusinessException(
        'network_error',
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _generateCode() {
    final random = Random.secure();

    return List.generate(
      8,
      (_) => _codeChars[random.nextInt(_codeChars.length)],
    ).join();
  }
}

final cloudBusinessServiceProvider = Provider<CloudBusinessService>((ref) {
  return CloudBusinessService(ref.watch(supabaseClientProvider));
});
