// lib/widgets/skin_metrics_panel.dart
//
// A clean, premium "Skin Metrics Panel" used wherever a snapshot of the
// patient's 0–10 skin metrics is shown side-by-side with baseline / prior
// values. Each row renders:
//
//   • Clinical metric name (e.g. "Erythema (Redness)")
//   • Current value (e.g. "5.2")
//   • Delta vs baseline with arrow + amount, coloured clinical-teal for
//     improvement and rose for regression.
//   • Optional short description shown beneath the row when [showHelp] is on.
//
// Use this anywhere you need a consistent clinical metric display.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/skin_metric_labels.dart';
import 'clinical_metric_label.dart';

class SkinMetricRow {
  final SkinMetricSpec spec;
  final double current;
  final double? previous;

  const SkinMetricRow({
    required this.spec,
    required this.current,
    this.previous,
  });
}

class SkinMetricsPanel extends StatelessWidget {
  final List<SkinMetricRow> rows;
  final bool showHelp;
  final EdgeInsetsGeometry padding;

  const SkinMetricsPanel({
    super.key,
    required this.rows,
    this.showHelp = false,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MyApp.textBrown.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: MyApp.textBrown.withValues(alpha: 0.06),
              ),
            _MetricLine(row: rows[i], showHelp: showHelp),
          ],
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  final SkinMetricRow row;
  final bool showHelp;

  const _MetricLine({required this.row, required this.showHelp});

  @override
  Widget build(BuildContext context) {
    final spec = row.spec;
    final delta = MetricDelta.compute(
      previous: row.previous,
      current: row.current,
      lowerIsBetter: spec.lowerIsBetter,
    );
    final textColor = MyApp.textBrown;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: MyApp.clinicalNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(spec.icon, size: 16, color: MyApp.clinicalNavy),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClinicalMetricLabel(
                      label: spec.clinicalName,
                      compact: !showHelp,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      spec.lowerIsBetter
                          ? 'Lower is better · 0–10 scale'
                          : 'Higher is better · 0–10 scale',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: MyApp.clinicalMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    row.current.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                  if (delta != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      delta.text,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: delta.color,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (showHelp) ...[
            const SizedBox(height: 8),
            Text(
              spec.description,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: textColor.withValues(alpha: 0.65),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
