import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../services/routing_strategy.dart';
import 'metrics_screen.dart';

/// A friendly summary of what your phone has been up to.
/// (Long-press the title to open the hidden experiments screen.)
class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final metrics = provider.metrics;

    var sent = 0;
    var delivered = 0;
    var relayed = 0;
    final latencies = <int>[];
    for (final name in metrics.strategyNames) {
      final m = metrics.forStrategy(name);
      sent += m.sent;
      delivered += m.delivered;
      relayed += m.relayed;
      latencies.addAll(m.latenciesMs);
    }

    final friendsMet = provider.getAllContacts().length;
    final rate =
    sent == 0 ? 0.0 : (delivered / sent).clamp(0.0, 1.0).toDouble();
    final avgSeconds = latencies.isEmpty
        ? null
        : latencies.reduce((a, b) => a + b) / latencies.length / 1000;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MetricsScreen()),
          ),
          child: const Text('Recent activity'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Since you opened Deadzone',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (provider.currentStrategyName != 'flood')
            _experimentBanner(provider),
          Row(
            children: [
              Expanded(child: _tile('💬', '$sent', 'private messages sent')),
              const SizedBox(width: 12),
              Expanded(
                child: _tile('👯', '$friendsMet',
                    friendsMet == 1 ? 'friend met' : 'friends met'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _tile('✅', '$delivered', 'reached their friend')),
              const SizedBox(width: 12),
              Expanded(child: _tile('🤝', '$relayed', 'carried for others')),
            ],
          ),
          const SizedBox(height: 16),
          if (sent == 0 && relayed == 0) _emptyState(),
          if (sent > 0) _deliveryCard(sent, delivered, rate, avgSeconds),
          if (relayed > 0) _helperCard(relayed),
        ],
      ),
    );
  }

  Widget _tile(String emoji, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard(int sent, int delivered, double rate, double? avgSeconds) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Did your messages arrive? 📬',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$delivered of $sent ${sent == 1 ? 'message' : 'messages'} reached their friend',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 8,
              backgroundColor: AppColors.surfaceRaised,
              valueColor: const AlwaysStoppedAnimation(AppColors.signal),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            avgSeconds == null
                ? '⏳ Waiting for the first confirmation'
                : '⏱️ Usually arrives in ${avgSeconds.toStringAsFixed(2)} s',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _helperCard(int relayed) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secure.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secure.withOpacity(0.4)),
      ),
      child: Text(
        "You're a great relay! 🤝\n"
            'Your phone helped $relayed ${relayed == 1 ? 'message' : 'messages'} '
            "hop along to someone else. You couldn't read any of them, they're locked 🔒",
        style: const TextStyle(
          color: AppColors.secure,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        children: [
          Text('👀', style: TextStyle(fontSize: 32)),
          SizedBox(height: 8),
          Text(
            'Nothing yet.\nChat with a friend and your activity shows up here!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _experimentBanner(MeshProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secure.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secure.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "🧪 Experiment mode is on. Your phone isn't using the normal Shout style.",
              style: TextStyle(color: AppColors.secure, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () => provider.switchStrategy(FloodStrategy()),
            child: const Text('Switch back'),
          ),
        ],
      ),
    );
  }
}