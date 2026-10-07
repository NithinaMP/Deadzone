import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../services/routing_strategy.dart';
import '../services/metrics_service.dart';

/// Phase 3's "wow" screen for faculty: pick a strategy, send test
/// messages, watch delivery rate / latency / overhead diverge in real
/// time. This is the actual evaluable contribution of the project.
class MetricsScreen extends StatelessWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final metrics = provider.metrics;

    return Scaffold(
      appBar: AppBar(title: const Text('Routing Comparison')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Active relay strategy',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _strategyChip(context, provider, 'Flood', FloodStrategy()),
              _strategyChip(context, provider, 'Gossip 60%',
                  ProbabilisticGossipStrategy(p: 0.6)),
              _strategyChip(context, provider, 'Priority Top-2',
                  PriorityStrategy(maxFanout: 2)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Switch strategy on all test devices, send a few messages '
                'under each, then compare the cards below.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 24),
          const Text('Observed on this device',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 8),
          if (metrics.strategyNames.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No messages sent yet under any strategy — send a few '
                    'test messages to populate this.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            )
          else
            ...metrics.strategyNames
                .map((name) => _metricsCard(name, metrics.forStrategy(name))),
        ],
      ),
    );
  }

  Widget _strategyChip(
      BuildContext context,
      MeshProvider provider,
      String label,
      RoutingStrategy strategy,
      ) {
    final isActive = provider.currentStrategyName == strategy.name;
    return ChoiceChip(
      label: Text(label),
      selected: isActive,
      selectedColor: AppColors.signal,
      backgroundColor: AppColors.surfaceRaised,
      labelStyle: TextStyle(
        color: isActive ? Colors.black : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) => provider.switchStrategy(strategy),
    );
  }

  Widget _metricsCard(String name, StrategyMetrics m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(
                  color: AppColors.signal,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const SizedBox(height: 10),
          _statRow('Sent', '${m.sent}'),
          _statRow('Delivered (acked)', '${m.delivered}'),
          _statRow('Delivery rate', '${(m.deliveryRate * 100).toStringAsFixed(0)}%'),
          _statRow('Avg latency', '${m.avgLatencyMs.toStringAsFixed(0)} ms'),
          _statRow('Relayed (hops carried)', '${m.relayed}'),
          _statRow('Duplicates dropped', '${m.duplicatesDropped}'),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}