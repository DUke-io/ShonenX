import 'dart:convert';

enum SyncPlayMessageType {
  hello,
  joinRequest,
  joinAccept,
  syncState,
  play,
  pause,
  seek,
  mediaChange,
  reaction,
  chat,
  ping,
  pong,
}

class SyncPlayMessage {
  final SyncPlayMessageType type;
  final String senderId;
  final String senderName;
  final int timestamp;
  final Map<String, dynamic> payload;

  const SyncPlayMessage({
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.timestamp,
    this.payload = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'senderId': senderId,
      'senderName': senderName,
      'timestamp': timestamp,
      'payload': payload,
    };
  }

  factory SyncPlayMessage.fromMap(Map<String, dynamic> map) {
    return SyncPlayMessage(
      type: SyncPlayMessageType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => SyncPlayMessageType.ping,
      ),
      senderId: map['senderId'] as String? ?? 'unknown',
      senderName: map['senderName'] as String? ?? 'Anonymous',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      payload: map['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SyncPlayMessage.fromJson(String source) =>
      SyncPlayMessage.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

class SyncPlayPeer {
  final String id;
  final String name;
  final bool isHost;
  final int latencyMs;
  final bool isSynced;

  const SyncPlayPeer({
    required this.id,
    required this.name,
    this.isHost = false,
    this.latencyMs = 0,
    this.isSynced = true,
  });

  SyncPlayPeer copyWith({
    String? id,
    String? name,
    bool? isHost,
    int? latencyMs,
    bool? isSynced,
  }) {
    return SyncPlayPeer(
      id: id ?? this.id,
      name: name ?? this.name,
      isHost: isHost ?? this.isHost,
      latencyMs: latencyMs ?? this.latencyMs,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

class SyncPlayRoomState {
  final bool isInRoom;
  final bool isHost;
  final String roomCode;
  final String hostAddress;
  final int hostPort;
  final List<SyncPlayPeer> peers;
  final bool allowGuestControl;
  final int clockOffsetMs;

  const SyncPlayRoomState({
    this.isInRoom = false,
    this.isHost = false,
    this.roomCode = '',
    this.hostAddress = '',
    this.hostPort = 8492,
    this.peers = const [],
    this.allowGuestControl = true,
    this.clockOffsetMs = 0,
  });

  SyncPlayRoomState copyWith({
    bool? isInRoom,
    bool? isHost,
    String? roomCode,
    String? hostAddress,
    int? hostPort,
    List<SyncPlayPeer>? peers,
    bool? allowGuestControl,
    int? clockOffsetMs,
  }) {
    return SyncPlayRoomState(
      isInRoom: isInRoom ?? this.isInRoom,
      isHost: isHost ?? this.isHost,
      roomCode: roomCode ?? this.roomCode,
      hostAddress: hostAddress ?? this.hostAddress,
      hostPort: hostPort ?? this.hostPort,
      peers: peers ?? this.peers,
      allowGuestControl: allowGuestControl ?? this.allowGuestControl,
      clockOffsetMs: clockOffsetMs ?? this.clockOffsetMs,
    );
  }
}

class SyncReaction {
  final String id;
  final String emoji;
  final String senderName;
  final double horizontalPercent;

  const SyncReaction({
    required this.id,
    required this.emoji,
    required this.senderName,
    required this.horizontalPercent,
  });
}
