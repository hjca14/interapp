import 'package:flutter/material.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';

/// Lists the user's registered InterBridges, or an empty-state prompt if
/// there are none.
///
/// Purely presentational — it owns no state and knows nothing about
/// persistence. The list and every action ([onAdd], [onEdit], [onDelete],
/// [onOpen]) are handed in by `HomePage`, which is the one that talks to
/// `LocalDevicesRepository`.
class DevicesPage extends StatelessWidget {
  const DevicesPage({
    super.key,
    required this.devices,
    required this.onAdd,
    required this.onDelete,
    required this.onEdit,
    required this.onOpen,
  });

  final List<InterBridgeDevice> devices;
  final VoidCallback onAdd;
  final ValueChanged<InterBridgeDevice> onDelete;
  final ValueChanged<InterBridgeDevice> onEdit;
  final ValueChanged<InterBridgeDevice> onOpen;

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar'),
        ),
        body: devices.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speaker_phone, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhum InterBridge adicionado',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Adicione um dispositivo para começar.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar dispositivo'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onOpen(device),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 27,
                              child: const Icon(Icons.speaker_phone),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device.name,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Aguardando conexão'),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') onEdit(device);
                                if (action == 'delete') onDelete(device);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Editar')),
                                PopupMenuItem(value: 'delete', child: Text('Remover')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      );
}
