import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../../core/network/stomp_client_manager.dart';
import '../../../../core/utils/logger.dart';

import '../../data/models/auth_models.dart';
import '../../data/repositories/auth_repository.dart';

// Auth state
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

const _noChange = Object();

class AuthState {
  final AuthStatus status;
  final UserResponse? user;
  final String? token;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.token,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    Object? user = _noChange,
    Object? token = _noChange,
    Object? errorMessage = _noChange,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: identical(user, _noChange) ? this.user : user as UserResponse?,
      token: identical(token, _noChange) ? this.token : token as String?,
      errorMessage: identical(errorMessage, _noChange)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final StompClientManager _stompManager;

  AuthNotifier(this._authRepository, this._stompManager)
    : super(const AuthState()) {
    _checkSavedAuth();
  }

  Future<void> _checkSavedAuth() async {
    final token = await _authRepository.getSavedToken();
    final savedUser = await _authRepository.getSavedUser();

    if (token != null && savedUser != null) {
      final user = await _authRepository.ensurePublicKeyPublished(savedUser);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        token: token,
      );
      await _stompManager.connect();
      _registerFcmToken();
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        log.i('Got FCM Token: $token');
        await _authRepository.updateFcmToken(token);
      }
    } catch (e) {
      log.e('FCM token registration failed: $e');
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    try {
      final response = await _authRepository.login(email, password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: response.user,
        token: response.accessToken,
      );
      await _stompManager.connect();
      _registerFcmToken();
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      state = AuthState(status: AuthStatus.error, errorMessage: message);
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: 'An unexpected error occurred',
      );
    }
  }

  Future<String?> register(
    String email,
    String password,
    String fullName,
  ) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    try {
      final message = await _authRepository.register(email, password, fullName);
      state = const AuthState(status: AuthStatus.unauthenticated);
      return message;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      state = AuthState(status: AuthStatus.error, errorMessage: message);
      return null;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.error,
        errorMessage: 'An unexpected error occurred',
      );
      return null;
    }
  }

  Future<void> logout() async {
    _stompManager.disconnect();
    await _authRepository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final data = e.response!.data as Map<String, dynamic>;
      return data['message'] as String? ??
          data['error'] as String? ??
          'Request failed';
    }
    if (e.response?.statusCode == 401) {
      return 'Invalid email/password or your session expired. Please sign in again.';
    }
    if (e.response?.statusCode == 403) {
      return 'Please verify your email before signing in. Check your inbox and spam folder.';
    }
    if (e.response?.statusCode == 409) return 'Email already registered';
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timed out';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection';
    }
    return 'Something went wrong. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authRepository = ref.read(authRepositoryProvider);
  final stompManager = ref.read(stompClientManagerProvider);
  return AuthNotifier(authRepository, stompManager);
});
