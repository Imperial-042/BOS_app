// Employee profile: stored in Supabase (employee_profiles), read directly
// from the cloud rather than through the Drift sync engine.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class EmployeeProfileException implements Exception {
  final String message;
  const EmployeeProfileException(this.message);

  @override
  String toString() => message;
}

class EmployeeProfile {
  final String fullName;
  final String? nickname;
  final String? jobTitle;
  final String? phone;
  final String? address;
  final DateTime? birthDate;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final DateTime? completedAt;

  const EmployeeProfile({
    required this.fullName,
    this.nickname,
    this.jobTitle,
    this.phone,
    this.address,
    this.birthDate,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.completedAt,
  });

  factory EmployeeProfile.fromMap(Map<String, dynamic> m) {
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return EmployeeProfile(
      fullName: (m['full_name'] as String?) ?? '',
      nickname: m['nickname'] as String?,
      jobTitle: m['job_title'] as String?,
      phone: m['phone'] as String?,
      address: m['address'] as String?,
      birthDate: date(m['birth_date']),
      emergencyContactName: m['emergency_contact_name'] as String?,
      emergencyContactPhone: m['emergency_contact_phone'] as String?,
      completedAt: date(m['completed_at']),
    );
  }

  Map<String, dynamic> toRow({
    required String businessId,
    required String userId,
  }) {
    String? birth;
    final b = birthDate;
    if (b != null) {
      birth =
          '${b.year.toString().padLeft(4, '0')}-'
          '${b.month.toString().padLeft(2, '0')}-'
          '${b.day.toString().padLeft(2, '0')}';
    }
    return {
      'business_id': businessId,
      'user_id': userId,
      'full_name': fullName,
      'nickname': nickname,
      'job_title': jobTitle,
      'phone': phone,
      'address': address,
      'birth_date': birth,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
    };
  }
}

class EmployeeProfileService {
  final SupabaseClient _client;
  EmployeeProfileService(this._client);

  String? get _uid => _client.auth.currentUser?.id;

  String _doneKey(String uid, String businessId) =>
      'employee_profile_done_${uid}_$businessId';

  Future<EmployeeProfile?> fetchMine(String businessId) async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from('employee_profiles')
        .select()
        .eq('business_id', businessId)
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? null : EmployeeProfile.fromMap(row);
  }

  /// Profiles of every member of [businessId], keyed by user id.
  /// What comes back is decided by your Supabase row-level security: owners
  /// and managers get the whole team, anyone else only gets their own row.
  Future<Map<String, EmployeeProfile>> fetchAllForBusiness(
    String businessId,
  ) async {
    final rows = await _client
        .from('employee_profiles')
        .select()
        .eq('business_id', businessId);

    return {
      for (final row in rows)
        if (row['user_id'] is String)
          row['user_id'] as String: EmployeeProfile.fromMap(row),
    };
  }

  /// True only when the cloud confirms this member has not finished the form.
  /// Offline or any error returns false, so the app is never blocked by it.
  Future<bool> needsProfile(String businessId) async {
    final uid = _uid;
    if (uid == null) return false;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey(uid, businessId)) ?? false) return false;

    try {
      final profile = await fetchMine(
        businessId,
      ).timeout(const Duration(seconds: 3));
      if (profile != null && profile.completedAt != null) {
        await prefs.setBool(_doneKey(uid, businessId), true);
        return false;
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> saveMine({
    required String businessId,
    required EmployeeProfile profile,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw const EmployeeProfileException(
        'Your cloud session has expired. Sign out and sign in again.',
      );
    }

    try {
      await _client.from('employee_profiles').upsert({
        ...profile.toRow(businessId: businessId, userId: uid),
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'business_id,user_id');
    } on PostgrestException catch (e) {
      throw EmployeeProfileException(
        e.code == '42501'
            ? 'You don\'t have permission to save this profile.'
            : e.message,
      );
    } on Object {
      throw const EmployeeProfileException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    // Keep the name shown in Users & Roles in sync. Best effort.
    try {
      await _client
          .from('profiles')
          .update({'display_name': profile.fullName})
          .eq('id', uid);
    } on Object {
      // ignored: the employee profile itself already saved
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_doneKey(uid, businessId), true);
  }
}

final employeeProfileServiceProvider = Provider<EmployeeProfileService>((ref) {
  return EmployeeProfileService(ref.watch(supabaseClientProvider));
});
