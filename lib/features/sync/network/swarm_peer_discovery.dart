import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Handles zero-configuration peer discovery across Local Area Networks (LAN)
/// via UDP socket broadcasts and multicasts.
class SwarmPeerDiscovery {
  static const int broadcastPort = 48892;
  static const String multicastGroupIpv4 = '239.255.255.250';

  final String localPeerId;
  final int localTcpPort;
  final void Function(String peerId, String host, int port) onPeerFound;

  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  bool _isRunning = false;

  final Set<String> _knownEndpoints = {};

  SwarmPeerDiscovery({
    required this.localPeerId,
    required this.localTcpPort,
    required this.onPeerFound,
  });

  /// Starts advertising and listening for peers across LAN.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    await _startUdpDiscovery();
  }

  /// Stops discovery services.
  Future<void> stop() async {
    _isRunning = false;
    _beaconTimer?.cancel();
    _beaconTimer = null;

    try {
      _udpSocket?.close();
      _udpSocket = null;
    } catch (_) {}
  }

  /// Broadcasts a discovery beacon immediately to announce presence.
  void sendBeacon() {
    if (_udpSocket == null) return;
    try {
      final payload = jsonEncode({
        'kurox': true,
        'peerId': localPeerId,
        'port': localTcpPort,
      });
      final bytes = utf8.encode(payload);

      // Send to global IPv4 broadcast
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), broadcastPort);

      // Also send to local multicast group
      try {
        _udpSocket!.send(bytes, InternetAddress(multicastGroupIpv4), broadcastPort);
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;

      // Join standard SSDP/multicast group for LAN discovery
      try {
        _udpSocket!.joinMulticast(InternetAddress(multicastGroupIpv4));
      } catch (_) {}

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram == null) return;

          try {
            final text = utf8.decode(datagram.data);
            final map = jsonDecode(text) as Map<String, dynamic>;
            if (map['kurox'] == true) {
              final remotePeerId = map['peerId'] as String?;
              final remotePort = map['port'] as int?;

              if (remotePeerId != null &&
                  remotePort != null &&
                  remotePeerId != localPeerId) {
                final host = datagram.address.address;
                final key = '$host:$remotePort';
                if (_knownEndpoints.add(key)) {
                  onPeerFound(remotePeerId, host, remotePort);
                }
              }
            }
          } catch (_) {}
        }
      });

      // Send beacon periodically every 15 seconds while active
      _beaconTimer = Timer.periodic(const Duration(seconds: 15), (_) => sendBeacon());
      sendBeacon();
    } catch (_) {}
  }
}

