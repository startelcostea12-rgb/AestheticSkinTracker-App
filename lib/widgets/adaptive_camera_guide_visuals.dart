import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/procedure.dart';

class AdaptiveCameraOutline extends StatelessWidget {
  const AdaptiveCameraOutline({
    super.key,
    required this.guideType,
    this.height = 300,
    this.showTopGuides = true,
    this.showBottomLabel = true,
    this.angleChips = const <String>[],
    this.selectedAngleChip,
    this.poseTemplate,
    this.bottomLabel,
    this.useGlassBackground = true,
  });

  final ProcedureCameraGuideType guideType;
  final double height;
  final bool showTopGuides;
  final bool showBottomLabel;
  final List<String> angleChips;
  final String? selectedAngleChip;
  final String? poseTemplate;
  final String? bottomLabel;
  final bool useGlassBackground;

  double get _aspectRatio {
    switch (guideType) {
      case ProcedureCameraGuideType.facial:
        return 0.86;
      case ProcedureCameraGuideType.body:
        return 0.78;
      case ProcedureCameraGuideType.general:
        return 1.0;
    }
  }

  String get _defaultBottomLabel {
    switch (guideType) {
      case ProcedureCameraGuideType.facial:
        return 'Keep the face centered and capture the same front, profile, and 45-degree framing each time.';
      case ProcedureCameraGuideType.body:
        return 'Keep shoulders, torso, and treatment area aligned so contour changes remain comparable.';
      case ProcedureCameraGuideType.general:
        return 'Keep the same framing and distance so your progress scans stay trustworthy.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final centerLabel = switch (guideType) {
      ProcedureCameraGuideType.body => 'Center treatment area',
      ProcedureCameraGuideType.facial => 'Center facial frame',
      ProcedureCameraGuideType.general => 'Center subject',
    };

    return SizedBox(
      height: height,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: useGlassBackground
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.52),
                      MyApp.roseGold.withValues(alpha: 0.08),
                    ],
                  )
                : null,
            color: useGlassBackground ? null : Colors.transparent,
            border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GuideBackdropPainter(
                    accent: MyApp.goldShimmer.withValues(alpha: 0.26),
                    lineColor: MyApp.textBrown.withValues(alpha: 0.18),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CustomPaint(
                    painter: _GuideOutlinePainter(
                      guideType: guideType,
                      color: MyApp.textBrown.withValues(alpha: 0.56),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CustomPaint(
                    painter: _PoseTemplatePainter(
                      guideType: guideType,
                      poseTemplate: poseTemplate,
                      color: MyApp.goldShimmer.withValues(alpha: 0.92),
                    ),
                  ),
                ),
              ),
              if (showTopGuides && angleChips.isNotEmpty)
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: angleChips.map((chip) {
                      final selected = selectedAngleChip == chip;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? MyApp.goldShimmer.withValues(alpha: 0.28)
                              : Colors.white.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(999),
                          border: selected
                              ? Border.all(
                                  color: MyApp.goldShimmer.withValues(
                                    alpha: 0.76,
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          chip,
                          style: TextStyle(
                            color: MyApp.textBrown,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Positioned(
                top: 18,
                left: 18,
                right: 18,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    3,
                    (index) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: index == 2 ? 0 : 10),
                        height: 4,
                        decoration: BoxDecoration(
                          color: MyApp.goldShimmer.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                left: 18,
                right: 18,
                child: Row(
                  children: [
                    Expanded(
                      child: _GuidePill(
                        icon: Icons.center_focus_strong,
                        label: centerLabel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _GuidePill(
                        icon: Icons.wb_sunny_outlined,
                        label: 'Match lighting',
                      ),
                    ),
                  ],
                ),
              ),
              if (showBottomLabel)
                Positioned(
                  bottom: 72,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      bottomLabel ?? _defaultBottomLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: MyApp.textBrown,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraExampleImageCard extends StatelessWidget {
  const CameraExampleImageCard({
    super.key,
    required this.guideType,
    required this.title,
    required this.caption,
    required this.isGood,
  });

  final ProcedureCameraGuideType guideType;
  final String title;
  final String caption;
  final bool isGood;

  @override
  Widget build(BuildContext context) {
    final accent = isGood ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final badgeIcon = isGood ? Icons.check_circle : Icons.cancel;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(badgeIcon, color: accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CustomPaint(
                  painter: _ExampleFramePainter(
                    guideType: guideType,
                    accent: accent,
                    isGood: isGood,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              caption,
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.78),
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePill extends StatelessWidget {
  const _GuidePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: MyApp.goldShimmer, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: MyApp.textBrown,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideBackdropPainter extends CustomPainter {
  const _GuideBackdropPainter({required this.accent, required this.lineColor});

  final Color accent;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()..color = accent;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28)),
      fillPaint,
    );

    for (var i = 1; i < 4; i++) {
      final dy = size.height * (i / 4);
      canvas.drawLine(Offset(16, dy), Offset(size.width - 16, dy), linePaint);
    }

    for (var i = 1; i < 3; i++) {
      final dx = size.width * (i / 3);
      canvas.drawLine(Offset(dx, 16), Offset(dx, size.height - 16), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuideBackdropPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.lineColor != lineColor;
  }
}

class _GuideOutlinePainter extends CustomPainter {
  const _GuideOutlinePainter({required this.guideType, required this.color});

  final ProcedureCameraGuideType guideType;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    switch (guideType) {
      case ProcedureCameraGuideType.facial:
        _paintFacial(canvas, size, paint);
        break;
      case ProcedureCameraGuideType.body:
        _paintBody(canvas, size, paint);
        break;
      case ProcedureCameraGuideType.general:
        _paintGeneral(canvas, size, paint);
        break;
    }
  }

  void _paintFacial(Canvas canvas, Size size, Paint paint) {
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.42,
      height: size.height * 0.48,
    );
    canvas.drawOval(ovalRect, paint);

    final shoulderRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.78),
        width: size.width * 0.56,
        height: size.height * 0.18,
      ),
      const Radius.circular(999),
    );
    canvas.drawRRect(shoulderRect, paint..strokeWidth = 2.4);
  }

  void _paintBody(Canvas canvas, Size size, Paint paint) {
    final headRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.22),
      width: size.width * 0.2,
      height: size.width * 0.2,
    );
    canvas.drawOval(headRect, paint);

    final bodyPath = Path()
      ..moveTo(size.width * 0.34, size.height * 0.34)
      ..quadraticBezierTo(
        size.width * 0.26,
        size.height * 0.42,
        size.width * 0.28,
        size.height * 0.56,
      )
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.8,
        size.width * 0.42,
        size.height * 0.88,
      )
      ..lineTo(size.width * 0.58, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.7,
        size.height * 0.8,
        size.width * 0.72,
        size.height * 0.56,
      )
      ..quadraticBezierTo(
        size.width * 0.74,
        size.height * 0.42,
        size.width * 0.66,
        size.height * 0.34,
      )
      ..close();
    canvas.drawPath(bodyPath, paint);

    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.88),
      Offset(size.width * 0.38, size.height * 0.98),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.88),
      Offset(size.width * 0.62, size.height * 0.98),
      paint,
    );
  }

  void _paintGeneral(Canvas canvas, Size size, Paint paint) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.48),
        width: size.width * 0.64,
        height: size.height * 0.44,
      ),
      const Radius.circular(28),
    );
    canvas.drawRRect(frame, paint);
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.48),
      size.width * 0.1,
      paint..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(covariant _GuideOutlinePainter oldDelegate) {
    return oldDelegate.guideType != guideType || oldDelegate.color != color;
  }
}

class _ExampleFramePainter extends CustomPainter {
  const _ExampleFramePainter({
    required this.guideType,
    required this.accent,
    required this.isGood,
  });

  final ProcedureCameraGuideType guideType;
  final Color accent;
  final bool isGood;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, accent.withValues(alpha: 0.08)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final framePaint = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    final badPaint = Paint()
      ..color = accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final frame = Rect.fromLTWH(
      size.width * 0.14,
      size.height * 0.12,
      size.width * 0.72,
      size.height * 0.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(20)),
      framePaint,
    );

    final outlinePainter = _GuideOutlinePainter(
      guideType: guideType,
      color: accent.withValues(alpha: 0.82),
    );
    canvas.save();
    if (isGood) {
      canvas.translate(size.width * 0.02, size.height * 0.02);
    } else {
      canvas.translate(size.width * 0.1, size.height * 0.02);
      canvas.rotate(math.pi / 18);
    }
    outlinePainter.paint(canvas, Size(size.width * 0.82, size.height * 0.74));
    canvas.restore();

    if (!isGood) {
      canvas.drawLine(
        Offset(size.width * 0.18, size.height * 0.2),
        Offset(size.width * 0.82, size.height * 0.8),
        badPaint,
      );
      canvas.drawLine(
        Offset(size.width * 0.82, size.height * 0.2),
        Offset(size.width * 0.18, size.height * 0.8),
        badPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExampleFramePainter oldDelegate) {
    return oldDelegate.guideType != guideType ||
        oldDelegate.accent != accent ||
        oldDelegate.isGood != isGood;
  }
}

class _PoseTemplatePainter extends CustomPainter {
  const _PoseTemplatePainter({
    required this.guideType,
    required this.poseTemplate,
    required this.color,
  });

  final ProcedureCameraGuideType guideType;
  final String? poseTemplate;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final template = (poseTemplate ?? '').trim();
    if (template.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    if (guideType == ProcedureCameraGuideType.facial) {
      _paintFacialTemplate(canvas, size, template, paint);
      return;
    }
    if (guideType == ProcedureCameraGuideType.body) {
      _paintBodyTemplate(canvas, size, template, paint);
      return;
    }

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.2,
        size.width * 0.6,
        size.height * 0.58,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(rect, paint);
  }

  void _paintFacialTemplate(
    Canvas canvas,
    Size size,
    String template,
    Paint paint,
  ) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final headRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.44,
      height: size.height * 0.5,
    );

    if (template == 'Front') {
      canvas.drawOval(headRect, paint);
      canvas.drawLine(
        Offset(center.dx, headRect.top + 18),
        Offset(center.dx, headRect.bottom - 18),
        paint,
      );
      return;
    }

    final isLeft = template.contains('Left');
    final isProfile = template.contains('Profile');
    final shift = isLeft ? -size.width * 0.08 : size.width * 0.08;
    final tilt = isLeft ? -1.0 : 1.0;
    final profileWidth = isProfile ? size.width * 0.3 : size.width * 0.36;

    final profileRect = Rect.fromCenter(
      center: Offset(center.dx + shift, center.dy),
      width: profileWidth,
      height: size.height * 0.5,
    );
    canvas.drawOval(profileRect, paint);

    final noseStart = Offset(
      center.dx + (tilt * size.width * 0.1),
      center.dy - size.height * 0.04,
    );
    final nosePeak = Offset(
      center.dx + (tilt * size.width * 0.16),
      center.dy + size.height * 0.01,
    );
    final noseEnd = Offset(
      center.dx + (tilt * size.width * 0.1),
      center.dy + size.height * 0.04,
    );
    final nosePath = Path()
      ..moveTo(noseStart.dx, noseStart.dy)
      ..lineTo(nosePeak.dx, nosePeak.dy)
      ..lineTo(noseEnd.dx, noseEnd.dy);
    canvas.drawPath(nosePath, paint);

    if (!isProfile) {
      final cheek = Path()
        ..moveTo(
          center.dx + (tilt * size.width * 0.03),
          center.dy - size.height * 0.16,
        )
        ..quadraticBezierTo(
          center.dx + (tilt * size.width * 0.16),
          center.dy - size.height * 0.05,
          center.dx + (tilt * size.width * 0.08),
          center.dy + size.height * 0.14,
        );
      canvas.drawPath(cheek, paint);
    }
  }

  void _paintBodyTemplate(
    Canvas canvas,
    Size size,
    String template,
    Paint paint,
  ) {
    final centerX = size.width / 2;
    final centerY = size.height * 0.56;
    final back = template == 'Back';
    final side = template.contains('Side');
    final left = template.contains('Left');
    final right = template.contains('Right');

    final lateralShift = left
        ? -size.width * (side ? 0.08 : 0.04)
        : right
        ? size.width * (side ? 0.08 : 0.04)
        : 0.0;
    final torsoWidth = side ? size.width * 0.26 : size.width * 0.38;

    final head = Rect.fromCenter(
      center: Offset(centerX + lateralShift, size.height * 0.2),
      width: side ? size.width * 0.16 : size.width * 0.2,
      height: side ? size.width * 0.18 : size.width * 0.2,
    );
    canvas.drawOval(head, paint);

    final torso = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(centerX + lateralShift, centerY),
        width: torsoWidth,
        height: size.height * 0.58,
      ),
      const Radius.circular(34),
    );
    canvas.drawRRect(torso, paint);

    if (!back && !side) {
      canvas.drawLine(
        Offset(centerX + lateralShift, size.height * 0.32),
        Offset(centerX + lateralShift, size.height * 0.84),
        paint,
      );
    }

    if (back) {
      canvas.drawLine(
        Offset(centerX + lateralShift - torsoWidth * 0.28, size.height * 0.42),
        Offset(centerX + lateralShift + torsoWidth * 0.28, size.height * 0.42),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PoseTemplatePainter oldDelegate) {
    return oldDelegate.guideType != guideType ||
        oldDelegate.poseTemplate != poseTemplate ||
        oldDelegate.color != color;
  }
}
