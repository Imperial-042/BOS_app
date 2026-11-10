import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/database/database_provider.dart';
import 'package:bos_application/core/supabase/supabase_service.dart';
import 'package:bos_application/features/transactions/presentation/screens/startup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/customer_commerce_service.dart';
import 'customer_home_screen.dart';

final customerAccountAvailableProvider = StateProvider<bool>((ref) => false);
final selectedAccountModeProvider = StateProvider<String?>((ref) => null);

class CustomerModeGate extends ConsumerStatefulWidget {
  const CustomerModeGate({required this.businessBuilder, super.key});

  final WidgetBuilder businessBuilder;

  @override
  ConsumerState<CustomerModeGate> createState() => _CustomerModeGateState();
}

class _CustomerModeGateState extends ConsumerState<CustomerModeGate> {
  late Future<({bool hasBusiness, bool hasCustomer})> _modes;

  @override
  void initState() {
    super.initState();
    ref.read(selectedAccountModeProvider.notifier).state = null;
    _modes = _loadModes();
  }

  Future<({bool hasBusiness, bool hasCustomer})> _loadModes() async {
    final userId = ref.read(authenticatedUserIdProvider);
    if (userId == null) return (hasBusiness: false, hasCustomer: false);
    final service = CustomerCommerceService(
      ref.read(databaseProvider),
      client: ref.read(supabaseAvailableProvider)
          ? ref.read(supabaseClientProvider)
          : null,
    );
    final hasCustomer = await service.hasCustomerProfile(userId);
    final hasBusiness = await service.hasBusinessMembership(userId);
    ref.read(customerAccountAvailableProvider.notifier).state = hasCustomer;
    return (hasBusiness: hasBusiness, hasCustomer: hasCustomer);
  }

  void _retry() => setState(() {
    _modes = _loadModes();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool hasBusiness, bool hasCustomer})>(
      future: _modes,
      builder: (context, snapshot) {
if (snapshot.hasError) {
  return StartupPanel(
    icon: Icons.wifi_off_rounded,
    tone: Theme.of(context).colorScheme.error,
    title: 'Couldn’t check your account',
    message: 'Connect to the internet and try again.',
    children: [
      FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
        onPressed: _retry,
        child: const Text('Try again'),
      ),
    ],
  );
}
if (!snapshot.hasData) {
  return const StartupLoadingScreen();
}

        final modes = snapshot.data!;
        final selectedMode = ref.watch(selectedAccountModeProvider);
        if (modes.hasCustomer && !modes.hasBusiness) {
          return const CustomerHomeScreen();
        }
        if (modes.hasCustomer && modes.hasBusiness) {
          if (selectedMode == 'customer') {
            return CustomerHomeScreen(
              onSwitchToBusiness: () =>
                  ref.read(selectedAccountModeProvider.notifier).state =
                      'business',
            );
          }
          if (selectedMode == 'business') {
            return widget.businessBuilder(context);
          }
          return _AccountModeChooser(
            onSelect: (mode) =>
                ref.read(selectedAccountModeProvider.notifier).state = mode,
          );
        }
        return widget.businessBuilder(context);
      },
    );
  }
}

class _AccountModeChooser extends StatelessWidget {
  const _AccountModeChooser({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose account mode')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How would you like to use BOS?',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => onSelect('customer'),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text('Customer mode'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => onSelect('business'),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Business mode'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
