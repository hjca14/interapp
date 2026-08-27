import 'package:flutter/material.dart';

/// A titled card wrapping one settings group, shared by `DeviceSettingsPage`
/// and `NotificationPreferencesPage` so the two screens stay visually
/// consistent.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
