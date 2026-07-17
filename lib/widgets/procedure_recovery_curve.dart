import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';

class ProcedureRecoveryPoint {
  const ProcedureRecoveryPoint({
    required this.day,
    required this.value,
  });

  final double day;
  final double value;
}

class ProcedureRecoveryCurve extends StatelessWidget {
  const ProcedureRecoveryCurve({
    super.key,
    required this.metricName,
    required this.points,
    this.procedureName,
    this.clinicalZoneMin = 30,
    this.clinicalZoneMax = 60,
    this.minX = 1,
    this.maxX = 30,
    this.minY = 0,
    this.maxY = 100,
    this.unitLabel = 'score',
  });

  final String metricName;
  final String? procedureName;
  final List<ProcedureRecoveryPoint> points;

  final double clinicalZoneMin;
  final double clinicalZoneMax;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final String unitLabel;

  ProcedureRecoveryPoint? get _latestPoint {
    if (points.isEmpty) return null;
    final sorted = List<ProcedureRecoveryPoint>.from(points)
      ..sort((a, b) => a.day.compareTo(b.day));
    return sorted.last;
  }

  String _recoveryMessage() {
    final latest = _latestPoint;
    if (latest == null) {
      return 'Add your first scan to begin tracking your recovery curve.';
    }

    final day = latest.day.round();
    if (latest.value >= clinicalZoneMin && latest.value <= clinicalZoneMax) {
      return 'Your recovery is exactly on track for Day $day.';
    }

    if (latest.value < clinicalZoneMin) {
      return 'You are trending below the clinical range for Day $day. This can still be normal depending on treatment intensity and skin baseline.';
    }

    return 'You are slightly above the clinical range for Day $day. Stay consistent with your recovery routine and monitor your next scan.';
  }

  List<FlSpot> _spots() {
    final sorted = List<ProcedureRecoveryPoint>.from(points)
      ..sort((a, b) => a.day.compareTo(b.day));
    return sorted.map((p) => FlSpot(p.day, p.value)).toList();
  }

  Widget _bottomTitle(double value, TitleMeta meta) {
    const labels = <int>{1, 7, 14, 30};
    final day = value.round();
    if (!labels.contains(day)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'Day $day',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: MyApp.textBrown.withValues(alpha: 0.72),
          letterSpacing: 0.15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spots();
    final latest = _latestPoint;

    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.08),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CLINICAL RECOVERY CURVE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: MyApp.roseGold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            procedureName == null
                ? '$metricName (30-Day Trend)'
                : '$metricName - ${procedureName!}',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: MyApp.clinicalNavy,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MyApp.goldShimmer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: MyApp.goldShimmer.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  'Clinical Standard Healing Zone: ${clinicalZoneMin.toStringAsFixed(0)}-${clinicalZoneMax.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ),
              if (latest != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: MyApp.roseGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: MyApp.roseGold.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    'Latest: Day ${latest.day.round()} - ${latest.value.toStringAsFixed(1)} $unitLabel',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MyApp.clinicalNavy,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (_) {
                    return FlLine(
                      color: MyApp.textBrown.withValues(alpha: 0.10),
                      strokeWidth: 0.8,
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    left: BorderSide(
                      color: MyApp.roseGold.withValues(alpha: 0.24),
                    ),
                    bottom: BorderSide(
                      color: MyApp.roseGold.withValues(alpha: 0.24),
                    ),
                    top: BorderSide.none,
                    right: BorderSide.none,
                  ),
                ),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(
                      y1: clinicalZoneMin,
                      y2: clinicalZoneMax,
                      color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: 10,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: MyApp.textBrown.withValues(alpha: 0.64),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 30,
                      getTitlesWidget: _bottomTitle,
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipColor: (_) => Colors.black.withValues(alpha: 0.72),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          'Day ${spot.x.toInt()}\n${spot.y.toStringAsFixed(1)} $unitLabel',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.28,
                    barWidth: 4,
                    color: MyApp.goldShimmer,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        final isLatest = latest != null &&
                            spot.x == latest.day &&
                            spot.y == latest.value;
                        return FlDotCirclePainter(
                          radius: isLatest ? 4.8 : 3.4,
                          color: Colors.white,
                          strokeWidth: isLatest ? 2.8 : 2,
                          strokeColor: MyApp.roseGold,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          MyApp.goldShimmer.withValues(alpha: 0.22),
                          MyApp.goldShimmer.withValues(alpha: 0.03),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: MyApp.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.favorite_outline,
                  size: 15,
                  color: MyApp.roseGold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _recoveryMessage(),
                    style: TextStyle(
                      fontSize: 12.4,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: MyApp.clinicalNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
