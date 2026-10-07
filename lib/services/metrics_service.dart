import 'package:flutter/foundation.dart';

/// Per-strategy counters, tracked locally on THIS device. There's no
/// central server to aggregate across the whole mesh (that would need
/// internet, which defeats the point of the project) — so this is
/// deliberately "what this device personally observed." Worth stating
/// as an honest scope note in your report: true network-wide metrics
/// would need every device to export its local log after a test run
/// for offline comparison.
class StrategyMetrics {
  int sent = 0;
  int delivered = 0; // acked by the actual recipient
  int relayed = 0; // times this device forwarded someone else's message
  int duplicatesDropped = 0; // dedup cache caught a re-flood
  final List<int> latenciesMs = [];

  double get deliveryRate => sent == 0 ? 0 : delivered / sent;
  double get avgLatencyMs => latenciesMs.isEmpty
      ? 0
      : latenciesMs.reduce((a, b) => a + b) / latenciesMs.length;
}

class MetricsService extends ChangeNotifier {
  final Map<String, StrategyMetrics> _byStrategy = {};

  StrategyMetrics forStrategy(String name) =>
      _byStrategy.putIfAbsent(name, () => StrategyMetrics());

  List<String> get strategyNames => _byStrategy.keys.toList();

  void recordSent(String strategy) {
    forStrategy(strategy).sent++;
    notifyListeners();
  }

  void recordDelivered(String strategy, int latencyMs) {
    final m = forStrategy(strategy);
    m.delivered++;
    m.latenciesMs.add(latencyMs);
    notifyListeners();
  }

  void recordRelayed(String strategy) {
    forStrategy(strategy).relayed++;
    notifyListeners();
  }

  void recordDuplicateDropped(String strategy) {
    forStrategy(strategy).duplicatesDropped++;
    notifyListeners();
  }
}