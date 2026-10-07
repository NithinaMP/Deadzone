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

const _uuid = Uuid();

/// The one object screens actually talk to. Owns the keypair, listens to
/// the mesh for incoming payloads, decrypts anything addressed to us,
/// and exposes simple lists/methods for the UI.
///
/// PHASE 3: owns a MetricsService and the currently-active RoutingStrategy.
/// Every message this device originates gets tagged with whatever
/// strategy is active at send time, so switching strategy mid-session and
/// comparing on MetricsScreen works correctly.
class MeshProvider extends ChangeNotifier {
  final StorageService storage;
  late final MeshService mesh;
  final MetricsService metrics = MetricsService();

  late SimpleKeyPair _myKeyPair;
  String myDeviceId = '';
  String myDisplayName = 'Unnamed Device';

  RoutingStrategy _currentStrategy = FloodStrategy();
  String get currentStrategyName => _currentStrategy.name;

  List<PeerDevice> peers = [];
  final Map<String, List<ChatMessage>> _conversations = {};
  bool isMeshActive = false;

  MeshProvider({required this.storage}) {
    mesh = MeshService(storage: storage, metrics: metrics, initialStrategy: _currentStrategy);
  }

  Future<void> initialize({String? displayName}) async {
    _myKeyPair = await storage.getOrCreateIdentity();
    myDeviceId = storage.myDeviceId;
    myDisplayName = displayName ?? storage.myDisplayName ?? 'Device-${myDeviceId.substring(3, 7)}';
    await storage.setMyDisplayName(myDisplayName);

    mesh.peerStream.listen((updatedPeers) {
      peers = updatedPeers;
      notifyListeners();
    });

    mesh.incomingMessages.listen(_handleIncomingMessage);

    metrics.addListener(notifyListeners);
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

  Future<bool> sendTextMessage({
    required String peerId,
    required String plainText,
  }) async {
    final peer = peers.firstWhere((p) => p.id == peerId,
        orElse: () => PeerDevice(id: peerId, displayName: 'Unknown'));
    if (peer.publicKeyB64 == null) return false;

    final payload = await CryptoService.encrypt(
      plainText: plainText,
      senderKeyPair: _myKeyPair,
      recipientPublicKeyB64: peer.publicKeyB64!,
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