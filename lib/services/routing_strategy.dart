import 'dart:math';
import '../models/peer_device.dart';
import '../models/chat_message.dart';

/// Phase 3: pluggable relay decision logic. Swapping strategies at
/// runtime is what turns this from "a chat app" into "a routing
/// protocol comparison" — the metrics screen measures the tradeoffs
/// between these three.
abstract class RoutingStrategy {
  String get name;

  /// Given everyone directly connected right now (already excluding
  /// whoever we just received this message from), decide who actually
  /// gets the forward. Returning everyone = flooding.
  List<PeerDevice> selectRelayTargets({
    required List<PeerDevice> eligiblePeers,
    required ChatMessage message,
  });
}

/// Baseline: forward to every eligible connection. Highest delivery
/// probability, highest overhead (every message duplicated across
/// every edge of the mesh) — this is what Phase 1/2 already did.
class FloodStrategy implements RoutingStrategy {
  @override
  String get name => 'flood';

  @override
  List<PeerDevice> selectRelayTargets({
    required List<PeerDevice> eligiblePeers,
    required ChatMessage message,
  }) =>
      eligiblePeers;
}

/// Each eligible peer gets the message with probability [p]. Lower
/// overhead than flooding, at the cost of a chance the message dies
/// out before reaching the destination — the classic epidemic/gossip
/// routing tradeoff from the DTN literature.
class ProbabilisticGossipStrategy implements RoutingStrategy {
  final double p;
  final Random _random;

  ProbabilisticGossipStrategy({this.p = 0.6, Random? random})
      : _random = random ?? Random();

  @override
  String get name => 'gossip_p${(p * 100).round()}';

  @override
  List<PeerDevice> selectRelayTargets({
    required List<PeerDevice> eligiblePeers,
    required ChatMessage message,
  }) {
    return eligiblePeers.where((_) => _random.nextDouble() < p).toList();
  }
}

/// Only relay through the [maxFanout] strongest-signal connections.
/// Lower overhead than flooding, more deterministic than gossip, but
/// concentrates load on fewer peers.
class PriorityStrategy implements RoutingStrategy {
  final int maxFanout;
  PriorityStrategy({this.maxFanout = 2});

  @override
  String get name => 'priority_top$maxFanout';

  @override
  List<PeerDevice> selectRelayTargets({
    required List<PeerDevice> eligiblePeers,
    required ChatMessage message,
  }) {
    final sorted = [...eligiblePeers]
      ..sort((a, b) => b.signalBars.compareTo(a.signalBars));
    return sorted.take(maxFanout).toList();
  }
}