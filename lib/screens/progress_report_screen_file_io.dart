import 'dart:io';
import 'package:flutter/material.dart';
import '../app_theme.dart';

bool canUseFileImage() => true;

Widget buildFileImage(String path) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.file(
      File(path),
      height: 120,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          buildCleanImagePlaceholder(),
    ),
  );
}

/// Shared clean placeholder for all image errors (no X icon ever)
Widget buildCleanImagePlaceholder() {
  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.grey[200]!,
          Colors.grey[100]!,
          MyApp.champagne.withValues(alpha: 0.3),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_camera_back, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            'Image unavailable',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}
