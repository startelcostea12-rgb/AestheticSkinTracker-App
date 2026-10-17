// The fixed "Place gray card here" target drawn on the live face preview
// when the gray-card switch is on. Nothing to drag: at capture, the same
// rectangle (grayCardTargetInStill) is cut from each still as the sample.

import 'package:flutter/material.dart';

import '../utils/gray_card_region.dart';

class GrayCardTargetOverlay extends StatelessWidget {
  const GrayCardTargetOverlay({super.key});

  static const String label = 'Place gray card here';

  @override
  Widget build(BuildContext context) {
    const target = grayCardPreviewTarget;
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              children: [
                Positioned(
                  key: const ValueKey('gray_card_target'),
                  left: target.x * w,
                  top: target.y * h,
                  width: target.w * w,
                  height: target.h * h,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
