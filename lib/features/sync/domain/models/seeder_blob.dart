import 'dart:convert';
import 'dart:typed_data';

/// Represents an opaque, encrypted data blob cached by a peer node to seed for another user.
/// Seeders cannot inspect or decrypt the payload — it is pure zero-knowledge hosting.
class SeederBlob {
  final String targetPeerId;
  final int version;
  final DateTime timestamp;
  final String signature;
  final String encryptedPayloadBase64;
  final DateTime cachedAt;
  final int sizeBytes;

  const SeederBlob({
    required this.targetPeerId,
    required this.version,
    required this.timestamp,
    required this.signature,
    required this.encryptedPayloadBase64,
    required this.cachedAt,
    required this.sizeBytes,
  });

  Uint8List get payloadBytes => base64Decode(encryptedPayloadBase64);

  Map<String, dynamic> toJson() => {
    'targetPeerId': targetPeerId,
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'signature': signature,
    'encryptedPayloadBase64': encryptedPayloadBase64,
    'cachedAt': cachedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
  };

  factory SeederBlob.fromJson(Map<String, dynamic> json) {
    return SeederBlob(
      targetPeerId: json['targetPeerId'] as String,
      version: json['version'] as int? ?? 1,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      signature: json['signature'] as String? ?? '',
      encryptedPayloadBase64: json['encryptedPayloadBase64'] as String? ?? '',
      cachedAt: DateTime.tryParse(json['cachedAt'] as String? ?? '') ?? DateTime.now(),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
    );
  }

  factory SeederBlob.fromPayload({
    required String targetPeerId,
    required int version,
    required DateTime timestamp,
    required String signature,
    required Uint8List encryptedBytes,
  }) {
    final b64 = base64Encode(encryptedBytes);
    return SeederBlob(
      targetPeerId: targetPeerId,
      version: version,
      timestamp: timestamp,
      signature: signature,
      encryptedPayloadBase64: b64,
      cachedAt: DateTime.now(),
      sizeBytes: encryptedBytes.length,
    );
  }
}
