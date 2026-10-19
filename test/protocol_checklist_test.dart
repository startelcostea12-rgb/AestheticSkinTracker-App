import 'dart:io';

import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/protocol_checklist.dart';
import 'package:aesthetic_skin_tracker/widgets/protocol_checklist_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _frontKey = ScanHistoryEntry.resolveAiBaselineKey(
  procedureId: null,
  focusArea: 'Full face',
  poseTemplate: 'Front',
  guideType: 'facial',
);

Future<String?> _token() =>
    frontBaselineResetToken(procedureId: null, focusArea: 'Full face');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'shown once per Front baseline reset, remembered after dismissal',
    () async {
      // No reset: nothing to show.
      expect(await _token(), isNull);
      expect(await shouldShowProtocolChecklist(await _token()), isFalse);

      // Reset: shown until dismissed.
      final firstReset = DateTime.utc(2026, 10, 19, 8);
      await AppPrefs.clearAiBaselineScanId(_frontKey, resetAt: firstReset);
      final token = await _token();
      expect(token, firstReset.toIso8601String());
      expect(await shouldShowProtocolChecklist(token), isTrue);
      await dismissProtocolChecklist(token!);
      expect(await shouldShowProtocolChecklist(await _token()), isFalse);

      // The next reset shows it again.
      final secondReset = DateTime.utc(2026, 10, 20, 8);
      await AppPrefs.clearAiBaselineScanId(_frontKey, resetAt: secondReset);
      expect(await shouldShowProtocolChecklist(await _token()), isTrue);

      // Once a new baseline is set, no reset is pending.
      await AppPrefs.setAiBaselineScanId(_frontKey, 'scan-new-baseline');
      expect(await _token(), isNull);
    },
  );

  test('another angle\'s reset does not trigger the Front checklist', () async {
    await AppPrefs.clearAiBaselineScanId(
      ScanHistoryEntry.resolveAiBaselineKey(
        procedureId: null,
        focusArea: 'Full face',
        poseTemplate: 'Left 45°',
        guideType: 'facial',
      ),
    );
    expect(await _token(), isNull);
  });

  testWidgets('the card lists the four items and is dismissible', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProtocolChecklistCard(onDismiss: () => dismissed++),
        ),
      ),
    );
    for (final item in const [
      'Gray card in first frame',
      'Lamp on',
      'Blinds closed',
      'Chin at same height',
    ]) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('protocol_checklist_dismiss')));
    await tester.tap(find.byKey(const ValueKey('protocol_checklist_close')));
    expect(dismissed, 2);
  });

  test('wired into the camera without gating capture', () {
    final camera = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    expect(camera, contains('if (_showProtocolChecklist)'));
    expect(camera, contains('onDismiss: _dismissProtocolChecklist,'));
    final gate = camera.indexOf('bool _isCaptureFramingReady(');
    expect(gate, isNonNegative);
    final gateBody = camera.substring(gate, camera.indexOf('\n  }\n', gate));
    expect(gateBody, isNot(contains('ProtocolChecklist')));
    expect(gateBody, isNot(contains('_showProtocolChecklist')));

    final scan = File(
      'lib/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart',
    ).readAsStringSync();
    expect(scan, contains('protocolChecklistResetToken: checklistToken,'));
    expect(scan, contains('frontBaselineResetToken('));
  });
}
