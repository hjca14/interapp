import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.profileName, required this.onEditProfile});
  final String? profileName;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(profileName ?? 'Perfil não configurado'), subtitle: const Text('Perfil do InterBridge'),
            trailing: const Icon(Icons.chevron_right), onTap: onEditProfile,
          ),
          const Divider(),
          const ListTile(leading: Icon(Icons.info_outline), title: Text('Sobre o InterBridge'), subtitle: Text('Versão 1.0.0')),
        ],
      );
}
