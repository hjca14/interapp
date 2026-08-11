import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/domain/entities/device_claim.dart';
import 'package:interapp/features/pairing/domain/entities/provisioning_state.dart';
import 'package:interapp/features/pairing/presentation/controllers/pairing_controller.dart';
import 'package:interapp/features/pairing/presentation/providers/pairing_providers.dart';

/// Onboarding entry point for a new physical InterBridge.
///
/// There is no QR scanner or real BLE transport wired up yet: `device_id`/
/// `claim_code` are entered manually here as a stand-in for scanning the
/// product QR code, and starting the flow exercises the real
/// [ProvisioningState] machine against the active `ProvisioningRepository`
/// (today, `StubProvisioningRepository`), which honestly reports that BLE
/// provisioning isn't implemented rather than pretending to succeed.
class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  final _deviceIdController = TextEditingController();
  final _claimCodeController = TextEditingController();
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  late final _controller = PairingController(
    ref.read(provisioningRepositoryProvider),
  );

  @override
  void dispose() {
    _deviceIdController.dispose();
    _claimCodeController.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    final deviceId = _deviceIdController.text.trim();
    final claimCode = _claimCodeController.text.trim();
    if (deviceId.isEmpty || claimCode.isEmpty) return;
    _controller.startProvisioning(
      claim: DeviceClaim(deviceId: deviceId, claimCode: claimCode),
      wifiSsid: _wifiSsidController.text.trim(),
      wifiPassword: _wifiPasswordController.text,
    );
    // The password only ever lived in this controller and the call above;
    // clear it immediately instead of leaving it sitting in the field.
    _wifiPasswordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parear InterBridge')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Em breve você vai poder escanear o QR code impresso no seu '
                'InterBridge. Por enquanto, informe os dados manualmente para '
                'testar o fluxo de pareamento.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _deviceIdController,
                decoration: const InputDecoration(labelText: 'device_id'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _claimCodeController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'claim_code'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wifiSsidController,
                decoration: const InputDecoration(
                  labelText: 'Wi-Fi (nome da rede)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _wifiPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha do Wi-Fi'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _start,
                child: const Text('Iniciar pareamento'),
              ),
              const SizedBox(height: 24),
              _ProvisioningStateCard(state: _controller.state),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvisioningStateCard extends StatelessWidget {
  const _ProvisioningStateCard({required this.state});

  final ProvisioningState state;

  @override
  Widget build(BuildContext context) {
    if (state.phase == ProvisioningPhase.idle) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${state.phase.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (state.failureReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(state.failureReason!),
              ),
          ],
        ),
      ),
    );
  }
}
