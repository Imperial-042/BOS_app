// lib/features/settings/presentation/screens/settings_page.dart
//
// Extracted from main.dart: the Settings list screen.

import 'package:bos_application/features/transactions/presentation/screens/profile_page.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Profile & businesses'),
            subtitle: const Text('Manage your profile and switch businesses'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme preferences'),
            trailing: Icon(Icons.chevron_right_rounded),
          ),
          ListTile(
            leading: Icon(Icons.currency_exchange_rounded),
            title: Text('Currency'),
            subtitle: Text('Philippine Peso (PHP)'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('About BOS'),
            subtitle: Text('Business Operating System'),
          ),
        ],
      ),
    );
  }
}
