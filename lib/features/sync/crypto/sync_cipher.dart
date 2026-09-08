import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Cryptographic engine handling end-to-end encryption and digital signatures.
class SyncCipher {
  static final _cipher = AesGcm.with256bits();
  static final _signatureAlgorithm = Ed25519();
  static final _sha256 = Sha256();

  /// Encrypts plaintext bytes using AES-GCM-256 with an authenticated MAC tag.
  /// Returns concatenation of nonce, ciphertext, and MAC tag.
  static Future<Uint8List> encrypt(
    Uint8List plaintext,
    SecretKey secretKey,
  ) async {
    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: secretKey,
    );
    return secretBox.concatenation();
  }

  /// Decrypts a concatenated [nonce + ciphertext + mac] box.
  /// Throws [SecretBoxAuthenticationError] if the payload was tampered with.
  static Future<Uint8List> decrypt(
    Uint8List encryptedData,
    SecretKey secretKey,
  ) async {
    final secretBox = SecretBox.fromConcatenation(
      encryptedData,
      nonceLength: _cipher.nonceLength,
      macLength: _cipher.macAlgorithm.macLength,
    );
    final decrypted = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );
    return Uint8List.fromList(decrypted);
  }

  /// Signs the given payload with an Ed25519 private key.
  static Future<Uint8List> sign(
    Uint8List data,
    SimpleKeyPair keyPair,
  ) async {
    final signature = await _signatureAlgorithm.sign(
      data,
      keyPair: keyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies an Ed25519 digital signature against the public key.
  static Future<bool> verify({
    required Uint8List data,
    required Uint8List signatureBytes,
    required List<int> publicKeyBytes,
  }) async {
    try {
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      );
      return await _signatureAlgorithm.verify(
        data,
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  /// Computes SHA-256 hash of bytes.
  static Future<Uint8List> hash(List<int> data) async {
    final digest = await _sha256.hash(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// Derives an encryption secret key from master seed bytes.
  static Future<SecretKey> deriveEncryptionKey(List<int> seedBytes) async {
    // Hash seed with domain separator for encryption key
    final encInput = utf8.encode('kurox-p2p-sync-encryption-v1') + seedBytes;
    final keyBytes = await hash(encInput);
    return SecretKey(keyBytes);
  }

  /// Derives an Ed25519 keypair from master seed bytes.
  static Future<SimpleKeyPair> deriveSigningKeyPair(List<int> seedBytes) async {
    // Hash seed with domain separator for signing key
    final signInput = utf8.encode('kurox-p2p-sync-signing-v1') + seedBytes;
    final keySeed = (await hash(signInput)).sublist(0, 32);
    return await _signatureAlgorithm.newKeyPairFromSeed(keySeed);
  }
}
