import 'package:flutter/material.dart';

import '../app_theme.dart';

enum MetricDirectionality { lowerIsBetter, higherIsBetter }

const Map<String, MetricDirectionality> _metricDirectionality = {
  'redness': MetricDirectionality.lowerIsBetter,
  'texture': MetricDirectionality.lowerIsBetter,
  'wrinkle': MetricDirectionality.lowerIsBetter,
  'wrinkles': MetricDirectionality.lowerIsBetter,
  'pore': MetricDirectionality.lowerIsBetter,
  'pores': MetricDirectionality.lowerIsBetter,
  'dark spots': MetricDirectionality.lowerIsBetter,
  'darkspots': MetricDirectionality.lowerIsBetter,
  'swelling': MetricDirectionality.lowerIsBetter,
  'bruising': MetricDirectionality.lowerIsBetter,
  'skin laxity': MetricDirectionality.higherIsBetter,
  'scar visibility': MetricDirectionality.lowerIsBetter,
  'asymmetry': MetricDirectionality.lowerIsBetter,
  'eyelid swelling': MetricDirectionality.lowerIsBetter,
  'firmness': MetricDirectionality.higherIsBetter,
  'elasticity': MetricDirectionality.higherIsBetter,
  'shape definition': MetricDirectionality.higherIsBetter,
  'symmetry': MetricDirectionality.higherIsBetter,
  'tip refinement': MetricDirectionality.higherIsBetter,
  'jawline definition': MetricDirectionality.higherIsBetter,
  'neck tightness': MetricDirectionality.higherIsBetter,
  'lift': MetricDirectionality.higherIsBetter,
  'fat retention': MetricDirectionality.higherIsBetter,
  'contour smoothness': MetricDirectionality.higherIsBetter,
  'skin tightness': MetricDirectionality.higherIsBetter,
  'hooding reduction': MetricDirectionality.higherIsBetter,
  // Extended skin / wellness metrics
  'hydration': MetricDirectionality.higherIsBetter,
  'barrier health': MetricDirectionality.higherIsBetter,
  'evenness': MetricDirectionality.higherIsBetter,
  'tone': MetricDirectionality.higherIsBetter,
  'skin tone': MetricDirectionality.higherIsBetter,
  'pigmentation': MetricDirectionality.lowerIsBetter,
  'dark spots / pigmentation': MetricDirectionality.lowerIsBetter,
  'inflammation': MetricDirectionality.lowerIsBetter,
  'redness / swelling': MetricDirectionality.lowerIsBetter,
  'skin age': MetricDirectionality.lowerIsBetter,
  'biological age': MetricDirectionality.lowerIsBetter,
  // Body composition
  'weight': MetricDirectionality.lowerIsBetter,
  'weight loss': MetricDirectionality.higherIsBetter,
  'body fat': MetricDirectionality.lowerIsBetter,
  'body fat %': MetricDirectionality.lowerIsBetter,
  'waist': MetricDirectionality.lowerIsBetter,
  'waist circumference': MetricDirectionality.lowerIsBetter,
  'muscle mass': MetricDirectionality.higherIsBetter,
  'muscle retention': MetricDirectionality.higherIsBetter,
  'appetite control': MetricDirectionality.higherIsBetter,
  'satiety': MetricDirectionality.higherIsBetter,
  'body composition score': MetricDirectionality.higherIsBetter,
  // Canonical clinical metric labels (see SkinMetricRegistry).
  'erythema': MetricDirectionality.lowerIsBetter,
  'erythema (redness)': MetricDirectionality.lowerIsBetter,
  'skin texture quality': MetricDirectionality.lowerIsBetter,
  'skin texture': MetricDirectionality.lowerIsBetter,
  'rhytids': MetricDirectionality.lowerIsBetter,
  'rhytids (fine lines & wrinkles)': MetricDirectionality.lowerIsBetter,
  'fine lines & wrinkles': MetricDirectionality.lowerIsBetter,
  'fine lines / wrinkles': MetricDirectionality.lowerIsBetter,
  'pore visibility': MetricDirectionality.lowerIsBetter,
  'hyperpigmentation': MetricDirectionality.lowerIsBetter,
  'hyperpigmentation (dark spots)': MetricDirectionality.lowerIsBetter,
  'skin laxity (firmness / elasticity)': MetricDirectionality.higherIsBetter,
  'skin laxity (firmness)': MetricDirectionality.higherIsBetter,
  'skin tone uniformity': MetricDirectionality.higherIsBetter,
  'skin hydration level': MetricDirectionality.higherIsBetter,
  'inflammatory response': MetricDirectionality.lowerIsBetter,
  'global skin quality score': MetricDirectionality.higherIsBetter,
};

String _normalizeMetricLabel(String metricLabel) {
  return metricLabel
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class MetricTrend {
  const MetricTrend({
    required this.icon,
    required this.color,
    required this.change,
    required this.hasMeaningfulChange,
    required this.isImproved,
  });

  final IconData? icon;
  final Color? color;
  final double change;
  final bool hasMeaningfulChange;
  final bool isImproved;

  String get absoluteChangeText => change.abs().toStringAsFixed(1);
}

MetricTrend resolveMetricTrend(
  String metricLabel, {
  required double baseline,
  required double current,
  double threshold = 0.05,
  MetricDirectionality? directionalityOverride,
}) {
  final normalizedLabel = _normalizeMetricLabel(metricLabel);
  final change = current - baseline;
  final hasMeaningfulChange = change.abs() > threshold;
  final directionality =
      directionalityOverride ?? _metricDirectionality[normalizedLabel];

  if (!hasMeaningfulChange) {
    return MetricTrend(
      icon: null,
      color: null,
      change: change,
      hasMeaningfulChange: false,
      isImproved: false,
    );
  }

  if (directionality == null) {
    return MetricTrend(
      icon: change < 0 ? Icons.arrow_downward : Icons.arrow_upward,
      color: MyApp.roseGold,
      change: change,
      hasMeaningfulChange: true,
      isImproved: false,
    );
  }

  final isImproved = directionality == MetricDirectionality.lowerIsBetter
      ? change < 0
      : change > 0;
  final directionalIcon = change < 0
      ? Icons.arrow_downward
      : Icons.arrow_upward;

  return MetricTrend(
    icon: directionalIcon,
    color: isImproved ? MyApp.clinicalTeal : MyApp.roseGold,
    change: change,
    hasMeaningfulChange: true,
    isImproved: isImproved,
  );
}
