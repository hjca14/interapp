import 'package:flutter/material.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';

class DeviceFormPage extends StatefulWidget {
  const DeviceFormPage({super.key, this.device});
  final InterBridgeDevice? device;

  @override
  State<DeviceFormPage> createState() => _DeviceFormPageState();
}

class _DeviceFormPageState extends State<DeviceFormPage> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.device?.name);
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      InterBridgeDevice(
        id: widget.device?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        createdAt: widget.device?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.device == null ? 'Adicionar InterBridge' : 'Editar dispositivo')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.router_outlined, size: 72),
              const SizedBox(height: 24),
              Text(widget.device == null ? 'Nomeie seu InterBridge' : 'Altere o nome do dispositivo', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('A conexão será configurada em uma próxima etapa.', textAlign: TextAlign.center),
              const SizedBox(height: 28),
              TextField(controller: _nameController, autofocus: true, textCapitalization: TextCapitalization.words, onSubmitted: (_) => _save(), decoration: const InputDecoration(labelText: 'Nome do dispositivo', hintText: 'Ex.: Casa')),
              const Spacer(),
              FilledButton(onPressed: _save, child: Text(widget.device == null ? 'Adicionar dispositivo' : 'Salvar alterações')),
            ]),
          ),
        ),
      );
}
