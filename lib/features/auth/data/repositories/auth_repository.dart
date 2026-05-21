import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../../core/utils/e2ee_service.dart';
import '../../../../core/utils/logger.dart';
import '../models/auth_models.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dioClient = ref.read(dioClientProvider);
  final secureStorage = ref.read(secureStorageProvider);
  return AuthRepository(dioClient.dio, secureStorage);
});

class AuthRepository {
  final Dio _dio;
  final SecureStorageService _secureStorage;
  late final E2eeService _e2eeService = E2eeService(_secureStorage);

  AuthRepository(this._dio, this._secureStorage);

  Future<AuthResponse> login(String email, String password) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: {'email': email, 'password': password},
    );
    final authResponse = AuthResponse.fromJson(response.data);
    await _secureStorage.saveToken(authResponse.accessToken);
    final userWithKey = await ensurePublicKeyPublished(authResponse.user, password);
    log.i('Logged in as ${userWithKey.email}');
    return AuthResponse(
      accessToken: authResponse.accessToken,
      tokenType: authResponse.tokenType,
      user: userWithKey,
    );
  }

  Future<String> register(String email, String password, String fullName) async {
    final response = await _dio.post(
      ApiConstants.register,
      data: {
        'email': email,
        'password': password,
        'fullName': fullName,
      },
    );
    return (response.data as Map<String, dynamic>)['message'] as String;
  }

  Future<UserResponse?> getSavedUser() async {
    final userJson = await _secureStorage.getUser();
    if (userJson == null) return null;
    return UserResponse.fromJsonString(userJson);
  }

  Future<UserResponse> ensurePublicKeyPublished(UserResponse user, [String? password]) async {
    final E2eeIdentity identity;
    if (password != null) {
      identity = await _e2eeService.initializeIdentity(
        userId: user.id,
        email: user.email,
        password: password,
        serverUser: user,
      );
    } else {
      identity = await _e2eeService.ensureIdentity(user.id);
    }

    var userWithKey = user.copyWith(
      publicKey: identity.publicKey,
      publicKeyAlgorithm: E2eeService.publicKeyAlgorithm,
      encryptedPrivateKey: user.encryptedPrivateKey ?? '',
    );

    if (user.publicKey != identity.publicKey ||
        user.publicKeyAlgorithm != E2eeService.publicKeyAlgorithm ||
        (password != null && (user.encryptedPrivateKey == null || user.encryptedPrivateKey!.isEmpty))) {
      
      String? encryptedPrivateKey;
      if (password != null) {
        final passwordKey = await _e2eeService.derivePasswordKey(password, user.email);
        encryptedPrivateKey = await _e2eeService.encryptPrivateKey(identity.keyPair, passwordKey);
      }

      final Map<String, dynamic> requestData = {
        'publicKey': identity.publicKey,
        'publicKeyAlgorithm': E2eeService.publicKeyAlgorithm,
      };
      if (encryptedPrivateKey != null) {
        requestData['encryptedPrivateKey'] = encryptedPrivateKey;
      }

      await _dio.put(
        '/users/profile/public-key',
        data: requestData,
      );
      if (encryptedPrivateKey != null) {
        userWithKey = userWithKey.copyWith(
          encryptedPrivateKey: encryptedPrivateKey,
        );
      }
    }

    await _secureStorage.saveUser(userWithKey.toJsonString());
    return userWithKey;
  }

  Future<String?> getSavedToken() async {
    return _secureStorage.getToken();
  }

  Future<void> logout() async {
    await _secureStorage.clearAuth();
    log.i('Logged out, cleared auth storage');
  }

  Future<void> updateFcmToken(String token) async {
    try {
      await _dio.put(
        '/users/profile/fcm-token', // Base URL handles /api automatically
        data: {'token': token},
      );
      log.i('FCM token sent to backend');
    } catch (e) {
      log.e('Failed to send FCM token: $e');
    }
  }
}
