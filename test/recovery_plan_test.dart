import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/recovery_plan.dart';
import 'package:aesthetic_skin_tracker/services/recovery_plan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Halo Laser pilot plan loads from structured asset as first draft', () async {
    final plan = await RecoveryPlanService.planForProcedureType('Halo Laser');

    expect(plan, isNotNull);
    expect(plan!.id, 'halo_laser_7_day_first_draft');
    expect(plan.reviewStatus, 'first_draft_requires_human_clinical_review');
    expect(plan.days, hasLength(7));
    expect(plan.disclaimer, contains('not a substitute for professional medical advice'));
    expect(plan.days.every((day) => day.whatsCommon.contains('common') || day.whatsCommon.contains('Many patients')), isTrue);
    expect(plan.days[2].reminder.kind, 'scan');
    expect(plan.days[6].reminder.kind, 'scan');
  });

  test('non-pilot procedures do not resolve a 7-day plan', () async {
    final plan = await RecoveryPlanService.planForProcedureType('Botox / Dysport / Xeomin');

    expect(plan, isNull);
  });

  test('current day lookup stays within the seven-day informational window', () {
    final plan = RecoveryPlan(
      id: 'test',
      procedureType: 'Halo Laser',
      title: 'Test',
      reviewStatus: 'first_draft_requires_human_clinical_review',
      disclaimer: 'General information only.',
      days: List.generate(
        7,
        (index) => RecoveryPlanDay(
          day: index + 1,
          whatsCommon: 'common ${index + 1}',
          watchFor: 'watch ${index + 1}',
          suggestedAction: 'action ${index + 1}',
          reminder: const RecoveryPlanReminder(
            kind: 'note',
            hour: 19,
            minute: 0,
            title: 'title',
            body: 'body',
          ),
        ),
      ),
    );
    final start = DateTime(2026, 9, 18);

    expect(plan.dayFor(start, DateTime(2026, 9, 18))?.day, 1);
    expect(plan.dayFor(start, DateTime(2026, 9, 24))?.day, 7);
    expect(plan.dayFor(start, DateTime(2026, 9, 25)), isNull);
    expect(plan.dayFor(start, DateTime(2026, 9, 17)), isNull);
  });

  test('procedure recoveryPlanId is opt-in and backward compatible', () {
    final legacy = Procedure.fromJson({
      'id': 'legacy_proc',
      'type': 'Halo Laser',
      'provider': 'Self / At-Home',
      'startDate': '2026-09-18T00:00:00.000',
      'numSessions': 1,
    });

    expect(legacy.recoveryPlanId, isNull);

    final activated = legacy.copyWith(recoveryPlanId: 'halo_laser_7_day_first_draft');
    expect(activated.toJson()['recoveryPlanId'], 'halo_laser_7_day_first_draft');
    expect(Procedure.fromJson(activated.toJson()).recoveryPlanId, 'halo_laser_7_day_first_draft');
    expect(activated.copyWith(clearRecoveryPlan: true).recoveryPlanId, isNull);
  });
}
