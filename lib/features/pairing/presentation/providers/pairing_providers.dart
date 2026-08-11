import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:interapp/features/pairing/data/repositories/stub_provisioning_repository.dart';
import 'package:interapp/features/pairing/domain/repositories/provisioning_repository.dart';

/// Typed as the abstract contract — the seam a real BLE-backed
/// implementation plugs into once one exists (see
/// `ProvisioningTransport`'s doc comment for the prerequisite).
final provisioningRepositoryProvider = Provider<ProvisioningRepository>(
  (_) => StubProvisioningRepository(),
);
