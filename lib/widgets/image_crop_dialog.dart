import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class NormalizedSquareCrop {
  const NormalizedSquareCrop({
    required this.left,
    required this.top,
    required this.size,
  });

  final double left;
  final double top;
  final double size;
}

class ImageCropSelection {
  const ImageCropSelection({required this.bytes, required this.region});

  final Uint8List bytes;
  final NormalizedSquareCrop region;
}

Uint8List applyNormalizedSquareCrop(
  Uint8List imageBytes,
  NormalizedSquareCrop region,
) {
  final source = img.decodeImage(imageBytes);
  if (source == null) return imageBytes;

  final sourceSize = math.min(source.width, source.height);
  final cropSize = (region.size * sourceSize)
      .round()
      .clamp(1, sourceSize)
      .toInt();
  final cropX = (region.left * source.width)
      .round()
      .clamp(0, source.width - cropSize)
      .toInt();
  final cropY = (region.top * source.height)
      .round()
      .clamp(0, source.height - cropSize)
      .toInt();
  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropSize,
    height: cropSize,
  );
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

/// Pure-Flutter manual crop dialog (web + mobile + desktop).
///
/// Replaces `image_cropper`, which is incompatible with Flutter 3.24+ on web.
/// Returns the cropped JPEG bytes via `Navigator.pop`, or `null` if the user
/// cancels. Use it with `showDialog<Uint8List>(...)`.
class ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final ValueChanged<ImageCropSelection>? onCropSelected;

  const ImageCropDialog({
    super.key,
    required this.imageBytes,
    this.onCropSelected,
  });

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  img.Image? _srcImage;

  double _containerW = 0;
  double _containerH = 0;
  double _cropLeft = 0;
  double _cropTop = 0;
  double _cropSize = 200;

  @override
  void initState() {
    super.initState();
    _srcImage = img.decodeImage(widget.imageBytes);
  }

  void _initCropRect(double w, double h) {
    _containerW = w;
    _containerH = h;
    _cropSize = math.min(w, h) * 0.78;
    _cropLeft = (w - _cropSize) / 2;
    _cropTop = (h - _cropSize) / 2;
  }

  void _clamp() {
    _cropLeft = _cropLeft.clamp(0.0, _containerW - _cropSize);
    _cropTop = _cropTop.clamp(0.0, _containerH - _cropSize);
  }

  Uint8List _doCrop() {
    final src = _srcImage;
    if (src == null) return widget.imageBytes;

    final imgW = src.width.toDouble();
    final imgH = src.height.toDouble();
    final scale = math.min(_containerW / imgW, _containerH / imgH);
    final displayW = imgW * scale;
    final displayH = imgH * scale;
    final offsetX = (_containerW - displayW) / 2;
    final offsetY = (_containerH - displayH) / 2;

    final srcX = ((_cropLeft - offsetX) / scale)
        .round()
        .clamp(0, src.width - 1)
        .toInt();
    final srcY = ((_cropTop - offsetY) / scale)
        .round()
        .clamp(0, src.height - 1)
        .toInt();
    final maxW = src.width - srcX;
    final maxH = src.height - srcY;
    final srcSize = (_cropSize / scale)
        .round()
        .clamp(1, math.min(maxW, maxH))
        .toInt();

    final region = NormalizedSquareCrop(
      left: srcX / imgW,
      top: srcY / imgH,
      size: srcSize / math.min(imgW, imgH),
    );
    final cropped = img.copyCrop(
      src,
      x: srcX,
      y: srcY,
      width: srcSize,
      height: srcSize,
    );
    final bytes = Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
    widget.onCropSelected?.call(ImageCropSelection(bytes: bytes, region: region));
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    if (_srcImage == null) {
      return const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.crop_rounded, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text(
                  'Select Skin Area',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Text(
                  'Drag to reposition',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = math.min(
                MediaQuery.of(context).size.height * 0.55,
                480.0,
              );
              if (_containerW != w || _containerH != h) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && (_containerW != w || _containerH != h)) {
                    setState(() => _initCropRect(w, h));
                  }
                });
                if (_containerW == 0) _initCropRect(w, h);
              }
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        widget.imageBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                    // Dark overlay — top
                    if (_cropTop > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        height: _cropTop,
                        child: const ColoredBox(color: Color(0x88000000)),
                      ),
                    // Dark overlay — bottom
                    if (_cropTop + _cropSize < h)
                      Positioned(
                        left: 0,
                        top: _cropTop + _cropSize,
                        right: 0,
                        height: h - _cropTop - _cropSize,
                        child: const ColoredBox(color: Color(0x88000000)),
                      ),
                    // Dark overlay — left
                    if (_cropLeft > 0)
                      Positioned(
                        left: 0,
                        top: _cropTop,
                        width: _cropLeft,
                        height: _cropSize,
                        child: const ColoredBox(color: Color(0x88000000)),
                      ),
                    // Dark overlay — right
                    if (_cropLeft + _cropSize < w)
                      Positioned(
                        left: _cropLeft + _cropSize,
                        top: _cropTop,
                        width: w - _cropLeft - _cropSize,
                        height: _cropSize,
                        child: const ColoredBox(color: Color(0x88000000)),
                      ),
                    // Draggable crop box
                    Positioned(
                      left: _cropLeft,
                      top: _cropTop,
                      width: _cropSize,
                      height: _cropSize,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (d) => setState(() {
                          _cropLeft += d.delta.dx;
                          _cropTop += d.delta.dy;
                          _clamp();
                        }),
                        child: CustomPaint(painter: _CropBoxPainter()),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: TextButton.styleFrom(foregroundColor: Colors.white54),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(_doCrop()),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Crop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CropBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), borderPaint);

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final t1 = size.width / 3;
    final t2 = t1 * 2;
    canvas.drawLine(Offset(t1, 0), Offset(t1, size.height), gridPaint);
    canvas.drawLine(Offset(t2, 0), Offset(t2, size.height), gridPaint);
    canvas.drawLine(Offset(0, t1), Offset(size.width, t1), gridPaint);
    canvas.drawLine(Offset(0, t2), Offset(size.width, t2), gridPaint);

    // Corner handles
    const hl = 16.0;
    final hp = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    // top-left
    canvas.drawLine(const Offset(0, hl), const Offset(0, 0), hp);
    canvas.drawLine(const Offset(0, 0), const Offset(hl, 0), hp);
    // top-right
    canvas.drawLine(Offset(w - hl, 0), Offset(w, 0), hp);
    canvas.drawLine(Offset(w, 0), Offset(w, hl), hp);
    // bottom-left
    canvas.drawLine(Offset(0, h - hl), Offset(0, h), hp);
    canvas.drawLine(Offset(0, h), Offset(hl, h), hp);
    // bottom-right
    canvas.drawLine(Offset(w, h - hl), Offset(w, h), hp);
    canvas.drawLine(Offset(w, h), Offset(w - hl, h), hp);
  }

  @override
  bool shouldRepaint(_CropBoxPainter old) => false;
}
