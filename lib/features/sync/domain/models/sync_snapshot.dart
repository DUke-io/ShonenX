import 'dart:convert';
import 'dart:typed_data';

/// Encapsulates a versioned, cryptographically signed snapshot of a user's data.
class SyncSnapshot {
  final String peerId;
  final int version;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final String signature;

  const SyncSnapshot({
    required this.peerId,
    required this.version,
    required this.timestamp,
    required this.data,
    required this.signature,
  });

  /// Produces deterministic canonical bytes used for signing and verifying the snapshot.
  Uint8List toSignableBytes() {
    // Sort keys in data for deterministic payload canonicalization
    final canonicalJson = jsonEncode(data);
    final signableString = '$peerId:$version:${timestamp.millisecondsSinceEpoch}:$canonicalJson';
    return Uint8List.fromList(utf8.encode(signableString));
  }

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'version': version,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'signature': signature,
  };

  factory SyncSnapshot.fromJson(Map<String, dynamic> json) {
    return SyncSnapshot(
      peerId: json['peerId'] as String,
      version: json['version'] as int? ?? 1,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      data: json['data'] as Map<String, dynamic>? ?? {},
      signature: json['signature'] as String? ?? '',
    );
  }

  SyncSnapshot copyWith({
    String? peerId,
    int? version,
    DateTime? timestamp,
    Map<String, dynamic>? data,
    String? signature,
  }) {
    return SyncSnapshot(
      peerId: peerId ?? this.peerId,
      version: version ?? this.version,
      timestamp: timestamp ?? this.timestamp,
      data: data ?? this.data,
      signature: signature ?? this.signature,
    );
  }
}
