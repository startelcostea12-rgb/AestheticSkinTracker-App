import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// History / Track Procedure layout (not the live results view) for a
/// saved scan whose pigment_load has no backend trend_status, so the
/// app's own comparison runs and the extraction paths matter.
Future<String> _pigmentCard(
  WidgetTester tester, {
  required String currentPath,
  required String baselinePath,
  double baseline = 20.0,
  double current = 40.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 4000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LuxeReportLayout(
            rawPayload: {
              'is_follow_up': true,
              'local_history_count': 2,
              'metric_matrix': {'pigment_load': current},
              'baseline_metric_matrix': {'pigment_load': baseline},
              'metric_extraction_paths': {'pigment_load': currentPath},
              'baseline_metric_extraction_paths': {
                'pigment_load': baselinePath,
              },
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return find
      .descendant(
        of: find.byKey(const ValueKey('result_metric_pigment_load')),
        matching: find.byType(Text),
      )
      .evaluate()
      .map((e) => (e.widget as Text).data ?? '')
      .join(' | ');
}

void main() {
  testWidgets('same current path on both scans now compares (was always '
      '"Stable" because the path was treated as unknown)', (tester) async {
    final text = await _pigmentCard(
      tester,
      currentPath: 'cheek_primary',
      baselinePath: 'cheek_primary',
    );
    // pigment is higher-is-worse: 20 -> 40 is a real worsening.
    expect(text, contains('Worsened'));
    expect(text, isNot(contains('Stable')));
  });

  testWidgets('different known paths read as a standalone entry', (
    tester,
  ) async {
    final text = await _pigmentCard(
      tester,
      currentPath: 'full_face_fallback',
      baselinePath: 'cheek_primary',
    );
    expect(text, contains('Standalone entry'));
    expect(text, isNot(contains('Worsened')));
  });

  testWidgets('a path the app does not know still reads as Stable', (
    tester,
  ) async {
    final text = await _pigmentCard(
      tester,
      currentPath: 'something_new',
      baselinePath: 'cheek_primary',
    );
    expect(text, contains('Stable'));
    expect(text, isNot(contains('Worsened')));
    expect(text, isNot(contains('Standalone entry')));
  });

  testWidgets('old saved labels still load and compare', (tester) async {
    for (final label in const ['approximate_face_bbox', 'fallback']) {
      final text = await _pigmentCard(
        tester,
        currentPath: label,
        baselinePath: label,
      );
      expect(text, contains('Worsened'), reason: label);
    }
  });

  testWidgets('the current backend paths are all recognised', (tester) async {
    for (final path in const [
      'cheek_primary',
      'cheek_primary_no_skin_mask',
      'laplacian_fallback',
      'tzone_landmark_fallback',
      'tzone_face_fallback',
      'full_face_yolo',
    ]) {
      final text = await _pigmentCard(
        tester,
        currentPath: path,
        baselinePath: path,
      );
      expect(text, contains('Worsened'), reason: path);
    }
  });
}
