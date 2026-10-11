import 'dart:async';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/chat_message.dart';
import '../models/peer_device.dart';
import '../models/mesh_envelope.dart';
import 'storage_service.dart';
import 'routing_strategy.dart';
import 'metrics_service.dart';
import 'battery_service.dart';
import 'dart:typed_data';

class _PendingSend {
  final DateTime sentAt;
  final String strategyTag;
  _PendingSend(this.sentAt, this.strategyTag);
}

/// THIS VERSION bundles three modifications on top of Phase 3:
///  - MOD #1 (outbox): if sendMessage() has zero live connections right
///    now, the message queues in `_outbox` instead of being silently
///    lost, and auto-flushes the moment any peer connects.
///  - MOD #2 (topology activity): `relayActivity` emits every time a
///    chat envelope is actually sent/relayed to specific peer ids, so
///    TopologyScreen can animate real traffic instead of faking it.
///  - MOD #3 (battery-aware relay): before forwarding someone ELSE's
///    message onward, checks battery via BatteryService — if low,
///    still delivers locally if addressed to us, still sends our own
///    outgoing messages, but stops acting as a relay for others.
class MeshService {
  static const String _serviceId = 'com.deadzone.mesh';
  final Strategy _strategy = Strategy.P2P_CLUSTER;

  final StorageService storage;
  final MetricsService metrics;
  final BatteryService battery;
  RoutingStrategy routingStrategy;

  MeshService({
    required this.storage,
    required this.metrics,
    required this.battery,
    RoutingStrategy? initialStrategy,
  }) : routingStrategy = initialStrategy ?? FloodStrategy();

  void setRoutingStrategy(RoutingStrategy strategy) {
    routingStrategy = strategy;
  }

  String _myPublicKeyB64 = '';
  String _myDisplayName = '';

  final Map<String, _PendingSend> _pendingSends = {};
  final List<ChatMessage> _outbox = [];
  int get outboxCount => _outbox.length;

  final _peersController = StreamController<List<PeerDevice>>.broadcast();
  final _incomingMessageController = StreamController<ChatMessage>.broadcast();
  final _activityController = StreamController<List<String>>.broadcast();

  Stream<List<PeerDevice>> get peerStream => _peersController.stream;
  Stream<ChatMessage> get incomingMessages => _incomingMessageController.stream;
  Stream<List<String>> get relayActivity => _activityController.stream;

  final Map<String, PeerDevice> _peers = {};

  Future<void> startAdvertisingAndDiscovery(
      String myDisplayName, {
        required String myPublicKeyB64,
      }) async {
    _myDisplayName = myDisplayName;
    _myPublicKeyB64 = myPublicKeyB64;

    await Nearby().startAdvertising(
      myDisplayName,
      _strategy,
      serviceId: _serviceId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );

    await Nearby().startDiscovery(
      myDisplayName,
      _strategy,
      serviceId: _serviceId,
      onEndpointFound: (id, name, serviceId) {
        _peers[id] = PeerDevice(id: id, displayName: name);
        _emitPeers();
        Nearby().requestConnection(
          myDisplayName,
          id,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: _onConnectionResult,
          onDisconnected: _onDisconnected,
        );
      },
      onEndpointLost: (id) {
        if (id != null) {
          _peers[id]?.status = PeerStatus.lost;
          _emitPeers();
        }
      },
    );
  }

  Future<void> stop() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    _peers[id] ??= PeerDevice(id: id, displayName: info.endpointName);
    _peers[id]!.status = PeerStatus.connecting;
    _emitPeers();
    Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived);
  }

  void _onConnectionResult(String id, Status status) {
    if (_peers[id] == null) return;
    _peers[id]!.status =
    status == Status.CONNECTED ? PeerStatus.connected : PeerStatus.lost;
    _emitPeers();
    if (status == Status.CONNECTED) {
      _sendHandshake(id);
      _flushOutbox();
    }
  }

  void _sendHandshake(String toEndpointId) {
    final envelope = MeshEnvelope(
      type: MeshEnvelope.typeHandshake,
      data: {'publicKey': _myPublicKeyB64, 'displayName': _myDisplayName},
    );
    final bytes = Uint8List.fromList(envelope.encode().codeUnits);
    Nearby().sendBytesPayload(toEndpointId, bytes);  }

  void _onDisconnected(String id) {
    _peers[id]?.status = PeerStatus.lost;
    _emitPeers();
  }

  void _emitPeers() => _peersController.add(_peers.values.toList());

  void _onPayloadReceived(String fromEndpointId, Payload payload) async {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    final raw = String.fromCharCodes(payload.bytes!);
    late MeshEnvelope envelope;
    try {
      envelope = MeshEnvelope.decode(raw);
    } catch (_) {
      return;
    }

    switch (envelope.type) {
      case MeshEnvelope.typeHandshake:
        _handleHandshake(fromEndpointId, envelope.data);
        break;
      case MeshEnvelope.typeChat:
        await _handleChatEnvelope(fromEndpointId, envelope.data);
        break;
      case MeshEnvelope.typeAck:
        _handleAckEnvelope(fromEndpointId, envelope.data);
        break;
    }
  }

  void _handleHandshake(String fromEndpointId, Map<String, dynamic> data) {
    final peer = _peers[fromEndpointId];
    if (peer == null) return;
    peer.publicKeyB64 = data['publicKey'] as String;
    peer.displayName = data['displayName'] as String? ?? peer.displayName;
    storage.savePeer(fromEndpointId, {
      'publicKey': peer.publicKeyB64,
      'displayName': peer.displayName,
    });
    _emitPeers();
  }

  Future<void> _handleChatEnvelope(
      String fromEndpointId,
      Map<String, dynamic> data,
      ) async {
    late ChatMessage message;
    try {
      message = ChatMessage.fromWireJson(data);
    } catch (_) {
      return;
    }

    if (storage.hasSeenMessage(message.id)) {
      metrics.recordDuplicateDropped(message.strategyTag);
      return;
    }
    await storage.markMessageSeen(message.id);

    final myId = storage.myDeviceId;
    final isForMe = message.receiverId == myId || message.isBroadcast;

    if (isForMe) {
      _incomingMessageController.add(message);
      if (!message.isBroadcast) {
        _sendAck(originalMessage: message);
      }
    }

    if (message.ttl > 1 && !(await battery.isBatteryLow())) {
      final eligible = _peers.values
          .where((p) => p.id != fromEndpointId && p.status == PeerStatus.connected)
          .toList();
      final targets = routingStrategy.selectRelayTargets(
        eligiblePeers: eligible,
        message: message,
      );
      if (targets.isNotEmpty) {
        metrics.recordRelayed(message.strategyTag);
        _activityController.add(targets.map((p) => p.id).toList());
      }
      _sendEnvelopeTo(
        targets,
        MeshEnvelope(
          type: MeshEnvelope.typeChat,
          data: message.copyWithTtl(message.ttl - 1).toWireJson(),
        ),
      );
    }
  }

  void _sendAck({required ChatMessage originalMessage}) {
    final ackEnvelope = MeshEnvelope(
      type: MeshEnvelope.typeAck,
      data: {
        'originalMessageId': originalMessage.id,
        'to': originalMessage.senderId,
        'from': storage.myDeviceId,
        'ttl': 8,
      },
    );
    final eligible = _peers.values.where((p) => p.status == PeerStatus.connected).toList();
    _sendEnvelopeTo(eligible, ackEnvelope);
  }

  void _handleAckEnvelope(String fromEndpointId, Map<String, dynamic> data) {
    final ackDedupId = 'ack-${data['originalMessageId']}-${data['from']}';
    if (storage.hasSeenMessage(ackDedupId)) return;
    storage.markMessageSeen(ackDedupId);

    final myId = storage.myDeviceId;
    if (data['to'] == myId) {
      final pending = _pendingSends.remove(data['originalMessageId']);
      if (pending != null) {
        final latency = DateTime.now().difference(pending.sentAt).inMilliseconds;
        metrics.recordDelivered(pending.strategyTag, latency);
      }
      return;
    }

    final ttl = (data['ttl'] as int?) ?? 1;
    if (ttl > 1) {
      final forwarded = Map<String, dynamic>.from(data)..['ttl'] = ttl - 1;
      final eligible = _peers.values
          .where((p) => p.id != fromEndpointId && p.status == PeerStatus.connected)
          .toList();
      _sendEnvelopeTo(eligible, MeshEnvelope(type: MeshEnvelope.typeAck, data: forwarded));
    }
  }

  void _sendEnvelopeTo(List<PeerDevice> targets, MeshEnvelope envelope) {
    final bytes = Uint8List.fromList(envelope.encode().codeUnits);

    for (final peer in targets) {
      Nearby().sendBytesPayload(peer.id, bytes);
    }
  }

  Future<void> sendMessage(ChatMessage message) async {
    await storage.markMessageSeen(message.id);
    if (!message.isBroadcast) {
      _pendingSends[message.id] = _PendingSend(DateTime.now(), message.strategyTag);
    }
    metrics.recordSent(message.strategyTag);

    final connected = _peers.values.where((p) => p.status == PeerStatus.connected).toList();
    final targets = routingStrategy.selectRelayTargets(eligiblePeers: connected, message: message);

    if (targets.isEmpty) {
      _outbox.add(message);
      _emitPeers();
      return;
    }

    _activityController.add(targets.map((p) => p.id).toList());
    _sendEnvelopeTo(targets, MeshEnvelope(type: MeshEnvelope.typeChat, data: message.toWireJson()));
  }

  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    final connected = _peers.values.where((p) => p.status == PeerStatus.connected).toList();
    if (connected.isEmpty) return;

    final stillPending = <ChatMessage>[];
    for (final message in _outbox) {
      final targets = routingStrategy.selectRelayTargets(eligiblePeers: connected, message: message);
      if (targets.isEmpty) {
        stillPending.add(message);
      } else {
        _activityController.add(targets.map((p) => p.id).toList());
        _sendEnvelopeTo(targets, MeshEnvelope(type: MeshEnvelope.typeChat, data: message.toWireJson()));
      }
    }
    _outbox
      ..clear()
      ..addAll(stillPending);
    _emitPeers();
  }

  void dispose() {
    _peersController.close();
    _incomingMessageController.close();
    _activityController.close();
  }
}