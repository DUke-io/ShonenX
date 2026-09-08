import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nsd/nsd.dart' as nsd;

/// Handles zero-configuration peer discovery across Local Area Networks (LAN)
/// via UDP socket broadcasts and mDNS service advertisements.
class SwarmPeerDiscovery {
  static const int broadcastPort = 48892;
  static const String serviceType = '_kurox-sync._tcp';

  final String localPeerId;
  final int localTcpPort;
  final void Function(String peerId, String host, int port) onPeerFound;

  RawDatagramSocket? _udpSocket;
  Timer? _beaconTimer;
  nsd.Registration? _nsdRegistration;
  nsd.Discovery? _nsdDiscovery;
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

    await _startUdpBroadcast();
    await _startNsdDiscovery();
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

    try {
      if (_nsdRegistration != null) {
        await nsd.unregister(_nsdRegistration!);
        _nsdRegistration = null;
      }
      if (_nsdDiscovery != null) {
        await nsd.stopDiscovery(_nsdDiscovery!);
        _nsdDiscovery = null;
      }
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
      _udpSocket!.send(bytes, InternetAddress('255.255.255.255'), broadcastPort);
    } catch (_) {}
  }

  Future<void> _startUdpBroadcast() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
        reuseAddress: true,
        reusePort: true,
      );
      _udpSocket!.broadcastEnabled = true;

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

  Future<void> _startNsdDiscovery() async {
    try {
      // Register local service
      _nsdRegistration = await nsd.register(
        nsd.Service(
          name: 'KuroX-$localPeerId',
          type: serviceType,
          port: localTcpPort,
          txt: {'peerId': utf8.encode(localPeerId)},
        ),
      );

      // Start discovery of nearby services
      _nsdDiscovery = await nsd.startDiscovery(serviceType);
      _nsdDiscovery!.addListener(() {
        for (final service in _nsdDiscovery!.services) {
          final host = service.host;
          final port = service.port;
          if (host != null && port != null) {
            final key = '$host:$port';
            if (_knownEndpoints.add(key)) {
              final peerId = service.name ?? 'peer';
              onPeerFound(peerId, host, port);
            }
          }
        }
      });
    } catch (_) {}
  }
}
