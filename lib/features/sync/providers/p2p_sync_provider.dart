import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/shared/providers/backup_provider.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/features/sync/crypto/sync_identity.dart';
import 'package:shonenx/features/sync/domain/models/seeder_blob.dart';
import 'package:shonenx/features/sync/network/p2p_channel.dart';
import 'package:shonenx/features/sync/network/seeder_storage_manager.dart';
import 'package:shonenx/features/sync/network/swarm_peer_discovery.dart';
import 'package:shonenx/features/sync/services/sync_data_bridge.dart';

class P2PSyncState {
  final SyncIdentity? identity;
  final bool isInitialized;
  final bool isSyncing;
  final int activePeersCount;
  final int seededPeersCount;
  final int seederDataSizeBytes;
  final DateTime? lastSyncDate;
  final String? syncError;
  final int snapshotVersion;

  const P2PSyncState({
    this.identity,
    this.isInitialized = false,
    this.isSyncing = false,
    this.activePeersCount = 0,
    this.seededPeersCount = 0,
    this.seederDataSizeBytes = 0,
    this.lastSyncDate,
    this.syncError,
    this.snapshotVersion = 1,
  });

  bool get isSignedIn => identity != null;

  P2PSyncState copyWith({
    SyncIdentity? identity,
    bool? isInitialized,
    bool? isSyncing,
    int? activePeersCount,
    int? seededPeersCount,
    int? seederDataSizeBytes,
    DateTime? lastSyncDate,
    String? syncError,
    int? snapshotVersion,
    bool clearIdentity = false,
  }) {
    return P2PSyncState(
      identity: clearIdentity ? null : (identity ?? this.identity),
      isInitialized: isInitialized ?? this.isInitialized,
      isSyncing: isSyncing ?? this.isSyncing,
      activePeersCount: activePeersCount ?? this.activePeersCount,
      seededPeersCount: seededPeersCount ?? this.seededPeersCount,
      seederDataSizeBytes: seederDataSizeBytes ?? this.seederDataSizeBytes,
      lastSyncDate: lastSyncDate ?? this.lastSyncDate,
      syncError: syncError,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    );
  }
}

final seederStorageManagerProvider = Provider<SeederStorageManager>((ref) {
  return SeederStorageManager();
});

final syncDataBridgeProvider = Provider<SyncDataBridge>((ref) {
  final backupService = ref.watch(backupServiceProvider);
  return SyncDataBridge(backupService);
});

final p2pSyncProvider = StateNotifierProvider<P2PSyncNotifier, P2PSyncState>((ref) {
  final storageManager = ref.watch(seederStorageManagerProvider);
  final dataBridge = ref.watch(syncDataBridgeProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return P2PSyncNotifier(
    storageManager: storageManager,
    dataBridge: dataBridge,
    prefs: prefs,
  );
});

class P2PSyncNotifier extends StateNotifier<P2PSyncState> {
  final SeederStorageManager _storageManager;
  final SyncDataBridge _dataBridge;
  final SharedPreferences _prefs;

  P2PChannel? _p2pChannel;
  SwarmPeerDiscovery? _discovery;
  Timer? _dailySyncTimer;

  static const _prefLastSync = 'kurox_p2p_last_sync_timestamp';
  static const _prefVersion = 'kurox_p2p_snapshot_version';

  P2PSyncNotifier({
    required SeederStorageManager storageManager,
    required SyncDataBridge dataBridge,
    required SharedPreferences prefs,
  })  : _storageManager = storageManager,
        _dataBridge = dataBridge,
        _prefs = prefs,
        super(const P2PSyncState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final identity = await SyncIdentity.loadFromStorage();
      final lastSyncMs = _prefs.getInt(_prefLastSync);
      final lastSync = lastSyncMs != null ? DateTime.fromMillisecondsSinceEpoch(lastSyncMs) : null;
      final version = _prefs.getInt(_prefVersion) ?? 1;

      final seederSize = await _storageManager.getTotalSizeBytes();
      final seededCount = await _storageManager.getSeededPeersCount();

      state = state.copyWith(
        identity: identity,
        isInitialized: true,
        lastSyncDate: lastSync,
        snapshotVersion: version,
        seederDataSizeBytes: seederSize,
        seededPeersCount: seededCount,
      );

      if (identity != null) {
        await _startP2PNetwork(identity);
        _checkDailySyncSchedule();
      }
    } catch (e) {
      state = state.copyWith(isInitialized: true, syncError: e.toString());
    }
  }

  /// Starts the P2P networking channel and LAN discovery.
  Future<void> _startP2PNetwork(SyncIdentity identity) async {
    await _stopP2PNetwork();

    _p2pChannel = P2PChannel(
      localPeerId: identity.peerId,
      storageManager: _storageManager,
      onBlobReceived: (blob) async {
        await _refreshSeederStats();
        // If this blob belongs to us, check if it is newer and apply
        if (blob.targetPeerId == identity.peerId && blob.version > state.snapshotVersion) {
          try {
            await _dataBridge.decryptAndApply(
              encryptedPayload: blob.payloadBytes,
              identity: identity,
            );
            await _saveSyncSuccess(blob.version);
          } catch (_) {}
        }
      },
      onPeerDiscovered: (peerId, ip, port) {
        state = state.copyWith(
          activePeersCount: _p2pChannel?.activeConnectionsCount ?? 0,
        );
      },
    );

    final tcpPort = await _p2pChannel!.startServer();

    _discovery = SwarmPeerDiscovery(
      localPeerId: identity.peerId,
      localTcpPort: tcpPort,
      onPeerFound: (peerId, host, port) async {
        await _p2pChannel?.connectToPeer(host, port);
        state = state.copyWith(
          activePeersCount: _p2pChannel?.activeConnectionsCount ?? 0,
        );
      },
    );

    await _discovery!.start();

    // Schedule daily sync checker (runs every 1 hour to check if 24h elapsed)
    _dailySyncTimer?.cancel();
    _dailySyncTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkDailySyncSchedule();
    });
  }

  Future<void> _stopP2PNetwork() async {
    _dailySyncTimer?.cancel();
    _dailySyncTimer = null;
    await _discovery?.stop();
    _discovery = null;
    await _p2pChannel?.stop();
    _p2pChannel = null;
  }

  void _checkDailySyncSchedule() {
    final lastSync = state.lastSyncDate;
    if (lastSync == null || DateTime.now().difference(lastSync).inHours >= 24) {
      syncNow();
    }
  }

  /// Signs up: Generates a new identity, persists it, and begins seeding immediately.
  /// Returns the 12-word mnemonic recovery phrase.
  Future<String> signUp() async {
    state = state.copyWith(isSyncing: true, syncError: null);
    try {
      final identity = await SyncIdentity.generateAndSave();
      state = state.copyWith(identity: identity, isSyncing: false);

      await _startP2PNetwork(identity);
      await syncNow();

      return identity.mnemonic;
    } catch (e) {
      state = state.copyWith(isSyncing: false, syncError: e.toString());
      rethrow;
    }
  }

  /// Signs in: Restores identity from a 12-word recovery mnemonic and restores data.
  Future<void> signInWithMnemonic(String mnemonic) async {
    state = state.copyWith(isSyncing: true, syncError: null);
    try {
      final identity = await SyncIdentity.fromMnemonic(mnemonic);
      await identity.saveToStorage();

      state = state.copyWith(identity: identity);
      await _startP2PNetwork(identity);

      // Immediately query peers for our blob
      _p2pChannel?.requestBlob(identity.peerId);

      // Also capture and seed current local state
      await syncNow();
    } catch (e) {
      state = state.copyWith(isSyncing: false, syncError: e.toString());
      rethrow;
    }
  }

  /// Synchronizes current state: captures local DB, encrypts, and broadcasts to peers.
  Future<void> syncNow() async {
    final identity = state.identity;
    if (identity == null) return;

    state = state.copyWith(isSyncing: true, syncError: null);
    try {
      final nextVersion = state.snapshotVersion + 1;
      final result = await _dataBridge.captureAndEncrypt(
        identity: identity,
        version: nextVersion,
      );

      final myBlob = SeederBlob.fromPayload(
        targetPeerId: identity.peerId,
        version: nextVersion,
        timestamp: result.snapshot.timestamp,
        signature: result.snapshot.signature,
        encryptedBytes: result.encryptedPayload,
      );

      // Save to local cache
      await _storageManager.saveBlob(myBlob);

      // Broadcast seed offer to all connected peers
      _p2pChannel?.broadcastSeedOffer(myBlob);

      // Also request if any peers have a newer blob for us
      _p2pChannel?.requestBlob(identity.peerId);

      await _saveSyncSuccess(nextVersion);
      await _refreshSeederStats();
    } catch (e) {
      state = state.copyWith(isSyncing: false, syncError: e.toString());
    }
  }

  /// Clears all cached peer data hosted on this device ("Delete Seeder Data").
  Future<void> clearSeederData() async {
    await _storageManager.clearAllSeederData();
    await _refreshSeederStats();
  }

  Future<void> _refreshSeederStats() async {
    final size = await _storageManager.getTotalSizeBytes();
    final count = await _storageManager.getSeededPeersCount();
    state = state.copyWith(
      seederDataSizeBytes: size,
      seededPeersCount: count,
      activePeersCount: _p2pChannel?.activeConnectionsCount ?? 0,
    );
  }

  Future<void> _saveSyncSuccess(int version) async {
    final now = DateTime.now();
    await _prefs.setInt(_prefLastSync, now.millisecondsSinceEpoch);
    await _prefs.setInt(_prefVersion, version);

    state = state.copyWith(
      isSyncing: false,
      lastSyncDate: now,
      snapshotVersion: version,
      syncError: null,
    );
  }

  /// Signs out and deletes identity from secure storage.
  Future<void> signOut() async {
    await _stopP2PNetwork();
    await SyncIdentity.clearStorage();
    state = state.copyWith(clearIdentity: true, activePeersCount: 0);
  }

  @override
  void dispose() {
    _stopP2PNetwork();
    super.dispose();
  }
}
