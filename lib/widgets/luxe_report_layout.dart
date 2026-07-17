import 'dart:async';

import 'package:flutter/material.dart';

import 'before_after_split_slider.dart';
import 'procedure_recovery_curve.dart';

class LuxeMetric {
  const LuxeMetric({
    required this.key,
    required this.name,
    required this.baselineScore,
    required this.currentScore,
    required this.improvementPercent,
    required this.lowerIsBetter,
  });

  final String key;
  final String name;
  final double baselineScore;
  final double currentScore;
  final double improvementPercent;
  final bool lowerIsBetter;
}

class LuxeMetricParser {
  const LuxeMetricParser._();

  static const Set<String> _defectMetricKeys = {
    'localized_redness',
    'breakout_activity',
    'pigment_load',
    'wrinkle_load',
    'pore_visibility',
    'sebum_excess_oil_gloss',
    'diffuse_flushing_erythema',
    'glabellar_wrinkle_depth',
    'pore_contraction_index',
  };

  static const Set<String> _benefitMetricKeys = {
    'texture_smoothness',
    'skin_tone_radiance_evenness',
    'structural_firmness_elasticity',
  };

  static bool _isDefectMetric(String metricKey) {
    if (_benefitMetricKeys.contains(metricKey)) return false;
    return _defectMetricKeys.contains(metricKey);
  }

  static List<LuxeMetric> parseTimelinePayload(Map<String, dynamic> payload) {
    final serverMetrics = _extractServerDeltaMetrics(payload);
    if (serverMetrics.isNotEmpty) {
      return serverMetrics;
    }

    final direct = _extractDirectMetrics(payload);
    if (direct != null) {
      return [
        LuxeMetric(
          key: 'localized_redness',
          name: 'Calibrated Redness',
          baselineScore: direct.redness,
          currentScore: direct.redness,
          improvementPercent: 0,
          lowerIsBetter: true,
        ),
        LuxeMetric(
          key: 'texture_smoothness',
          name: 'Calibrated Smoothness',
          baselineScore: direct.smoothness,
          currentScore: direct.smoothness,
          improvementPercent: 0,
          lowerIsBetter: false,
        ),
      ];
    }

    final baseline = _asMap(payload['baseline']);
    final current = _asMap(payload['current']);

    final baselineRednessScore =
        _scoreFromNode(baseline, 'calibrated_redness_score');
    final currentRednessScore =
        _scoreFromNode(current, 'calibrated_redness_score');

    final baselineTextureScore =
        _scoreFromNode(baseline, 'calibrated_smoothness_score');
    final currentTextureScore =
        _scoreFromNode(current, 'calibrated_smoothness_score');

    return [
      LuxeMetric(
        key: 'localized_redness',
        name: 'Vascular Redness',
        baselineScore: baselineRednessScore,
        currentScore: currentRednessScore,
        improvementPercent: _improvementPercent(
          baseline: baselineRednessScore,
          current: currentRednessScore,
          lowerIsBetter: true,
        ),
        lowerIsBetter: true,
      ),
      LuxeMetric(
        key: 'texture_smoothness',
        name: 'Texture Smoothness',
        baselineScore: baselineTextureScore,
        currentScore: currentTextureScore,
        improvementPercent: _improvementPercent(
          baseline: baselineTextureScore,
          current: currentTextureScore,
          lowerIsBetter: false,
        ),
        lowerIsBetter: false,
      ),
    ];
  }

  static List<LuxeMetric> _extractServerDeltaMetrics(
    Map<String, dynamic> payload,
  ) {
    final trendDeltas = _asMap(payload['trend_deltas']);
    if (trendDeltas.isEmpty) return const [];

    final metricMatrix = _asMap(payload['metric_matrix']);
    final metrics = _asMap(payload['metrics']);
    final scoreSource = metricMatrix.isNotEmpty ? metricMatrix : metrics;

    final specs = <_ServerMetricSpec>[
      const _ServerMetricSpec(
        deltaKey: 'localized_redness',
        name: 'Localized Redness',
        currentKeys: ['localized_redness', 'calibrated_redness_score', 'redness'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'texture_smoothness',
        name: 'Texture Smoothness',
        currentKeys: ['texture_smoothness', 'calibrated_smoothness_score', 'smoothness', 'texture'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'pore_visibility',
        name: 'Pore Visibility',
        currentKeys: ['pore_visibility', 'raw_pore_density', 'pores', 'poreSize'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'breakout_activity',
        name: 'Breakout Activity',
        currentKeys: ['breakout_activity', 'acne_activity_score', 'acneSeverity', 'activeBreakouts'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'sebum_excess_oil_gloss',
        name: 'Sebum & Oil Gloss',
        currentKeys: ['sebum_excess_oil_gloss', 'oil_gloss', 'sebum_gloss'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'diffuse_flushing_erythema',
        name: 'Diffuse Flushing (Erythema)',
        currentKeys: ['diffuse_flushing_erythema', 'flushing_erythema', 'erythema_diffuse'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'skin_tone_radiance_evenness',
        name: 'Skin Radiance & Evenness',
        currentKeys: ['skin_tone_radiance_evenness', 'radiance_evenness', 'skin_radiance_evenness'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'glabellar_wrinkle_depth',
        name: "Glabellar '11' Lines Depth",
        currentKeys: ['glabellar_wrinkle_depth', 'glabella_wrinkle_depth', 'wrinkle_depth_glabella'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'pore_contraction_index',
        name: 'Pore Contraction Index',
        currentKeys: ['pore_contraction_index', 'pore_index', 'average_pore_size_index'],
      ),
      const _ServerMetricSpec(
        deltaKey: 'structural_firmness_elasticity',
        name: 'Structural Firmness & Elasticity',
        currentKeys: [
          'structural_firmness_elasticity',
          'firmness_elasticity',
          'structural_firmness',
        ],
      ),
    ];

    final out = <LuxeMetric>[];
    for (final spec in specs) {
      final rawDelta = _asDouble(trendDeltas[spec.deltaKey]);
      if (rawDelta.isNaN || rawDelta.isInfinite) continue;
      final current = _scoreFromAny(scoreSource, spec.currentKeys);
      if (current == null) continue;
      final lowerIsBetter = _isDefectMetric(spec.deltaKey);
      final baseline = _baselineFromCurrentAndDelta(
        current,
        rawDelta,
        lowerIsBetter: lowerIsBetter,
      );
      final improvementPercent = rawDelta;
      out.add(
        LuxeMetric(
          key: spec.deltaKey,
          name: spec.name,
          baselineScore: baseline,
          currentScore: current.clamp(0.0, 100.0).toDouble(),
          improvementPercent: improvementPercent,
          lowerIsBetter: lowerIsBetter,
        ),
      );
    }
    return out;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  static _DirectMetrics? _extractDirectMetrics(Map<String, dynamic> payload) {
    final metrics = _asMap(payload['metrics']);
    final source = metrics.isNotEmpty ? metrics : payload;

    final redness = _scoreFromAny(source, const [
      'calibrated_redness_score',
      'redness',
      'redness_score',
    ]);
    final smoothness = _scoreFromAny(source, const [
      'calibrated_smoothness_score',
      'smoothness',
      'texture',
      'texture_score',
    ]);

    if (redness == null || smoothness == null) return null;
    return _DirectMetrics(redness: redness, smoothness: smoothness);
  }

  static double? _scoreFromAny(Map<String, dynamic> node, List<String> keys) {
    for (final key in keys) {
      final parsed = _asDouble(node[key]);
      if (parsed.isNaN || parsed.isInfinite) continue;
      return parsed.clamp(0.0, 100.0).toDouble();
    }
    return null;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double _scoreFromNode(Map<String, dynamic> node, String key) {
    final parsed = _asDouble(node[key]);
    if (parsed.isNaN || parsed.isInfinite) return 0.0;
    return parsed.clamp(0.0, 100.0).toDouble();
  }

  static double _improvementPercent({
    required double baseline,
    required double current,
    required bool lowerIsBetter,
  }) {
    if (baseline <= 0) {
      return 0.0;
    }
    final raw = ((current - baseline) / baseline) * 100;
    return lowerIsBetter ? -raw : raw;
  }

  static double _baselineFromCurrentAndDelta(
    double current,
    double delta, {
    required bool lowerIsBetter,
  }) {
    final denominator = lowerIsBetter
        ? 1.0 - (delta / 100.0)
        : 1.0 + (delta / 100.0);
    if (denominator.abs() < 0.001) {
      return current.clamp(0.0, 100.0).toDouble();
    }
    return (current / denominator).clamp(0.0, 100.0).toDouble();
  }
}

class _ServerMetricSpec {
  const _ServerMetricSpec({
    required this.deltaKey,
    required this.name,
    required this.currentKeys,
  });

  final String deltaKey;
  final String name;
  final List<String> currentKeys;
}

class _DirectMetrics {
  const _DirectMetrics({required this.redness, required this.smoothness});

  final double redness;
  final double smoothness;
}

class LuxeReportLayout extends StatefulWidget {
  const LuxeReportLayout({
    super.key,
    required this.rawPayload,
    this.baselineImageProvider,
    this.currentImageProvider,
    this.baselineLabel = 'Baseline Image',
    this.currentLabel = 'Current Scan',
  });

  final Map<String, dynamic> rawPayload;
  final ImageProvider<Object>? baselineImageProvider;
  final ImageProvider<Object>? currentImageProvider;
  final String baselineLabel;
  final String currentLabel;

  static const Color bg = Color(0xFF0F1013);
  static const Color card = Color(0xFF1A1F2C);
  static const Color gold = Color(0xFFD4AF37);
  static const Color roseGold = Color(0xFFB76E79);

  @override
  State<LuxeReportLayout> createState() => _LuxeReportLayoutState();
}

class _LuxeReportLayoutState extends State<LuxeReportLayout>
  with SingleTickerProviderStateMixin {
  bool _showAiOverlay = true;
  String? _selectedMetricKey;
  String? _highlightedZone;
  bool _flashActive = false;
  Timer? _flashTimer;
  late final AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  String _zoneForMetric(String key) {
    switch (key) {
      case 'glabellar_wrinkle_depth':
        return 'glabella';
      case 'pore_contraction_index':
      case 'pore_visibility':
        return 'cheeks_nose';
      case 'localized_redness':
      case 'diffuse_flushing_erythema':
        return 'cheeks';
      case 'breakout_activity':
      case 'sebum_excess_oil_gloss':
        return 'tzone';
      case 'structural_firmness_elasticity':
        return 'jawline';
      default:
        return 'full_face';
    }
  }

  void _handleMetricTap(LuxeMetric metric) {
    final zone = _zoneForMetric(metric.key);
    setState(() {
      _selectedMetricKey = metric.key;
      _highlightedZone = zone;
      _flashActive = true;
    });

    _flashTimer?.cancel();
    _flashController
      ..stop()
      ..value = 0
      ..repeat(reverse: true);

    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _flashController.stop();
      setState(() {
        _flashActive = false;
      });
    });
  }

  List<LuxeMetric> _topTrendMetrics(List<LuxeMetric> metrics, {int count = 4}) {
    final sorted = List<LuxeMetric>.from(metrics)
      ..sort(
        (a, b) => b.improvementPercent.abs().compareTo(a.improvementPercent.abs()),
      );
    return sorted.take(count).toList();
  }

  List<BeforeAfterMetricTag> _floatingMetricTags(List<LuxeMetric> metrics) {
    final top = _topTrendMetrics(metrics);
    final tags = <BeforeAfterMetricTag>[];
    for (var i = 0; i < top.length; i++) {
      final metric = top[i];
      final headline = '${metric.improvementPercent >= 0 ? '+' : '-'}${metric.improvementPercent.abs().toStringAsFixed(1)}%';
      tags.add(
        BeforeAfterMetricTag(
          label: _shortMetricTagLabel(metric.name),
          value: headline,
          side: i.isEven ? BeforeAfterTagSide.left : BeforeAfterTagSide.right,
        ),
      );
    }
    return tags;
  }

  String _shortMetricTagLabel(String name) {
    final n = name.toLowerCase();
    if (n.contains('redness')) return 'Redness';
    if (n.contains('texture')) return 'Texture';
    if (n.contains('pore')) return 'Pores';
    if (n.contains('wrinkle')) return 'Wrinkles';
    if (n.contains('breakout')) return 'Breakouts';
    if (n.contains('firmness')) return 'Firmness';
    if (name.length <= 14) return name;
    return '${name.substring(0, 14)}...';
  }

  Widget _buildClinicalContextCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medical_information_outlined,
            size: 18,
            color: Color(0xFFB76E79),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clinical Context & Disclaimer',
                  style: TextStyle(
                    color: Color(0xFF1F232D),
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'These AI-derived values are designed for progress tracking across your own baseline and follow-up scans. They do not diagnose disease, replace medical evaluation, or prescribe treatment.',
                  style: TextStyle(
                    color: const Color(0xFF1F232D).withValues(alpha: 0.78),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCurves(List<LuxeMetric> metrics) {
    final highlights = _topTrendMetrics(metrics, count: 2);
    if (highlights.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (final metric in highlights) {
      final midpoint = ((metric.baselineScore + metric.currentScore) / 2).clamp(0.0, 100.0);
      final points = <ProcedureRecoveryPoint>[
        ProcedureRecoveryPoint(day: 1, value: metric.baselineScore),
        ProcedureRecoveryPoint(day: 14, value: midpoint),
        ProcedureRecoveryPoint(day: 30, value: metric.currentScore),
      ];

      children.add(
        ProcedureRecoveryCurve(
          metricName: metric.name,
          procedureName: 'Progress Tracking Curve',
          points: points,
          clinicalZoneMin: metric.lowerIsBetter ? 20 : 60,
          clinicalZoneMax: metric.lowerIsBetter ? 55 : 90,
          unitLabel: 'index',
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    if (children.isNotEmpty) {
      children.removeLast();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Progress Tracking Curves',
          style: TextStyle(
            color: Color(0xFF1F232D),
            fontSize: 13.2,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = LuxeMetricParser.parseTimelinePayload(widget.rawPayload);
    final showComparisonFrames =
      widget.baselineImageProvider != null && widget.currentImageProvider != null;

    return Container(
      color: const Color(0xFFFFF8EE),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showComparisonFrames) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.28)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: Color(0xFFD4AF37),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Before vs After comparison',
                      style: TextStyle(
                        color: Color(0xFF1F232D),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _showAiOverlay = !_showAiOverlay);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _showAiOverlay
                          ? const Color(0xFF4FAE8B)
                          : Colors.white.withValues(alpha: 0.7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      _showAiOverlay
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 14,
                    ),
                    label: Text(
                      _showAiOverlay ? 'AI Overlay On' : 'AI Overlay Off',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveBeforeAfterSlider(
                beforeImage: widget.baselineImageProvider!,
                afterImage: widget.currentImageProvider!,
                beforeLabel: widget.baselineLabel,
                afterLabel: widget.currentLabel,
                aspectRatio: 0.96,
                metricTags: _floatingMetricTags(metrics),
                beforeLayerBuilder: (context, image) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(image: image, fit: BoxFit.cover),
                      if (_showAiOverlay)
                        CustomPaint(
                          painter: _AiOverlayPainter(
                            highlightedZone: _highlightedZone,
                            pulse: _flashActive ? _flashController : null,
                          ),
                        ),
                    ],
                  );
                },
                afterLayerBuilder: (context, image) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(image: image, fit: BoxFit.cover),
                      if (_showAiOverlay)
                        CustomPaint(
                          painter: _AiOverlayPainter(
                            highlightedZone: _highlightedZone,
                            pulse: _flashActive ? _flashController : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final colWidth = (width - 14) / 2;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: colWidth,
                      child: _MetricCard(
                        metric: metric,
                        selected: _selectedMetricKey == metric.key,
                        onTap: () => _handleMetricTap(metric),
                      ),
                    ),
                ],
              );
            },
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildTrendCurves(metrics),
            const SizedBox(height: 16),
            _buildClinicalContextCard(),
          ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.selected,
    required this.onTap,
  });

  final LuxeMetric metric;
  final bool selected;
  final VoidCallback onTap;

  static const Color gold = LuxeReportLayout.gold;

  @override
  Widget build(BuildContext context) {
    final delta = metric.improvementPercent;
    final chipLabel = _chipLabel(delta, lowerIsBetter: metric.lowerIsBetter);
    final chipIcon = _chipIcon(delta, lowerIsBetter: metric.lowerIsBetter);
    final chipColor = _chipColor(delta);
    const titleColor = Color(0xFF1E242F);
    final headlineDelta = '${delta >= 0 ? '+' : '-'}${delta.abs().toStringAsFixed(1)}%';
    final progressionLine =
        '${metric.name}: ${metric.baselineScore.toStringAsFixed(1)} -> ${metric.currentScore.toStringAsFixed(1)} '
      '(${_deltaNarrative(delta, lowerIsBetter: metric.lowerIsBetter)})';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFFD4AF37)
                  : const Color(0xFFDACDB2).withValues(alpha: 0.65),
              width: selected ? 1.8 : 0.9,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headlineDelta,
                style: TextStyle(
                  color: chipColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Current ${metric.currentScore.toStringAsFixed(1)}  |  Baseline ${metric.baselineScore.toStringAsFixed(1)}',
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 10.9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                metric.name,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.88),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(chipIcon, size: 11.5, color: chipColor),
                    const SizedBox(width: 6),
                    Text(
                      chipLabel,
                      style: TextStyle(
                        color: chipColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (delta.abs() > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${delta.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: chipColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                progressionLine,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 10.8,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _metricDescription(metric),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor.withValues(alpha: 0.76),
                  fontSize: 10.6,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metricDescription(LuxeMetric metric) {
    switch (metric.key) {
      case 'pore_contraction_index':
      case 'pore_visibility':
        return 'Tracks visible pore appearance in key zones under consistent lighting for cosmetic progress checks.';
      case 'glabellar_wrinkle_depth':
        return 'Follows visible line contrast in the brow zone to reflect surface texture smoothing trends.';
      case 'sebum_excess_oil_gloss':
        return 'Summarizes shine concentration across the T-zone to monitor oil-balance consistency over time.';
      case 'diffuse_flushing_erythema':
      case 'localized_redness':
        return 'Reflects broad visible redness distribution to help track calmness and tone consistency.';
      case 'skin_tone_radiance_evenness':
        return 'Represents overall tone uniformity and brightness balance for a smoother, more radiant look.';
      case 'structural_firmness_elasticity':
        return 'Compares facial support geometry trends to indicate tighter, more lifted visual structure.';
      case 'texture_smoothness':
        return 'Measures surface uniformity signals associated with smoother visual skin texture.';
      case 'breakout_activity':
        return 'Tracks visible breakout pattern intensity to monitor cosmetic flare-up frequency changes.';
      default:
        return 'Compares baseline and current scan vectors to track visible skin-quality progression.';
    }
  }

  String _chipLabel(double delta, {required bool lowerIsBetter}) {
    if (delta > 0) return 'Improving';
    if (delta < 0) return 'Needs Attention';
    return 'Stable';
  }

  IconData _chipIcon(double delta, {required bool lowerIsBetter}) {
    if (delta > 0) {
      return lowerIsBetter
          ? Icons.arrow_downward_rounded
          : Icons.arrow_upward_rounded;
    }
    if (delta < 0) {
      return lowerIsBetter
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded;
    }
    return Icons.trending_flat_rounded;
  }

  Color _chipColor(double delta) {
    if (delta > 0) return const Color(0xFF4FAE8B);
    if (delta < 0) return const Color(0xFFC76A55);
    return gold;
  }

  String _deltaNarrative(double delta, {required bool lowerIsBetter}) {
    final pct = delta.abs().toStringAsFixed(1);
    if (delta == 0) {
      return lowerIsBetter
          ? 'Stable (no defect change)'
          : 'Stable (no benefit change)';
    }

    if (delta > 0) {
      if (lowerIsBetter) return 'Reduced by $pct%';
      return 'Improved by $pct%';
    }

    if (lowerIsBetter) return 'Needs attention (+$pct%)';
    return 'Needs attention (-$pct%)';
  }
}

class _AiOverlayPainter extends CustomPainter {
  _AiOverlayPainter({
    required this.highlightedZone,
    required this.pulse,
  }) : super(repaint: pulse);

  final String? highlightedZone;
  final Animation<double>? pulse;

  bool _isZone(String zone) => highlightedZone == zone || highlightedZone == 'full_face';

  @override
  void paint(Canvas canvas, Size size) {
    final pulseBoost = pulse == null ? 0.0 : (pulse!.value * 0.28);

    final forehead = Paint()
      ..color = (_isZone('glabella') || _isZone('tzone'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x66D4AF37);
    final cheek = Paint()
      ..color = (_isZone('cheeks') || _isZone('cheeks_nose'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x664FAE8B);
    final tzone = Paint()
      ..color = (_isZone('tzone') || _isZone('cheeks_nose'))
          ? const Color(0xFFD4AF37).withValues(alpha: 0.22 + pulseBoost)
          : const Color(0x66C76A55);
    final jawline = Paint()
      ..color = _isZone('jawline')
          ? const Color(0xFFD4AF37).withValues(alpha: 0.20 + pulseBoost)
          : const Color(0x554FAE8B);

    final foreheadPath = Path()
      ..moveTo(size.width * 0.24, size.height * 0.20)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.06,
        size.width * 0.76,
        size.height * 0.20,
      )
      ..lineTo(size.width * 0.70, size.height * 0.33)
      ..lineTo(size.width * 0.30, size.height * 0.33)
      ..close();
    canvas.drawPath(foreheadPath, forehead);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.30, size.height * 0.58),
        width: size.width * 0.28,
        height: size.height * 0.24,
      ),
      cheek,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.70, size.height * 0.58),
        width: size.width * 0.28,
        height: size.height * 0.24,
      ),
      cheek,
    );

    final tzonePath = Path()
      ..moveTo(size.width * 0.44, size.height * 0.32)
      ..lineTo(size.width * 0.56, size.height * 0.32)
      ..lineTo(size.width * 0.62, size.height * 0.64)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.72,
        size.width * 0.38,
        size.height * 0.64,
      )
      ..close();
    canvas.drawPath(tzonePath, tzone);

    final jawlinePath = Path()
      ..moveTo(size.width * 0.22, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.92,
        size.width * 0.78,
        size.height * 0.78,
      )
      ..lineTo(size.width * 0.72, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.97,
        size.width * 0.28,
        size.height * 0.88,
      )
      ..close();
    canvas.drawPath(jawlinePath, jawline);
  }

  @override
  bool shouldRepaint(covariant _AiOverlayPainter oldDelegate) {
    return oldDelegate.highlightedZone != highlightedZone ||
        oldDelegate.pulse != pulse;
  }
}
