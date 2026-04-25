import 'dart:convert';

class UserResponse {
  final String id;
  final String email;
  final String fullName;
  final bool isVerified;
  final bool isSuperUser;
  final String? publicKey;
  final String? publicKeyAlgorithm;
  final int unreadCount;

  UserResponse({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isVerified,
    required this.isSuperUser,
    this.publicKey,
    this.publicKeyAlgorithm,
    this.unreadCount = 0,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String,
      isVerified: json['isVerified'] as bool? ?? false,
      isSuperUser: json['isSuperUser'] as bool? ?? false,
      publicKey: json['publicKey'] as String?,
      publicKeyAlgorithm: json['publicKeyAlgorithm'] as String?,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'isVerified': isVerified,
        'isSuperUser': isSuperUser,
        'publicKey': publicKey,
        'publicKeyAlgorithm': publicKeyAlgorithm,
        'unreadCount': unreadCount,
      };

  String toJsonString() => jsonEncode(toJson());

  factory UserResponse.fromJsonString(String source) =>
      UserResponse.fromJson(jsonDecode(source) as Map<String, dynamic>);

  UserResponse copyWith({
    String? publicKey,
    String? publicKeyAlgorithm,
    int? unreadCount,
  }) {
    return UserResponse(
      id: id,
      email: email,
      fullName: fullName,
      isVerified: isVerified,
      isSuperUser: isSuperUser,
      publicKey: publicKey ?? this.publicKey,
      publicKeyAlgorithm: publicKeyAlgorithm ?? this.publicKeyAlgorithm,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final UserResponse user;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      tokenType: json['tokenType'] as String,
      user: UserResponse.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
