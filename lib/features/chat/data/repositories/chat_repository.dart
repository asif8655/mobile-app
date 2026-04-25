import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/data/models/auth_models.dart';
import '../models/chat_models.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final dioClient = ref.read(dioClientProvider);
  return ChatRepository(dioClient.dio);
});

class ChatRepository {
  final Dio _dio;

  ChatRepository(this._dio);

  Future<List<UserResponse>> getUsers() async {
    final response = await _dio.get(ApiConstants.users);
    return (response.data as List)
        .map((json) => UserResponse.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageResponse>> getConversation(String userId) async {
    final response = await _dio.get('${ApiConstants.messages}/$userId');
    return (response.data as List)
        .map((json) => MessageResponse.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<MessageResponse> sendMessage(String receiverId, String content) async {
    final response = await _dio.post(
      ApiConstants.messages,
      data: {
        'receiverId': receiverId,
        'content': content,
      },
    );
    return MessageResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> markAsRead(String userId) async {
    await _dio.put('${ApiConstants.messages}/$userId/read');
  }

  Future<void> deleteMessageForMe(String messageId) async {
    await _dio.delete('${ApiConstants.messages}/$messageId/delete-for-me');
  }

  Future<void> deleteMessageForBoth(String messageId) async {
    await _dio.delete('${ApiConstants.messages}/$messageId/delete-for-both');
  }

  Future<void> deleteAllForMe(String userId) async {
    await _dio.delete('${ApiConstants.messages}/$userId/delete-all-for-me');
  }

  Future<RtcTokenResponse> getRtcToken(String channelName, String targetUserId, {int role = 1}) async {
    final response = await _dio.post(
      ApiConstants.rtcToken,
      data: {
        'channelName': channelName,
        'targetUserId': targetUserId,
        'role': role,
      },
    );
    return RtcTokenResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
