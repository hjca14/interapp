import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:interapp/features/devices/domain/entities/interbridge_device.dart';
import 'package:interapp/features/devices/presentation/pages/device_form_page.dart';
import 'package:interapp/features/devices/presentation/pages/devices_page.dart';
import 'package:interapp/features/devices/presentation/providers/devices_providers.dart';
import 'package:interapp/features/profile/presentation/pages/registration_page.dart';
import 'package:interapp/features/settings/presentation/pages/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final _profileRepository = ref.read(profileRepositoryProvider);
  late final _devicesRepository = ref.read(devicesRepositoryProvider);
  String? _profileName;
  int _selectedIndex = 0;
  bool _loading = true;
  bool _registrationPromptShown = false;
  List<InterBridgeDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
    unawaited(_loadDevices());
  }

  Future<void> _loadDevices() async {
    final devices = await _devicesRepository.getAll();
    if (!mounted) return;
    setState(() {
      _devices = devices;
    });
  }

  Future<void> _saveDevices() => _devicesRepository.saveAll(_devices);

  Future<void> _openDeviceForm({InterBridgeDevice? device}) async {
    final result = await Navigator.of(context).push<InterBridgeDevice>(MaterialPageRoute(builder: (_) => DeviceFormPage(device: device)));
    if (result == null) return;
    setState(() {
      if (device == null) { _devices.add(result); } else { _devices[_devices.indexOf(device)] = result; }
    });
    await _saveDevices();
    await _devicesRepository.setSelectedId(result.id);
  }

  Future<void> _deleteDevice(InterBridgeDevice device) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Remover dispositivo?'), content: Text('Isso remove “${device.name}” desta instalação.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remover'))]));
    if (confirmed != true) return;
    setState(() {
      _devices.remove(device);
    });
    await _saveDevices();
  }

  Future<void> _loadProfile() async {
    final name = await _profileRepository.getName();
    if (!mounted) return;
    setState(() {
      _profileName = name;
      _loading = false;
    });
  }

  Future<void> _openRegistration() async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegistrationPage(initialName: _profileName),
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _profileName = name);
  }

  void _openDevice(InterBridgeDevice device) {
    context.pushNamed(
      'device-detail',
      pathParameters: {'deviceId': device.id},
      extra: device,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_profileName == null && !_registrationPromptShown) {
      _registrationPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRegistration());
    }

    final pages = [
      DevicesPage(devices: _devices, onAdd: _openDeviceForm, onEdit: (device) => _openDeviceForm(device: device), onDelete: _deleteDevice, onOpen: _openDevice),
      SettingsPage(profileName: _profileName, onEditProfile: _openRegistration),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('InterBridge')),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.devices_other_outlined), selectedIcon: Icon(Icons.devices_other), label: 'Dispositivos'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
