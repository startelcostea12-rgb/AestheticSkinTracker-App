import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

Widget buildLocalImagePreview(
  String ref, {
  required double width,
  required double height,
  double borderRadius = 12,
}) {
  if (ref.trim().isEmpty) {
    return const SizedBox.shrink();
  }

  Widget image;
  if (ref.startsWith('data:image')) {
    final comma = ref.indexOf(',');
    if (comma == -1) return const SizedBox.shrink();
    try {
      final bytes = base64Decode(ref.substring(comma + 1));
      image = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  } else if (ref.startsWith('http') || ref.startsWith('blob:')) {
    image = Image.network(
      ref,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  } else {
    final file = File(ref);
    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }
    image = Image.file(
      file,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: image,
  );
}
