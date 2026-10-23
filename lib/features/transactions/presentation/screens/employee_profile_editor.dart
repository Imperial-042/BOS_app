import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

  late final String _businessId;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

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
    _name.dispose();
    _nickname.dispose();
    _jobTitle.dispose();
    _phone.dispose();
    _address.dispose();
    _emergencyName.dispose();
    _emergencyPhone.dispose();
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
    if (!_formKey.currentState!.validate()) return;
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
      Navigator.pop(context, true);
    } on EmployeeProfileException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (!ref.watch(supabaseAvailableProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Employee profiles need the cloud connection, which is not '
              'configured in this build.',
              textAlign: TextAlign.center,
            ),
          ),
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }

    final email = ref.read(cloudAuthServiceProvider).currentEmail ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              'Only you and the business owner or managers can see this.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
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
              decoration: const InputDecoration(
                labelText: 'Nickname (optional)',
                prefixIcon: Icon(Icons.tag_faces_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: email,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                return digits.length < 7
                    ? 'Enter a valid mobile number.'
                    : null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _jobTitle,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Position / job title (optional)',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              enabled: !_saving,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Home address (optional)',
                prefixIcon: Icon(Icons.home_outlined),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _saving ? null : _pickBirthDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Birth date (optional)',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                child: Text(
                  _birthDate == null
                      ? 'Tap to choose'
                      : DateFormat('MMMM d, yyyy').format(_birthDate!),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Emergency contact',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emergencyName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Contact name (optional)',
                prefixIcon: Icon(Icons.contact_emergency_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emergencyPhone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact number (optional)',
                prefixIcon: Icon(Icons.phone_in_talk_outlined),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Save profile'),
            ),
          ],
        ),
      ),
    );
  }
}
