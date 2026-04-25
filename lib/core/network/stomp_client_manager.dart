import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../constants/api_constants.dart';
import '../storage/secure_storage.dart';
import '../utils/logger.dart';

typedef StompMessageCallback = void Function(Map<String, dynamic> body);

final stompClientManagerProvider = Provider<StompClientManager>((ref) {
  final secureStorage = ref.read(secureStorageProvider);
  return StompClientManager(secureStorage);
});

class StompClientManager {
  final SecureStorageService _secureStorage;
  StompClient? _client;
  bool _isConnected = false;

  final Map<String, StompMessageCallback> _subscriptionCallbacks = {};
  final List<StompUnsubscribe> _activeSubscriptions = [];

  /// Messages queued while STOMP is not yet connected.
  final List<_QueuedMessage> _sendQueue = [];

  bool get isConnected => _isConnected;

  StompClientManager(this._secureStorage);

  Future<void> connect() async {
    if (_isConnected && _client != null) return;

    final token = await _secureStorage.getToken();
    if (token == null) {
      log.w('Cannot connect STOMP — no JWT token');
      return;
    }

    final wsUrl = '${ApiConstants.wsNativeUrl}?token=$token';
    log.i('Connecting STOMP to $wsUrl');

    _client = StompClient(
      config: StompConfig(
        url: wsUrl,
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
        onConnect: _onConnect,
        onDisconnect: _onDisconnect,
        onWebSocketError: (error) {
          log.e('STOMP WebSocket error: $error');
          _isConnected = false;
        },
        onStompError: (frame) {
          log.e('STOMP error: ${frame.body}');
          _isConnected = false;
        },
        reconnectDelay: const Duration(seconds: 5),
      ),
    );

    _client!.activate();
  }

  void _onConnect(StompFrame frame) {
    log.i('STOMP connected');
    _isConnected = true;

    // Re-subscribe to all registered callbacks
    for (final entry in _subscriptionCallbacks.entries) {
      _subscribe(entry.key, entry.value);
    }

    // Drain any messages that were queued while disconnected
    _drainSendQueue();
  }

  void _onDisconnect(StompFrame frame) {
    log.w('STOMP disconnected');
    _isConnected = false;
    _activeSubscriptions.clear();
  }

  void registerSubscription(String destination, StompMessageCallback callback) {
    _subscriptionCallbacks[destination] = callback;
    if (_isConnected && _client != null) {
      _subscribe(destination, callback);
    }
  }

  void _subscribe(String destination, StompMessageCallback callback) {
    final unsub = _client!.subscribe(
      destination: destination,
      callback: (frame) {
        if (frame.body != null) {
          try {
            final body = jsonDecode(frame.body!) as Map<String, dynamic>;
            callback(body);
          } catch (e) {
            log.e('Failed to parse STOMP message on $destination: $e');
          }
        }
      },
    );
    _activeSubscriptions.add(unsub);
  }

  /// Send immediately if connected. Returns false when the socket is not ready.
  bool send(String destination, Map<String, dynamic> body) {
    if (!_isConnected || _client == null) {
      log.w('Cannot send — STOMP not connected (destination: $destination)');
      return false;
    }
    _client!.send(destination: destination, body: jsonEncode(body));
    return true;
  }

  /// Send if connected; otherwise enqueue and send as soon as STOMP connects.
  /// Use this for critical messages (e.g. call-accept) that must not be lost.
  void sendWhenReady(String destination, Map<String, dynamic> body) {
    if (_isConnected && _client != null) {
      _client!.send(destination: destination, body: jsonEncode(body));
      log.d('STOMP sent immediately to $destination');
    } else {
      log.i('STOMP not connected — queuing message to $destination');
      _sendQueue.add(_QueuedMessage(destination, body));
    }
  }

  void _drainSendQueue() {
    if (_sendQueue.isEmpty) return;
    log.i('Draining ${_sendQueue.length} queued STOMP message(s)');
    for (final msg in _sendQueue) {
      try {
        _client!.send(destination: msg.destination, body: jsonEncode(msg.body));
        log.d('Queued message sent to ${msg.destination}');
      } catch (e) {
        log.e('Failed to send queued message to ${msg.destination}: $e');
      }
    }
    _sendQueue.clear();
  }

  void disconnect() {
    for (final unsub in _activeSubscriptions) {
      unsub(unsubscribeHeaders: {});
    }
    _activeSubscriptions.clear();
    _subscriptionCallbacks.clear();
    _sendQueue.clear();
    _client?.deactivate();
    _isConnected = false;
    _client = null;
    log.i('STOMP disconnected and cleaned up');
  }
}

class _QueuedMessage {
  final String destination;
  final Map<String, dynamic> body;
  _QueuedMessage(this.destination, this.body);
}
