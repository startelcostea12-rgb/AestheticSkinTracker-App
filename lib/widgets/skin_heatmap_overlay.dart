import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Color channels used for heatmap semantics.
enum SkinHeatmapTone { redness, wrinkles, improvement }

/// Body map presets for procedure photos outside facial framing.
enum SkinHeatmapBodyRegion { abdomen, flanks, thighs, arms, breasts, generic }

/// A single soft-focus heatmap zone anchored to an [Alignment].
class SkinHeatmapSpot {
  const SkinHeatmapSpot({
    required this.alignment,
    required this.intensity,
    required this.radius,
    required this.tone,
  });

  final Alignment alignment;
  final double intensity;
  final double radius;
  final SkinHeatmapTone tone;
}

/// Reusable overlay that renders a photo plus semi-transparent heatmap glows.
///
/// This widget is intentionally generic: pass any [spots] layout for any
/// procedure, or use [SkinHeatmapOverlay.laser] for a laser-oriented default.
class SkinHeatmapOverlay extends StatelessWidget {
  const SkinHeatmapOverlay({
    super.key,
    required this.photo,
    required this.spots,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.showPhoto = true,
    this.imageOpacity = 1,
  });

  factory SkinHeatmapOverlay.laser({
    Key? key,
    required ImageProvider<Object> photo,
    required double redness,
    required double wrinkles,
    required double improvement,
    BoxFit fit = BoxFit.cover,
    BorderRadius borderRadius = BorderRadius.zero,
    bool showPhoto = true,
    double imageOpacity = 1,
  }) {
    final rednessN = _normalizeMetric(redness);
    final wrinkleN = _normalizeMetric(wrinkles);
    final improvedN = _normalizeMetric(improvement);

    return SkinHeatmapOverlay(
      key: key,
      photo: photo,
      fit: fit,
      borderRadius: borderRadius,
      showPhoto: showPhoto,
      imageOpacity: imageOpacity,
      spots: <SkinHeatmapSpot>[
        SkinHeatmapSpot(
          alignment: const Alignment(-0.34, -0.05),
          intensity: rednessN,
          radius: 0.22,
          tone: SkinHeatmapTone.redness,
        ),
        SkinHeatmapSpot(
          alignment: const Alignment(0.34, -0.05),
          intensity: rednessN * 0.94,
          radius: 0.22,
          tone: SkinHeatmapTone.redness,
        ),
        SkinHeatmapSpot(
          alignment: const Alignment(-0.22, -0.40),
          intensity: wrinkleN,
          radius: 0.20,
          tone: SkinHeatmapTone.wrinkles,
        ),
        SkinHeatmapSpot(
          alignment: const Alignment(0.22, -0.40),
          intensity: wrinkleN * 0.92,
          radius: 0.20,
          tone: SkinHeatmapTone.wrinkles,
        ),
        SkinHeatmapSpot(
          alignment: const Alignment(0.0, 0.25),
          intensity: improvedN,
          radius: 0.30,
          tone: SkinHeatmapTone.improvement,
        ),
      ],
    );
  }

  factory SkinHeatmapOverlay.bodyContouring({
    Key? key,
    required ImageProvider<Object> photo,
    required double inflammation,
    required double textureIrregularity,
    required double improvement,
    SkinHeatmapBodyRegion region = SkinHeatmapBodyRegion.generic,
    BoxFit fit = BoxFit.cover,
    BorderRadius borderRadius = BorderRadius.zero,
    bool showPhoto = true,
    double imageOpacity = 1,
  }) {
    final inflammationN = _normalizeMetric(inflammation);
    final textureN = _normalizeMetric(textureIrregularity);
    final improvedN = _normalizeMetric(improvement);

    return SkinHeatmapOverlay(
      key: key,
      photo: photo,
      fit: fit,
      borderRadius: borderRadius,
      showPhoto: showPhoto,
      imageOpacity: imageOpacity,
      spots: _bodySpots(
        region: region,
        inflammation: inflammationN,
        texture: textureN,
        improvement: improvedN,
      ),
    );
  }

  final ImageProvider<Object> photo;
  final List<SkinHeatmapSpot> spots;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool showPhoto;
  final double imageOpacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showPhoto)
            Opacity(
              opacity: imageOpacity.clamp(0, 1),
              child: Image(image: photo, fit: fit),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _SkinHeatmapPainter(spots),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.03),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.06),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _normalizeMetric(double value) {
    if (value <= 0) return 0;
    if (value <= 1) return value.clamp(0, 1);
    if (value <= 10) return (value / 10).clamp(0, 1);
    return (value / 100).clamp(0, 1);
  }

  static List<SkinHeatmapSpot> _bodySpots({
    required SkinHeatmapBodyRegion region,
    required double inflammation,
    required double texture,
    required double improvement,
  }) {
    switch (region) {
      case SkinHeatmapBodyRegion.abdomen:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, -0.08),
            intensity: inflammation,
            radius: 0.28,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.20),
            intensity: texture,
            radius: 0.24,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.32),
            intensity: improvement,
            radius: 0.26,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
      case SkinHeatmapBodyRegion.flanks:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(-0.48, 0.02),
            intensity: inflammation,
            radius: 0.22,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.48, 0.02),
            intensity: inflammation * 0.95,
            radius: 0.22,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(-0.34, 0.22),
            intensity: texture,
            radius: 0.20,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.34, 0.22),
            intensity: texture * 0.95,
            radius: 0.20,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.18),
            intensity: improvement,
            radius: 0.30,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
      case SkinHeatmapBodyRegion.thighs:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(-0.24, 0.36),
            intensity: inflammation,
            radius: 0.22,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.24, 0.36),
            intensity: inflammation * 0.95,
            radius: 0.22,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(-0.24, 0.56),
            intensity: texture,
            radius: 0.20,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.24, 0.56),
            intensity: texture * 0.95,
            radius: 0.20,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.46),
            intensity: improvement,
            radius: 0.32,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
      case SkinHeatmapBodyRegion.arms:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(-0.62, 0.08),
            intensity: inflammation,
            radius: 0.18,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.62, 0.08),
            intensity: inflammation * 0.95,
            radius: 0.18,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(-0.58, 0.28),
            intensity: texture,
            radius: 0.16,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.58, 0.28),
            intensity: texture * 0.95,
            radius: 0.16,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.14),
            intensity: improvement,
            radius: 0.30,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
      case SkinHeatmapBodyRegion.breasts:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(-0.28, -0.04),
            intensity: inflammation,
            radius: 0.20,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.28, -0.04),
            intensity: inflammation * 0.95,
            radius: 0.20,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(-0.22, 0.12),
            intensity: texture,
            radius: 0.16,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.22, 0.12),
            intensity: texture * 0.95,
            radius: 0.16,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.04),
            intensity: improvement,
            radius: 0.28,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
      case SkinHeatmapBodyRegion.generic:
        return <SkinHeatmapSpot>[
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, -0.04),
            intensity: inflammation,
            radius: 0.26,
            tone: SkinHeatmapTone.redness,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(-0.22, 0.20),
            intensity: texture,
            radius: 0.22,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.22, 0.20),
            intensity: texture * 0.92,
            radius: 0.22,
            tone: SkinHeatmapTone.wrinkles,
          ),
          SkinHeatmapSpot(
            alignment: const Alignment(0.0, 0.30),
            intensity: improvement,
            radius: 0.30,
            tone: SkinHeatmapTone.improvement,
          ),
        ];
    }
  }
}

class _SkinHeatmapPainter extends CustomPainter {
  const _SkinHeatmapPainter(this.spots);

  final List<SkinHeatmapSpot> spots;

  @override
  void paint(Canvas canvas, Size size) {
    if (spots.isEmpty) return;
    final shortest = math.min(size.width, size.height);

    for (final spot in spots) {
      final intensity = spot.intensity.clamp(0, 1).toDouble();
      if (intensity <= 0.01) continue;

      final center = Offset(
        ((spot.alignment.x + 1) / 2) * size.width,
        ((spot.alignment.y + 1) / 2) * size.height,
      );
      final radius = (shortest * spot.radius)
          .clamp(18.0, shortest * 0.6)
          .toDouble();
      final tone = _toneColor(spot.tone);

      final aura = Paint()
        ..shader = RadialGradient(
          colors: [
            tone.withValues(alpha: 0.34 * intensity),
            tone.withValues(alpha: 0.18 * intensity),
            tone.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, aura);

      final halo = Paint()
        ..color = tone.withValues(alpha: 0.12 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(center, radius * 0.68, halo);
    }
  }

  Color _toneColor(SkinHeatmapTone tone) {
    switch (tone) {
      case SkinHeatmapTone.redness:
        return const Color(0xFFE8505B);
      case SkinHeatmapTone.wrinkles:
        return const Color(0xFF4D77FF);
      case SkinHeatmapTone.improvement:
        return const Color(0xFF2FBF71);
    }
  }

  @override
  bool shouldRepaint(covariant _SkinHeatmapPainter oldDelegate) {
    return oldDelegate.spots != spots;
  }
}