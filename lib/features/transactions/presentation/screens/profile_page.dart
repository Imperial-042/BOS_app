// lib/features/profile/presentation/screens/profile_page.dart
//
// ONE Profile destination for every member.
//   * Owner    -> personal + business details, business management
//                 (edit / switch / add / archive / delete), account security.
//   * Everyone else -> EmployeeProfileScreen (no business switching).

import 'dart:convert';

import 'package:bos_application/core/auth/auth_providers.dart';
import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/business/business_service.dart';
import 'package:bos_application/core/supabase/cloud_business_service.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/core/sync/sync_trigger_service.dart';
import 'package:bos_application/features/transactions/presentation/providers/product_catalog_providers.dart';
import 'package:bos_application/features/transactions/presentation/screens/employee_profile_screen.dart';
import 'package:bos_application/features/transactions/presentation/screens/products_page.dart';
import 'package:bos_application/features/transactions/presentation/widgets/profile_widgets.dart';
import 'package:bos_application/main.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/sync/sync_tracker.dart';
import '../../../transactions/presentation/screens/transaction_page.dart'
    show
        businessProfileProvider,
        kCurrentBusinessId,
        ledgerVersionProvider,
        paymentAccountsProvider;
import '../../../transactions/presentation/screens/cashflow_page.dart'
    show capitalAssetLiabilityServiceProvider, capitalBalanceProvider;

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

/// The single Profile page. Picks the owner or employee experience.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authenticatedUserIdProvider);
    final profile = ref.watch(businessProfileProvider);

    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) =>
          const Scaffold(body: Center(child: Text('Unable to load profile.'))),
      data: (business) => business.ownerUserId == uid
          ? _OwnerProfileView(business: business)
          : const EmployeeProfileScreen(),
    );
  }
}

class _OwnerProfileView extends ConsumerWidget {
  const _OwnerProfileView({required this.business});

  final BusinessesData business;

  String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final canManage = ref.watch(canProvider(BosPermission.businessManage));
    final canDelete = ref.watch(canProvider(BosPermission.businessDelete));

    final ownerName = _clean(business.ownerName);
    final email = _clean(user?.email);

    final classification = [
      BusinessTypes.labelOf(business.businessType),
      _clean(business.industry) ?? _clean(business.businessCategory) ?? '',
    ].where((s) => s.isNotEmpty).toList();

    final address = [
      business.addressBarangay,
      business.addressCity,
      business.addressProvince,
      business.addressCountry,
      business.addressZipCode,
    ].map(_clean).whereType<String>().join(', ');

    final about = <(IconData, String, String)>[
      if (ownerName != null) (Icons.person_outline_rounded, 'Owner', ownerName),
      if (email != null) (Icons.email_outlined, 'Account email', email),
    ];

    final details = <(IconData, String, String)>[
      if (_clean(business.managerName) != null)
        (
          Icons.manage_accounts_outlined,
          'Manager',
          _clean(business.managerName)!,
        ),
      if (_clean(business.legalName) != null)
        (Icons.gavel_outlined, 'Legal name', _clean(business.legalName)!),
      if (_clean(business.email) != null)
        (Icons.email_outlined, 'Business email', _clean(business.email)!),
      if (_clean(business.phone) != null)
        (Icons.phone_outlined, 'Business phone', _clean(business.phone)!),
      if (address.isNotEmpty) (Icons.location_on_outlined, 'Address', address),
    ];

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          ProfileHero(
            name: ownerName ?? business.name,
            subtitle: business.name,
            badges: ['Owner', ...classification],
          ),
          if (about.isNotEmpty) ...[
            const SizedBox(height: 24),
            ProfileSection(
              title: 'About you',
              children: [
                for (final r in about)
                  ProfileDetailRow(icon: r.$1, label: r.$2, value: r.$3),
              ],
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 24),
            ProfileSection(
              title: 'Business details',
              children: [
                for (final r in details)
                  ProfileDetailRow(icon: r.$1, label: r.$2, value: r.$3),
              ],
            ),
          ],
          const SizedBox(height: 24),
          ProfileSection(
            title: 'Business',
            children: [
              ProfileActionTile(
                icon: Icons.edit_outlined,
                label: 'Edit profile',
                subtitle: 'Update your name and business details',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (editorContext) => _BusinessProfileEditor(
                      title: 'Edit profile',
                      subtitle: 'Update your name and business details.',
                      onFinished: () {
                        if (editorContext.mounted) {
                          Navigator.of(editorContext).pop();
                        }
                      },
                    ),
                  ),
                ),
              ),
              ProfileActionTile(
                icon: Icons.swap_horiz_rounded,
                label: 'Switch business',
                subtitle: 'Work in a different business',
                onTap: () => _openBusinessSwitcher(context, ref),
              ),
              ProfileActionTile(
                icon: Icons.add_business_outlined,
                label: 'Add another business',
                subtitle: 'Create a new business to manage',
                onTap: () => _addBusiness(context, ref, business),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ProfileSection(
            title: 'Account',
            children: [
              ProfileActionTile(
                icon: Icons.lock_outline_rounded,
                label: 'Password & security',
                subtitle: 'Password, app lock and your signed-in devices',
                onTap: () => openAccountSecurity(context),
              ),
            ],
          ),
          if (canManage) ...[
            const SizedBox(height: 24),
            ProfileSection(
              title: 'Danger zone',
              danger: true,
              children: [
                ProfileActionTile(
                  icon: Icons.archive_outlined,
                  label: 'Archive this business',
                  subtitle:
                      'Hide it; records are kept and it can be reactivated',
                  destructive: true,
                  onTap: () => _archiveBusiness(context, ref, business),
                ),
                if (canDelete)
                  ProfileActionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete this business',
                    subtitle: 'Only possible while it has no financial records',
                    destructive: true,
                    onTap: () => _deleteBusiness(context, ref, business),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
// ============================================================================
// OWNER-ONLY BUSINESS ACTIONS
// ============================================================================

extension on _OwnerProfileView {
  Future<void> _openBusinessSwitcher(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = ref.read(businessServiceProvider);
    // Only businesses the signed-in user actually belongs to — never the
    // whole local table, so another tenant's rows can't leak into the list.
    final businesses = await service.listMyBusinesses(includeArchived: true);
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
                leading: Icon(
                  item.isActive
                      ? Icons.business_outlined
                      : Icons.archive_outlined,
                ),
                title: Text(item.name),
                subtitle: Text(
                  item.isActive
                      ? (BusinessTypes.labelOf(item.businessType).isNotEmpty
                            ? BusinessTypes.labelOf(item.businessType)
                            : (item.businessCategory ?? 'Business'))
                      : 'Archived',
                ),
                trailing: item.id == kCurrentBusinessId
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                selected: item.id == kCurrentBusinessId,
                enabled: item.isActive,

                onTap: !item.isActive
                    ? null
                    : () async {
                        if (item.id != kCurrentBusinessId) {
                          try {
                            await ref
                                .read(syncTriggerServiceProvider)
                                .switchToBusiness(item.id);
                          } catch (error) {
                            if (!sheetContext.mounted) return;

                            ScaffoldMessenger.of(
                              sheetContext,
                            ).showSnackBar(SnackBar(content: Text('$error')));
                            return;
                          }
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
}

Future<void> _addBusiness(
  BuildContext context,
  WidgetRef ref,
  BusinessesData currentBusiness,
) async {
  // Capture everything that depends on this (soon-to-be-disposed) page
  // BEFORE any await. Creating a business rebuilds the profile page.
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context);

  final input = await showDialog<_NewBusinessInput>(
    context: context,
    builder: (_) => const _NewBusinessDialog(),
  );
  if (input == null) return;

  try {
    final business = await container
        .read(businessServiceProvider)
        .createBusiness(
          name: input.name,
          businessType: input.businessType,
          industry: input.industry,
        );

    // Open the newly created business through the sync trigger service.
    if (!context.mounted) return;

    await container
        .read(syncTriggerServiceProvider)
        .openNewBusiness(business.id);

    // Refresh business-dependent providers.
    container.invalidate(selectedBusinessIdProvider);
    container.invalidate(productsProvider);
    container.invalidate(producibilityProvider);
    container.invalidate(productListingsProvider);

    await navigator.push(
      MaterialPageRoute(
        builder: (editorContext) => _BusinessProfileEditor(
          title: 'Set up ${input.name}',
          subtitle:
              'Complete the business details. Owner name is optional here.',
          showSkip: true,
          showOwnerName: false,
          // Pop the editor's OWN route, not the profile page's context.
          onFinished: () {
            if (editorContext.mounted) Navigator.of(editorContext).pop();
          },
        ),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('Unable to add business: $error')),
    );
  }
}

Future<void> _archiveBusiness(
  BuildContext context,
  WidgetRef ref,
  BusinessesData business,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: const Text('Archive this business?'),
      content: Text(
        '${business.name} will be hidden and no longer selectable, but '
        'all of its records are kept. You can reactivate it later.',
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final service = ref.read(businessServiceProvider);
    await service.archive(business.id);

    // If the archived business was current, the service already moved
    // isCurrent to another active business — adopt it locally too.
    final remaining = await service.listMyBusinesses();
    if (remaining.isNotEmpty) {
      final next = remaining.firstWhere(
        (b) => b.isCurrent,
        orElse: () => remaining.first,
      );

      if (next.id != kCurrentBusinessId) {
        await ref.read(syncTriggerServiceProvider).switchToBusiness(next.id);
      }
    }
    ref.invalidate(selectedBusinessIdProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business archived.')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

Future<void> _deleteBusiness(
  BuildContext context,
  WidgetRef ref,
  BusinessesData business,
) async {
  // Grab everything needed up front: deleting the selected business makes
  // this page rebuild, so ref/context must not be used after the delete.
  final service = ref.read(businessServiceProvider);
  final sync = ref.read(syncTriggerServiceProvider);
  final userId = ref.read(authenticatedUserIdProvider);
  final messenger = ScaffoldMessenger.of(context);

  final deletable = await service.canDelete(business.id);
  if (!context.mounted) return;

  if (!deletable) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'This business has financial records, so it can only be '
          'archived, never deleted.',
        ),
      ),
    );
    return;
  }

  // The app needs a business to land on afterwards.
  // final others = (await service.listMyBusinesses())
  //     .where((b) => b.id != business.id)
  //     .toList();
  // if (!context.mounted) return;
  // if (others.isEmpty) {
  //   messenger.showSnackBar(
  //     const SnackBar(
  //       content: Text(
  //         'This is your only business. Add another business first, '
  //         'then delete this one.',
  //       ),
  //     ),
  //   );
  //   return;
  // }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog.adaptive(
      title: const Text('Delete this business?'),
      content: Text(
        '${business.name} has no financial records and will be removed '
        'permanently, including from the cloud and all your devices. '
        'This cannot be undone.',
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    // Cloud first, then local (see BusinessService.delete).
    await service.delete(business.id);

    final moved = userId == null
        ? true
        : await sync.moveOffRemovedBusiness(userId, business.id);

    if (!moved) {
      // No business left: restart the startup flow, which shows the
      // "Create my business / I have an invite code" screen.
      restartStartupFlow?.call();
      return;
    }

    messenger.showSnackBar(const SnackBar(content: Text('Business deleted.')));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _NewBusinessInput {
  final String name;
  final String? businessType;
  final String? industry;

  const _NewBusinessInput({
    required this.name,
    this.businessType,
    this.industry,
  });
}

// Replace _NewBusinessDialog and _NewBusinessDialogState in profile_page.dart.
// _NewBusinessInput stays exactly as it is.

class _NewBusinessDialog extends StatefulWidget {
  const _NewBusinessDialog();

  @override
  State<_NewBusinessDialog> createState() => _NewBusinessDialogState();
}

class _NewBusinessDialogState extends State<_NewBusinessDialog> {
  // Icon + one-line description for each business type.
  static const _typeMeta = <String, (IconData, String)>{
    BusinessTypes.retailer: (
      Icons.storefront_rounded,
      'Sell directly to customers',
    ),
    BusinessTypes.wholesaler: (
      Icons.inventory_2_rounded,
      'Sell in bulk to other businesses',
    ),
    BusinessTypes.distributor: (
      Icons.local_shipping_rounded,
      'Move goods from makers to sellers',
    ),
    BusinessTypes.manufacturer: (
      Icons.precision_manufacturing_rounded,
      'Make or assemble products',
    ),
    BusinessTypes.serviceProvider: (
      Icons.handyman_rounded,
      'Offer skills, repairs or time',
    ),
  };

  // Must match _BusinessProfileEditorState._categories exactly, otherwise the
  // setup screen cannot pre-select the industry chosen here.
  static const _industries = <String, IconData>{
    'Retail': Icons.shopping_bag_rounded,
    'Food and beverage': Icons.restaurant_rounded,
    'Services': Icons.design_services_rounded,
    'Manufacturing': Icons.factory_rounded,
    'Agriculture': Icons.agriculture_rounded,
    'Construction': Icons.construction_rounded,
    'Online business': Icons.language_rounded,
    'Other': Icons.category_rounded,
  };

  final _nameController = TextEditingController();
  String? _businessType;
  String? _industry;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _name => _nameController.text.trim();
  bool get _canCreate => _name.isNotEmpty;

  void _submit() {
    if (!_canCreate) {
      setState(() => _submitted = true);
      return;
    }
    Navigator.pop(
      context,
      _NewBusinessInput(
        name: _name,
        businessType: _businessType,
        industry: _industry,
      ),
    );
  }

  InputDecoration _decoration(
    ColorScheme scheme, {
    required String label,
    required IconData icon,
    String? hint,
    String? errorText,
  }) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border(scheme.outlineVariant.withValues(alpha: 0.6)),
      enabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.6)),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.8),
    );
  }

  Widget _iconBadge(ColorScheme scheme, IconData icon, {double size = 34}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.55, color: scheme.onPrimaryContainer),
    );
  }

  Widget _sectionLabel(
    BuildContext context,
    String text, {
    bool optional = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(
              'optional',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Header
  // ------------------------------------------------------------------
  Widget _buildHeader(ColorScheme scheme) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 24, 12, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.add_business_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add another business',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Its own books, products and team.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        // Decorative soft circles
        Positioned(
          right: -30,
          top: -30,
          child: IgnorePointer(
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
        ),
        Positioned(
          right: 50,
          bottom: -40,
          child: IgnorePointer(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Dropdowns
  // ------------------------------------------------------------------
  Widget _buildTypeDropdown(ColorScheme scheme, ThemeData theme) {
    final entries = BusinessTypes.labels.entries.toList();

    return DropdownButtonFormField<String>(
      initialValue: _businessType,
      isExpanded: true,
      itemHeight: null,
      menuMaxHeight: 380,
      borderRadius: BorderRadius.circular(18),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      dropdownColor: scheme.surface,
      decoration: _decoration(
        scheme,
        label: 'Business type',
        hint: 'Select how you operate',
        icon: Icons.storefront_outlined,
      ),
      // Compact one-line version shown inside the field once selected.
      selectedItemBuilder: (context) => [
        for (final e in entries)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              e.value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
      // Rich two-line version shown in the open menu.
      items: [
        for (final e in entries)
          DropdownMenuItem<String>(
            value: e.key,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  _iconBadge(
                    scheme,
                    _typeMeta[e.key]?.$1 ?? Icons.business_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.value,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (_typeMeta[e.key] != null)
                          Text(
                            _typeMeta[e.key]!.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      onChanged: (v) => setState(() => _businessType = v),
    );
  }

  Widget _buildIndustryDropdown(ColorScheme scheme) {
    final entries = _industries.entries.toList();

    return DropdownButtonFormField<String>(
      initialValue: _industry,
      isExpanded: true,
      menuMaxHeight: 360,
      borderRadius: BorderRadius.circular(18),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      dropdownColor: scheme.surface,
      decoration: _decoration(
        scheme,
        label: 'Industry',
        hint: 'What do you do?',
        icon: Icons.category_outlined,
      ),
      selectedItemBuilder: (context) => [
        for (final e in entries)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              e.key,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
      items: [
        for (final e in entries)
          DropdownMenuItem<String>(
            value: e.key,
            child: Row(
              children: [
                _iconBadge(scheme, e.value, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.key,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) => setState(() => _industry = v),
    );
  }

  // ------------------------------------------------------------------
  // Live preview
  // ------------------------------------------------------------------
  Widget _buildPreview(ColorScheme scheme, ThemeData theme) {
    final hasName = _name.isNotEmpty;
    final typeLabel = _businessType == null
        ? null
        : BusinessTypes.labelOf(_businessType);

    final chips = <String>[?typeLabel, ?_industry];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: hasName ? 0.55 : 0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.primary.withValues(alpha: hasName ? 0.35 : 0.12),
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary,
                  scheme.primary.withValues(alpha: hasName ? 0.75 : 0.35),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: hasName
                ? Text(
                    _name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : const Icon(Icons.storefront_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasName ? _name : 'Your new business',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: hasName
                        ? scheme.onPrimaryContainer
                        : scheme.onPrimaryContainer.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 4),
                if (chips.isEmpty)
                  Text(
                    'Address, contact and capital come next.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(scheme),

              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(context, 'Business name', optional: false),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: _decoration(
                          scheme,
                          label: 'Name',
                          hint: 'e.g. Santos General Store',
                          icon: Icons.business_rounded,
                          errorText: _submitted && !_canCreate
                              ? 'Enter a business name'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _sectionLabel(context, 'Business type'),
                      _buildTypeDropdown(scheme, theme),
                      const SizedBox(height: 22),
                      _sectionLabel(context, 'Industry'),
                      _buildIndustryDropdown(scheme),
                      const SizedBox(height: 22),
                      _buildPreview(scheme, theme),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _canCreate ? _submit : null,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text(
                            'Create business',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
  final _legalNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cityController = TextEditingController();
  final _provinceController = TextEditingController();
  final _zipController = TextEditingController();
  final _capitalController = TextEditingController();
  String? _category;
  String? _businessType;
  String? _country;
  String? _province;
  String? _city;
  String? _barangay;
  String? _capitalAccountId;
  BusinessesData? _business;
  int _currentCapitalBalance =
      0; // NEW: live ledger capital, not the stale column
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
      await Future<void>.delayed(Duration.zero);
      ref.invalidate(capitalBalanceProvider);
      ref.invalidate(paymentAccountsProvider);
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
      _legalNameController.text = business.legalName ?? '';
      _emailController.text = business.email ?? '';
      _phoneController.text = business.phone ?? '';
      _descriptionController.text = business.description ?? '';
      _businessType = business.businessType?.isNotEmpty == true
          ? business.businessType
          : null;
      _category =
          _validDropdownValue(business.industry, _categories) ??
          _validDropdownValue(business.businessCategory, _categories);
      _country = _validDropdownValue(business.addressCountry, _countries);
      _province = business.addressProvince;
      _city = business.addressCity;
      _barangay = business.addressBarangay;
      _provinceController.text = business.addressProvince ?? '';
      _cityController.text = business.addressCity ?? '';
      _zipController.text = business.addressZipCode ?? '';

      // THE FIX: read the actual capital balance from the ledger — this
      // reflects the starting-capital entry AND any capital added later
      // via Journal Entry → Add Capital, not just this column. Falls back
      // to the stored column if the ledger read fails for any reason.
      int currentCapitalBalance;
      try {
        currentCapitalBalance = await ref.read(capitalBalanceProvider.future);
      } catch (_) {
        currentCapitalBalance = business.startingCapital;
      }
      if (!mounted) return;

      _currentCapitalBalance = currentCapitalBalance;
      _capitalController.text = currentCapitalBalance == 0
          ? ''
          : (currentCapitalBalance / 100).toStringAsFixed(2);
      _capitalAccountId = await _existingPaymentAccountId(
        db,
        business.startingCapitalAccountId,
      );

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
    if (_country != 'Philippines') {
      setState(() {
        _provinces = [];
        _cities = [];
        _barangays = [];
        _locationsLoading = false;
        _locationsError = null;
      });
      return;
    }

    setState(() {
      _locationsLoading = true;
      _locationsError = null;
    });

    try {
      final provinces = await _fetchPlaces('provinces');
      if (!mounted || _country != 'Philippines') return;

      setState(() {
        _provinces = provinces;
        _locationsLoading = false;
      });

      final selected = provinces
          .where((item) => item.name == _province)
          .firstOrNull;
      if (selected != null) {
        await _loadCities(selected);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationsLoading = false;
        _locationsError =
            'Unable to load Philippine locations. Please try again.';
      });
    }
  }

  Future<void> _loadCities(_PsgcPlace province) async {
    if (_country != 'Philippines' || province.name != _province) {
      return;
    }

    try {
      final cities = await _fetchPlaces(
        'provinces/${province.code}/cities-municipalities',
      );
      if (!mounted || _country != 'Philippines' || province.name != _province) {
        return;
      }

      setState(() {
        _cities = cities;
        _barangays = [];
      });

      final selected = cities.where((item) => item.name == _city).firstOrNull;
      if (selected != null) {
        await _loadBarangays(selected);
      }
    } catch (error) {
      if (!mounted || _country != 'Philippines') return;
      setState(() {
        _cities = [];
        _barangays = [];
        _locationsError = 'Unable to load Philippine cities. Please try again.';
      });
    }
  }

  Future<void> _loadBarangays(_PsgcPlace city) async {
    if (_country != 'Philippines' || city.name != _city) {
      return;
    }

    try {
      final barangays = await _fetchPlaces(
        'cities-municipalities/${city.code}/barangays',
      );
      if (!mounted || _country != 'Philippines' || city.name != _city) {
        return;
      }
      setState(() => _barangays = barangays);
    } catch (error) {
      if (!mounted || _country != 'Philippines') return;
      setState(() {
        _barangays = [];
        _locationsError =
            'Unable to load Philippine barangays. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _managerController.dispose();
    _businessController.dispose();
    _legalNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _zipController.dispose();
    _capitalController.dispose();
    super.dispose();
  }

  /// Returns [accountId] only when it is an active payment account of the
  /// current business; otherwise null so a stale id is never posted.
  Future<String?> _existingPaymentAccountId(
    AppDatabase db,
    String? accountId,
  ) async {
    if (accountId == null) return null;
    final account =
        await (db.select(db.accounts)..where(
              (a) =>
                  a.id.equals(accountId) &
                  a.businessId.equals(kCurrentBusinessId) &
                  a.isPaymentAccount.equals(true) &
                  a.isActive.equals(true),
            ))
            .getSingleOrNull();
    return account?.id;
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
      // was: final previousCapitalCents = business?.startingCapital ?? 0;
      final previousCapitalCents = _currentCapitalBalance;
      final capitalDelta = capitalCents - previousCapitalCents;

      if (!skip && business != null && capitalDelta > 0) {
        if (_capitalAccountId == null) {
          throw Exception('No capital account was selected.');
        }

        final capitalAccountId = await _existingPaymentAccountId(
          db,
          _capitalAccountId,
        );
        if (capitalAccountId == null) {
          ref.invalidate(paymentAccountsProvider);
          if (mounted) setState(() => _capitalAccountId = null);
          throw Exception(
            'The selected capital account is not available for this '
            'business. Choose the account again and save.',
          );
        }

        await ref
            .read(capitalAssetLiabilityServiceProvider)
            .recordCapital(
              businessId: kCurrentBusinessId,
              date: DateTime.now(),
              amount: capitalDelta,
              paymentAccountId: capitalAccountId,
              description: previousCapitalCents == 0
                  ? 'Starting capital'
                  : 'Starting capital adjustment',
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
          businessCategory: Value(
            skip ? '' : (_business?.businessCategory ?? ''),
          ),
          industry: Value(skip ? '' : (_category ?? '')),
          businessType: Value(skip ? null : _businessType),
          legalName: Value(
            skip || _legalNameController.text.trim().isEmpty
                ? null
                : _legalNameController.text.trim(),
          ),
          email: Value(
            skip || _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
          ),
          phone: Value(
            skip || _phoneController.text.trim().isEmpty
                ? null
                : _phoneController.text.trim(),
          ),
          description: Value(
            skip || _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
          ),
          updatedAt: Value(DateTime.now()),
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

      // Queue the profile so it reaches the cloud and every other device
      // signed in with this account.
      await SyncTracker.record(
        db,
        businessId: kCurrentBusinessId,
        entityType: 'businesses',
        entityId: kCurrentBusinessId,
        operation: SyncOp.update,
      );

      // Keep the signed-in account's name in step with "Your name", so the
      // dashboard greeting, drawer and avatars all show the same name.
      // Only the owner's own profile does this: "Add another business"
      // hides the name field, and an owner's name must never be written
      // onto someone else's account.
      final signedInId = ref.read(authenticatedUserIdProvider);
      final newOwnerName = _ownerController.text.trim();
      if (!skip &&
          widget.showOwnerName &&
          newOwnerName.isNotEmpty &&
          signedInId != null &&
          business?.ownerUserId == signedInId) {
        await ref
            .read(authServiceProvider)
            .updateDisplayName(userId: signedInId, displayName: newOwnerName);
        ref.invalidate(currentUserProvider);

        // Mirror the name to the cloud profile. Best-effort: a failure here
        // (offline, slow network) must never block saving the profile.
        if (SupabaseService.isAvailable) {
          try {
            await ref
                .read(cloudBusinessServiceProvider)
                .updateMyProfile(displayName: newOwnerName)
                .timeout(const Duration(seconds: 5));
          } on CloudBusinessException catch (e) {
            debugPrint('[profile] cloud name update skipped: ${e.message}');
          } catch (e) {
            debugPrint('[profile] cloud name update skipped: $e');
          }
        }
      }
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

  Widget _buildSaveBar() {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      elevation: 10,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  if (widget.showSkip) ...[
                    TextButton(
                      onPressed: _saving ? null : () => _save(skip: true),
                      child: const Text('Skip for now'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : () => _save(skip: false),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: const Text(
                          'Save profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      // Fixed above the keyboard and the gesture bar, so it is always
      // fully tappable no matter how far the form is scrolled.
      bottomNavigationBar: _buildSaveBar(),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _EditorHeader(title: widget.title, subtitle: widget.subtitle),
                const SizedBox(height: 16),

                // ---------------- About you ----------------
                _FormSection(
                  icon: Icons.person_rounded,
                  title: 'About you',
                  subtitle: 'Who runs this business',
                  children: [
                    if (widget.showOwnerName)
                      TextField(
                        controller: _ownerController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                    TextField(
                      controller: _managerController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Manager name (optional)',
                        prefixIcon: Icon(Icons.manage_accounts_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------------- Business ----------------
                _FormSection(
                  icon: Icons.storefront_rounded,
                  title: 'Business',
                  subtitle: 'Name, type and what you do',
                  children: [
                    TextField(
                      controller: _businessController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Business name',
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _businessType,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      decoration: const InputDecoration(
                        labelText: 'Business type',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: BusinessTypes.labels.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _businessType = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _validDropdownValue(_category, _categories),
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      decoration: const InputDecoration(
                        labelText: 'Industry',
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
                          : (value) => setState(() => _category = value),
                    ),
                    TextField(
                      controller: _legalNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Legal / registered name (optional)',
                        prefixIcon: Icon(Icons.gavel_outlined),
                      ),
                    ),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        alignLabelWithHint: true,
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------------- Contact ----------------
                _FormSection(
                  icon: Icons.call_rounded,
                  title: 'Contact',
                  subtitle: 'How customers can reach you',
                  children: [
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Business email (optional)',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Business phone (optional)',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------------- Address ----------------
                _FormSection(
                  icon: Icons.location_on_rounded,
                  title: 'Business address',
                  subtitle: 'Where you operate',
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('country-$_country'),
                      initialValue: _validDropdownValue(_country, _countries),
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
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
                    if (_country == 'Philippines') ...[
                      if (_locationsLoading)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: const LinearProgressIndicator(minHeight: 4),
                        ),
                      if (_locationsError != null)
                        Text(
                          _locationsError!,
                          style: TextStyle(color: scheme.error),
                        ),
                      DropdownButtonFormField<String>(
                        key: ValueKey('province-${_provinces.length}'),
                        initialValue:
                            _provinces.any((item) => item.name == _province)
                            ? _province
                            : null,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        menuMaxHeight: 360,
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
                      DropdownButtonFormField<String>(
                        key: ValueKey('city-$_province-${_cities.length}'),
                        initialValue: _cities.any((item) => item.name == _city)
                            ? _city
                            : null,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        menuMaxHeight: 360,
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
                      DropdownButtonFormField<String>(
                        key: ValueKey('brgy-$_city-${_barangays.length}'),
                        initialValue:
                            _barangays.any((item) => item.name == _barangay)
                            ? _barangay
                            : null,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        menuMaxHeight: 360,
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
                      TextField(
                        controller: _cityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'City',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                      ),
                    ],
                    TextField(
                      controller: _zipController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'ZIP / postal code (optional)',
                        prefixIcon: Icon(Icons.markunread_mailbox_outlined),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---------------- Starting capital ----------------
                _FormSection(
                  icon: Icons.savings_rounded,
                  title: 'Starting capital',
                  subtitle: 'Money you put in to begin',
                  children: [
                    TextField(
                      controller: _capitalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Starting capital (optional)',
                        prefixText: '₱ ',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                    accountsAsync.when(
                      loading: () => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: const LinearProgressIndicator(minHeight: 4),
                      ),
                      error: (error, stack) => Text(
                        'Unable to load accounts.',
                        style: TextStyle(color: scheme.error),
                      ),
                      data: (accounts) => DropdownButtonFormField<String>(
                        initialValue:
                            accounts.any(
                              (account) => account.id == _capitalAccountId,
                            )
                            ? _capitalAccountId
                            : null,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
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
                            : (value) =>
                                  setState(() => _capitalAccountId = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// FORM WIDGETS
// ============================================================================

/// Gradient intro card at the top of the editor.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.72)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded card with an icon header and evenly spaced fields.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    // Fields sit on a white card, so give them a visible fill and outline.
    final fieldTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: border(scheme.outlineVariant.withValues(alpha: 0.6)),
        enabledBorder: border(scheme.outlineVariant.withValues(alpha: 0.6)),
        focusedBorder: border(scheme.primary, 1.6),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
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
            ],
          ),
          const SizedBox(height: 16),
          Theme(
            data: fieldTheme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
