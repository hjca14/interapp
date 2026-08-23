import 'package:flutter/material.dart';

import '../domain/entities/api_device.dart';
import '../domain/entities/intercom_state.dart';

enum UserDeviceStatus { online, offline, unavailable }

class DeviceStatusPresentation {
  const DeviceStatusPresentation(this.status);

  factory DeviceStatusPresentation.from(ApiDeviceStatus? value) {
    if (value?.health == null ||
        value!.freshness == DeviceFreshness.unknown ||
        value.connectivity == DeviceConnectivity.unknown) {
      return const DeviceStatusPresentation(UserDeviceStatus.unavailable);
    }
    if (value.freshness == DeviceFreshness.fresh &&
        value.connectivity == DeviceConnectivity.recentlySeen) {
      return const DeviceStatusPresentation(UserDeviceStatus.online);
    }
    return const DeviceStatusPresentation(UserDeviceStatus.offline);
  }

  final UserDeviceStatus status;

  String get label => switch (status) {
    UserDeviceStatus.online => 'Online',
    UserDeviceStatus.offline => 'Offline',
    UserDeviceStatus.unavailable => 'Status indisponível',
  };

  IconData get icon => switch (status) {
    UserDeviceStatus.online => Icons.check_circle_outline,
    UserDeviceStatus.offline => Icons.cloud_off_outlined,
    UserDeviceStatus.unavailable => Icons.help_outline,
  };

  Color color(BuildContext context) => switch (status) {
    UserDeviceStatus.online => Colors.green.shade700,
    UserDeviceStatus.offline => Theme.of(context).colorScheme.error,
    UserDeviceStatus.unavailable => Theme.of(context).colorScheme.outline,
  };
}

String friendlyIntercomState(IntercomState state) {
  if (state == IntercomState.idle) return 'Em espera';
  if (state == IntercomState.ringing) return 'Chamando';
  if (state == IntercomState.offHook) return 'Fora do gancho';
  if (state == IntercomState.inCall) return 'Em chamada';
  if (state == IntercomState.error) return 'Com erro';
  return 'Não informado';
}

String friendlyFreshness(DeviceFreshness freshness) => switch (freshness) {
  DeviceFreshness.fresh => 'Comunicação recente',
  DeviceFreshness.stale => 'Comunicação antiga',
  DeviceFreshness.unknown => 'Não informada',
};

String formatLastCommunication(DateTime value, DateTime now) {
  final localValue = value.toLocal();
  final difference = now.toLocal().difference(localValue);
  if (difference < const Duration(minutes: 1)) return 'Agora';
  if (difference < const Duration(minutes: 2)) return 'Há 1 minuto';
  if (difference < const Duration(hours: 1)) {
    return 'Há ${difference.inMinutes} minutos';
  }
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(localValue.day)}/${twoDigits(localValue.month)}/${localValue.year} '
      'às ${twoDigits(localValue.hour)}:${twoDigits(localValue.minute)}';
}
