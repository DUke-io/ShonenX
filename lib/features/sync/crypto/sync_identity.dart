import 'dart:convert';
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shonenx/features/sync/crypto/sync_cipher.dart';

/// Represents a user's cryptographic identity derived from a 12-word BIP-39 mnemonic.
class SyncIdentity {
  final String mnemonic;
  final String peerId;
  final List<int> publicKeyBytes;
  final SimpleKeyPair signingKeyPair;
  final SecretKey encryptionKey;

  const SyncIdentity({
    required this.mnemonic,
    required this.peerId,
    required this.publicKeyBytes,
    required this.signingKeyPair,
    required this.encryptionKey,
  });

  static const _storageKey = 'kurox_sync_mnemonic_v1';
  static const _secureStorage = FlutterSecureStorage();

  /// Creates a [SyncIdentity] instance from a given 12-word mnemonic.
  static Future<SyncIdentity> fromMnemonic(String mnemonic) async {
    final cleaned = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(cleaned)) {
      throw ArgumentError('Invalid 12-word recovery mnemonic.');
    }

    final seed = bip39.mnemonicToSeed(cleaned);
    final signingKeyPair = await SyncCipher.deriveSigningKeyPair(seed);
    final publicKey = await signingKeyPair.extractPublicKey();
    final encryptionKey = await SyncCipher.deriveEncryptionKey(seed);

    // Derive deterministic peerId from public key SHA-256
    final hashBytes = await SyncCipher.hash(publicKey.bytes);
    final peerId = hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().substring(0, 24);

    return SyncIdentity(
      mnemonic: cleaned,
      peerId: peerId,
      publicKeyBytes: publicKey.bytes,
      signingKeyPair: signingKeyPair,
      encryptionKey: encryptionKey,
    );
  }

  /// Generates a fresh identity with a new 12-word mnemonic and saves it to secure storage.
  static Future<SyncIdentity> generateAndSave() async {
    final mnemonic = bip39.generateMnemonic();
    final identity = await fromMnemonic(mnemonic);
    await identity.saveToStorage();
    return identity;
  }

  /// Restores identity from secure storage, or returns null if not logged in.
  static Future<SyncIdentity?> loadFromStorage() async {
    try {
      final mnemonic = await _secureStorage.read(key: _storageKey);
      if (mnemonic == null || mnemonic.isEmpty) return null;
      return await fromMnemonic(mnemonic);
    } catch (_) {
      return null;
    }
  }

  /// Persists this identity's mnemonic into secure storage.
  Future<void> saveToStorage() async {
    await _secureStorage.write(key: _storageKey, value: mnemonic);
  }

  /// Deletes the identity from secure storage (Sign Out).
  static Future<void> clearStorage() async {
    await _secureStorage.delete(key: _storageKey);
  }
}
