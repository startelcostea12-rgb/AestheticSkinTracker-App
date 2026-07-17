import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A refined clinical-luxury loading indicator.
///
/// Renders softly glowing concentric champagne-gold rings with a sweeping
/// progress arc and an optional caption. Designed to replace bare
/// [CircularProgressIndicator] usages across the Premium Hub screens so the
/// loading experience matches the warm alabaster / champagne gold language.
class LuxeLoadingView extends StatefulWidget {
  const LuxeLoadingView({super.key, this.label, this.size = 64});

  /// Optional caption shown beneath the rings (e.g. "Loading notes…").
  final String? label;

  /// Diameter of the outer ring in logical pixels.
  final double size;

  @override
  State<LuxeLoadingView> createState() => _LuxeLoadingViewState();
}

class _LuxeLoadingViewState extends State<LuxeLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gold = MyApp.goldShimmer;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer soft glow halo.
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: gold.withValues(alpha: 0.22),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                // Concentric resting rings.
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: gold.withValues(alpha: 0.16),
                      width: 1.2,
                    ),
                  ),
                ),
                Container(
                  width: widget.size * 0.66,
                  height: widget.size * 0.66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: gold.withValues(alpha: 0.24),
                      width: 1.1,
                    ),
                  ),
                ),
                // Sweeping progress arc.
                SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(gold),
                    backgroundColor: Colors.transparent,
                  ),
                ),
                // Pulsing gold core.
                ScaleTransition(
                  scale: Tween<double>(begin: 0.78, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: Container(
                    width: widget.size * 0.20,
                    height: widget.size * 0.20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: gold.withValues(alpha: 0.9),
                      boxShadow: [
                        BoxShadow(
                          color: gold.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 18),
            Text(
              widget.label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: MyApp.textBrown.withValues(alpha: 0.66),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
