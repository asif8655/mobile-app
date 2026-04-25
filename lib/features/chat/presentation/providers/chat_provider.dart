import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/stomp_client_manager.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/chat_models.dart';
import '../../data/repositories/chat_repository.dart';
import '../../../auth/data/models/auth_models.dart';

// ─── Users List Provider ───
final usersProvider =
    StateNotifierProvider<UsersNotifier, AsyncValue<List<UserResponse>>>((ref) {
      final chatRepo = ref.read(chatRepositoryProvider);
      final authState = ref.watch(authProvider);
      return UsersNotifier(chatRepo, authState);
    });

class UsersNotifier extends StateNotifier<AsyncValue<List<UserResponse>>> {
  final ChatRepository _chatRepo;
  final AuthState _authState;

  UsersNotifier(this._chatRepo, this._authState)
    : super(const AsyncValue.loading()) {
    if (_authState.status == AuthStatus.authenticated) {
      loadUsers();
    }
  }

  Future<void> loadUsers() async {
    state = const AsyncValue.loading();
    try {
      final currentUser = _authState.user;
      if (currentUser != null) {
        final identity = await _chatRepo.e2ee.ensureIdentity(currentUser.id);
        if (_chatRepo.e2ee.needsPublicKeyUpload(
          currentUser,
          identity.publicKey,
        )) {
          await _chatRepo.updatePublicKey(identity.publicKey);
        }
      }

      final users = await _chatRepo.getUsers();
      state = AsyncValue.data(users);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void updateUnreadCount(String userId, int delta) {
    state.whenData((users) {
      final updated = users.map((u) {
        if (u.id == userId) {
          return u.copyWith(unreadCount: u.unreadCount + delta);
        }
        return u;
      }).toList();
      state = AsyncValue.data(updated);
    });
  }

  void clearUnreadCount(String userId) {
    state.whenData((users) {
      final updated = users.map((u) {
        if (u.id == userId) {
          return u.copyWith(unreadCount: 0);
        }
        return u;
      }).toList();
      state = AsyncValue.data(updated);
    });
  }
}

// ─── Conversation Provider ───
final conversationProvider =
    StateNotifierProvider.family<
      ConversationNotifier,
      AsyncValue<List<MessageResponse>>,
      String
>((ref, userId) {
      final chatRepo = ref.read(chatRepositoryProvider);
      final stompManager = ref.read(stompClientManagerProvider);
      final authState = ref.read(authProvider);
      final users = ref.read(usersProvider).valueOrNull ?? const <UserResponse>[];
      return ConversationNotifier(
        chatRepo,
        stompManager,
        userId,
        authState,
        users,
      );
    });

class ConversationNotifier
    extends StateNotifier<AsyncValue<List<MessageResponse>>> {
  final ChatRepository _chatRepo;
  final StompClientManager _stompManager;
  final String _userId;
  final AuthState _authState;
  List<UserResponse> _users;

  ConversationNotifier(
    this._chatRepo,
    this._stompManager,
    this._userId,
    this._authState,
    this._users,
  ) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    loadMessages();
    _subscribeToMessages();
  }

  Future<void> loadMessages() async {
    try {
      final messages = await _chatRepo.getConversation(_userId);
      state = AsyncValue.data(await _decryptMessages(messages));
      // Mark as read when opening conversation
      await _chatRepo.markAsRead(_userId);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _subscribeToMessages() {
    _stompManager.registerSubscription(StompDestinations.userMessages, (body) {
      try {
        final message = MessageResponse.fromJson(body);
        // Only add if relevant to current conversation
        final currentUserId = _authState.user?.id;
        if ((message.senderId == _userId &&
                message.receiverId == currentUserId) ||
            (message.senderId == currentUserId &&
                message.receiverId == _userId)) {
          final currentMessages = state.valueOrNull ?? const <MessageResponse>[];
          if (!currentMessages.any((m) => m.id == message.id)) {
            _decryptMessage(message).then((decryptedMessage) {
              state = AsyncValue.data([...currentMessages, decryptedMessage]);
            });
          }
        }
      } catch (e) {
        log.e('Error parsing incoming message: $e');
      }
    });
  }

  Future<void> sendMessage(String content) async {
    try {
      final currentUserId = _authState.user?.id;
      if (currentUserId == null) return;

      final receiver = await _chatRepo.getUserById(_userId);
      _users = [
        ..._users.where((user) => user.id != receiver.id),
        receiver,
      ];
      Map<String, dynamic> payload;
      try {
        payload = await _chatRepo.e2ee.encryptChatPayload(
          senderId: currentUserId,
          receiver: receiver,
          plaintext: content,
        );
      } catch (encryptionError) {
        log.w('Encryption unavailable, sending plaintext: $encryptionError');
        payload = {
          'receiverId': receiver.id,
          'content': content,
          'encrypted': false,
        };
      }

      // Persist via REST to ensure message delivery even if realtime socket is unstable.
      final savedMessage = await _chatRepo.sendEncryptedMessage(payload);
      final messages = state.valueOrNull ?? const <MessageResponse>[];
      state = AsyncValue.data([
        ...messages,
        await _decryptMessage(savedMessage),
      ]);
    } catch (e) {
      log.e('Failed to send message: $e');
      rethrow;
    }
  }

  Future<void> deleteForMe(String messageId) async {
    await _chatRepo.deleteMessageForMe(messageId);
    state.whenData((messages) {
      state = AsyncValue.data(
        messages.where((m) => m.id != messageId).toList(),
      );
    });
  }

  Future<void> deleteForBoth(String messageId) async {
    await _chatRepo.deleteMessageForBoth(messageId);
    state.whenData((messages) {
      state = AsyncValue.data(
        messages.where((m) => m.id != messageId).toList(),
      );
    });
  }

  Future<List<MessageResponse>> _decryptMessages(
    List<MessageResponse> messages,
  ) async {
    return Future.wait(messages.map(_decryptMessage));
  }

  Future<MessageResponse> _decryptMessage(MessageResponse message) async {
    final currentUserId = _authState.user?.id;
    if (currentUserId == null) return message;

    return _chatRepo.e2ee.decryptMessage(
      message: message,
      currentUserId: currentUserId,
      users: _users,
    );
  }
}
