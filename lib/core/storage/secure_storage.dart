import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveToken(String token) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: AppConstants.tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
  }

  Future<void> saveUser(String userJson) async {
    await _storage.write(key: AppConstants.userKey, value: userJson);
  }

  Future<String?> getUser() async {
    return _storage.read(key: AppConstants.userKey);
  }

  Future<void> deleteUser() async {
    await _storage.delete(key: AppConstants.userKey);
  }

  Future<void> clearAuth() async {
    await deleteToken();
    await deleteUser();
  }

  Future<void> saveE2eePrivateKey(String userId, String privateKey) async {
    await _storage.write(key: 'e2ee_private_key_$userId', value: privateKey);
  }

  Future<String?> getE2eePrivateKey(String userId) async {
    return _storage.read(key: 'e2ee_private_key_$userId');
  }

  Future<void> saveE2eePublicKey(String userId, String publicKey) async {
    await _storage.write(key: 'e2ee_public_key_$userId', value: publicKey);
  }

  Future<String?> getE2eePublicKey(String userId) async {
    return _storage.read(key: 'e2ee_public_key_$userId');
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
