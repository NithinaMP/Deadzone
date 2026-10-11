import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import '../models/chat_message.dart';
import '../models/peer_device.dart';
import '../models/mesh_envelope.dart';
import 'storage_service.dart';
import 'routing_strategy.dart';
import 'metrics_service.dart';
import 'battery_service.dart';

/// Debug lines show up in the Android Studio "Run" console.
void _log(String message) => debugPrint('[Deadzone] $message');

class _PendingSend {
  final DateTime sentAt;
  final String strategyTag;
  _PendingSend(this.sentAt, this.strategyTag);
}

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

  String _myDeviceId = '';
  String _myPublicKeyB64 = '';
  String _myDisplayName = '';
  bool _active = false;

  final Map<String, int> _retryCount = {};
  final Map<String, _PendingSend> _pendingSends = {};
  final List<ChatMessage> _outbox = [];
  int get outboxCount => _outbox.length;

  final _peersController = StreamController<List<PeerDevice>>.broadcast();
  final _incomingMessageController = StreamController<ChatMessage>.broadcast();
  final _activityController = StreamController<List<String>>.broadcast();

  Stream<List<PeerDevice>> get peerStream => _peersController.stream;
  Stream<ChatMessage> get incomingMessages => _incomingMessageController.stream;
  Stream<List<String>> get relayActivity => _activityController.stream;

  // key = temporary connection id (only meaningful on this phone)
  final Map<String, PeerDevice> _peers = {};

  List<PeerDevice> get _connectedPeers =>
      _peers.values.where((p) => p.status == PeerStatus.connected).toList();

  // ---------------------------------------------------------------
  // Start / stop
  // ---------------------------------------------------------------

  Future<void> startAdvertisingAndDiscovery(
      String myDisplayName, {
        required String myPublicKeyB64,
      }) async {
    _myDisplayName = myDisplayName;
    _myPublicKeyB64 = myPublicKeyB64;
    _myDeviceId = storage.myDeviceId;
    _active = true;
    _log('starting as "$_myDisplayName" ($_myDeviceId)');

    // We advertise our permanent device id as our "nickname". That way a
    // phone that finds us immediately knows who we are, and both phones
    // can agree on who starts the connection (see onEndpointFound).
    try {
      await Nearby().startAdvertising(
        _myDeviceId,
        _strategy,
        serviceId: _serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _log('startAdvertising failed: $e');
    }

    try {
      await Nearby().startDiscovery(
        _myDeviceId,
        _strategy,
        serviceId: _serviceId,
        onEndpointFound: (id, name, serviceId) {
          _log('found endpoint $id (device $name)');
          final peer = _peers[id] ??
              PeerDevice(id: id, deviceId: name, displayName: 'New friend');
          peer.deviceId = name;
          if (peer.status == PeerStatus.lost) {
            peer.status = PeerStatus.discovered;
          }
          _peers[id] = peer;
          _dropStaleEntriesFor(peer);
          _emitPeers();

          // Only ONE phone should start the connection, otherwise both
          // phones request each other at once and it can half-fail.
          // Rule: the phone with the smaller device id starts it.
          if (_myDeviceId.compareTo(name) < 0) {
            _requestConnectionTo(id);
          }
        },
        onEndpointLost: (id) {
          if (id == null) return;
          final peer = _peers[id];
          if (peer != null && peer.status != PeerStatus.connected) {
            peer.status = PeerStatus.lost;
            _emitPeers();
          }
        },
      );
    } catch (e) {
      _log('startDiscovery failed: $e');
    }
  }

  Future<void> stop() async {
    _active = false;
    try {
      await Nearby().stopAdvertising();
    } catch (_) {}
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    try {
      await Nearby().stopAllEndpoints();
    } catch (_) {}
    _peers.clear();
    _retryCount.clear();
    _emitPeers();
  }

  // ---------------------------------------------------------------
  // Connecting
  // ---------------------------------------------------------------

  Future<void> _requestConnectionTo(String endpointId) async {
    try {
      _log('requesting connection to $endpointId');
      await Nearby().requestConnection(
        _myDeviceId,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _log('requestConnection failed: $e');
      _retryIfInitiator(endpointId);
    }
  }

  void _retryIfInitiator(String endpointId) {
    final peer = _peers[endpointId];
    if (!_active || peer == null || peer.deviceId == null) return;
    if (_myDeviceId.compareTo(peer.deviceId!) >= 0) return; // not our job
    final tries = _retryCount[endpointId] ?? 0;
    if (tries >= 3) return;
    _retryCount[endpointId] = tries + 1;
    Future.delayed(const Duration(seconds: 3), () {
      final p = _peers[endpointId];
      if (!_active || p == null || p.status == PeerStatus.connected) return;
      _requestConnectionTo(endpointId);
    });
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    _log('connection initiated with $id (${info.endpointName})');
    final peer = _peers[id] ??
        PeerDevice(
          id: id,
          deviceId: info.endpointName,
          displayName: 'New friend',
        );
    peer.deviceId ??= info.endpointName;
    peer.status = PeerStatus.connecting;
    _peers[id] = peer;
    _dropStaleEntriesFor(peer);
    _emitPeers();
    Nearby().acceptConnection(id, onPayLoadRecieved: _onPayloadReceived);
  }

  void _onConnectionResult(String id, Status status) {
    _log('connection result for $id: $status');
    final peer = _peers[id];
    if (peer == null) return;

    if (status == Status.CONNECTED) {
      peer.status = PeerStatus.connected;
      _retryCount.remove(id);
      _emitPeers();
      _sendHandshake(id);
      _flushOutbox();
    } else {
      peer.status = PeerStatus.lost;
      _emitPeers();
      _retryIfInitiator(id);
    }
  }

  void _onDisconnected(String id) {
    _log('disconnected from $id');
    final peer = _peers[id];
    if (peer == null) return;
    peer.status = PeerStatus.lost;
    _emitPeers();
    _retryCount[id] = 0;
    _retryIfInitiator(id);
  }

  /// If the same phone shows up again with a new temporary id, forget the
  /// old dead entries so we don't list one friend twice.
  void _dropStaleEntriesFor(PeerDevice p) {
    _peers.removeWhere((key, other) =>
    key != p.id &&
        other.deviceId != null &&
        other.deviceId == p.deviceId &&
        other.status != PeerStatus.connected);
  }

  /// Tell everyone we're connected to that our name changed.
  /// (We just send our handshake again, since it carries the name.)
  void announceNewName(String newName) {
    _myDisplayName = newName;
    for (final peer in _connectedPeers) {
      _sendHandshake(peer.id);
    }
  }

  void _sendHandshake(String toEndpointId) {
    final envelope = MeshEnvelope(
      type: MeshEnvelope.typeHandshake,
      data: {
        'publicKey': _myPublicKeyB64,
        'displayName': _myDisplayName,
        'deviceId': _myDeviceId,
      },
    );
    _sendEnvelopeTo([_peers[toEndpointId]!], envelope);
  }

  void _emitPeers() {
    if (!_peersController.isClosed) {
      _peersController.add(_peers.values.toList());
    }
  }

  // ---------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------

  void _onPayloadReceived(String fromEndpointId, Payload payload) async {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    late MeshEnvelope envelope;
    try {
      envelope = MeshEnvelope.decode(utf8.decode(payload.bytes!));
    } catch (e) {
      _log('could not read payload from $fromEndpointId: $e');
      return;
    }
    _log('received ${envelope.type} from $fromEndpointId');

    try {
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
    } catch (e) {
      _log('error while handling ${envelope.type}: $e');
    }
  }

  void _handleHandshake(String fromEndpointId, Map<String, dynamic> data) {
    final peer = _peers[fromEndpointId];
    if (peer == null) return;
    peer.publicKeyB64 = data['publicKey'] as String?;
    peer.displayName = (data['displayName'] as String?) ?? peer.displayName;
    peer.deviceId = (data['deviceId'] as String?) ?? peer.deviceId;
    _dropStaleEntriesFor(peer);

    if (peer.deviceId != null && peer.publicKeyB64 != null) {
      storage.savePeer(peer.deviceId!, {
        'publicKey': peer.publicKeyB64,
        'displayName': peer.displayName,
      });
    }
    _log('handshake done with ${peer.displayName} (${peer.deviceId})');
    _emitPeers();
  }

  Future<bool> _isBatteryLow() async {
    try {
      return await battery.isBatteryLow();
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleChatEnvelope(
      String fromEndpointId,
      Map<String, dynamic> data,
      ) async {
    late ChatMessage message;
    try {
      message = ChatMessage.fromWireJson(data);
    } catch (e) {
      _log('bad chat message: $e');
      return;
    }

    if (storage.hasSeenMessage(message.id)) {
      metrics.recordDuplicateDropped(message.strategyTag);
      return;
    }
    await storage.markMessageSeen(message.id);

    final isForMe =
        message.receiverId == storage.myDeviceId || message.isBroadcast;
    _log('chat message ${message.id.substring(0, 6)} '
        'for me: $isForMe (to ${message.receiverId})');

    if (isForMe) {
      _incomingMessageController.add(message);
      if (!message.isBroadcast) {
        _sendAck(originalMessage: message);
      }
    }

    // Pass it on to others (this is the "hopping" part), unless our
    // battery is low. We never skip our own messages, only other people's.
    if (message.ttl > 1 && !(await _isBatteryLow())) {
      final eligible =
      _connectedPeers.where((p) => p.id != fromEndpointId).toList();
      final targets = routingStrategy.selectRelayTargets(
        eligiblePeers: eligible,
        message: message,
      );
      if (targets.isNotEmpty) {
        metrics.recordRelayed(message.strategyTag);
        _activityController.add(targets.map((p) => p.id).toList());
        _sendEnvelopeTo(
          targets,
          MeshEnvelope(
            type: MeshEnvelope.typeChat,
            data: message.copyWithTtl(message.ttl - 1).toWireJson(),
          ),
        );
      }
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
    _sendEnvelopeTo(_connectedPeers, ackEnvelope);
  }

  void _handleAckEnvelope(String fromEndpointId, Map<String, dynamic> data) {
    final ackDedupId = 'ack-${data['originalMessageId']}-${data['from']}';
    if (storage.hasSeenMessage(ackDedupId)) return;
    storage.markMessageSeen(ackDedupId);

    if (data['to'] == storage.myDeviceId) {
      final pending = _pendingSends.remove(data['originalMessageId']);
      if (pending != null) {
        final latency =
            DateTime.now().difference(pending.sentAt).inMilliseconds;
        metrics.recordDelivered(pending.strategyTag, latency);
      }
      return;
    }

    final ttl = (data['ttl'] as int?) ?? 1;
    if (ttl > 1) {
      final forwarded = Map<String, dynamic>.from(data)..['ttl'] = ttl - 1;
      final eligible =
      _connectedPeers.where((p) => p.id != fromEndpointId).toList();
      _sendEnvelopeTo(
        eligible,
        MeshEnvelope(type: MeshEnvelope.typeAck, data: forwarded),
      );
    }
  }

  // ---------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------

  void _sendEnvelopeTo(List<PeerDevice> targets, MeshEnvelope envelope) {
    final bytes = Uint8List.fromList(utf8.encode(envelope.encode()));
    for (final peer in targets) {
      _log('sending ${envelope.type} (${bytes.length} bytes) to ${peer.id}');
      Nearby().sendBytesPayload(peer.id, bytes).catchError((e) {
        _log('send to ${peer.id} failed: $e');
      });
    }
  }

  /// Sends a message we wrote. If nobody is connected right now, it waits
  /// in the outbox and goes out automatically when someone connects.
  Future<void> sendMessage(ChatMessage message) async {
    await storage.markMessageSeen(message.id);
    if (!message.isBroadcast) {
      _pendingSends[message.id] =
          _PendingSend(DateTime.now(), message.strategyTag);
      // Only private messages get a delivery confirmation, so only
      // those count toward the "reached their friend" numbers.
      metrics.recordSent(message.strategyTag);
    }

    final targets = routingStrategy.selectRelayTargets(
      eligiblePeers: _connectedPeers,
      message: message,
    );

    if (targets.isEmpty) {
      _log('nobody connected, message goes to outbox');
      _outbox.add(message);
      _emitPeers();
      return;
    }

    _activityController.add(targets.map((p) => p.id).toList());
    _sendEnvelopeTo(
      targets,
      MeshEnvelope(type: MeshEnvelope.typeChat, data: message.toWireJson()),
    );
  }

  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    final connected = _connectedPeers;
    if (connected.isEmpty) return;

    final stillPending = <ChatMessage>[];
    for (final message in _outbox) {
      final targets = routingStrategy.selectRelayTargets(
        eligiblePeers: connected,
        message: message,
      );
      if (targets.isEmpty) {
        stillPending.add(message);
      } else {
        _activityController.add(targets.map((p) => p.id).toList());
        _sendEnvelopeTo(
          targets,
          MeshEnvelope(type: MeshEnvelope.typeChat, data: message.toWireJson()),
        );
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