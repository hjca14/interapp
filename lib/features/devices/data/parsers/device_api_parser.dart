import '../../../../core/network/api_failure.dart';
import '../../../sharing/domain/entities/device_access.dart';
import '../../domain/entities/api_device.dart';
import '../../domain/entities/intercom_state.dart';

/// Pure parser for the three deployed device API response contracts.
class DeviceApiParser {
  const DeviceApiParser();

  /// Parses a list response while preserving the cursor as an opaque string.
  ApiDevicePage parseDevicePage(Map<String, dynamic> responseJson) {
    final reader = _JsonReader(responseJson);
    final itemValues = reader.requiredList('items');
    final summaries = itemValues
        .map(_requiredObject)
        .map(parseDeviceSummary)
        .toList(growable: false);
    return ApiDevicePage(
      items: summaries,
      // Cursors are intentionally accepted as opaque strings. They are never
      // decoded, interpreted, or persisted by app code.
      nextCursor: reader.nullableString('next_cursor'),
    );
  }

  /// Parses one membership summary from a list response.
  ApiDeviceSummary parseDeviceSummary(Map<String, dynamic> summaryJson) {
    final reader = _JsonReader(summaryJson);
    return ApiDeviceSummary(
      deviceId: reader.requiredString('device_id'),
      displayName: reader.nullableString('display_name'),
      role: _parseRole(reader.requiredString('role')),
      status: _parseMembershipStatus(reader.requiredString('status')),
    );
  }

  /// Parses the deployed device-detail contract.
  ApiDeviceDetail parseDeviceDetail(Map<String, dynamic> detailJson) {
    final reader = _JsonReader(detailJson);
    return ApiDeviceDetail(
      deviceId: reader.requiredString('device_id'),
      displayName: reader.nullableString('display_name'),
      hardwareVersion: reader.nullableString('hardware_version'),
      ownershipStatus: reader.requiredString('ownership_status'),
      provisioningStatus: reader.requiredString('provisioning_status'),
      role: _parseRole(reader.requiredString('role')),
    );
  }

  /// Parses status and keeps a missing `health` object as null.
  ApiDeviceStatus parseDeviceStatus(Map<String, dynamic> statusJson) {
    final reader = _JsonReader(statusJson);
    return ApiDeviceStatus(
      deviceId: reader.requiredString('device_id'),
      connectivity: _parseConnectivity(reader.requiredString('connectivity')),
      freshness: _parseFreshness(reader.requiredString('freshness')),
      health: _parseDeviceHealth(reader.value('health')),
    );
  }

  ApiDeviceHealth? _parseDeviceHealth(Object? healthValue) {
    if (healthValue == null) {
      return null;
    }
    final healthJson = _requiredObject(healthValue);
    final reader = _JsonReader(healthJson);
    return ApiDeviceHealth(
      intercomState: _parseIntercomState(
        reader.requiredString('intercom_state'),
      ),
      firmwareVersion: reader.requiredString('firmware_version'),
      lastSeenAt: _parseRequiredTimestamp(
        reader.requiredString('last_seen_at'),
      ),
    );
  }

  DateTime _parseRequiredTimestamp(String rawTimestamp) {
    final timestamp = DateTime.tryParse(rawTimestamp);
    if (timestamp == null) {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'Timestamp de status inválido.',
      );
    }
    return timestamp;
  }

  DeviceRole _parseRole(String rawRole) {
    return switch (rawRole) {
      'OWNER' => DeviceRole.owner,
      'ADMIN' => DeviceRole.admin,
      'MEMBER' => DeviceRole.member,
      _ => throw _unknownEnumFailure('papel de acesso'),
    };
  }

  MembershipStatus _parseMembershipStatus(String rawStatus) {
    return switch (rawStatus) {
      'ACTIVE' => MembershipStatus.active,
      _ => throw _unknownEnumFailure('status de membership'),
    };
  }

  DeviceConnectivity _parseConnectivity(String rawConnectivity) {
    return switch (rawConnectivity) {
      'RECENTLY_SEEN' => DeviceConnectivity.recentlySeen,
      'STALE' => DeviceConnectivity.stale,
      'UNKNOWN' => DeviceConnectivity.unknown,
      _ => throw _unknownEnumFailure('conectividade'),
    };
  }

  DeviceFreshness _parseFreshness(String rawFreshness) {
    return switch (rawFreshness) {
      'FRESH' => DeviceFreshness.fresh,
      'STALE' => DeviceFreshness.stale,
      'UNKNOWN' => DeviceFreshness.unknown,
      _ => throw _unknownEnumFailure('freshness'),
    };
  }

  IntercomState _parseIntercomState(String rawState) {
    final state = IntercomState.fromRaw(rawState);
    if (!state.isKnown) {
      throw _unknownEnumFailure('estado do interfone');
    }
    return state;
  }

  static Map<String, dynamic> _requiredObject(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'Resposta incompatível com o contrato.',
      );
    }
    return value;
  }

  static ApiFailure _unknownEnumFailure(String fieldDescription) {
    return ApiFailure(
      ApiFailureKind.invalidResponse,
      'Valor de $fieldDescription incompatível com o contrato.',
    );
  }
}

class _JsonReader {
  const _JsonReader(this.json);

  final Map<String, dynamic> json;

  Object? value(String key) => json[key];

  String requiredString(String key) {
    final fieldValue = json[key];
    if (fieldValue is! String || fieldValue.isEmpty) {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'Resposta incompatível com o contrato.',
      );
    }
    return fieldValue;
  }

  String? nullableString(String key) {
    final fieldValue = json[key];
    if (fieldValue == null) {
      return null;
    }
    if (fieldValue is! String) {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'Resposta incompatível com o contrato.',
      );
    }
    return fieldValue;
  }

  List<Object?> requiredList(String key) {
    final fieldValue = json[key];
    if (fieldValue is! List<Object?>) {
      throw const ApiFailure(
        ApiFailureKind.invalidResponse,
        'Resposta incompatível com o contrato.',
      );
    }
    return fieldValue;
  }
}
