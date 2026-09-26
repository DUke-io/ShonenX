import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/player/providers/video_engine_provider.dart';
import 'package:shonenx/features/player/syncplay/domain/models/syncplay_message.dart';
import 'package:shonenx/features/player/syncplay/services/syncplay_service.dart';

final syncPlayServiceProvider = Provider<SyncPlayService>((ref) {
  final service = SyncPlayService();
  ref.onDispose(() => service.dispose());
  return service;
});

final syncPlayRoomProvider =
    NotifierProvider<SyncPlayNotifier, SyncPlayRoomState>(
      SyncPlayNotifier.new,
    );

class SyncPlayNotifier extends Notifier<SyncPlayRoomState> {
  static final _log = AppLogger.scope('SyncPlayNotifier');
  late SyncPlayService _service;
  StreamSubscription? _msgSub;
  bool _isProcessingRemoteCommand = false;

  @override
  SyncPlayRoomState build() {
    _service = ref.watch(syncPlayServiceProvider);

    _msgSub?.cancel();
    _msgSub = _service.onMessage.listen(_handleIncomingMessage);

    // Listen to local engine play/pause state
    ref.listen(videoEngineStateProvider.select((s) => s.isPlaying), (
      prev,
      current,
    ) {
      if (state.isInRoom && !_isProcessingRemoteCommand) {
        if (state.isHost || state.allowGuestControl) {
          final pos = ref.read(videoEngineProvider).currentPosition.inMilliseconds;
          if (current) {
            _service.sendMessage(
              SyncPlayMessage(
                type: SyncPlayMessageType.play,
                senderId: _service.localPeerId,
                senderName: _service.localUsername,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                payload: {'positionMs': pos},
              ),
            );
          } else {
            _service.sendMessage(
              SyncPlayMessage(
                type: SyncPlayMessageType.pause,
                senderId: _service.localPeerId,
                senderName: _service.localUsername,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                payload: {'positionMs': pos},
              ),
            );
          }
        }
      }
    });

    ref.onDispose(() {
      _msgSub?.cancel();
    });

    return const SyncPlayRoomState();
  }

  void _handleIncomingMessage(SyncPlayMessage msg) async {
    switch (msg.type) {
      case SyncPlayMessageType.hello:
        final newPeer = SyncPlayPeer(
          id: msg.senderId,
          name: msg.senderName,
          isHost: false,
        );
        final updated = List<SyncPlayPeer>.from(state.peers)
          ..removeWhere((p) => p.id == newPeer.id)
          ..add(newPeer);
        state = state.copyWith(peers: updated);

        // If we are host, respond with joinAccept & current state
        if (state.isHost) {
          final engine = ref.read(videoEngineProvider);
          _service.sendMessage(
            SyncPlayMessage(
              type: SyncPlayMessageType.joinAccept,
              senderId: _service.localPeerId,
              senderName: _service.localUsername,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              payload: {
                'isPlaying': engine.isPlaying,
                'positionMs': engine.currentPosition.inMilliseconds,
              },
            ),
          );
        }
        break;

      case SyncPlayMessageType.joinAccept:
        final isPlaying = msg.payload['isPlaying'] as bool? ?? false;
        final posMs = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        final hostPeer = SyncPlayPeer(
          id: msg.senderId,
          name: msg.senderName,
          isHost: true,
        );
        state = state.copyWith(
          peers: [hostPeer],
          isInRoom: true,
          isHost: false,
        );

        _applyPlaybackState(isPlaying: isPlaying, targetPosMs: posMs);
        break;

      case SyncPlayMessageType.play:
        final posMs = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        _applyPlaybackState(isPlaying: true, targetPosMs: posMs);
        break;

      case SyncPlayMessageType.pause:
        final posMs = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        _applyPlaybackState(isPlaying: false, targetPosMs: posMs);
        break;

      case SyncPlayMessageType.seek:
        final posMs = (msg.payload['positionMs'] as num?)?.toInt() ?? 0;
        _applySeek(posMs);
        break;

      default:
        break;
    }
  }

  Future<void> _applyPlaybackState({
    required bool isPlaying,
    required int targetPosMs,
  }) async {
    _isProcessingRemoteCommand = true;
    try {
      final engine = ref.read(videoEngineProvider);
      final currentPos = engine.currentPosition.inMilliseconds;
      final drift = (currentPos - targetPosMs).abs();

      // Align timestamp if drift exceeds threshold (250ms)
      if (drift > 250) {
        await engine.seekTo(Duration(milliseconds: targetPosMs));
      }

      if (isPlaying && !engine.isPlaying) {
        await engine.play();
      } else if (!isPlaying && engine.isPlaying) {
        await engine.pause();
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _isProcessingRemoteCommand = false;
    }
  }

  Future<void> _applySeek(int targetPosMs) async {
    _isProcessingRemoteCommand = true;
    try {
      final engine = ref.read(videoEngineProvider);
      await engine.seekTo(Duration(milliseconds: targetPosMs));
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      _isProcessingRemoteCommand = false;
    }
  }

  /// Hosts a SyncPlay watch party.
  Future<String> createRoom({String username = 'Host'}) async {
    final port = await _service.hostRoom(username: username);
    final ip = await _getLocalIp();
    final roomCode = _generateRoomCode(ip, port);

    state = SyncPlayRoomState(
      isInRoom: true,
      isHost: true,
      roomCode: roomCode,
      hostAddress: ip,
      hostPort: port,
      peers: [
        SyncPlayPeer(
          id: _service.localPeerId,
          name: username,
          isHost: true,
        ),
      ],
    );

    return roomCode;
  }

  /// Joins an existing SyncPlay room.
  Future<bool> joinRoomByAddress({
    required String host,
    required int port,
    String username = 'Guest',
  }) async {
    final success = await _service.joinRoom(
      host: host,
      port: port,
      username: username,
    );

    if (success) {
      state = SyncPlayRoomState(
        isInRoom: true,
        isHost: false,
        roomCode: '$host:$port',
        hostAddress: host,
        hostPort: port,
      );
    }
    return success;
  }

  /// Joins via room code or IP:port string.
  Future<bool> joinByCode(String code, {String username = 'Guest'}) async {
    final clean = code.trim();
    if (clean.contains(':')) {
      final parts = clean.split(':');
      final host = parts[0];
      final port = int.tryParse(parts[1]) ?? 8492;
      return joinRoomByAddress(host: host, port: port, username: username);
    }

    // Direct IP format
    return joinRoomByAddress(host: clean, port: 8492, username: username);
  }

  /// Sends a seek event to peers.
  void broadcastSeek(Duration position) {
    if (state.isInRoom && !_isProcessingRemoteCommand) {
      if (state.isHost || state.allowGuestControl) {
        _service.sendMessage(
          SyncPlayMessage(
            type: SyncPlayMessageType.seek,
            senderId: _service.localPeerId,
            senderName: _service.localUsername,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            payload: {'positionMs': position.inMilliseconds},
          ),
        );
      }
    }
  }

  void sendReaction(String emoji) {
    _service.sendReaction(emoji);
  }

  Future<void> leaveRoom() async {
    await _service.leaveRoom();
    state = const SyncPlayRoomState();
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  String _generateRoomCode(String ip, int port) {
    // Generate clean human-readable code: e.g. "192.168.1.12:8492"
    return '$ip:$port';
  }
}
