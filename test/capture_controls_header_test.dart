import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capture controls card as laid out on the camera screen: 16 px scroll
/// padding, 14 px card padding, and a 12 px-padded Reference Alignment panel.
Widget _card(String modeLabel, String status) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CaptureControlsHeader(modeLabel: modeLabel),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: ReferenceAlignmentRow(
                statusLabel: status,
                statusColor: Colors.green,
                referenceAvailable: true,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  for (final width in const [320.0, 375.0, 390.0]) {
    for (final mode in const [
      'Facial template set',
      'General template set',
      'Body template set',
    ]) {
      testWidgets('no overflow stripe at $width wide ($mode)', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _card(mode, 'Live Pose Detection • Standard Reference'),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Progress Capture Controls'), findsOneWidget);
        expect(find.text(mode), findsOneWidget);
        expect(find.text('Reference Alignment'), findsOneWidget);
      });
    }
  }

  testWidgets('header texts wrap or ellipsize instead of overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CaptureControlsHeader(modeLabel: 'Facial template set'),
        ),
      ),
    );
    for (final key in const [
      'capture-controls-title',
      'capture-controls-mode',
    ]) {
      final text = tester.widget<Text>(find.byKey(ValueKey(key)));
      expect(text.maxLines, 2, reason: key);
      expect(text.overflow, TextOverflow.ellipsis, reason: key);
    }
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets(
        'reference status stays inside panel at $width scale $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 42),
                    child: ReferenceAlignmentRow(
                      key: const ValueKey('alignment-panel'),
                      statusLabel: 'Live Pose Detection • Standard Reference',
                      statusColor: Colors.green,
                      referenceAvailable: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final panel = tester.getRect(
            find.byKey(const ValueKey('alignment-panel')),
          );
          final status = tester.getRect(
            find.byKey(const ValueKey('reference-alignment-status')),
          );
          expect(status.left, greaterThanOrEqualTo(panel.left));
          expect(status.right, lessThanOrEqualTo(panel.right));
          expect(status.bottom, lessThanOrEqualTo(panel.bottom));
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('reference-alignment-status')),
                )
                .data,
            'Live Pose Detection • Standard Reference',
          );
        },
      );
    }
  }
}
