import 'package:flutter/material.dart';

class ImagePlaceholder extends StatelessWidget {
  final double? iconSize;
  final String? message;
  final Color? backgroundColor;

  const ImagePlaceholder({
    super.key,
    this.iconSize,
    this.message,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image,
              size: iconSize ?? 56,
              color: Colors.grey[500],
            ),
            const SizedBox(height: 12),
            Text(
              message ?? "Image unavailable",
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
