import 'package:flutter/material.dart';

class AppBrandTitle extends StatelessWidget {
  const AppBrandTitle({
    super.key,
    this.height = 46,
    this.maxWidth = 228,
    this.verticalPadding = 2,
    this.alignment = Alignment.center,
  });

  final double height;
  final double maxWidth;
  final double verticalPadding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: SizedBox(
          height: height,
          width: maxWidth,
          child: Center(
            child: Image.asset(
              'assets/logo/logo.png',
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => Icon(
                Icons.spa_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: height * 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
