// Home primary card: the last comparable pair of AI scans (or the latest
// scan alone), absolute values only -- no arrows and no percentages.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../utils/last_comparable_pair.dart';

class LastComparablePairCard extends StatelessWidget {
  const LastComparablePairCard({
    super.key,
    required this.pair,
    this.onOpenSummary,
  });

  final ComparablePair pair;

  /// Opens the progress summary; no button when null.
  final VoidCallback? onOpenSummary;

  static const String noPriorText = 'No prior comparable scan.';

  static String formatTimestamp(DateTime t) =>
      DateFormat('MMM d, y · h:mm a').format(t);

  static String lockReasonText(String reason) => reason.replaceAll('_', ' ');

  static String valueText(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    final baseline = pair.baseline;
    final header = TextStyle(
      color: ink.withValues(alpha: 0.7),
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
    );
    return Container(
      key: const ValueKey('last_comparable_pair_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pair.hasBaseline ? 'Last comparable pair' : 'Latest scan',
            style: const TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          if (baseline != null)
            Text(
              '${formatTimestamp(baseline.timestamp)}  and  '
              '${formatTimestamp(pair.latest.timestamp)}',
              key: const ValueKey('last_pair_timestamps'),
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            )
          else ...[
            Text(
              formatTimestamp(pair.latest.timestamp),
              key: const ValueKey('last_pair_timestamps'),
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              noPriorText,
              style: TextStyle(color: ink, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: [
                  Text('Metric', style: header),
                  if (baseline != null)
                    Text('Earlier', style: header, textAlign: TextAlign.right)
                  else
                    const SizedBox.shrink(),
                  Text(
                    baseline != null ? 'Later' : 'Value',
                    style: header,
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              for (final key in comparablePairMetricKeys)
                TableRow(
                  key: ValueKey('last_pair_row_$key'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        comparablePairMetricLabels[key]!,
                        style: const TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: baseline != null
                          ? Text(
                              valueText(pair.baselineValue(key)),
                              textAlign: TextAlign.right,
                            )
                          : const SizedBox.shrink(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        valueText(pair.latestValue(key)),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (pair.lockReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Locks on this scan: ${pair.lockReasons.entries.map((e) => '${e.key.replaceAll('_', ' ')} (${lockReasonText(e.value)})').join('; ')}',
              key: const ValueKey('last_pair_lock_reasons'),
              style: TextStyle(
                color: ink.withValues(alpha: 0.75),
                fontSize: 11.5,
              ),
            ),
          ],
          if (onOpenSummary != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('open_progress_summary'),
                onPressed: onOpenSummary,
                child: const Text('Progress summary'),
              ),
            ),
        ],
      ),
    );
  }
}
