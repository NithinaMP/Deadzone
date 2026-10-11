import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../models/peer_device.dart';
import '../services/storage_service.dart';
import '../services/mesh_service.dart';
import '../services/crypto_service.dart';
import '../services/routing_strategy.dart';
import '../services/metrics_service.dart';
import '../services/battery_service.dart';

const _uuid = Uuid();

/// The key used for the group "Lobby" conversation.
const String lobbyKey = 'LOBBY';

const _adjectives = [
  'Sneaky', 'Sleepy', 'Jolly', 'Cosmic', 'Fuzzy', 'Zippy',
  'Mighty', 'Grumpy', 'Bouncy', 'Spicy', 'Cheeky', 'Wobbly',
];
const _animals = [
  'Panda', 'Otter', 'Llama', 'Penguin', 'Koala', 'Gecko',
  'Walrus', 'Narwhal', 'Hedgehog', 'Capybara', 'Quokka', 'Axolotl',
];

String _funName() {
  final r = Random();
  return '${_adjectives[r.nextInt(_adjectives.length)]} '
      '${_animals[r.nextInt(_animals.length)]}';
}

class MeshProvider extends ChangeNotifier {
  final StorageService storage;
  late final MeshService mesh;
  final MetricsService metrics = MetricsService();
  final BatteryService battery = BatteryService();

  late SimpleKeyPair _myKeyPair;
  String myDeviceId = '';
  String myDisplayName = 'Unnamed Device';

  RoutingStrategy _currentStrategy = FloodStrategy();
  String get currentStrategyName => _currentStrategy.name;

  List<PeerDevice> peers = [];
  final Map<String, List<ChatMessage>> _conversations = {};
  bool isMeshActive = false;

  int get outboxCount => mesh.outboxCount;
  Stream<List<String>> get relayActivity => mesh.relayActivity;

  MeshProvider({required this.storage}) {
    mesh = MeshService(
      storage: storage,
      metrics: metrics,
      battery: battery,
      initialStrategy: _currentStrategy,
    );
  }

  Future<void> initialize({String? displayName}) async {
    _myKeyPair = await storage.getOrCreateIdentity();
    myDeviceId = storage.myDeviceId;

    var name = displayName ?? storage.myDisplayName;
    if (name == null || name.startsWith('Device-')) {
      name = _funName(); // e.g. "Sneaky Panda"
    }
    myDisplayName = name;
    await storage.setMyDisplayName(myDisplayName);

    await _loadConversationsFromStorage();

    mesh.peerStream.listen((updatedPeers) {
      peers = updatedPeers;
      notifyListeners();
    });

    mesh.incomingMessages.listen(_handleIncomingMessage);
    metrics.addListener(notifyListeners);
  }

  /// Reload saved chats so they survive closing the app.
  Future<void> _loadConversationsFromStorage() async {
    for (final key in storage.getAllConversationKeys()) {
      final rawMessages = storage.getConversation(key);
      final restored = <ChatMessage>[];

      for (final raw in rawMessages) {
        late ChatMessage message;
        try {
          message = ChatMessage.fromWireJson(raw);
        } catch (_) {
          continue;
        }

        if (message.isBroadcast) {
          message.decryptedText = message.cipherTextB64;
        } else if (message.senderId == myDeviceId) {
          // We sent this one, so use the other person's public key.
          final peerPublicKey = storage.getPeer(key)?['publicKey'] as String?;
          if (peerPublicKey != null) {
            message.decryptedText = await CryptoService.decrypt(
              payload: EncryptedPayload(
                cipherTextB64: message.cipherTextB64,
                nonceB64: message.nonceB64,
                macB64: message.macB64,
              ),
              receiverKeyPair: _myKeyPair,
              senderPublicKeyB64: peerPublicKey,
            );
          }
        } else {
          message.decryptedText = await CryptoService.decrypt(
            payload: EncryptedPayload(
              cipherTextB64: message.cipherTextB64,
              nonceB64: message.nonceB64,
              macB64: message.macB64,
            ),
            receiverKeyPair: _myKeyPair,
            senderPublicKeyB64: message.senderPublicKeyB64,
          );
        }
        restored.add(message);
      }
      _conversations[key] = restored;
    }
  }

  /// Lets the Profile page suggest a fun random name (the 🎲 button).
  String suggestFunName() => _funName();

  /// Changes your name, saves it, and tells friends who are nearby.
  Future<void> updateDisplayName(String newName) async {
    final cleaned = newName.trim();
    if (cleaned.isEmpty) return;
    myDisplayName = cleaned;
    await storage.setMyDisplayName(cleaned);
    mesh.announceNewName(cleaned);
    notifyListeners();
  }

  bool get hasOnboarded => storage.hasOnboarded;

  /// Called by the welcome screen: saves your name and marks setup done.
  Future<void> completeOnboarding(String name) async {
    await updateDisplayName(name);
    await storage.setOnboarded();
  }

  Future<void> startMesh() async {
    final myPublicKeyB64 = await storage.getMyPublicKeyB64();
    await mesh.startAdvertisingAndDiscovery(
      myDisplayName,
      myPublicKeyB64: myPublicKeyB64,
    );
    isMeshActive = true;
    notifyListeners();
  }

  Future<void> stopMesh() async {
    await mesh.stop();
    isMeshActive = false;
    notifyListeners();
  }

  void switchStrategy(RoutingStrategy strategy) {
    _currentStrategy = strategy;
    mesh.setRoutingStrategy(strategy);
    notifyListeners();
  }

  List<ChatMessage> conversationWith(String key) =>
      _conversations[key] ?? [];

  /// Finds the nearby phone with this permanent device id.
  /// Prefers one that's actually connected right now.
  PeerDevice? livePeerFor(String deviceId) {
    PeerDevice? found;
    for (final p in peers) {
      if (p.deviceId == deviceId) {
        if (p.status == PeerStatus.connected) return p;
        found ??= p;
      }
    }
    return found;
  }

  /// Everyone we've ever said hello to, in range or not.
  List<PeerDevice> getAllContacts() {
    final stored = storage.getAllPeersMap();
    final result = <PeerDevice>[];
    final seen = <String>{};

    for (final entry in stored.entries) {
      seen.add(entry.key);
      final live = livePeerFor(entry.key);
      if (live != null) {
        result.add(live);
      } else {
        result.add(PeerDevice(
          id: '',
          deviceId: entry.key,
          displayName:
          entry.value['displayName'] as String? ?? 'Unknown friend',
          publicKeyB64: entry.value['publicKey'] as String?,
          status: PeerStatus.lost,
          isDirect: false,
        ));
      }
    }

    for (final p in peers) {
      final id = p.deviceId;
      if (id != null && !seen.contains(id) && p.publicKeyB64 != null) {
        seen.add(id);
        result.add(p);
      }
    }
    return result;
  }

  Future<bool> sendTextMessage({
    required String peerDeviceId,
    required String plainText,
  }) async {
    String? publicKeyB64 = livePeerFor(peerDeviceId)?.publicKeyB64;
    publicKeyB64 ??= storage.getPeer(peerDeviceId)?['publicKey'] as String?;
    if (publicKeyB64 == null) return false;

    final payload = await CryptoService.encrypt(
      plainText: plainText,
      senderKeyPair: _myKeyPair,
      recipientPublicKeyB64: publicKeyB64,
    );
    final myPubKeyB64 = await storage.getMyPublicKeyB64();

    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: myDeviceId,
      senderName: myDisplayName,
      receiverId: peerDeviceId,
      cipherTextB64: payload.cipherTextB64,
      nonceB64: payload.nonceB64,
      macB64: payload.macB64,
      senderPublicKeyB64: myPubKeyB64,
      sentAt: DateTime.now(),
      ttl: 8,
      strategyTag: _currentStrategy.name,
    )..decryptedText = plainText;

    _conversations.putIfAbsent(peerDeviceId, () => []).add(message);
    await storage.saveMessage(peerDeviceId, message.toWireJson());
    await mesh.sendMessage(message);
    notifyListeners();
    return true;
  }

  /// A message to the Lobby: everyone nearby with Deadzone open sees it.
  /// (Not private, so it isn't encrypted to one person.)
  Future<void> sendLobbyMessage(String plainText) async {
    final myPubKeyB64 = await storage.getMyPublicKeyB64();
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: myDeviceId,
      senderName: myDisplayName,
      receiverId: lobbyKey,
      cipherTextB64: plainText,
      nonceB64: '',
      macB64: '',
      senderPublicKeyB64: myPubKeyB64,
      sentAt: DateTime.now(),
      ttl: 16,
      isBroadcast: true,
      strategyTag: _currentStrategy.name,
    )..decryptedText = plainText;

    _conversations.putIfAbsent(lobbyKey, () => []).add(message);
    await storage.saveMessage(lobbyKey, message.toWireJson());
    await mesh.sendMessage(message);
    notifyListeners();
  }

  Future<void> _handleIncomingMessage(ChatMessage message) async {
    if (message.isBroadcast) {
      message.decryptedText = message.cipherTextB64;
    } else {
      message.decryptedText = await CryptoService.decrypt(
        payload: EncryptedPayload(
          cipherTextB64: message.cipherTextB64,
          nonceB64: message.nonceB64,
          macB64: message.macB64,
        ),
        receiverKeyPair: _myKeyPair,
        senderPublicKeyB64: message.senderPublicKeyB64,
      );
      if (message.decryptedText == null) return;
    }

    final convoKey = message.isBroadcast ? lobbyKey : message.senderId;
    _conversations.putIfAbsent(convoKey, () => []).add(message);
    await storage.saveMessage(convoKey, message.toWireJson());
    notifyListeners();
  }

  @override
  void dispose() {
    mesh.dispose();
    metrics.removeListener(notifyListeners);
    super.dispose();
  }
}