// Results-screen check for scans marked as having a gray card: a small crop
// of the exact region that was sampled (the patch uploaded as
// gray_card_image), so the user can see whether the box caught the card or
// skin, plus whether main.py used or ignored it. Display only.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Plain-language reason a sampled card was ignored, from main.py's
/// gray_card_reason. Null for an unknown or missing reason.
String? grayCardIgnoredReasonText(Object? reason) => switch (reason) {
  'disagrees_with_scene' =>
    "Its colour didn't match the rest of the scene's lighting.",
  'implausible_card_color' =>
    'It read too colourful to be a gray card (often skin in the box).',
  'implausible_exposure' => 'It was too dark or too bright to read.',
  'insufficient_region_pixels' ||
  'empty_region' => 'Too little of it was visible.',
  'region_out_of_bounds' => 'The box fell outside the photo.',
  _ => null,
};

class GrayCardSampleCard extends StatelessWidget {
  const GrayCardSampleCard({
    super.key,
    required this.patch,
    required this.imageQuality,
  });

  /// The sampled region (PNG) from the first frame.
  final Uint8List patch;

  /// The scan's image_quality summary (summarizeGrayCardFrames).
  final Map<String, dynamic> imageQuality;

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    final applied = imageQuality['gray_card_correction_applied'] == true;
    final reason = grayCardIgnoredReasonText(imageQuality['gray_card_reason']);
    final offset = imageQuality['gray_card_chroma_offset'];
    return Container(
      key: const ValueKey('gray_card_sample_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              patch,
              key: const ValueKey('gray_card_sample_image'),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox(width: 72, height: 72),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  applied ? 'Gray card used' : 'Gray card ignored',
                  key: const ValueKey('gray_card_sample_status'),
                  style: const TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  applied
                      ? 'This is the area sampled for colour balance. '
                            'It should show only the gray card, not skin.'
                      : '${reason ?? 'It could not be used.'} '
                            'Automatic colour balance was used instead. '
                            'This is the area that was sampled.',
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.75),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                if (offset is num) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Colour offset ${offset.toStringAsFixed(1)} (limit 12)',
                    key: const ValueKey('gray_card_sample_offset'),
                    style: TextStyle(
                      color: ink.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
