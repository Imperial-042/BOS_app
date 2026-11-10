// lib/features/auth/presentation/screens/register_screen.dart
//
// Creates a new login (Users row). Owners get a fresh business created for
// them by _StartupGate. Every other role has no business of their own to
// join automatically — offline, there's no server to email them an invite
// link — so they must redeem an invite code an existing member generated
// for them in Users & Roles, which is how they attach to that business.

import 'package:bos_application/core/device/device_management_service.dart';
import 'package:bos_application/core/device/device_providers.dart';
import 'package:bos_application/core/supabase/cloud_membership_bootstrap.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/transactions/presentation/widgets/barcode_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/location/location_models.dart';
import '../../../../core/location/location_picker_map.dart';
import '../../../../core/location/location_services.dart';

import '../../../../core/auth/auth_providers.dart';
import '../../../../core/auth/auth_service.dart';
import '../../../../core/auth/authorization_providers.dart';
import '../../../../core/auth/bos_access.dart';
import '../../../../core/auth/membership_service.dart';
import '../../../../core/auth/session_store.dart';
import '../../../../core/branding/branding.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/supabase/cloud_business_service.dart';
import '../../../../core/supabase/supabase_auth_service.dart';
import '../../../../core/supabase/supabase_service.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.customerMode = false});

  final bool customerMode;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  GeoCoordinate? _coordinate;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  BosRole _role = BosRole.owner;
  bool _obscurePassword = true;
  bool _submitting = false;
  bool _confirmationSent = false;
  String? _error;

  Future<void> _scanInviteCode() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerPage(
          title: 'Scan invite QR code',
          instruction: 'Position the invitation QR code inside the box',
          qrMode: true,
        ),
      ),
    );
    if (!mounted || scanned == null) return;

    final code = scanned.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That QR code is not a valid invitation.'),
        ),
      );
      return;
    }

    _inviteCodeController.text = code;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final db = ref.read(databaseProvider);
    final cloudBusiness = ref.read(cloudBusinessServiceProvider);
    final cloudAvailable = ref.read(supabaseAvailableProvider);
    final sessionNotifier = ref.read(authenticatedUserIdProvider.notifier);
    final deviceService = ref.read(deviceManagementServiceProvider);

    final needsCode = !widget.customerMode && _role != BosRole.owner;
    final code = _inviteCodeController.text;

    try {
      // 1) Validate the code BEFORE creating any account, so a typo never
      //    leaves an orphan login behind.
      BusinessInvite? localInvite;
      if (needsCode) {
        String? roleId;
        if (cloudAvailable) {
          roleId = await cloudBusiness.validateInviteCode(code);
        } else {
          localInvite = await MembershipService.findPendingInvite(db, code);
          roleId = localInvite?.role;
        }
        if (roleId == null) {
          setState(
            () => _error =
                'That invitation code is invalid or has already been used.',
          );
          return;
        }
      }

      // 2) Create the account.
      final String userId;
      var sessionEstablished = true;
      if (cloudAvailable) {
        final cloudAuth = ref.read(cloudAuthServiceProvider);
        final result = await cloudAuth.register(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text,
        );
        userId = result.user.id;
        sessionEstablished = result.sessionEstablished;
        await ref
            .read(authServiceProvider)
            .ensureLocalUser(
              id: userId,
              email: _emailController.text,
              displayName: _nameController.text,
            );
      } else {
        final user = await ref
            .read(authServiceProvider)
            .register(
              email: _emailController.text,
              password: _passwordController.text,
              displayName: _nameController.text,
            );
        userId = user.id;
      }

      if (widget.customerMode) {
        final phone = _phoneController.text.trim();
        final city = _cityController.text.trim();
        final address = _addressController.text.trim();
        final email = _emailController.text.trim();
        if (cloudAvailable && !sessionEstablished) {
          await CustomerCommerceService(db).ensureCustomerProfile(
            userId: userId,
            displayName: _nameController.text,
            phone: phone,
            city: city,
            address: address,
            coordinate: _coordinate,
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            pendingCustomerProfileKey(email),
            _nameController.text.trim(),
          );
        } else {
          await ref
              .read(customerCommerceServiceProvider)
              .ensureCustomerProfile(
                userId: userId,
                displayName: _nameController.text,
                phone: phone,
                city: city,
                address: address,
                coordinate: _coordinate,
              );
        }
      }

      // 3) Remember the invite code. Redeeming here fails with "device
      //    authorization required": the device is only registered when
      //    _StartupGate runs. Startup redeems the saved code after it
      //    registers the device.
      if (needsCode) {
        if (cloudAvailable) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            pendingInviteKey(_emailController.text),
            code.trim().toUpperCase(),
          );
        } else if (localInvite != null) {
          await MembershipService.redeemInviteCode(
            db,
            code: code,
            userId: userId,
          );
        }
      } // Owners: remember that this account should get its own business, so
      // startup creates it automatically instead of showing "join or create".
      if (!needsCode && cloudAvailable && !widget.customerMode) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(
          createBusinessIntentKey(_emailController.text),
          true,
        );
      }

      if (!sessionEstablished) {
        setState(() => _confirmationSent = true);
        return;
      }

      if (cloudAvailable) {
        // ← add
        await deviceService.registerCurrentDevice(); // ← add
      } // ← add

      await SessionStore.saveUserId(userId);
      sessionNotifier.state = userId;
      if (mounted) Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on CloudAuthException catch (e) {
      setState(() => _error = e.message);
    } on CloudBusinessException catch (e) {
      setState(() => _error = e.message);
    } on DeviceManagementException catch (e) {
      setState(() => _error = e.message);
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _confirmationSent
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.mark_email_read_outlined,
                          size: 64,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Confirm your email',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We sent a confirmation link to '
                          '${_emailController.text.trim()}. Tap it to '
                          'activate your account, then sign in.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back to sign in'),
                        ),
                      ],
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: AppLogo(height: 72)),
                          const SizedBox(height: 20),
                          Text(
                            'Set up your sign-in',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "You'll use this to access ${AppStrings.appName}.",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (_error != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Your name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Enter your name.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          if (widget.customerMode) ...[
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Phone number',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().length < 5
                                  ? 'Enter a valid phone number.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _cityController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'City or area',
                                prefixIcon: Icon(Icons.location_city_outlined),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Enter your city or area.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _addressController,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText: 'Address (optional)',
                                prefixIcon: Icon(Icons.home_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('Pin your location'),
                            const SizedBox(height: 8),
                            LocationPickerMap(
                              provider: const OpenStreetMapTileProvider(),
                              selected: _coordinate,
                              onSelected: (coordinate) =>
                                  setState(() => _coordinate = coordinate),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (widget.customerMode)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Create a customer account to discover '
                                  'published stores, follow their catalogs, '
                                  'and place pickup orders. Customer mode does '
                                  'not provide business access.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            )
                          else
                            DropdownButtonFormField<BosRole>(
                              initialValue: _role,
                              decoration: InputDecoration(
                                labelText: 'I am',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: BosRole.owner,
                                  child: Text('Starting a new business'),
                                ),
                                DropdownMenuItem(
                                  value: BosRole.employee,
                                  child: Text('Joining with an invite code'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _role = value);
                                }
                              },
                            ),
                          if (!widget.customerMode &&
                              _role != BosRole.owner) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _inviteCodeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Invitation code',
                                helperText:
                                    'Enter a code or scan the invite QR code.',
                                prefixIcon: const Icon(
                                  Icons.confirmation_number_outlined,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: 'Scan invite QR code',
                                  onPressed: _submitting
                                      ? null
                                      : _scanInviteCode,
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? 'Enter your invitation code.'
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your email.';
                              }
                              if (!value.contains('@') ||
                                  !value.contains('.')) {
                                return 'Enter a valid email.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.length < 6)
                                ? 'At least 6 characters.'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            validator: (value) =>
                                value != _passwordController.text
                                ? 'Passwords don\'t match.'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : const Text('Create account'),
                          ),
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
