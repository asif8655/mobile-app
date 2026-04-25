import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../features/auth/data/models/auth_models.dart';
import '../../features/chat/data/models/chat_models.dart';
import '../storage/secure_storage.dart';

class E2eeIdentity {
  final EcKeyPairData keyPair;
  final String publicKey;
  final String keyId;

  const E2eeIdentity({
    required this.keyPair,
    required this.publicKey,
    required this.keyId,
  });
}

class E2eeService {
  static const publicKeyAlgorithm = 'ECDH-P-256-AES-GCM';
  static const encryptionVersion = 'web-ecdh-p256-aesgcm-v1';

  final SecureStorageService _secureStorage;
  final Ecdh _ecdh = Ecdh.p256(length: 32);
  final AesGcm _aesGcm = AesGcm.with256bits();

  E2eeService(this._secureStorage);

  Future<E2eeIdentity> ensureIdentity(String userId) async {
    final privateKey = await _secureStorage.getE2eePrivateKey(userId);
    final publicKey = await _secureStorage.getE2eePublicKey(userId);

    if (privateKey != null && publicKey != null) {
      final privateBytes = _fromBase64Url(privateKey);
      final ecPublicKey = _publicKeyFromEncodedJwk(publicKey);
      return E2eeIdentity(
        keyPair: EcKeyPairData(
          d: privateBytes,
          x: ecPublicKey.x,
          y: ecPublicKey.y,
          type: KeyPairType.p256,
        ),
        publicKey: publicKey,
        keyId: await _calculateKeyId(publicKey),
      );
    }

    final keyPair = await _ecdh.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKeyString = _encodePublicKeyAsJwk(keyPairData.publicKey);

    await _secureStorage.saveE2eePrivateKey(
      userId,
      _toBase64Url(Uint8List.fromList(keyPairData.d)),
    );
    await _secureStorage.saveE2eePublicKey(userId, publicKeyString);

    return E2eeIdentity(
      keyPair: keyPairData,
      publicKey: publicKeyString,
      keyId: await _calculateKeyId(publicKeyString),
    );
  }

  bool needsPublicKeyUpload(UserResponse user, String publicKey) {
    return user.publicKey != publicKey ||
        user.publicKeyAlgorithm != publicKeyAlgorithm;
  }

  Future<Map<String, dynamic>> encryptChatPayload({
    required String senderId,
    required UserResponse receiver,
    required String plaintext,
  }) async {
    final receiverPublicKey = receiver.publicKey;
    if (receiverPublicKey == null || receiverPublicKey.isEmpty) {
      throw StateError('This user has not published an encryption key yet.');
    }

    final identity = await ensureIdentity(senderId);
    final secretKey = await _deriveAesKey(identity.keyPair, receiverPublicKey);
    final nonce = _randomBytes(12);
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );
    final encryptedBytes = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    final encodedNonce = _toBase64Url(Uint8List.fromList(nonce));
    final encryptedPayload = {
      'ciphertext': _toBase64Url(encryptedBytes),
      'nonce': encodedNonce,
    };

    return {
      'receiverId': receiver.id,
      'content': jsonEncode(encryptedPayload),
      'encrypted': true,
      'encryptionVersion': encryptionVersion,
      'encryptionNonce': encodedNonce,
      'senderKeyId': identity.keyId,
      'receiverKeyId': await _calculateKeyId(receiverPublicKey),
    };
  }

  Future<MessageResponse> decryptMessage({
    required MessageResponse message,
    required String currentUserId,
    required List<UserResponse> users,
  }) async {
    if (!message.encrypted) return message;

    if (message.encryptionVersion != encryptionVersion) {
      return message.copyWith(
        content: 'Unable to decrypt: unsupported encryption version.',
      );
    }

    try {
      final identity = await ensureIdentity(currentUserId);
      final peerUserId = message.senderId == currentUserId
          ? message.receiverId
          : message.senderId;
      final peer = users.where((user) => user.id == peerUserId).firstOrNull;
      final peerPublicKey = peer?.publicKey;

      if (peerPublicKey == null || peerPublicKey.isEmpty) {
        return message.copyWith(content: 'Unable to decrypt: missing public key.');
      }

      final payload = jsonDecode(message.content) as Map<String, dynamic>;
      final encryptedBytes = _fromBase64Url(payload['ciphertext'] as String);
      final nonceValue = message.encryptionNonce ?? payload['nonce'] as String;
      final nonce = _fromBase64Url(nonceValue);
      final macStart = encryptedBytes.length - 16;
      final secretBox = SecretBox(
        encryptedBytes.sublist(0, macStart),
        nonce: nonce,
        mac: Mac(encryptedBytes.sublist(macStart)),
      );
      final secretKey = await _deriveAesKey(identity.keyPair, peerPublicKey);
      final plaintextBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return message.copyWith(content: utf8.decode(plaintextBytes));
    } catch (_) {
      return message.copyWith(content: 'Unable to decrypt this message.');
    }
  }

  Future<SecretKey> _deriveAesKey(
    EcKeyPair keyPair,
    String peerPublicKey,
  ) async {
    final sharedSecret = await _ecdh.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: _publicKeyFromEncodedJwk(peerPublicKey),
    );
    final sharedBytes = await sharedSecret.extractBytes();
    final digest = await Sha256().hash(sharedBytes);
    return SecretKey(digest.bytes);
  }

  Future<String> _calculateKeyId(String publicKey) async {
    final digest = await Sha256().hash(utf8.encode(publicKey));
    return _toBase64Url(Uint8List.fromList(digest.bytes.take(16).toList()));
  }

  String _encodePublicKeyAsJwk(EcPublicKey publicKey) {
    final x = publicKey.x;
    final y = publicKey.y;
    final jwk = {
      'key_ops': <String>[],
      'ext': true,
      'kty': 'EC',
      'x': _toBase64Url(Uint8List.fromList(x)),
      'y': _toBase64Url(Uint8List.fromList(y)),
      'crv': 'P-256',
    };

    return _toBase64Url(Uint8List.fromList(utf8.encode(jsonEncode(jwk))));
  }

  EcPublicKey _publicKeyFromEncodedJwk(String encodedJwk) {
    final jwk = jsonDecode(utf8.decode(_fromBase64Url(encodedJwk)))
        as Map<String, dynamic>;
    final x = _fromBase64Url(jwk['x'] as String);
    final y = _fromBase64Url(jwk['y'] as String);
    return EcPublicKey(x: x, y: y, type: KeyPairType.p256);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  String _toBase64Url(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Uint8List _fromBase64Url(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
