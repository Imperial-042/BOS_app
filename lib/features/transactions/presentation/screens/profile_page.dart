// lib/features/profile/presentation/screens/profile_page.dart
//
// Extracted from main.dart: business onboarding, the profile view,
// and the shared business-profile editing form (name, category,
// address, and starting capital).

import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show
        businessProfileProvider,
        kCurrentBusinessId,
        ledgerVersionProvider,
        paymentAccountsProvider,
        transactionServiceProvider;

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return _BusinessProfileEditor(
      title: 'Set up your profile',
      subtitle: 'Add your details now or skip and update them later.',
      showSkip: true,
      showOwnerName: true,
      onFinished: onFinished,
    );
  }
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(businessProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            const Center(child: Text('Unable to load profile.')),
        data: (business) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            CircleAvatar(
              radius: 42,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.person_rounded,
                size: 44,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              business.ownerName?.isNotEmpty == true
                  ? business.ownerName!
                  : 'Your name',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              business.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (business.businessCategory?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                business.businessCategory!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (business.managerName?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                'Manager: ${business.managerName}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (business.addressCity?.isNotEmpty == true ||
                business.addressProvince?.isNotEmpty == true ||
                business.addressCountry?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                [
                      business.addressCity,
                      business.addressBarangay,
                      business.addressProvince,
                      business.addressCountry,
                      business.addressZipCode,
                    ]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(', '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _BusinessProfileEditor(
                      title: 'Edit profile',
                      subtitle: 'Update your name and business details.',
                      onFinished: () => Navigator.pop(context),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit profile'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openBusinessSwitcher(context, ref),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Switch business'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _addBusiness(context, ref, business),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add another business'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBusinessSwitcher(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final db = ref.read(databaseProvider);
    final businesses = await db.select(db.businesses).get();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Your businesses',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final item in businesses)
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(item.name),
                subtitle: Text(item.businessCategory ?? 'Business'),
                selected: item.id == kCurrentBusinessId,
                onTap: () async {
                  if (item.id != kCurrentBusinessId) {
                    await db.transaction(() async {
                      await (db.update(db.businesses)).write(
                        const BusinessesCompanion(isCurrent: Value(false)),
                      );
                      await (db.update(db.businesses)
                            ..where((business) => business.id.equals(item.id)))
                          .write(
                            const BusinessesCompanion(isCurrent: Value(true)),
                          );
                    });
                    kCurrentBusinessId = item.id;
                    ref.read(ledgerVersionProvider.notifier).state++;
                  }
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBusiness(
    BuildContext context,
    WidgetRef ref,
    BusinessesData currentBusiness,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _BusinessNameDialog(),
    );

    if (name == null || !context.mounted) return;

    try {
      final db = ref.read(databaseProvider);
      final businessId = const Uuid().v4();

      await db.transaction(() async {
        await (db.update(
          db.businesses,
        )).write(const BusinessesCompanion(isCurrent: Value(false)));
        await db
            .into(db.businesses)
            .insert(
              BusinessesCompanion.insert(
                id: businessId,
                name: name,
                ownerUserId: currentBusiness.ownerUserId,
                isCurrent: const Value(true),
              ),
            );
        await db.seedDefaultsForBusiness(businessId);
      });

      kCurrentBusinessId = businessId;
      ref.read(ledgerVersionProvider.notifier).state++;

      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _BusinessProfileEditor(
            title: 'Set up $name',
            subtitle:
                'Complete the business details. Owner name is optional here.',
            showSkip: true,
            showOwnerName: false,
            onFinished: () => Navigator.pop(context),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add business: $error')));
    }
  }
}

class _BusinessNameDialog extends StatefulWidget {
  const _BusinessNameDialog();

  @override
  State<_BusinessNameDialog> createState() => _BusinessNameDialogState();
}

class _BusinessNameDialogState extends State<_BusinessNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add another business'),
      content: TextField(
        controller: _controller,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Business name',
          prefixIcon: Icon(Icons.business_outlined),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(context, value);
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _PsgcPlace {
  final String code;
  final String name;

  const _PsgcPlace({required this.code, required this.name});

  factory _PsgcPlace.fromJson(Map<String, dynamic> json) {
    return _PsgcPlace(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

class _BusinessProfileEditor extends ConsumerStatefulWidget {
  final String title;
  final String subtitle;
  final bool showSkip;
  final bool showOwnerName;
  final VoidCallback onFinished;

  const _BusinessProfileEditor({
    required this.title,
    required this.subtitle,
    this.showSkip = false,
    this.showOwnerName = true,
    required this.onFinished,
  });

  @override
  ConsumerState<_BusinessProfileEditor> createState() =>
      _BusinessProfileEditorState();
}

class _BusinessProfileEditorState
    extends ConsumerState<_BusinessProfileEditor> {
  final _ownerController = TextEditingController();
  final _managerController = TextEditingController();
  final _businessController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _zipController = TextEditingController();
  final _capitalController = TextEditingController();
  String? _category;
  String? _country;
  String? _province;
  String? _city;
  String? _barangay;
  String? _capitalAccountId;
  BusinessesData? _business;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  static const _categories = [
    'Retail',
    'Food and beverage',
    'Services',
    'Manufacturing',
    'Agriculture',
    'Construction',
    'Online business',
    'Other',
  ];

  static const _countries = [
    'Philippines',
    'United States',
    'Canada',
    'United Kingdom',
    'Australia',
    'Other',
  ];

  List<_PsgcPlace> _provinces = [];
  List<_PsgcPlace> _cities = [];
  List<_PsgcPlace> _barangays = [];
  bool _locationsLoading = false;
  String? _locationsError;

  String? _validDropdownValue(String? value, List<String> allowedValues) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return allowedValues.contains(value) ? value : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(databaseProvider);
      final business = await (db.select(
        db.businesses,
      )..where((item) => item.id.equals(kCurrentBusinessId))).getSingle();

      if (!mounted) return;
      _ownerController.text = business.ownerName ?? '';
      _managerController.text = business.managerName ?? '';
      _business = business;
      _businessController.text = business.name == 'My Business'
          ? ''
          : business.name;
      _category = _validDropdownValue(business.businessCategory, _categories);

      _country = _validDropdownValue(business.addressCountry, _countries);

      _province = business.addressProvince;
      _city = business.addressCity;
      _barangay = business.addressBarangay;
      _provinceController.text = business.addressProvince ?? '';
      _cityController.text = business.addressCity ?? '';
      _zipController.text = business.addressZipCode ?? '';
      _capitalController.text = business.startingCapital == 0
          ? ''
          : (business.startingCapital / 100).toStringAsFixed(2);
      _capitalAccountId = business.startingCapitalAccountId;
      if (_country == 'Philippines') {
        await _loadProvinces();
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Unable to load your profile. Please try again.';
      });
    }
  }

  Future<List<_PsgcPlace>> _fetchPlaces(String path) async {
    final response = await http.get(
      Uri.parse('https://psgc.gitlab.io/api/$path'),
    );
    if (response.statusCode != 200) {
      throw StateError('Location service returned ${response.statusCode}.');
    }
    final values = jsonDecode(response.body) as List<dynamic>;
    return values
        .map((value) => _PsgcPlace.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadProvinces() async {
    setState(() {
      _locationsLoading = true;
      _locationsError = null;
    });
    try {
      final provinces = await _fetchPlaces('provinces');
      if (!mounted) return;
      setState(() {
        _provinces = provinces;
        _locationsLoading = false;
      });
      final selected = provinces
          .where((item) => item.name == _province)
          .firstOrNull;
      if (selected != null) await _loadCities(selected);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationsLoading = false;
        _locationsError = 'Unable to load Philippine locations.';
      });
    }
  }

  Future<void> _loadCities(_PsgcPlace province) async {
    final cities = await _fetchPlaces(
      'provinces/${province.code}/cities-municipalities',
    );
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _barangays = [];
    });
    final selected = cities.where((item) => item.name == _city).firstOrNull;
    if (selected != null) await _loadBarangays(selected);
  }

  Future<void> _loadBarangays(_PsgcPlace city) async {
    final barangays = await _fetchPlaces(
      'cities-municipalities/${city.code}/barangays',
    );
    if (!mounted) return;
    setState(() => _barangays = barangays);
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _managerController.dispose();
    _businessController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _zipController.dispose();
    _capitalController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool skip}) async {
    final capitalText = _capitalController.text.replaceAll(',', '').trim();

    final capital = capitalText.isEmpty ? null : double.tryParse(capitalText);

    if (!skip && capitalText.isNotEmpty && (capital == null || capital < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid starting capital amount.')),
      );
      return;
    }

    if (!skip && capital != null && capital > 0 && _capitalAccountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select the account holding the starting capital.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = ref.read(databaseProvider);

      final business = _business;

      final capitalCents = capital == null || capital <= 0
          ? 0
          : (capital * 100).round();

      final province = _country == 'Philippines'
          ? _province
          : (_provinceController.text.trim().isEmpty
                ? null
                : _provinceController.text.trim());

      final city = _country == 'Philippines'
          ? _city
          : (_cityController.text.trim().isEmpty
                ? null
                : _cityController.text.trim());

      bool ledgerChanged = false;

      // ============================================================
      // STARTING CAPITAL
      // ============================================================
      // THE FIX: this used to only post when `business.startingCapital
      // == 0` — a one-shot gate. That meant: skip onboarding (capital
      // stays 0) → later enter capital via Profile → posts correctly
      // ONCE. But any edit after that (correcting the amount, or
      // entering it a second time for any reason) silently did
      // nothing, because startingCapital was no longer 0 — nothing
      // in Journal Entry, Cashflow, or Dashboard would ever reflect
      // the change, with no error shown to the user.
      //
      // Fixed by comparing against the PREVIOUS stored value and
      // posting only the difference (delta), so capital entered or
      // corrected at any point — not just the very first time —
      // always reaches the ledger.
      final previousCapitalCents = business?.startingCapital ?? 0;
      final capitalDelta = capitalCents - previousCapitalCents;

      if (!skip && business != null && capitalDelta > 0) {
        final categories =
            await (db.select(db.categories)..where(
                  (category) =>
                      category.businessId.equals(kCurrentBusinessId) &
                      category.name.equals('Additional Capital') &
                      category.txnType.equals('income'),
                ))
                .get();

        if (categories.isEmpty) {
          throw Exception(
            'The "Additional Capital" income category was not found.',
          );
        }

        if (_capitalAccountId == null) {
          throw Exception('No capital account was selected.');
        }

        await ref
            .read(transactionServiceProvider)
            .saveIncome(
              date: DateTime.now(),
              categoryId: categories.first.id,
              amount: capitalDelta,
              paymentAccountId: _capitalAccountId,
              description: previousCapitalCents == 0
                  ? 'Starting capital'
                  : 'Starting capital adjustment',
              markAsPending: false,
            );

        ledgerChanged = true;
      } else if (!skip && business != null && capitalDelta < 0) {
        // Lowering a previously-posted capital amount isn't posted
        // automatically — that would need a capital-withdrawal entry,
        // which is out of scope here. Surface this clearly instead of
        // silently ignoring it, so the profile and the ledger never
        // silently disagree.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Lowering starting capital here does not remove it from '
                'your records. Record a withdrawal transaction instead.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }

      // ============================================================
      // UPDATE BUSINESS PROFILE
      // ============================================================

      await (db.update(
        db.businesses,
      )..where((business) => business.id.equals(kCurrentBusinessId))).write(
        BusinessesCompanion(
          name: Value(
            skip || _businessController.text.trim().isEmpty
                ? 'My Business'
                : _businessController.text.trim(),
          ),
          ownerName: Value(
            skip || _ownerController.text.trim().isEmpty
                ? ''
                : _ownerController.text.trim(),
          ),
          managerName: Value(
            skip || _managerController.text.trim().isEmpty
                ? null
                : _managerController.text.trim(),
          ),
          businessCategory: Value(skip ? '' : _category ?? ''),
          addressCountry: Value(skip ? '' : _country ?? ''),
          addressProvince: Value(skip ? '' : province ?? ''),
          addressCity: Value(skip ? '' : city ?? ''),
          addressBarangay: Value(skip ? '' : _barangay ?? ''),
          addressZipCode: Value(
            skip || _zipController.text.trim().isEmpty
                ? null
                : _zipController.text.trim(),
          ),
          startingCapital: Value(skip ? 0 : capitalCents),
          startingCapitalAccountId: Value(skip ? null : _capitalAccountId),
        ),
      );

      // ============================================================
      // REFRESH ALL LEDGER-DEPENDENT PROVIDERS
      // ============================================================

      if (ledgerChanged) {
        ref.read(ledgerVersionProvider.notifier).state++;
      }

      // Refresh the business/profile provider as well.
      ref.invalidate(businessProfileProvider);

      if (!mounted) return;

      widget.onFinished();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save profile: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(paymentAccountsProvider);

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: FilledButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _loadError = null;
              });
              _load();
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Text(
            widget.subtitle,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (widget.showOwnerName) ...[
            TextField(
              controller: _ownerController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _managerController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Manager name (optional)',
              prefixIcon: Icon(Icons.manage_accounts_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _businessController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Business name',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _validDropdownValue(_category, _categories),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Business category',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: _categories
                .map(
                  (category) => DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _category = value;
                  }),
          ),
          const SizedBox(height: 24),
          Text(
            'Business address',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _validDropdownValue(_country, _countries),
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Country',
              prefixIcon: Icon(Icons.public_outlined),
            ),
            items: _countries
                .map(
                  (country) => DropdownMenuItem<String>(
                    value: country,
                    child: Text(country),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) async {
                    setState(() {
                      _country = value;
                      _province = null;
                      _city = null;
                      _barangay = null;
                      _provinces = [];
                      _cities = [];
                      _barangays = [];
                      _provinceController.clear();
                      _cityController.clear();
                    });

                    if (value == 'Philippines') {
                      await _loadProvinces();
                    }
                  },
          ),
          const SizedBox(height: 12),
          if (_country == 'Philippines') ...[
            if (_locationsLoading) const LinearProgressIndicator(),
            if (_locationsError != null)
              Text(_locationsError!, style: TextStyle(color: scheme.error)),
            DropdownButtonFormField<String>(
              initialValue: _provinces.any((item) => item.name == _province)
                  ? _province
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Province',
                prefixIcon: Icon(Icons.map_outlined),
              ),
              items: _provinces
                  .map(
                    (province) => DropdownMenuItem<String>(
                      value: province.name,
                      child: Text(province.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) async {
                      final place = _provinces
                          .where((item) => item.name == value)
                          .firstOrNull;
                      setState(() {
                        _province = value;
                        _city = null;
                        _barangay = null;
                      });
                      if (place != null) await _loadCities(place);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cities.any((item) => item.name == _city)
                  ? _city
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'City',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: _cities
                  .map(
                    (city) => DropdownMenuItem<String>(
                      value: city.name,
                      child: Text(city.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) async {
                      final place = _cities
                          .where((item) => item.name == value)
                          .firstOrNull;
                      setState(() {
                        _city = value;
                        _barangay = null;
                      });
                      if (place != null) await _loadBarangays(place);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _barangays.any((item) => item.name == _barangay)
                  ? _barangay
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Barangay',
                prefixIcon: Icon(Icons.holiday_village_outlined),
              ),
              items: _barangays
                  .map(
                    (barangay) => DropdownMenuItem<String>(
                      value: barangay.name,
                      child: Text(barangay.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _barangay = value),
            ),
          ] else ...[
            TextField(
              controller: _provinceController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Province / state',
                prefixIcon: Icon(Icons.map_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'City',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _zipController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'ZIP / postal code (optional)',
              prefixIcon: Icon(Icons.markunread_mailbox_outlined),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Starting capital',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capitalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Starting capital (optional)',
              prefixText: '₱ ',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 12),
          accountsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => Text(
              'Unable to load accounts.',
              style: TextStyle(color: scheme.error),
            ),
            data: (accounts) => DropdownButtonFormField<String>(
              initialValue:
                  accounts.any((account) => account.id == _capitalAccountId)
                  ? _capitalAccountId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Capital account',
                hintText: 'Cash, bank, or e-wallet',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              items: accounts
                  .map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _capitalAccountId = value),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(skip: false),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save profile'),
          ),
          if (widget.showSkip)
            TextButton(
              onPressed: _saving ? null : () => _save(skip: true),
              child: const Text('Skip for now'),
            ),
        ],
      ),
    );
  }
}
