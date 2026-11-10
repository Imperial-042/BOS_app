import 'package:bos_application/core/auth/auth_providers.dart'
    show authServiceProvider, currentUserProvider;
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:bos_application/features/customer/presentation/customer_menu_drawer.dart'
    show customerInitials;
import 'package:bos_application/features/customer/presentation/customer_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/location/location_models.dart';
import '../../../core/location/location_picker_map.dart';
import '../../../core/location/location_services.dart';

const _kGood = Color(0xFF1F9D74);

/// Customer profile page: edit name, phone, city and street address.
///
/// Pops with `true` after a successful save so the caller can refresh
/// anything that depends on the profile (for example the stores near the
/// customer's city).
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  ConsumerState<CustomerProfileScreen> createState() =>
      _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();

  late final Listenable _fields = Listenable.merge([
    _name,
    _phone,
    _city,
    _address,
  ]);

  CustomerLocationProfile? _initial;
  bool _loading = true;
  bool _saving = false;
  GeoCoordinate? _coordinate;

  /// True once the user has dropped or cleared the map pin, so the save bar
  /// appears for pin-only changes too.
  bool _pinTouched = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  String _clean(String? value) => (value ?? '').trim();

  bool get _dirty {
    final p = _initial;
    return _pinTouched ||
        _clean(_name.text) != _clean(p?.displayName) ||
        _clean(_phone.text) != _clean(p?.phone) ||
        _clean(_city.text) != _clean(p?.city) ||
        _clean(_address.text) != _clean(p?.address);
  }

  /// Profile details filled in, out of 5 (name, phone, city, address, pin).
  static const _totalDetails = 5;
  int get _completed =>
      [
        _name,
        _phone,
        _city,
        _address,
      ].where((c) => _clean(c.text).isNotEmpty).length +
      (_coordinate != null ? 1 : 0);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final userId = ref.read(authenticatedUserIdProvider);
      if (userId == null) throw StateError('You are signed out.');
      final profile = await ref
          .read(customerCommerceServiceProvider)
          .loadCustomerProfile(userId);
      if (!mounted) return;
      setState(() {
        _initial = profile;
        _name.text = profile?.displayName ?? '';
        _phone.text = profile?.phone ?? '';
        _city.text = profile?.city ?? '';
        _address.text = profile?.address ?? '';
        _coordinate = profile?.coordinate;
        _pinTouched = false;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.mediumImpact();
      return;
    }
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await ref
          .read(customerCommerceServiceProvider)
          .updateCustomerProfile(
            userId: userId,
            displayName: _name.text,
            phone: _phone.text,
            city: _city.text,
            address: _address.text,
            coordinate: _coordinate,
          );
      // Keep the name shown in the drawer / app bar in sync with the
      // local account row (no-op if it already matches).
      try {
        await ref
            .read(authServiceProvider)
            .updateDisplayName(userId: userId, displayName: _name.text);
      } catch (_) {}
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: const Text('Profile saved.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text('Could not save profile: ${friendlyError(error)}'),
        ),
      );
    }
  }

  void _reset() {
    final p = _initial;
    setState(() {
      _name.text = p?.displayName ?? '';
      _phone.text = p?.phone ?? '';
      _city.text = p?.city ?? '';
      _address.text = p?.address ?? '';
      _coordinate = p?.coordinate;
      _pinTouched = false;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _confirmDiscard() async {
    final scheme = Theme.of(context).colorScheme;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.edit_off_outlined,
            color: scheme.onErrorContainer,
            size: 28,
          ),
        ),
        title: const Text(
          'Discard changes?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Your edits have not been saved.',
          textAlign: TextAlign.center,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Keep editing'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  InputDecoration _dec(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? helper,
    bool alignHint = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      alignLabelWithHint: alignHint,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      disabledBorder: border(Colors.transparent),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(scheme.error, 1.2),
      focusedErrorBorder: border(scheme.error, 1.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: _fields,
      builder: (context, _) {
        final dirty = _dirty;

        return PopScope(
          canPop: !dirty || _saving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmDiscard();
          },
          child: Scaffold(
            backgroundColor: scheme.surface,
            appBar: AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              titleSpacing: 4,
              title: const Text(
                'My profile',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            body: _body(context),
            bottomNavigationBar: _loading || _loadError != null
                ? null
                : AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.bottomCenter,
                    child: dirty
                        ? _saveBar(context)
                        : const SizedBox(width: double.infinity),
                  ),
          ),
        );
      },
    );
  }

  Widget _saveBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE08A1E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'You have unsaved changes',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _saving ? null : _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        _saving ? 'Saving…' : 'Save changes',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          SkeletonPulse(
            child: Column(
              children: [
                Container(
                  height: 190,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < 3; i++) ...[
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
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
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 38,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Could not load your profile',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final city = _clean(_city.text);
    final name = _clean(_name.text);
    final email = ref.watch(currentUserProvider).value?.email;
    final done = _completed;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // ── Hero ──
          Container(
            padding: const EdgeInsets.all(20),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.alphaBlend(
                    scheme.tertiary.withValues(alpha: 0.55),
                    scheme.primary,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -50,
                  top: -60,
                  child: IgnorePointer(
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.onPrimary.withValues(alpha: 0.12),
                          width: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.onPrimary.withValues(alpha: 0.45),
                              width: 2,
                            ),
                          ),
                          child: Container(
                            width: 68,
                            height: 68,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.onPrimary.withValues(alpha: 0.2),
                            ),
                            child: Text(
                              customerInitials(name),
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              if ((email ?? '').isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  email!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onPrimary.withValues(
                                      alpha: 0.82,
                                    ),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.onPrimary.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_rounded,
                                      size: 14,
                                      color: scheme.onPrimary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        city.isEmpty ? 'Set your city' : city,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
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
                          done == _totalDetails
                              ? 'Profile complete'
                              : '$done of $_totalDetails details added',
                          style: TextStyle(
                            color: scheme.onPrimary.withValues(alpha: 0.92),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(done / _totalDetails * 100).round()}%',
                          style: TextStyle(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: done / _totalDetails),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: scheme.onPrimary.withValues(
                            alpha: 0.22,
                          ),
                          valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _HeroCheck(
                          label: 'Name',
                          done: _clean(_name.text).isNotEmpty,
                        ),
                        _HeroCheck(
                          label: 'Phone',
                          done: _clean(_phone.text).isNotEmpty,
                        ),
                        _HeroCheck(
                          label: 'City',
                          done: _clean(_city.text).isNotEmpty,
                        ),
                        _HeroCheck(
                          label: 'Address',
                          done: _clean(_address.text).isNotEmpty,
                        ),
                        _HeroCheck(label: 'Pin', done: _coordinate != null),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Personal ──
          _Section(
            icon: Icons.person_outline_rounded,
            title: 'Personal details',
            subtitle: 'How stores see you on an order.',
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: _dec(
                    context,
                    label: 'Full name',
                    icon: Icons.badge_outlined,
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: _dec(
                    context,
                    label: 'Phone (optional)',
                    icon: Icons.call_outlined,
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return text.length < 5
                        ? 'Enter a valid phone number'
                        : null;
                  },
                ),
                if ((email ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    key: ValueKey('email-$email'),
                    initialValue: email,
                    readOnly: true,
                    enableInteractiveSelection: false,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                    decoration:
                        _dec(
                          context,
                          label: 'Email',
                          icon: Icons.alternate_email_rounded,
                          helper:
                              'Your sign-in email can\u2019t be changed here.',
                        ).copyWith(
                          suffixIcon: const Icon(Icons.lock_outline, size: 18),
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Location ──
          _Section(
            icon: Icons.location_city_rounded,
            title: 'Location',
            subtitle: 'Helps us show stores near you.',
            trailing: _coordinate == null
                ? null
                : TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _coordinate = null;
                            _pinTouched = true;
                          }),
                    icon: const Icon(Icons.location_off_outlined, size: 18),
                    label: const Text('Clear pin'),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _city,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: _dec(
                    context,
                    label: 'City or area',
                    helper: 'Used to show stores near you.',
                    icon: Icons.place_outlined,
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter your city or area'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _address,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLines: 2,
                  decoration: _dec(
                    context,
                    label: 'Street address (optional)',
                    icon: Icons.home_outlined,
                    alignHint: true,
                  ),
                ),
                const SizedBox(height: 16),
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
                          ? 'Tap the map to pin your location'
                          : 'Location pinned',
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
                    onSelected: (coordinate) => setState(() {
                      _coordinate = coordinate;
                      _pinTouched = true;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Privacy ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Who sees what',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PrivacyRow(
                  icon: Icons.location_city_rounded,
                  text: 'Your city is used only to find stores near you.',
                  color: scheme.onPrimaryContainer,
                ),
                _PrivacyRow(
                  icon: Icons.call_outlined,
                  text:
                      'Your phone is shared with a store only when you send it an order.',
                  color: scheme.onPrimaryContainer,
                ),
                _PrivacyRow(
                  icon: Icons.home_outlined,
                  text: 'Your street address stays private to your profile.',
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroCheck extends StatelessWidget {
  const _HeroCheck({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.onPrimary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(7, 5, 10, 5),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: done ? 0.24 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: done ? 0.4 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: fg.withValues(alpha: done ? 1 : 0.6),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: done ? 1 : 0.7),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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

class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}