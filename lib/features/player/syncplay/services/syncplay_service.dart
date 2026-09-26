import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/player/syncplay/domain/models/syncplay_message.dart';

class SyncPlayService {
  static final _log = AppLogger.scope('SyncPlayService');

  final String localPeerId =
      'peer_${DateTime.now().millisecondsSinceEpoch % 100000}';
  String localUsername = 'User';

  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];

  final _messageController = StreamController<SyncPlayMessage>.broadcast();
  final _reactionController = StreamController<SyncReaction>.broadcast();

  Stream<SyncPlayMessage> get onMessage => _messageController.stream;
  Stream<SyncReaction> get onReaction => _reactionController.stream;

  bool get isHosting => _serverSocket != null;
  bool get isConnected => _clientSocket != null || isHosting;

  /// Starts hosting a SyncPlay room on the given or ephemeral port.
  Future<int> hostRoom({int port = 8492, String username = 'Host'}) async {
    localUsername = username;
    await leaveRoom();

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      final boundPort = _serverSocket!.port;
      _log.i('SyncPlay room hosted on port $boundPort');

      _serverSocket!.listen(
        _handleIncomingClient,
        onError: (e) => _log.e('Server socket error', e),
      );

      return boundPort;
    } catch (e) {
      _log.w('Could not bind port $port, trying ephemeral port...');
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final boundPort = _serverSocket!.port;
      _serverSocket!.listen(_handleIncomingClient);
      return boundPort;
    }
  }

  /// Connects to a remote SyncPlay room by host IP and port.
  Future<bool> joinRoom({
    required String host,
    required int port,
    String username = 'Guest',
  }) async {
    localUsername = username;
    await leaveRoom();

    try {
      _log.i('Connecting to SyncPlay room at $host:$port...');
      _clientSocket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 6),
      );

      _setupSocketListener(_clientSocket!);

      // Send initial HELLO handshake
      sendMessage(
        SyncPlayMessage(
          type: SyncPlayMessageType.hello,
          senderId: localPeerId,
          senderName: localUsername,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      return true;
    } catch (e) {
      _log.e('Failed to join SyncPlay room', e);
      return false;
    }
  }

  void _handleIncomingClient(Socket client) {
    _connectedClients.add(client);
    _log.i('New client connected: ${client.remoteAddress.address}:${client.remotePort}');

    _setupSocketListener(client, onDone: () {
      _connectedClients.remove(client);
      _log.i('Client disconnected: ${client.remoteAddress.address}');
    });
  }

  void _setupSocketListener(Socket socket, {void Function()? onDone}) {
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.trim().isEmpty) return;
            try {
              final map = jsonDecode(line) as Map<String, dynamic>;
              final msg = SyncPlayMessage.fromMap(map);

              _messageController.add(msg);

              // If host, forward message to all other connected clients
              if (isHosting) {
                _broadcastMessage(msg, exclude: socket);
              }

              // Handle reactions
              if (msg.type == SyncPlayMessageType.reaction) {
                final emoji = msg.payload['emoji'] as String? ?? '🔥';
                _reactionController.add(
                  SyncReaction(
                    id: '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
                    emoji: emoji,
                    senderName: msg.senderName,
                    horizontalPercent: 0.2 + (Random().nextDouble() * 0.6),
                  ),
                );
              }
            } catch (e) {
              _log.w('Failed to decode sync message: $line, error: $e');
            }
          },
          onError: (_) {
            socket.destroy();
            onDone?.call();
          },
          onDone: () {
            socket.destroy();
            onDone?.call();
          },
          cancelOnError: false,
        );
  }

  /// Sends a message either to host (if client) or broadcasts to all clients (if host).
  void sendMessage(SyncPlayMessage msg) {
    if (isHosting) {
      _broadcastMessage(msg);
    } else if (_clientSocket != null) {
      _sendRaw(_clientSocket!, msg);
    }
  }

  void _broadcastMessage(SyncPlayMessage msg, {Socket? exclude}) {
    for (final client in _connectedClients) {
      if (client != exclude) {
        _sendRaw(client, msg);
      }
    }
  }

  void _sendRaw(Socket socket, SyncPlayMessage msg) {
    try {
      socket.write('${msg.toJson()}\n');
    } catch (_) {}
  }

  /// Sends a quick emoji reaction to the room.
  void sendReaction(String emoji) {
    sendMessage(
      SyncPlayMessage(
        type: SyncPlayMessageType.reaction,
        senderId: localPeerId,
        senderName: localUsername,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        payload: {'emoji': emoji},
      ),
    );
    // Also trigger locally
    _reactionController.add(
      SyncReaction(
        id: '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}',
        emoji: emoji,
        senderName: localUsername,
        horizontalPercent: 0.2 + (Random().nextDouble() * 0.6),
      ),
    );
  }

  /// Closes room, disconnects all sockets, and resets state.
  Future<void> leaveRoom() async {
    try {
      for (final client in _connectedClients) {
        client.destroy();
      }
      _connectedClients.clear();

      _clientSocket?.destroy();
      _clientSocket = null;

      await _serverSocket?.close();
      _serverSocket = null;
    } catch (_) {}
  }

  void dispose() {
    leaveRoom();
    _messageController.close();
    _reactionController.close();
  }
}
