import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders exactly what the real top status card and the real "Smart
/// lighting guidance" chip show, for a given lighting level, using the same
/// production functions ([resolveReadyCameraStatusBarContent] and
/// [lightingChipLabelForLevel]) the actual widget calls. This is the
/// smallest possible real widget tree that can catch a regression of the
/// bug: the top card claiming "Optimal" while the chip says otherwise for
/// the same live frame.
class _StatusAndChipHarness extends StatelessWidget {
  const _StatusAndChipHarness({required this.level});

  final LightingLevel level;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveReadyCameraStatusBarContent(
      streamLive: true,
      isWeb: false,
      lightingLevel: level,
    );
    final chipLabel = lightingChipLabelForLevel(level);

    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Text('badge:${resolved.badgeLabel}'),
            Text('primary:${resolved.primaryStatus}'),
            Text('chip:$chipLabel'),
          ],
        ),
      ),
    );
  }
}

/// Whether a piece of top-card text and the chip text both claim optimal
/// lighting, or both claim non-optimal lighting -- the two must always
/// agree on this, even though their exact wording differs.
bool _claimsOptimal(String text) {
  final lower = text.toLowerCase();
  return lower.contains('optimal') || lower.contains('well-calibrated');
}

bool _claimsNonOptimal(String text) {
  final lower = text.toLowerCase();
  return lower.contains('dim') ||
      lower.contains('dark') ||
      lower.contains('harsh') ||
      lower.contains('bright') ||
      lower.contains('calibrat');
}

void main() {
  for (final level in LightingLevel.values) {
    testWidgets(
      'top status card and lighting chip never contradict for LightingLevel.$level',
      (tester) async {
        await tester.pumpWidget(_StatusAndChipHarness(level: level));

        final badgeFinder = find.textContaining('badge:');
        final primaryFinder = find.textContaining('primary:');
        final chipFinder = find.textContaining('chip:');

        expect(badgeFinder, findsOneWidget);
        expect(primaryFinder, findsOneWidget);
        expect(chipFinder, findsOneWidget);

        final badgeText = tester.widget<Text>(badgeFinder).data!;
        final primaryText = tester.widget<Text>(primaryFinder).data!;
        final chipText = tester.widget<Text>(chipFinder).data!;

        final chipSaysOptimal = _claimsOptimal(chipText);
        final chipSaysNonOptimal = _claimsNonOptimal(chipText);

        if (level == LightingLevel.optimal) {
          expect(chipSaysOptimal, isTrue);
          expect(
            _claimsOptimal(badgeText) || _claimsOptimal(primaryText),
            isTrue,
            reason: 'chip says optimal, so the top card must too: $badgeText / $primaryText',
          );
          expect(
            _claimsNonOptimal(badgeText),
            isFalse,
            reason: 'chip says optimal, top card badge must not claim otherwise: $badgeText',
          );
        } else {
          expect(chipSaysNonOptimal, isTrue);
          expect(
            _claimsOptimal(badgeText),
            isFalse,
            reason:
                'chip says "$chipText" (not optimal), but top card badge said "$badgeText" -- '
                'exactly the contradiction this test guards against.',
          );
          expect(
            _claimsOptimal(primaryText),
            isFalse,
            reason:
                'chip says "$chipText" (not optimal), but top card primary status said '
                '"$primaryText" -- exactly the contradiction this test guards against.',
          );
        }
      },
    );
  }
}
