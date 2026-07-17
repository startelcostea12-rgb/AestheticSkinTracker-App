import 'package:flutter/material.dart';

import '../app_theme.dart';

typedef BeforeAfterLayerBuilder =
  Widget Function(BuildContext context, ImageProvider<Object> image);

enum BeforeAfterTagSide { left, right }

class BeforeAfterMetricTag {
  const BeforeAfterMetricTag({
    required this.label,
    required this.value,
    this.side = BeforeAfterTagSide.left,
  });

  final String label;
  final String value;
  final BeforeAfterTagSide side;
}

class InteractiveBeforeAfterSlider extends StatefulWidget {
  const InteractiveBeforeAfterSlider({
    super.key,
    required this.beforeImage,
    required this.afterImage,
    this.beforeLayerBuilder,
    this.afterLayerBuilder,
    this.beforeLabel = 'Before',
    this.afterLabel = 'After',
    this.metricTags = const <BeforeAfterMetricTag>[],
    this.initialPosition = 0.5,
    this.aspectRatio = 1,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.snapPoints = const <double>[0.18, 0.35, 0.5, 0.65, 0.82],
    this.snapDuration = const Duration(milliseconds: 170),
  });

  final ImageProvider<Object> beforeImage;
  final ImageProvider<Object> afterImage;
  final BeforeAfterLayerBuilder? beforeLayerBuilder;
  final BeforeAfterLayerBuilder? afterLayerBuilder;
  final String beforeLabel;
  final String afterLabel;
  final List<BeforeAfterMetricTag> metricTags;
  final double initialPosition;
  final double aspectRatio;
  final BorderRadius borderRadius;
  final List<double> snapPoints;
  final Duration snapDuration;

  @override
  State<InteractiveBeforeAfterSlider> createState() =>
      _InteractiveBeforeAfterSliderState();
}

class _InteractiveBeforeAfterSliderState
    extends State<InteractiveBeforeAfterSlider>
    with SingleTickerProviderStateMixin {
  late double _position;
  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition.clamp(0.1, 0.9);
    _snapController = AnimationController(
      vsync: this,
      duration: widget.snapDuration,
    );
    _snapController.addListener(() {
      final animation = _snapAnimation;
      if (animation == null) return;
      setState(() => _position = animation.value);
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _updateByDx(double dx, double width) {
    _snapController.stop();
    setState(() {
      _position = (dx / width).clamp(0.05, 0.95);
    });
  }

  void _animateTo(double target) {
    final clampedTarget = target.clamp(0.05, 0.95);
    _snapController
      ..stop()
      ..duration = widget.snapDuration
      ..reset();
    _snapAnimation = Tween<double>(begin: _position, end: clampedTarget)
        .animate(
          CurvedAnimation(
            parent: _snapController,
            curve: Curves.easeOutCubic,
          ),
        );
    _snapController.forward();
  }

  double _nearestSnap(double value) {
    if (widget.snapPoints.isEmpty) return value;
    final normalized = value.clamp(0.05, 0.95);
    var best = widget.snapPoints.first.clamp(0.05, 0.95);
    var bestDistance = (best - normalized).abs();
    for (final snap in widget.snapPoints.skip(1)) {
      final candidate = snap.clamp(0.05, 0.95);
      final d = (candidate - normalized).abs();
      if (d < bestDistance) {
        best = candidate;
        bestDistance = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dividerX = constraints.maxWidth * _position;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              _updateByDx(details.localPosition.dx, constraints.maxWidth);
            },
            onHorizontalDragUpdate: (details) {
              _updateByDx(details.localPosition.dx, constraints.maxWidth);
            },
            onHorizontalDragEnd: (_) {
              _animateTo(_nearestSnap(_position));
            },
            onTapDown: (details) {
              final tapped =
                  (details.localPosition.dx / constraints.maxWidth).clamp(
                    0.05,
                    0.95,
                  );
              _animateTo(_nearestSnap(tapped));
            },
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.afterLayerBuilder?.call(context, widget.afterImage) ??
                      Image(
                        image: widget.afterImage,
                        fit: BoxFit.cover,
                      ),
                  ClipRect(
                    clipper: _LeftSplitClipper(_position),
                    child:
                        widget.beforeLayerBuilder
                            ?.call(context, widget.beforeImage) ??
                        Image(
                          image: widget.beforeImage,
                          fit: BoxFit.cover,
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
                              Colors.black.withValues(alpha: 0.08),
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.10),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _buildFloatingTags(constraints),
                    ),
                  ),
                  Positioned(
                    left: dividerX - 1.2,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2.4,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                  Positioned(
                    left: dividerX - 20,
                    top: (constraints.maxHeight / 2) - 20,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            MyApp.goldShimmer.withValues(alpha: 0.95),
                            MyApp.roseGold.withValues(alpha: 0.95),
                          ],
                        ),
                        border: Border.all(color: Colors.white, width: 1.6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.drag_indicator,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _labelPill(widget.beforeLabel),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: _labelPill(widget.afterLabel),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFloatingTags(BoxConstraints constraints) {
    if (widget.metricTags.isEmpty) {
      return const SizedBox.shrink();
    }

    final dividerX = constraints.maxWidth * _position;
    final topStart = constraints.maxHeight * 0.18;
    const tagGap = 34.0;

    final leftTags = widget.metricTags
        .where((t) => t.side == BeforeAfterTagSide.left)
        .toList();
    final rightTags = widget.metricTags
        .where((t) => t.side == BeforeAfterTagSide.right)
        .toList();

    final children = <Widget>[];

    for (var i = 0; i < leftTags.length; i++) {
      final desiredLeft = dividerX - 172;
      children.add(
        Positioned(
          left: desiredLeft.clamp(10.0, constraints.maxWidth - 166),
          top: topStart + (i * tagGap),
          child: _metricTag(leftTags[i]),
        ),
      );
    }

    for (var i = 0; i < rightTags.length; i++) {
      final desiredLeft = dividerX + 12;
      children.add(
        Positioned(
          left: desiredLeft.clamp(10.0, constraints.maxWidth - 166),
          top: topStart + (i * tagGap),
          child: _metricTag(rightTags[i]),
        ),
      );
    }

    return Stack(children: children);
  }

  Widget _metricTag(BeforeAfterMetricTag tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MyApp.champagne.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.46)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '${tag.label} ${tag.value}',
        style: TextStyle(
          color: MyApp.clinicalNavy,
          fontSize: 10.3,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.22,
        ),
      ),
    );
  }

  Widget _labelPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _LeftSplitClipper extends CustomClipper<Rect> {
  const _LeftSplitClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_LeftSplitClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}

class BeforeAfterSplitSlider extends InteractiveBeforeAfterSlider {
  const BeforeAfterSplitSlider({
    super.key,
    required super.beforeImage,
    required super.afterImage,
    super.beforeLayerBuilder,
    super.afterLayerBuilder,
    super.beforeLabel = 'Before',
    super.afterLabel = 'After',
    super.metricTags = const <BeforeAfterMetricTag>[],
    super.initialPosition = 0.5,
    super.aspectRatio = 1,
    super.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });
}

class InteractiveBeforeAfterSplitSlider extends InteractiveBeforeAfterSlider {
  const InteractiveBeforeAfterSplitSlider({
    super.key,
    required super.beforeImage,
    required super.afterImage,
    super.beforeLayerBuilder,
    super.afterLayerBuilder,
    super.beforeLabel = 'Before',
    super.afterLabel = 'After',
    super.metricTags = const <BeforeAfterMetricTag>[],
    super.initialPosition = 0.5,
    super.aspectRatio = 1,
    super.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.snapPoints = const <double>[0.18, 0.35, 0.5, 0.65, 0.82],
    super.snapDuration = const Duration(milliseconds: 170),
  });
}
