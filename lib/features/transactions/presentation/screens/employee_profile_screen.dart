import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/transactions/presentation/widgets/profile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'employee_profile_editor.dart';

/// Profile for every non-owner member. Rendered by [ProfileScreen]; it has
/// no business switching, by design.
class EmployeeProfileScreen extends ConsumerStatefulWidget {
  const EmployeeProfileScreen({super.key});

  @override
  ConsumerState<EmployeeProfileScreen> createState() =>
      _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends ConsumerState<EmployeeProfileScreen> {
  EmployeeProfile? _profile;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(supabaseAvailableProvider)) {
      _load();
    } else {
      _loading = false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final profile = await ref
          .read(employeeProfileServiceProvider)
          .fetchMine(ref.read(selectedBusinessIdProvider))
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EmployeeProfileEditor()),
    );
    if (saved == true && mounted) _load();
  }

  String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final cloud = ref.watch(supabaseAvailableProvider);

    final user = ref.watch(currentUserProvider).value;
    final roleLabel = ref.watch(currentRoleLabelProvider);
    final business = ref.watch(currentBusinessProvider).value;
    final membership = ref.watch(currentBusinessMembershipProvider).value;

    final profile = _profile;
    final email =
        (cloud ? ref.read(cloudAuthServiceProvider).currentEmail : null) ??
        user?.email;
    final name =
        _clean(profile?.fullName) ??
        _clean(user?.displayName) ??
        'Your profile';
    final jobTitle = _clean(profile?.jobTitle);

    final emergency = [
      _clean(profile?.emergencyContactName),
      _clean(profile?.emergencyContactPhone),
    ].whereType<String>().join(' · ');

    final rows = <(IconData, String, String)>[
      if (_clean(profile?.nickname) != null)
        (Icons.tag_faces_outlined, 'Nickname', _clean(profile!.nickname)!),
      if (jobTitle != null) (Icons.work_outline_rounded, 'Position', jobTitle),
      if (_clean(email) != null)
        (Icons.email_outlined, 'Email', _clean(email)!),
      if (_clean(profile?.phone) != null)
        (Icons.phone_outlined, 'Mobile', _clean(profile!.phone)!),
      if (_clean(profile?.address) != null)
        (Icons.home_outlined, 'Address', _clean(profile!.address)!),
      if (profile?.birthDate != null)
        (
          Icons.cake_outlined,
          'Birth date',
          DateFormat('MMMM d, yyyy').format(profile!.birthDate!),
        ),
      if (emergency.isNotEmpty)
        (Icons.contact_emergency_outlined, 'Emergency contact', emergency),
    ];

    final workplace = <(IconData, String, String)>[];
    if (business != null) {
      final address = [
        business.addressBarangay,
        business.addressCity,
        business.addressProvince,
        business.addressCountry,
      ].map(_clean).whereType<String>().join(', ');

      workplace.addAll([
        (Icons.storefront_outlined, 'Business', business.name),
        if (_clean(business.businessCategory) != null)
          (
            Icons.category_outlined,
            'Category',
            _clean(business.businessCategory)!,
          ),
        if (_clean(business.ownerName) != null)
          (Icons.person_outline_rounded, 'Owner', _clean(business.ownerName)!),
        if (_clean(business.phone) != null)
          (Icons.phone_outlined, 'Business phone', _clean(business.phone)!),
        if (_clean(business.email) != null)
          (Icons.email_outlined, 'Business email', _clean(business.email)!),
        if (address.isNotEmpty)
          (Icons.location_on_outlined, 'Location', address),
        if (membership != null)
          (
            Icons.event_available_outlined,
            'Member since',
            DateFormat('MMM d, yyyy').format(membership.joinedAt),
          ),
      ]);
    }

    final incomplete =
        cloud && !_loading && !_loadFailed && profile?.completedAt == null;

    final badges = <String>[
      if (roleLabel.isNotEmpty) roleLabel,
      if (jobTitle != null && jobTitle != roleLabel) jobTitle,
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: cloud ? _load : () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            if (_loading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            ProfileHero(name: name, subtitle: business?.name, badges: badges),
            if (_loadFailed) ...[
              const SizedBox(height: 16),
              ProfileBanner(
                isError: true,
                icon: Icons.cloud_off_rounded,
                message: 'Could not load your details.',
                actionLabel: 'Retry',
                onAction: _load,
              ),
            ],
            if (incomplete) ...[
              const SizedBox(height: 16),
              ProfileBanner(
                icon: Icons.info_outline_rounded,
                message: 'Your profile isn\'t complete yet.',
                actionLabel: 'Complete',
                onAction: _edit,
              ),
            ],
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 24),
              ProfileSection(
                title: 'My details',
                children: [
                  for (final r in rows)
                    ProfileDetailRow(icon: r.$1, label: r.$2, value: r.$3),
                ],
              ),
            ],
            if (workplace.isNotEmpty) ...[
              const SizedBox(height: 24),
              ProfileSection(
                title: 'Your workplace',
                children: [
                  for (final r in workplace)
                    ProfileDetailRow(icon: r.$1, label: r.$2, value: r.$3),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ProfileSection(
              title: 'Account',
              children: [
                if (cloud)
                  ProfileActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Edit profile',
                    subtitle: 'Update your name and contact details',
                    onTap: _edit,
                  ),
                ProfileActionTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Password & security',
                  subtitle: 'Password, app lock and your signed-in devices',
                  onTap: () => openAccountSecurity(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
