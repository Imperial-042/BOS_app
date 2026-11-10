import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/location/location_models.dart';
import '../../../../core/location/location_picker_map.dart';
import '../../../../core/location/location_services.dart';

const _kGood = Color(0xFF1F9D74);

/// Edit form for the signed-in member's own profile. Pops `true` when saved.
class EmployeeProfileEditor extends ConsumerStatefulWidget {
  const EmployeeProfileEditor({super.key});

  @override
  ConsumerState<EmployeeProfileEditor> createState() =>
      _EmployeeProfileEditorState();
}

class _EmployeeProfileEditorState extends ConsumerState<EmployeeProfileEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _jobTitle = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  DateTime? _birthDate;
  GeoCoordinate? _coordinate;

  late final String _businessId;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  List<TextEditingController> get _controllers => [
    _name,
    _nickname,
    _jobTitle,
    _phone,
    _address,
    _emergencyName,
    _emergencyPhone,
  ];

  @override
  void initState() {
    super.initState();
    _businessId = ref.read(selectedBusinessIdProvider);
    if (ref.read(supabaseAvailableProvider)) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final profile = await ref
          .read(employeeProfileServiceProvider)
          .fetchMine(_businessId)
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      final fallback = ref.read(cloudAuthServiceProvider).currentDisplayName;
      _name.text = (profile?.fullName.isNotEmpty ?? false)
          ? profile!.fullName
          : (fallback ?? '');
      _nickname.text = profile?.nickname ?? '';
      _jobTitle.text = profile?.jobTitle ?? '';
      _phone.text = profile?.phone ?? '';
      _address.text = profile?.address ?? '';
      _coordinate = profile?.coordinate;
      _emergencyName.text = profile?.emergencyContactName ?? '';
      _emergencyPhone.text = profile?.emergencyContactPhone ?? '';
      _birthDate = profile?.birthDate;
      setState(() => _loading = false);
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your profile. Check your connection.';
      });
    }
  }

  String? _text(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.mediumImpact();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final db = ref.read(databaseProvider);
    final uid = ref.read(authenticatedUserIdProvider);
    final name = _name.text.trim();

    try {
      await ref
          .read(employeeProfileServiceProvider)
          .saveMine(
            businessId: _businessId,
            profile: EmployeeProfile(
              fullName: name,
              nickname: _text(_nickname),
              jobTitle: _text(_jobTitle),
              phone: _text(_phone),
              address: _text(_address),
              coordinate: _coordinate,
              birthDate: _birthDate,
              emergencyContactName: _text(_emergencyName),
              emergencyContactPhone: _text(_emergencyPhone),
            ),
          );
      if (uid != null) {
        await (db.update(db.users)..where((u) => u.id.equals(uid))).write(
          UsersCompanion(displayName: Value(name)),
        );
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } on EmployeeProfileException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 0..1 share of the profile that has been filled in.
  double get _completeness {
    final filled = [
      _name.text.trim().isNotEmpty,
      _nickname.text.trim().isNotEmpty,
      _jobTitle.text.trim().isNotEmpty,
      _phone.text.trim().isNotEmpty,
      _address.text.trim().isNotEmpty,
      _coordinate != null,
      _birthDate != null,
      _emergencyName.text.trim().isNotEmpty,
      _emergencyPhone.text.trim().isNotEmpty,
    ];
    return filled.where((f) => f).length / filled.length;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!ref.watch(supabaseAvailableProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const _StateView(
          icon: Icons.cloud_off_outlined,
          title: 'Cloud connection needed',
          message:
              'Employee profiles need the cloud connection, which is not '
              'configured in this build.',
        ),
      );
    }

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: _StateView(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn’t load your profile',
          message: _loadError!,
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
      );
    }

    final email = ref.read(cloudAuthServiceProvider).currentEmail ?? '';

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Edit profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            ListenableBuilder(
              listenable: Listenable.merge(_controllers),
              builder: (context, _) => _ProfileHero(
                name: _name.text.trim(),
                jobTitle: _jobTitle.text.trim(),
                email: email,
                completeness: _completeness,
              ),
            ),
            const SizedBox(height: 12),
            const _PrivacyNote(),
            const SizedBox(height: 12),
            if (_error != null) ...[
              _ErrorBanner(message: _error!),
              const SizedBox(height: 12),
            ],
            _Section(
              icon: Icons.person_outline_rounded,
              title: 'Personal',
              subtitle: 'How you appear to your team.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter your full name.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nickname,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nickname (optional)',
                      prefixIcon: Icon(Icons.tag_faces_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: _saving ? null : _pickBirthDate,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Birth date (optional)',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        suffixIcon: _birthDate == null
                            ? const Icon(Icons.calendar_month_outlined)
                            : IconButton(
                                tooltip: 'Clear birth date',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _birthDate = null),
                              ),
                      ),
                      child: Text(
                        _birthDate == null
                            ? 'Tap to choose'
                            : DateFormat('MMMM d, yyyy').format(_birthDate!),
                        style: TextStyle(
                          color: _birthDate == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              icon: Icons.contact_phone_outlined,
              title: 'Contact',
              subtitle: 'So the business can reach you.',
              child: Column(
                children: [
                  TextFormField(
                    initialValue: email,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      helperText: 'Email comes from your sign-in and can’t be changed here.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      return digits.length < 7
                          ? 'Enter a valid mobile number.'
                          : null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              icon: Icons.work_outline_rounded,
              title: 'Work',
              child: TextFormField(
                controller: _jobTitle,
                enabled: !_saving,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Position / job title (optional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              icon: Icons.home_outlined,
              title: 'Home',
              subtitle: 'Address and a pin on the map.',
              trailing: _coordinate == null
                  ? null
                  : TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _coordinate = null),
                      icon: const Icon(Icons.location_off_outlined, size: 18),
                      label: const Text('Clear pin'),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _address,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Home address (optional)',
                      prefixIcon: Icon(Icons.place_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        _coordinate == null
                            ? Icons.touch_app_outlined
                            : Icons.check_circle_rounded,
                        size: 16,
                        color: _coordinate == null
                            ? scheme.onSurfaceVariant
                            : _kGood,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _coordinate == null
                            ? 'Tap the map to drop your home pin'
                            : 'Home pin set',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _coordinate == null
                              ? scheme.onSurfaceVariant
                              : _kGood,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: LocationPickerMap(
                      provider: const OpenStreetMapTileProvider(),
                      selected: _coordinate,
                      onSelected: (coordinate) =>
                          setState(() => _coordinate = coordinate),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Section(
              icon: Icons.contact_emergency_outlined,
              title: 'Emergency contact',
              subtitle: 'Someone we can call if something happens.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _emergencyName,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Contact name (optional)',
                      prefixIcon: Icon(Icons.person_pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emergencyPhone,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Contact number (optional)',
                      prefixIcon: Icon(Icons.phone_in_talk_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SizedBox(
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _saving ? 'Saving…' : 'Save profile',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// HERO
// ============================================================================

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.jobTitle,
    required this.email,
    required this.completeness,
  });

  final String name;
  final String jobTitle;
  final String email;
  final double completeness;

  String get _initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    final list = parts.toList();
    final first = list.first[0];
    final last = list.length > 1 ? list.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimary;
    final percent = (completeness * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg.withValues(alpha: 0.2),
                  border: Border.all(color: fg.withValues(alpha: 0.5), width: 2),
                ),
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: fg,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your name' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (jobTitle.isNotEmpty)
                      Text(
                        jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.8),
                          fontSize: 12.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                percent == 100 ? 'Profile complete' : 'Profile completeness',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: TextStyle(color: fg, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(end: completeness),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: fg.withValues(alpha: 0.22),
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SHARED PIECES
// ============================================================================

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only you and the business owner or managers can see this.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}