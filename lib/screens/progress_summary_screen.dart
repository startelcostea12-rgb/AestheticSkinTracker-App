import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/last_comparable_pair.dart';
import '../utils/progress_summary.dart';
import '../widgets/last_comparable_pair_card.dart';

/// The last comparable pair for the main metrics, with a trend word only
/// where the stored verdict is valid (see progressTrendLabel). No arrows or
/// percentages. [scans] is for tests; by default the saved history is read.
class ProgressSummaryScreen extends StatefulWidget {
  const ProgressSummaryScreen({super.key, this.scans});

  final List<ScanHistoryEntry>? scans;

  @override
  State<ProgressSummaryScreen> createState() => _ProgressSummaryScreenState();
}

class _ProgressSummaryScreenState extends State<ProgressSummaryScreen> {
  ComparablePair? _pair;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scans = widget.scans ?? await AppPrefs.getScanEntries();
    if (!mounted) return;
    setState(() {
      _pair = lastComparablePair(scans);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    final pair = _pair;
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(title: const Text('Progress summary')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pair == null
          ? const Center(child: Text('No scans yet.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  pair.baseline != null
                      ? '${LastComparablePairCard.formatTimestamp(pair.baseline!.timestamp)}  and  '
                            '${LastComparablePairCard.formatTimestamp(pair.latest.timestamp)}'
                      : LastComparablePairCard.formatTimestamp(
                          pair.latest.timestamp,
                        ),
                  style: TextStyle(color: ink.withValues(alpha: 0.75)),
                ),
                if (pair.baseline == null) ...[
                  const SizedBox(height: 6),
                  const Text(
                    LastComparablePairCard.noPriorText,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 12),
                for (final key in comparablePairMetricKeys) _row(pair, key),
                const SizedBox(height: 14),
                Text(
                  'A trend is shown only when both scans were comparable '
                  '(same lighting, angle and scoring) and the change is '
                  'larger than this metric\'s measurement noise.',
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(ComparablePair pair, String key) {
    const ink = AppColors.textStructure;
    final trend = progressTrendLabel(pair, key);
    final values = pair.baseline != null
        ? '${LastComparablePairCard.valueText(pair.baselineValue(key))}  ·  '
              '${LastComparablePairCard.valueText(pair.latestValue(key))}'
        : LastComparablePairCard.valueText(pair.latestValue(key));
    return Container(
      key: ValueKey('progress_row_$key'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comparablePairMetricLabels[key]!,
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(values, style: const TextStyle(color: ink)),
              ],
            ),
          ),
          Text(
            trend ?? 'Value only',
            key: ValueKey('progress_trend_$key'),
            style: TextStyle(
              color: trend == null ? ink.withValues(alpha: 0.6) : ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
