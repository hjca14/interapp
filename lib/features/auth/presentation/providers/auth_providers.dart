import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/repositories/cognito_auth_repository.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (_) => CognitoAuthRepository(),
);

final authSessionProvider = StreamProvider<AuthSession>((ref) {
  return ref.watch(authRepositoryProvider).watchSession();
});
