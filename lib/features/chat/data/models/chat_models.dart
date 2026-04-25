class MessageResponse {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final bool isRead;
  final DateTime sentAt;

  MessageResponse({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.isRead,
    required this.sentAt,
  });

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    return MessageResponse(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      content: json['content'] as String,
      isRead: json['isRead'] as bool? ?? false,
      sentAt: DateTime.parse(json['sentAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'isRead': isRead,
        'sentAt': sentAt.toIso8601String(),
      };
}

class CallEventResponse {
  final String fromUserId;
  final String fromUserName;
  final String eventType;
  final String? channelName;

  CallEventResponse({
    required this.fromUserId,
    required this.fromUserName,
    required this.eventType,
    this.channelName,
  });

  factory CallEventResponse.fromJson(Map<String, dynamic> json) {
    return CallEventResponse(
      fromUserId: json['fromUserId'] as String,
      fromUserName: json['fromUserName'] as String,
      eventType: json['eventType'] as String,
      channelName: json['channelName'] as String?,
    );
  }
}

class RtcTokenResponse {
  final String token;
  final String appId;
  final String channelName;
  final String uid;
  final int expiresIn;

  RtcTokenResponse({
    required this.token,
    required this.appId,
    required this.channelName,
    required this.uid,
    required this.expiresIn,
  });

  factory RtcTokenResponse.fromJson(Map<String, dynamic> json) {
    return RtcTokenResponse(
      token: json['token'] as String,
      appId: json['appId'] as String,
      channelName: json['channelName'] as String,
      uid: json['uid'] as String,
      expiresIn: (json['expiresIn'] as num).toInt(),
    );
  }
}
