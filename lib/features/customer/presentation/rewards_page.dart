import 'package:bos_application/core/auth/authorization_providers.dart';
import 'package:bos_application/core/auth/bos_access.dart';
import 'package:bos_application/core/database/app_database.dart';
import 'package:bos_application/features/customer/domain/customer_commerce_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RewardsPage extends ConsumerStatefulWidget {
  const RewardsPage({super.key});

  @override
  ConsumerState<RewardsPage> createState() => _RewardsPageState();
}

class _RewardsPageState extends ConsumerState<RewardsPage> {
  Future<CustomerStorefront?>? _storefront;
  final _points = TextEditingController();

  @override
  void initState() {
    super.initState();
    final businessId = ref.read(selectedBusinessIdProvider);
    _storefront = ref
        .read(customerCommerceServiceProvider)
        .loadManagedStorefront(businessId)
        .then((value) {
          _points.text = '${value.storefront?.pointsPerCurrencyUnit ?? 0}';
          return value.storefront;
        });
  }

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authorizationServiceProvider);
    if (!auth.isOwner && !auth.can(BosPermission.businessSettings)) {
      return const Scaffold(
        body: Center(
          child: Text('Only owners and administrators can manage rewards.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rewards')),
      body: FutureBuilder<CustomerStorefront?>(
        future: _storefront,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Customer rewards',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Customers earn points when completed orders are credited. '
                'Use the Online store page to publish the final reward settings.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _points,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Points per currency unit',
                  prefixIcon: Icon(Icons.stars_outlined),
                  helperText:
                      'Edit this value from Online store > Loyalty points.',
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    snapshot.data!.pointsPerCurrencyUnit == 0
                        ? 'Rewards are disabled'
                        : 'Rewards are active',
                  ),
                  subtitle: Text(
                    snapshot.data!.pointsPerCurrencyUnit == 0
                        ? 'Set a value above zero to let customers earn points.'
                        : 'Customers earn points after completed orders.',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
