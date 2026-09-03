import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/domain/entities/discovered_interbridge.dart';
import 'package:interapp/features/pairing/domain/entities/onboarding_state.dart';
import 'package:interapp/features/pairing/presentation/controllers/onboarding_coordinator.dart';
import 'package:interapp/features/pairing/presentation/providers/pairing_providers.dart';

/// Entry point for onboarding a new physical InterBridge.
///
/// Nearby BLE discovery is the primary path — no QR code needed for the
/// normal case. QR/manual `setup_code` entry are fallbacks reachable from
/// the scanning/error steps. All three converge into one
/// [OnboardingCoordinator]; this widget only renders whatever
/// [OnboardingState.phase] the coordinator is in — it holds no provisioning
/// logic itself.
///
/// AWS IoT/MQTT/X.509/Fleet Provisioning/Thing are never mentioned to the
/// user — see the copy in each step below.
class AddInterBridgePage extends ConsumerStatefulWidget {
  const AddInterBridgePage({super.key});

  @override
  ConsumerState<AddInterBridgePage> createState() => _AddInterBridgePageState();
}

class _AddInterBridgePageState extends ConsumerState<AddInterBridgePage> {
  late final _coordinator = OnboardingCoordinator(
    bleTransport: ref.read(bleOnboardingTransportProvider),
    claimRepository: ref.read(onboardingClaimRepositoryProvider),
    analytics: ref.read(onboardingAnalyticsProvider),
  );

  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();
  final _qrPayloadController = TextEditingController();
  final _manualCodeController = TextEditingController();
  String? _manualCodeError;

  @override
  void dispose() {
    _coordinator.dispose();
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _qrPayloadController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  Future<void> _submitWifi() async {
    final ssid = _wifiSsidController.text.trim();
    if (ssid.isEmpty) {
      return;
    }
    final password = _wifiPasswordController.text;
    await _coordinator.submitWifi(ssid, password);
    // The password only ever lived in this controller and the call above;
    // clear it immediately instead of leaving it sitting in the field.
    _wifiPasswordController.clear();
  }

  Future<void> _submitManualCode() async {
    final accepted = await _coordinator.submitManualCode(
      _manualCodeController.text,
    );
    setState(() {
      _manualCodeError = accepted
          ? null
          : 'Código inválido. Confira os 12 dígitos.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar InterBridge')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _coordinator,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: _buildStep(_coordinator.state),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(OnboardingState state) {
    switch (state.phase) {
      case OnboardingPhase.idle:
        return _IntroStep(onContinue: _coordinator.startBleOnboarding);
      case OnboardingPhase.checkingSetupMode:
        return const _ProgressStep(message: 'Verificando Bluetooth...');
      case OnboardingPhase.scanningBle:
        return _ScanningStep(
          onUseQr: _coordinator.startQrFallback,
          onUseManualCode: _coordinator.startManualFallback,
        );
      case OnboardingPhase.deviceFound:
        return _DeviceListStep(
          devices: state.discoveredDevices,
          onSelect: _coordinator.selectDevice,
          onUseQr: _coordinator.startQrFallback,
          onUseManualCode: _coordinator.startManualFallback,
        );
      case OnboardingPhase.confirmingDevice:
        return _ConfirmDeviceStep(
          device: state.selectedDevice,
          onConfirm: _coordinator.confirmDevice,
          onReject: _coordinator.rejectSelectedDevice,
        );
      case OnboardingPhase.connectingBle:
        return const _ProgressStep(message: 'Conectando ao InterBridge...');
      case OnboardingPhase.selectingWifi:
        return _WifiFormStep(
          ssidController: _wifiSsidController,
          passwordController: _wifiPasswordController,
          onSubmit: _submitWifi,
        );
      case OnboardingPhase.sendingWifi:
        return const _ProgressStep(
          message: 'Enviando configuração do Wi-Fi...',
        );
      case OnboardingPhase.startingClaim:
      case OnboardingPhase.claimActive:
        return const _ProgressStep(message: 'Registrando o dispositivo...');
      case OnboardingPhase.awsProvisioning:
        return const _ProgressStep(
          message: 'Conectando o InterBridge à internet...',
        );
      case OnboardingPhase.verifyingDevice:
        return const _ProgressStep(message: 'Finalizando configuração...');
      case OnboardingPhase.success:
        return _SuccessStep(onDone: () => Navigator.of(context).pop());
      case OnboardingPhase.error:
        return _ErrorStep(
          state: state,
          onRetry: _coordinator.retry,
          onCancel: () {
            _coordinator.cancel();
            Navigator.of(context).pop();
          },
          onUseQr: _coordinator.startQrFallback,
          onUseManualCode: _coordinator.startManualFallback,
        );
      case OnboardingPhase.scanningQr:
        return _QrFallbackStep(
          controller: _qrPayloadController,
          onSubmit: () =>
              _coordinator.submitQrPayload(_qrPayloadController.text),
          onBack: _coordinator.startBleOnboarding,
        );
      case OnboardingPhase.enteringSetupCode:
        return _ManualCodeStep(
          controller: _manualCodeController,
          errorText: _manualCodeError,
          onSubmit: _submitManualCode,
          onBack: _coordinator.startBleOnboarding,
        );
      case OnboardingPhase.resolvingSetupCode:
        return const _ProgressStep(message: 'Verificando código...');
    }
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.speaker_phone,
      title: 'Vamos adicionar seu InterBridge',
      body: const Text(
        '1. Ligue o seu InterBridge.\n'
        '2. Verifique se a luz está piscando azul rapidamente.\n'
        '3. Toque em Continuar.',
      ),
      primaryAction: FilledButton(
        onPressed: onContinue,
        child: const Text('Continuar'),
      ),
    );
  }
}

class _ScanningStep extends StatelessWidget {
  const _ScanningStep({required this.onUseQr, required this.onUseManualCode});
  final VoidCallback onUseQr;
  final VoidCallback onUseManualCode;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      loading: true,
      title: 'Procurando InterBridge próximo...',
      body: const Text('Mantenha o aplicativo aberto e o Bluetooth ligado.'),
      secondaryAction: _FallbackLinks(
        onUseQr: onUseQr,
        onUseManualCode: onUseManualCode,
      ),
    );
  }
}

class _DeviceListStep extends StatelessWidget {
  const _DeviceListStep({
    required this.devices,
    required this.onSelect,
    required this.onUseQr,
    required this.onUseManualCode,
  });

  final List<DiscoveredInterBridge> devices;
  final ValueChanged<DiscoveredInterBridge> onSelect;
  final VoidCallback onUseQr;
  final VoidCallback onUseManualCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'InterBridge encontrados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text('Ainda procurando outros dispositivos por perto...'),
        const SizedBox(height: 16),
        ...devices.map(
          (device) => Card(
            child: ListTile(
              leading: const Icon(Icons.speaker_phone),
              title: Text(device.friendlyName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onSelect(device),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _FallbackLinks(onUseQr: onUseQr, onUseManualCode: onUseManualCode),
      ],
    );
  }
}

class _ConfirmDeviceStep extends StatelessWidget {
  const _ConfirmDeviceStep({
    required this.device,
    required this.onConfirm,
    required this.onReject,
  });

  final DiscoveredInterBridge? device;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.bluetooth_searching,
      title: 'Encontramos um InterBridge próximo.',
      body: Text(
        '${device?.friendlyName ?? ''}\n\nA luz dele está piscando azul rapidamente?',
      ),
      primaryAction: FilledButton(
        onPressed: onConfirm,
        child: const Text('Sim, continuar'),
      ),
      secondaryAction: TextButton(
        onPressed: onReject,
        child: const Text('Não é este'),
      ),
    );
  }
}

class _WifiFormStep extends StatelessWidget {
  const _WifiFormStep({
    required this.ssidController,
    required this.passwordController,
    required this.onSubmit,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Conectar à internet',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: ssidController,
          decoration: const InputDecoration(labelText: 'Nome da rede Wi-Fi'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(labelText: 'Senha do Wi-Fi'),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onSubmit, child: const Text('Continuar')),
      ],
    );
  }
}

class _SuccessStep extends StatelessWidget {
  const _SuccessStep({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.check_circle,
      title: 'InterBridge configurado com sucesso.',
      body: const Text('Seu InterBridge já aparece na lista de dispositivos.'),
      primaryAction: FilledButton(
        onPressed: onDone,
        child: const Text('Concluir'),
      ),
    );
  }
}

class _ErrorStep extends StatelessWidget {
  const _ErrorStep({
    required this.state,
    required this.onRetry,
    required this.onCancel,
    required this.onUseQr,
    required this.onUseManualCode,
  });

  final OnboardingState state;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onUseQr;
  final VoidCallback onUseManualCode;

  /// Fallbacks only make sense when the failure is about *finding* the
  /// device — not once a claim/Wi-Fi attempt is already underway for a
  /// specific one.
  bool get _offersFallback =>
      state.failureKind == OnboardingFailureKind.bleUnavailable ||
      state.failureKind == OnboardingFailureKind.scanTimeout ||
      state.failureKind == OnboardingFailureKind.connectionFailed ||
      state.failureKind == OnboardingFailureKind.permanentIdentityUnavailable;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      icon: Icons.error_outline,
      title: 'Não foi possível continuar.',
      body: Text(state.failureReason ?? 'Tente novamente.'),
      primaryAction: FilledButton(
        onPressed: onRetry,
        child: const Text('Tentar novamente'),
      ),
      secondaryAction: Column(
        children: [
          if (_offersFallback)
            _FallbackLinks(onUseQr: onUseQr, onUseManualCode: onUseManualCode),
          TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}

class _QrFallbackStep extends StatelessWidget {
  const _QrFallbackStep({
    required this.controller,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Escanear código QR',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'A leitura por câmera ainda não está disponível neste app — cole '
          'abaixo o conteúdo do código QR para testar o fluxo.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Conteúdo do QR'),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onSubmit, child: const Text('Continuar')),
        TextButton(onPressed: onBack, child: const Text('Voltar')),
      ],
    );
  }
}

class _ManualCodeStep extends StatelessWidget {
  const _ManualCodeStep({
    required this.controller,
    required this.errorText,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Digitar código manualmente',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: 'Código de 12 dígitos',
            errorText: errorText,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onSubmit, child: const Text('Continuar')),
        TextButton(onPressed: onBack, child: const Text('Voltar')),
      ],
    );
  }
}

class _FallbackLinks extends StatelessWidget {
  const _FallbackLinks({required this.onUseQr, required this.onUseManualCode});
  final VoidCallback onUseQr;
  final VoidCallback onUseManualCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Text('Não encontrou seu InterBridge?'),
        TextButton(onPressed: onUseQr, child: const Text('Escanear código QR')),
        TextButton(
          onPressed: onUseManualCode,
          child: const Text('Digitar código manualmente'),
        ),
      ],
    );
  }
}

/// Shared layout for the simple "icon + title + body + actions" steps.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    this.icon,
    this.loading = false,
    required this.title,
    required this.body,
    this.primaryAction,
    this.secondaryAction,
  });

  final IconData? icon;
  final bool loading;
  final String title;
  final Widget body;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          const CircularProgressIndicator()
        else if (icon != null)
          Icon(icon, size: 64),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        DefaultTextStyle.merge(textAlign: TextAlign.center, child: body),
        const SizedBox(height: 32),
        ?primaryAction,
        if (secondaryAction != null) ...[
          const SizedBox(height: 8),
          secondaryAction!,
        ],
      ],
    );
  }
}

/// Simple "message + spinner" step, reused for every waiting phase.
class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      loading: true,
      title: message,
      body: const SizedBox.shrink(),
    );
  }
}
