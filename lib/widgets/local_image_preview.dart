import 'package:flutter/material.dart';

import 'local_image_preview_stub.dart'
    if (dart.library.io) 'local_image_preview_io.dart'
    as impl;

Widget buildLocalImagePreview(
  String ref, {
  required double width,
  required double height,
  double borderRadius = 12,
}) {
  return impl.buildLocalImagePreview(
    ref,
    width: width,
    height: height,
    borderRadius: borderRadius,
  );
}
