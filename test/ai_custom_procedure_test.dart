import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_intelligence_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Custom procedure AI context', () {
    test('procedure context label prefers custom description', () {
      final label = procedureContextLabel(
        procedureType: 'Body Contouring - Other',
        customDescription: 'Brazilian Butt Lift with fat transfer to hips',
        focusArea: 'Other',
      );

      expect(label, 'Brazilian Butt Lift with fat transfer to hips');
      expect(isCustomProcedureType('Body Contouring - Other'), true);
    });

    test('daily briefing uses custom body contouring description', () {
      final briefing = AiIntelligenceEngine.generateDailyBriefing(
        scans: const <ScanHistoryEntry>[],
        procedures: [
          Procedure(
            id: 'proc_custom_body',
            type: 'Body Contouring - Other',
            category: 'Cosmetic Procedures',
            provider: 'Test Clinic',
            startDate: DateTime.now().subtract(const Duration(days: 3)),
            numSessions: 1,
            focusArea: 'Other',
            customDescription: 'Brazilian Butt Lift with fat transfer to hips',
          ),
        ],
      );

      expect(
        briefing.headline,
        contains('Brazilian Butt Lift with fat transfer to hips'),
      );
      expect(briefing.todaysFocus, contains('fat transfer to hips'));
      expect(briefing.todaysFocus, isNot(contains('BBL pillow')));
    });

    test('scan interpretation uses custom description in narrative', () {
      final report = AiIntelligenceEngine.interpretScanMetrics(
        const SkinMetrics(redness: 3, texture: 3, wrinkle: 3, pore: 3),
        procedureType: 'Body Contouring - Other',
        customDescription: 'Lower-back contour revision',
        focusArea: 'Other',
        daysSinceProcedure: 10,
      );

      expect(report.overallNarrative, contains('Lower-back contour revision'));
      expect(report.primaryRecommendation, isNot(contains('BBL pillow')));
    });
  });
}
