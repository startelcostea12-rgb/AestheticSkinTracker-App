import 'dart:convert';

import 'package:flutter/material.dart';

/// Web implementation. Renders base64 data URIs via [Image.memory] and
/// blob:/http(s) URLs (produced by the web image picker) via [Image.network].
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
  } else {
    // blob:, http, https — all readable by the browser via Image.network.
    image = Image.network(
      ref,
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
