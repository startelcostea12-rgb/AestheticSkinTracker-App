// lib/widgets/clinical_camera_guidance.dart
//
// Clinical-grade real-time guidance system for the camera. Provides:
//   - [QualityState]   — green / yellow / red traffic light for a single signal
//   - [ClinicalQualityReport] — aggregate of four signals (distance, head
//     angle, lighting, expression) + a single rotating primary instruction
//   - [ClinicalCameraOverlayPainter] — face-alignment oval with cross-hairs
//     for the eyes, nose bridge, and jawline. Tints from amber → teal as the
//     subject's alignment improves.
//   - [ClinicalQualityIndicators] — horizontal row of compact status chips
//     suitable for placement above the capture button.
//   - [ClinicalCaptureButton] — the gated capture surface. Renders an
//     auto-capture countdown ring when [countdownProgress] is non-null.
//
// All visuals follow the clinical palette: navy / teal / rose-gold / champagne.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────
// Quality model
// ─────────────────────────────────────────────────────────────────────────

enum QualityState { red, yellow, green }

extension QualityStateExt on QualityState {
  Color get color {
    switch (this) {
      case QualityState.green:
        return const Color(0xFF2E7D32);
      case QualityState.yellow:
        return const Color(0xFFC77E10);
      case QualityState.red:
        return const Color(0xFFB23A48);
    }
  }

  IconData get icon {
    switch (this) {
      case QualityState.green:
        return Icons.check_circle_rounded;
      case QualityState.yellow:
        return Icons.error_outline_rounded;
      case QualityState.red:
        return Icons.cancel_outlined;
    }
  }
}

class QualitySignal {
  const QualitySignal({
    required this.label,
    required this.state,
    required this.detail,
    this.icon,
  });

  final String label;
  final QualityState state;
  final String detail;
  final IconData? icon;
}

class ClinicalQualityReport {
  const ClinicalQualityReport({
    required this.distance,
    required this.headAngle,
    required this.lighting,
    required this.expression,
    required this.primaryInstruction,
  });

  final QualitySignal distance;
  final QualitySignal headAngle;
  final QualitySignal lighting;
  final QualitySignal expression;
  final String primaryInstruction;

  List<QualitySignal> get all => [distance, headAngle, lighting, expression];

  bool get allGreen => all.every((s) => s.state == QualityState.green);
  bool get acceptable => all.every((s) => s.state != QualityState.red);

  /// 0..1 aggregate score (green=1.0, yellow=0.55, red=0.10).
  double get aggregateScore {
    double v(QualityState s) {
      switch (s) {
        case QualityState.green:
          return 1.0;
        case QualityState.yellow:
          return 0.55;
        case QualityState.red:
          return 0.10;
      }
    }

    return (v(distance.state) +
            v(headAngle.state) +
            v(lighting.state) +
            v(expression.state)) /
        4.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────

/// Draws an oval face-alignment guide with thirds gridlines, eye-line and
/// jawline cross-hairs, and a clipped-out vignette outside the oval. The
/// oval colour and stroke weight reflect [score] (0..1).
class ClinicalCameraOverlayPainter extends CustomPainter {
  ClinicalCameraOverlayPainter({
    required this.score,
    required this.pulse,
    this.bodyMode = false,
  });

  final double score;
  final double pulse;
  final bool bodyMode;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2.0;
    final cy = h / 2.0;

    // Facial mode uses a 0.62 × 0.78 oval. Body mode uses a taller,
    // narrower rounded-rect "capsule" instead of an oval — a stretched
    // oval still reads as a face guide, whereas a capsule silhouette is
    // the standard shape for a full-body framing guide.
    final ovalW = w * (bodyMode ? 0.55 : 0.62);
    final ovalH = h * (bodyMode ? 0.86 : 0.78);
    final guideRect = Rect.fromCenter(
      center: Offset(cx, cy - h * 0.02),
      width: ovalW,
      height: ovalH,
    );
    final bodyRRect = RRect.fromRectAndRadius(
      guideRect,
      Radius.circular(ovalW * 0.42),
    );

    Path outlinePath() =>
        bodyMode ? (Path()..addRRect(bodyRRect)) : (Path()..addOval(guideRect));

    // ── Outer scrim — dim everything outside the guide shape ─────────────
    final scrimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, w, h))
      ..addPath(outlinePath(), Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // ── Outline stroke ─────────────────────────────────────────────────
    final tint = Color.lerp(
      const Color(0xFFB23A48), // red on poor alignment
      const Color(0xFF2E7D32), // green on optimal alignment
      score.clamp(0.0, 1.0),
    )!;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 + (pulse * 1.4)
      ..color = tint.withValues(alpha: 0.92);

    if (bodyMode) {
      canvas.drawRRect(bodyRRect, stroke);
    } else {
      canvas.drawOval(guideRect, stroke);
    }

    // Inner ghosted outline — subtle parallax to read as "depth".
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.20);
    if (bodyMode) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          guideRect.deflate(6),
          Radius.circular((ovalW - 12) * 0.42),
        ),
        innerPaint,
      );
    } else {
      canvas.drawOval(guideRect.deflate(6), innerPaint);
    }

    // ovalRect retained under its historical name below for the
    // still-shared face-only drawing code (grid, crosshairs, jaw arc).
    final ovalRect = guideRect;

    if (bodyMode) {
      // Body mode: vertical centerline only.
      canvas.drawLine(
        Offset(cx, ovalRect.top + 12),
        Offset(cx, ovalRect.bottom - 12),
        Paint()
          ..color = tint.withValues(alpha: 0.35)
          ..strokeWidth = 1.0,
      );
      return;
    }

    // ── Rule-of-thirds inside oval (faint) ───────────────────────────────
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 0.7;

    final third = ovalRect.height / 3.0;
    final thirdW = ovalRect.width / 3.0;
    canvas.save();
    canvas.clipPath(Path()..addOval(ovalRect));
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.top + third),
      Offset(ovalRect.right, ovalRect.top + third),
      gridPaint,
    );
    canvas.drawLine(
      Offset(ovalRect.left, ovalRect.top + 2 * third),
      Offset(ovalRect.right, ovalRect.top + 2 * third),
      gridPaint,
    );
    canvas.drawLine(
      Offset(ovalRect.left + thirdW, ovalRect.top),
      Offset(ovalRect.left + thirdW, ovalRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(ovalRect.left + 2 * thirdW, ovalRect.top),
      Offset(ovalRect.left + 2 * thirdW, ovalRect.bottom),
      gridPaint,
    );
    canvas.restore();

    // ── Eye line (upper-third) cross-hair ────────────────────────────────
    final eyeLineY = ovalRect.top + ovalRect.height * 0.38;
    final eyeOffset = ovalRect.width * 0.18;
    _drawCross(canvas, Offset(cx - eyeOffset, eyeLineY), tint, 9);
    _drawCross(canvas, Offset(cx + eyeOffset, eyeLineY), tint, 9);

    // ── Nose-bridge marker (centerline) ──────────────────────────────────
    canvas.drawLine(
      Offset(cx, eyeLineY + 6),
      Offset(cx, ovalRect.top + ovalRect.height * 0.62),
      Paint()
        ..color = tint.withValues(alpha: 0.55)
        ..strokeWidth = 1.2,
    );
    _drawCross(
      canvas,
      Offset(cx, ovalRect.top + ovalRect.height * 0.62),
      tint,
      7,
    );

    // ── Jawline arc (lower portion) ──────────────────────────────────────
    final jawRect = Rect.fromCenter(
      center: Offset(cx, ovalRect.top + ovalRect.height * 0.78),
      width: ovalRect.width * 0.74,
      height: ovalRect.height * 0.36,
    );
    canvas.drawArc(
      jawRect,
      math.pi * 0.15,
      math.pi * 0.70,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = tint.withValues(alpha: 0.55),
    );
  }

  void _drawCross(Canvas canvas, Offset c, Color color, double r) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), p);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), p);
    canvas.drawCircle(c, 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant ClinicalCameraOverlayPainter old) {
    return old.score != score || old.pulse != pulse || old.bodyMode != bodyMode;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Quality indicator chips
// ─────────────────────────────────────────────────────────────────────────

class ClinicalQualityIndicators extends StatelessWidget {
  const ClinicalQualityIndicators({super.key, required this.report});
  final ClinicalQualityReport report;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: report.all
          .map((s) => Expanded(child: _Chip(signal: s)))
          .toList(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.signal});
  final QualitySignal signal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: signal.state.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: signal.state.color.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(signal.state.icon, color: signal.state.color, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    signal.label.toUpperCase(),
                    style: TextStyle(
                      color: signal.state.color,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              signal.detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Capture button + countdown
// ─────────────────────────────────────────────────────────────────────────

class ClinicalCaptureButton extends StatelessWidget {
  const ClinicalCaptureButton({
    super.key,
    required this.onPressed,
    required this.enabled,
    required this.busy,
    this.countdownProgress, // 0..1 when counting down, else null
    this.countdownLabel,
  });

  final VoidCallback? onPressed;
  final bool enabled;
  final bool busy;
  final double? countdownProgress;
  final String? countdownLabel;

  @override
  Widget build(BuildContext context) {
    final accent = enabled ? MyApp.clinicalTeal : MyApp.clinicalMuted;
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (countdownProgress != null)
            SizedBox(
              width: 86,
              height: 86,
              child: CircularProgressIndicator(
                value: countdownProgress!.clamp(0.0, 1.0),
                strokeWidth: 4,
                valueColor: AlwaysStoppedAnimation<Color>(MyApp.clinicalTeal),
                backgroundColor: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          GestureDetector(
            onTap: (busy || onPressed == null) ? null : onPressed,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: enabled
                      ? [MyApp.clinicalTeal, MyApp.clinicalNavy]
                      : [
                          MyApp.clinicalMuted.withValues(alpha: 0.55),
                          MyApp.clinicalMuted.withValues(alpha: 0.85),
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.42),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 3,
                ),
              ),
              child: Center(
                child: busy
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
              ),
            ),
          ),
          if (countdownLabel != null && countdownLabel!.isNotEmpty)
            Positioned(
              bottom: -22,
              child: Text(
                countdownLabel!,
                style: TextStyle(
                  color: MyApp.clinicalTeal,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
