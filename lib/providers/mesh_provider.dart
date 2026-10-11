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
    myDisplayName = displayName ?? storage.myDisplayName ?? 'Device-${myDeviceId.substring(3, 7)}';
    await storage.setMyDisplayName(myDisplayName);

    await _loadConversationsFromStorage();

    mesh.peerStream.listen((updatedPeers) {
      peers = updatedPeers;
      notifyListeners();
    });

    mesh.incomingMessages.listen(_handleIncomingMessage);
    metrics.addListener(notifyListeners);
  }

  /// MOD #4: for each stored conversation, re-decrypt every message so
  /// the UI has readable text again, not just ciphertext.
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
          final peerData = storage.getPeer(key);
          final peerPublicKey = peerData?['publicKey'] as String?;
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

  List<ChatMessage> conversationWith(String peerId) =>
      _conversations[peerId] ?? [];

  List<PeerDevice> getAllContacts() {
    final storedMap = storage.getAllPeersMap();
    final result = <PeerDevice>[];

    for (final entry in storedMap.entries) {
      final livePeer = peers.where((p) => p.id == entry.key);
      if (livePeer.isNotEmpty) {
        result.add(livePeer.first);
      } else {
        result.add(PeerDevice(
          id: entry.key,
          displayName: entry.value['displayName'] as String? ?? 'Unknown device',
          publicKeyB64: entry.value['publicKey'] as String?,
          status: PeerStatus.lost,
          isDirect: false,
        ));
      }
    }

    for (final p in peers) {
      if (!storedMap.containsKey(p.id) && p.publicKeyB64 != null) {
        result.add(p);
      }
    }

    return result;
  }

  Future<bool> sendTextMessage({
    required String peerId,
    required String plainText,
  }) async {
    String? publicKeyB64;
    final live = peers.where((p) => p.id == peerId && p.publicKeyB64 != null);
    if (live.isNotEmpty) {
      publicKeyB64 = live.first.publicKeyB64;
    } else {
      final stored = storage.getPeer(peerId);
      publicKeyB64 = stored?['publicKey'] as String?;
    }
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
      receiverId: peerId,
      cipherTextB64: payload.cipherTextB64,
      nonceB64: payload.nonceB64,
      macB64: payload.macB64,
      senderPublicKeyB64: myPubKeyB64,
      sentAt: DateTime.now(),
      ttl: 8,
      strategyTag: _currentStrategy.name,
    )..decryptedText = plainText;

    _conversations.putIfAbsent(peerId, () => []).add(message);
    await storage.saveMessage(peerId, message.toWireJson());
    await mesh.sendMessage(message);
    notifyListeners();
    return true;
  }

  Future<void> sendBroadcast(String plainText) async {
    final myPubKeyB64 = await storage.getMyPublicKeyB64();
    final message = ChatMessage(
      id: _uuid.v4(),
      senderId: myDeviceId,
      receiverId: 'BROADCAST',
      cipherTextB64: plainText,
      nonceB64: '',
      macB64: '',
      senderPublicKeyB64: myPubKeyB64,
      sentAt: DateTime.now(),
      ttl: 16,
      isBroadcast: true,
      strategyTag: _currentStrategy.name,
    )..decryptedText = plainText;

    _conversations.putIfAbsent('BROADCAST', () => []).add(message);
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

    final convoKey = message.isBroadcast ? 'BROADCAST' : message.senderId;
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