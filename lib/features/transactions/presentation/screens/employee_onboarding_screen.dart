import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/role_labels.dart';
import 'package:bos_application/core/branding/branding.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/employee_profile_service.dart';
import 'package:bos_application/core/supabase/supabase_auth_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Shown once to every non-owner member after joining a business.
class EmployeeOnboardingScreen extends ConsumerStatefulWidget {
  const EmployeeOnboardingScreen({
    super.key,
    required this.businessId,
    required this.businessName,
    required this.onFinished,
    this.allowSkip = true,
  });

  final String businessId;
  final String businessName;
  final VoidCallback onFinished;

  /// "Do this later" returns to the app without saving; the form comes back
  /// on the next launch until it is completed.
  final bool allowSkip;

  @override
  ConsumerState<EmployeeOnboardingScreen> createState() =>
      _EmployeeOnboardingScreenState();
}

class _EmployeeOnboardingScreenState
    extends ConsumerState<EmployeeOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _nickname = TextEditingController();
  final _jobTitle = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  DateTime? _birthDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(cloudAuthServiceProvider).currentDisplayName ?? '';
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

    final service = ref.read(employeeProfileServiceProvider);
    final db = ref.read(databaseProvider);
    final uid = ref.read(authenticatedUserIdProvider);
    final name = _name.text.trim();

    try {
      await service.saveMine(
        businessId: widget.businessId,
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

      // Keep the on-device name in step with the cloud profile.
      if (uid != null) {
        await (db.update(db.users)..where((u) => u.id.equals(uid))).write(
          UsersCompanion(displayName: Value(name)),
        );
      }

      if (mounted) widget.onFinished();
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roleLabel = ref.watch(currentRoleLabelProvider);
    final email = ref.read(cloudAuthServiceProvider).currentEmail ?? '';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo(height: 64)),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome to ${widget.businessName}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      roleLabel.isEmpty
                          ? 'Complete your employee profile.'
                          : 'You\'re joining as $roleLabel. '
                                'Complete your employee profile.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Only you and the business owner or managers can see this.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _jobTitle,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Position / job title (optional)',
                        hintText: roleLabel.isEmpty ? null : roleLabel,
                        prefixIcon: const Icon(Icons.work_outline_rounded),
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
                    const SizedBox(height: 22),
                    Text(
                      'Emergency contact',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _emergencyName,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
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
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Contact number (optional)',
                        prefixIcon: Icon(Icons.phone_in_talk_outlined),
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('Save and continue'),
                    ),
                    if (widget.allowSkip) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : widget.onFinished,
                        child: const Text('Do this later'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
