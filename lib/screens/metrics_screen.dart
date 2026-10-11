import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/mesh_provider.dart';
import '../services/routing_strategy.dart';
import '../services/metrics_service.dart';

/// One way of passing messages along, described in plain words.
class _Style {
  final String key; // matches RoutingStrategy.name
  final String emoji;
  final String title;
  final String blurb;
  final RoutingStrategy Function() make;

  _Style({
    required this.key,
    required this.emoji,
    required this.title,
    required this.blurb,
    required this.make,
  });
}

final List<_Style> _styles = [
  _Style(
    key: 'flood',
    emoji: '📣',
    title: 'Shout',
    blurb: 'Tells every friend nearby. Most likely to arrive, a bit noisy.',
    make: () => FloodStrategy(),
  ),
  _Style(
    key: 'gossip_p60',
    emoji: '🤫',
    title: 'Whisper',
    blurb: 'Tells some friends at random. Quieter, but might miss.',
    make: () => ProbabilisticGossipStrategy(p: 0.6),
  ),
  _Style(
    key: 'priority_top2',
    emoji: '🏆',
    title: 'Best buddies',
    blurb: 'Only tells your 2 closest friends. Neat and tidy.',
    make: () => PriorityStrategy(maxFanout: 2),
  ),
];

_Style? _styleFor(String key) {
  for (final s in _styles) {
    if (s.key == key) return s;
  }
  return null;
}

/// A friendly page: pick how your phone passes messages along, chat for
/// a bit, then see which style did best. (Under the hood this compares
/// three routing strategies; here it's just a game.)
class MetricsScreen extends StatelessWidget {
  const MetricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final metrics = provider.metrics;
    final withData = metrics.strategyNames
        .where((n) => metrics.forStrategy(n).sent > 0)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mesh Playground 🎮')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'How should your phone pass messages along?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick a style, chat for a bit, then come back and see how it did.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ..._styles.map((s) => _styleCard(provider, s)),
          const SizedBox(height: 20),
          const Text(
            'Recent Activity',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (withData.isEmpty)
            _emptyState()
          else ...[
            if (withData.length >= 2) _badges(metrics, withData),
            ...withData.map((k) => _scoreCard(k, metrics.forStrategy(k))),
          ],
          const SizedBox(height: 8),
          const Text(
            'These numbers come from this phone only. '
                'The differences show up best with 3 or more phones.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ---------- Style picker ----------

  Widget _styleCard(MeshProvider provider, _Style s) {
    final active = provider.currentStrategyName == s.key;
    return GestureDetector(
      onTap: () => provider.switchStrategy(s.make()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active
              ? AppColors.signal.withOpacity(0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppColors.signal : AppColors.divider,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(s.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.signal,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.blurb,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Scoreboard ----------

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
            'Nothing to see yet.\nSend a few messages to a friend, then come back!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Picks the winner for one category, or null if there's no clear one.
  String? _winner(
      MetricsService metrics,
      List<String> keys,
      double Function(StrategyMetrics) score, {
        required bool lowerIsBetter,
        bool Function(StrategyMetrics)? eligible,
      }) {
    final candidates = keys
        .where((k) => eligible?.call(metrics.forStrategy(k)) ?? true)
        .toList();
    if (candidates.length < 2) return null;
    candidates.sort((a, b) {
      final sa = score(metrics.forStrategy(a));
      final sb = score(metrics.forStrategy(b));
      return lowerIsBetter ? sa.compareTo(sb) : sb.compareTo(sa);
    });
    final best = score(metrics.forStrategy(candidates[0]));
    final second = score(metrics.forStrategy(candidates[1]));
    if (best == second) return null; // tie, so no winner
    return candidates[0];
  }

  Widget _badges(MetricsService metrics, List<String> keys) {
    final fastest = _winner(
      metrics,
      keys,
          (m) => m.avgLatencyMs,
      lowerIsBetter: true,
      eligible: (m) => m.delivered > 0,
    );
    final reliable = _winner(
      metrics,
      keys,
          (m) => m.deliveryRate,
      lowerIsBetter: false,
    );
    final quietest = _winner(
      metrics,
      keys,
          (m) => m.sent == 0 ? 0 : m.relayed / m.sent,
      lowerIsBetter: true,
    );

    final pills = <Widget>[];
    if (fastest != null) {
      pills.add(_pill('⚡ Fastest: ${_styleFor(fastest)?.title ?? fastest}'));
    }
    if (reliable != null) {
      pills.add(
          _pill('🎯 Most reliable: ${_styleFor(reliable)?.title ?? reliable}'));
    }
    if (quietest != null) {
      pills.add(_pill('🤫 Quietest: ${_styleFor(quietest)?.title ?? quietest}'));
    }
    if (pills.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: pills),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secure.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secure.withOpacity(0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.secure,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _scoreCard(String key, StrategyMetrics m) {
    final style = _styleFor(key);
    final rate = m.deliveryRate.clamp(0.0, 1.0).toDouble();
    final msgWord = m.sent == 1 ? 'message' : 'messages';
    final carriedWord = m.relayed == 1 ? 'message' : 'messages';
    final repeatWord = m.duplicatesDropped == 1 ? 'copy' : 'copies';

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
          Row(
            children: [
              Text(style?.emoji ?? '📡', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Text(
                style?.title ?? key,
                style: const TextStyle(
                  color: AppColors.signal,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${(rate * 100).round()}%',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${m.delivered} of ${m.sent} $msgWord reached their friend',
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
          _fact(
            '⏱️',
            m.delivered == 0
                ? 'No arrival times yet'
                : 'Usually arrives in ${(m.avgLatencyMs / 1000).toStringAsFixed(2)} s',
          ),
          _fact('🤝', 'Helped carry ${m.relayed} $carriedWord for others'),
          _fact('🔁', 'Ignored ${m.duplicatesDropped} repeat $repeatWord'),
        ],
      ),
    );
  }

  Widget _fact(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}