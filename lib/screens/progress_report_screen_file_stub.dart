import 'package:flutter/material.dart';

bool canUseFileImage() => false;

Widget buildFileImage(String path) {
  // Show a placeholder icon on web
  return Container(
    height: 120,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.grey[200],
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
  );
}
