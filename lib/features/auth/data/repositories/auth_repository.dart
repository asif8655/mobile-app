import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
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

  AuthRepository(this._dio, this._secureStorage);

  Future<AuthResponse> login(String email, String password) async {
    final response = await _dio.post(
      ApiConstants.login,
      data: {'email': email, 'password': password},
    );
    final authResponse = AuthResponse.fromJson(response.data);
    await _secureStorage.saveToken(authResponse.accessToken);
    await _secureStorage.saveUser(authResponse.user.toJsonString());
    log.i('Logged in as ${authResponse.user.email}');
    return authResponse;
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

  Future<String?> getSavedToken() async {
    return _secureStorage.getToken();
  }

  Future<void> logout() async {
    await _secureStorage.clearAll();
    log.i('Logged out, cleared storage');
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
