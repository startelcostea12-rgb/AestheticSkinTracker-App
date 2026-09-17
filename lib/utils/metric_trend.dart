import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

const Map<String, bool> _metricLowerIsBetter = {
  'redness': true,
  'texture': true,
  'wrinkle': true,
  'wrinkles': true,
  'pore': true,
  'pores': true,
  'dark spots': true,
  'darkspots': true,
  'swelling': true,
  'bruising': true,
  'skin laxity': false,
  'scar visibility': true,
  'asymmetry': true,
  'eyelid swelling': true,
  'firmness': false,
  'elasticity': false,
  'shape definition': false,
  'symmetry': false,
  'tip refinement': false,
  'jawline definition': false,
  'neck tightness': false,
  'lift': false,
  'fat retention': false,
  'contour smoothness': false,
  'skin tightness': false,
  'hooding reduction': false,
  // Extended skin / wellness metrics
  'hydration': false,
  'barrier health': false,
  'evenness': false,
  'tone': false,
  'skin tone': false,
  'pigmentation': true,
  'dark spots / pigmentation': true,
  'inflammation': true,
  'redness / swelling': true,
  'skin age': true,
  'biological age': true,
  // Body composition
  'weight': true,
  'weight loss': false,
  'body fat': true,
  'body fat %': true,
  'waist': true,
  'waist circumference': true,
  'muscle mass': false,
  'muscle retention': false,
  'appetite control': false,
  'satiety': false,
  'body composition score': false,
  // Canonical clinical metric labels (see SkinMetricRegistry).
  'erythema': true,
  'erythema (redness)': true,
  'skin texture quality': true,
  'skin texture': true,
  'rhytids': true,
  'rhytids (fine lines & wrinkles)': true,
  'fine lines & wrinkles': true,
  'fine lines / wrinkles': true,
  'pore visibility': true,
  'localized redness': true,
  'pigment load': true,
  'breakout activity': true,
  'wrinkle load': true,
  'diffuse flushing erythema': true,
  'hyperpigmentation': true,
  'hyperpigmentation (dark spots)': true,
  'skin laxity (firmness / elasticity)': false,
  'skin laxity (firmness)': false,
  'texture smoothness': false,
  'skin tone uniformity': false,
  'skin tone radiance evenness': false,
  'structural firmness elasticity': false,
  'skin hydration level': false,
  'skin hydration': false,
  'inflammatory response': true,
  'rosacea severity': true,
  'global skin quality score': false,
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
  bool? lowerIsBetterOverride,
}) {
  final normalizedLabel = _normalizeMetricLabel(metricLabel);
  final change = current - baseline;
  final hasMeaningfulChange = change.abs() > threshold;
  final lowerIsBetter =
      lowerIsBetterOverride ?? _metricLowerIsBetter[normalizedLabel];

  if (!hasMeaningfulChange) {
    return MetricTrend(
      icon: null,
      color: null,
      change: change,
      hasMeaningfulChange: false,
      isImproved: false,
    );
  }

  if (lowerIsBetter == null) {
    return MetricTrend(
      icon: change < 0 ? Icons.arrow_downward : Icons.arrow_upward,
      color: AppColors.kMetricWorsenedColor,
      change: change,
      hasMeaningfulChange: true,
      isImproved: false,
    );
  }

  final isImproved = lowerIsBetter ? change < 0 : change > 0;
  final directionalIcon = change < 0
      ? Icons.arrow_downward
      : Icons.arrow_upward;

  return MetricTrend(
    icon: directionalIcon,
    color: isImproved
        ? AppColors.kMetricImprovedColor
        : AppColors.kMetricWorsenedColor,
    change: change,
    hasMeaningfulChange: true,
    isImproved: isImproved,
  );
}
