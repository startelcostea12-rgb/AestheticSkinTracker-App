// Optional step after an AI scan capture: the user taps or drags a box on
// the gray card in the captured still. The square that will be uploaded is
// outlined, since only the part of the card inside it can be used. Returns
// the box as fractions of the still, or null when skipped.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/gray_card_region.dart';
import 'image_crop_dialog.dart' show NormalizedSquareCrop;

class GrayCardMarkDialog extends StatefulWidget {
  const GrayCardMarkDialog({
    super.key,
    required this.imageBytes,
    required this.stillWidth,
    required this.stillHeight,
    required this.uploadCrop,
  });

  final Uint8List imageBytes;
  final int stillWidth;
  final int stillHeight;
  final NormalizedSquareCrop uploadCrop;

  /// Side of the box a single tap places, as a fraction of the still's
  /// shorter side.
  static const double tapBoxFraction = 0.12;

  @override
  State<GrayCardMarkDialog> createState() => _GrayCardMarkDialogState();
}

class _GrayCardMarkDialogState extends State<GrayCardMarkDialog> {
  GrayCardRegion? _box;
  Offset? _dragStart;

  Offset _fraction(Offset local, Size size) => Offset(
    (local.dx / size.width).clamp(0.0, 1.0),
    (local.dy / size.height).clamp(0.0, 1.0),
  );

  void _tap(Offset local, Size size) {
    final f = _fraction(local, size);
    final shorter = widget.stillWidth < widget.stillHeight
        ? widget.stillWidth
        : widget.stillHeight;
    final w = GrayCardMarkDialog.tapBoxFraction * shorter / widget.stillWidth;
    final h = GrayCardMarkDialog.tapBoxFraction * shorter / widget.stillHeight;
    setState(() {
      _box = (
        x: (f.dx - w / 2).clamp(0.0, 1.0 - w),
        y: (f.dy - h / 2).clamp(0.0, 1.0 - h),
        w: w,
        h: h,
      );
    });
  }

  void _drag(Offset local, Size size) {
    final start = _dragStart;
    if (start == null) return;
    final end = _fraction(local, size);
    final x = start.dx < end.dx ? start.dx : end.dx;
    final y = start.dy < end.dy ? start.dy : end.dy;
    setState(() {
      _box = (
        x: x,
        y: y,
        w: (start.dx - end.dx).abs(),
        h: (start.dy - end.dy).abs(),
      );
    });
  }

  GrayCardRegion? get _uploadedRegion {
    final box = _box;
    if (box == null) return null;
    return grayCardRegionInUploadedFrame(
      stillBox: box,
      stillWidth: widget.stillWidth,
      stillHeight: widget.stillHeight,
      crop: widget.uploadCrop,
    );
  }

  Rect _uploadSquare(Size size) {
    final crop = widget.uploadCrop;
    final shorter = widget.stillWidth < widget.stillHeight
        ? widget.stillWidth
        : widget.stillHeight;
    final side = (crop.size * shorter).clamp(1, shorter).toDouble();
    final left = (crop.left * widget.stillWidth).clamp(
      0.0,
      widget.stillWidth - side,
    );
    final top = (crop.top * widget.stillHeight).clamp(
      0.0,
      widget.stillHeight - side,
    );
    final sx = size.width / widget.stillWidth;
    final sy = size.height / widget.stillHeight;
    return Rect.fromLTWH(left * sx, top * sy, side * sx, side * sy);
  }

  @override
  Widget build(BuildContext context) {
    final box = _box;
    final hasUsableBox = _uploadedRegion != null;
    return AlertDialog(
      title: const Text('Mark the gray card'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tap the card, or drag a box over it. Only the part inside the '
              'outlined square is uploaded.',
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ConstrainedBox(
                // Keeps the dialog on screen for tall stills / short screens.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: AspectRatio(
                  aspectRatio: widget.stillWidth / widget.stillHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      return GestureDetector(
                        key: const ValueKey('gray_card_mark_area'),
                        onTapUp: (d) => _tap(d.localPosition, size),
                        onPanStart: (d) =>
                            _dragStart = _fraction(d.localPosition, size),
                        onPanUpdate: (d) => _drag(d.localPosition, size),
                        onPanEnd: (_) => _dragStart = null,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              widget.imageBytes,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                            Positioned.fromRect(
                              rect: _uploadSquare(size),
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (box != null)
                              Positioned(
                                left: box.x * size.width,
                                top: box.y * size.height,
                                width: box.w * size.width,
                                height: box.h * size.height,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    key: const ValueKey('gray_card_box'),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.brandAccent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (box != null && !hasUsableBox) ...[
              const SizedBox(height: 8),
              const Text(
                'That box is outside the uploaded square, so it can\'t be '
                'used. Move the card closer to your face or skip.',
                key: ValueKey('gray_card_outside_note'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('gray_card_skip'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          key: const ValueKey('gray_card_use'),
          onPressed: hasUsableBox
              ? () => Navigator.of(context).pop<GrayCardRegion>(box)
              : null,
          child: const Text('Use this box'),
        ),
      ],
    );
  }
}
