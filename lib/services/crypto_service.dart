import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// This is the file that answers "but can B and C read my message?" — no.
///
/// How it works:
/// 1. Every device generates its own X25519 keypair on first launch.
/// 2. To send a message, the sender does an ECDH key exchange with the
///    *recipient's* public key, deriving a shared secret only the sender
///    and the intended recipient can ever compute.
/// 3. That shared secret becomes an AES-GCM key used to encrypt the message.
/// 4. Every relay in between only ever sees the ciphertext — they don't
///    have the recipient's private key, so they can't derive the same
///    shared secret, so they can't decrypt. They're just carrying bytes.
class CryptoService {
  static final _algorithm = X25519();
  static final _aesGcm = AesGcm.with256bits();

  /// Call once per device, store the result (private key never leaves
  /// local storage, public key is safe to share with anyone).
  static Future<SimpleKeyPair> generateKeyPair() {
    return _algorithm.newKeyPair();
  }

  static Future<String> publicKeyToB64(SimpleKeyPair keyPair) async {
    final pub = await keyPair.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  static SimplePublicKey publicKeyFromB64(String b64) {
    return SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);
  }

  /// Encrypts [plainText] so that only the holder of the private key
  /// matching [recipientPublicKeyB64] can read it.
  static Future<EncryptedPayload> encrypt({
    required String plainText,
    required SimpleKeyPair senderKeyPair,
    required String recipientPublicKeyB64,
  }) async {
    final recipientPubKey = publicKeyFromB64(recipientPublicKeyB64);

    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: senderKeyPair,
      remotePublicKey: recipientPubKey,
    );

    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: sharedSecret,
      nonce: nonce,
    );

    return EncryptedPayload(
      cipherTextB64: base64Encode(secretBox.cipherText),
      nonceB64: base64Encode(secretBox.nonce),
      macB64: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Reverses [encrypt]. Only succeeds if this device's [receiverKeyPair]
  /// is the actual intended recipient — any other device trying this with
  /// its own keypair gets a different shared secret and decryption fails.
  static Future<String?> decrypt({
    required EncryptedPayload payload,
    required SimpleKeyPair receiverKeyPair,
    required String senderPublicKeyB64,
  }) async {
    try {
      final senderPubKey = publicKeyFromB64(senderPublicKeyB64);

      final sharedSecret = await _algorithm.sharedSecretKey(
        keyPair: receiverKeyPair,
        remotePublicKey: senderPubKey,
      );

      final secretBox = SecretBox(
        base64Decode(payload.cipherTextB64),
        nonce: base64Decode(payload.nonceB64),
        mac: Mac(base64Decode(payload.macB64)),
      );

      final clearBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: sharedSecret,
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      // Wrong key, corrupted payload, or (if you're a relay) just not
      // meant for you. Fail closed, never throw raw crypto errors to UI.
      return null;
    }
  }
}

class EncryptedPayload {
  final String cipherTextB64;
  final String nonceB64;
  final String macB64;

  EncryptedPayload({
    required this.cipherTextB64,
    required this.nonceB64,
    required this.macB64,
  });
}