import 'package:flutter/material.dart';

/// The "Ajustes" tab: profile entry (opens `RegistrationPage` again for
/// editing via [onEditProfile]) and a static app-info row. Everything else
/// that will eventually live here (device management, notifications, etc.)
/// isn't built yet — keep it that way rather than adding placeholder rows.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.profileName,
    required this.onEditProfile,
    required this.onSecurity,
    required this.onLogout,
  });
  final String? profileName;
  final VoidCallback onEditProfile;
  final VoidCallback onSecurity;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 12),
    children: [
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(profileName ?? 'Perfil não configurado'),
        subtitle: const Text('Perfil do InterBridge'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onEditProfile,
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.security_outlined),
        title: const Text('Segurança'),
        subtitle: const Text('Biometria e bloqueio do aplicativo'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onSecurity,
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sair'),
        subtitle: const Text('Encerrar a sessão neste dispositivo'),
        onTap: onLogout,
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Sobre o InterBridge'),
        subtitle: Text('Versão 1.0.0'),
      ),
    ],
  );
}
