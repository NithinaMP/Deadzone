import 'package:hive_flutter/hive_flutter.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import '../services/crypto_service.dart';

/// All local-only persistence. Nothing in here ever touches a network —
/// that's the whole point. Four boxes:
///  - `identity`   : this device's own keypair (generated once, kept forever)
///  - `messages`   : chat history, keyed by conversation peer id
///  - `peers`      : known peers + their public keys, for quick lookup
///  - `seenCache`  : message IDs already relayed, so we never re-flood the
///                   same message twice (this is the dedup mechanism)
class StorageService {
  static const _identityBox = 'identity';
  static const _messagesBox = 'messages';
  static const _peersBox = 'peers';
  static const _seenCacheBox = 'seen_cache';

  late Box _identity;
  late Box _messages;
  late Box _peers;
  late Box _seenCache;

  Future<void> init() async {
    await Hive.initFlutter();
    _identity = await Hive.openBox(_identityBox);
    _messages = await Hive.openBox(_messagesBox);
    _peers = await Hive.openBox(_peersBox);
    _seenCache = await Hive.openBox(_seenCacheBox);
  }

  // ---------- Identity (this device's keypair) ----------

  /// Returns the existing keypair, or generates + persists a new one on
  /// first run. Private key material stored as raw bytes, base64-encoded.
  Future<SimpleKeyPair> getOrCreateIdentity() async {
    final existingPrivate = _identity.get('privateKeyB64');
    if (existingPrivate != null) {
      final bytes = base64Decode(existingPrivate);
      return SimpleKeyPairData(
        bytes,
        publicKey: SimplePublicKey(
          base64Decode(_identity.get('publicKeyB64')),
          type: KeyPairType.x25519,
        ),
        type: KeyPairType.x25519,
      );
    }

    final newPair = await CryptoService.generateKeyPair();
    final privateBytes = await newPair.extractPrivateKeyBytes();
    final publicB64 = await CryptoService.publicKeyToB64(newPair);

    await _identity.put('privateKeyB64', base64Encode(privateBytes));
    await _identity.put('publicKeyB64', publicB64);
    return newPair;
  }

  Future<String> getMyPublicKeyB64() async {
    final key = _identity.get('publicKeyB64');
    if (key != null) return key;
    await getOrCreateIdentity();
    return _identity.get('publicKeyB64');
  }

  String get myDeviceId {
    var id = _identity.get('deviceId');
    if (id == null) {
      id = 'dz-${DateTime.now().millisecondsSinceEpoch}';
      _identity.put('deviceId', id);
    }
    return id;
  }

  String? get myDisplayName => _identity.get('displayName');
  Future<void> setMyDisplayName(String name) =>
      _identity.put('displayName', name);

  // ---------- Messages ----------

  /// Conversation key is the *other* peer's id (or 'BROADCAST').
  Future<void> saveMessage(String conversationKey, Map<String, dynamic> messageJson) async {
    final list = (_messages.get(conversationKey) as List?) ?? [];
    list.add(messageJson);
    await _messages.put(conversationKey, list);
  }

  List<Map<String, dynamic>> getConversation(String conversationKey) {
    final list = (_messages.get(conversationKey) as List?) ?? [];
    return list
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  List<String> getAllConversationKeys() => _messages.keys.cast<String>().toList();

  // ---------- Peers ----------

  Future<void> savePeer(String peerId, Map<String, dynamic> peerJson) =>
      _peers.put(peerId, peerJson);

  Map<String, dynamic>? getPeer(String peerId) =>
      (_peers.get(peerId) as Map?)?.cast<String, dynamic>();

  List<Map<String, dynamic>> getAllPeers() =>
      _peers.values.cast<Map<String, dynamic>>().toList();

  /// Same data as getAllPeers(), but keyed by peer id — needed so the
  /// Contacts screen can open a chat with someone even when they're
  /// not currently in the live `peers` list from MeshService.
  Map<String, Map<String, dynamic>> getAllPeersMap() {
    final result = <String, Map<String, dynamic>>{};
    for (final key in _peers.keys) {
      final value = (_peers.get(key) as Map?)?.cast<String, dynamic>();
      if (value != null) result[key.toString()] = value;
    }
    return result;
  }

  // ---------- Seen-message dedup cache ----------
  // This is what stops the mesh from flooding the same message forever.

  bool hasSeenMessage(String messageId) => _seenCache.containsKey(messageId);

  Future<void> markMessageSeen(String messageId) async {
    await _seenCache.put(messageId, DateTime.now().toIso8601String());
    if (_seenCache.length > 2000) {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final staleKeys = _seenCache.keys.where((k) {
        final ts = DateTime.tryParse(_seenCache.get(k) ?? '');
        return ts == null || ts.isBefore(cutoff);
      }).toList();
      await _seenCache.deleteAll(staleKeys);
    }
  }
}