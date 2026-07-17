import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';

class SkinProgressChart extends StatelessWidget {
  final List<Map<String, dynamic>> scanHistory;
  final String metric;

  const SkinProgressChart({
    super.key,
    required this.scanHistory,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    if (scanHistory.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.10),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights, color: MyApp.goldShimmer, size: 38),
              const SizedBox(height: 16),
              Text('No scans yet', style: MyApp.pageTitleStyle()),
              const SizedBox(height: 8),
              Text(
                'Start your journey by taking your first scan. Your progress will appear here with beautiful charts and insights!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sortedScans = List<Map<String, dynamic>>.from(scanHistory)
      ..sort((a, b) {
        final aDate = DateTime.tryParse((a['date'] ?? '').toString());
        final bDate = DateTime.tryParse((b['date'] ?? '').toString());
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

    final spots = sortedScans.asMap().entries.map((entry) {
      final index = entry.key.toDouble();
      final dynamic rawValue = entry.value[metric];
      final value = rawValue is num ? rawValue.toDouble() : 0.0;
      return FlSpot(index, value);
    }).toList();

    final dates = sortedScans.map((s) {
      final parsed = DateTime.tryParse((s['date'] ?? '').toString());
      return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.10),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.show_chart, color: MyApp.goldShimmer, size: 22),
                const SizedBox(width: 8),
                Text(
                  '${metric.capitalize()} Progress',
                  style: MyApp.pageTitleStyle(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dates.length) {
                            return Text(
                              DateFormat('MM/dd').format(dates[idx]),
                              style: TextStyle(
                                fontSize: 10,
                                color: MyApp.textBrown.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      color: MyApp.goldShimmer,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.white,
                            strokeColor: MyApp.roseGold,
                            strokeWidth: 2,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: MyApp.roseGold.withValues(alpha: 0.13),
                      ),
                    ),
                  ],
                  minY: 0,
                  maxY: 100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
