import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/services/notification_service.dart';

Procedure _baseProcedure({
  DateTime? nextAppointmentDate,
  int? appointmentRecurrenceMonths,
  bool appointmentReminderEnabled = true,
}) {
  return Procedure(
    id: 'proc_appt_test',
    type: 'Botox / Dysport / Xeomin',
    provider: 'Test Clinic',
    startDate: DateTime(2026, 1, 1),
    numSessions: 1,
    nextAppointmentDate: nextAppointmentDate,
    appointmentRecurrenceMonths: appointmentRecurrenceMonths,
    appointmentReminderEnabled: appointmentReminderEnabled,
  );
}

void main() {
  group('Procedure appointment reminder fields', () {
    test('defaults to no appointment (fully opt-in, no behavior change)', () {
      final procedure = _baseProcedure();
      expect(procedure.nextAppointmentDate, isNull);
      expect(procedure.appointmentRecurrenceMonths, isNull);
      expect(procedure.appointmentReminderEnabled, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      final date = DateTime(2026, 4, 1, 9, 30);
      final procedure = _baseProcedure(
        nextAppointmentDate: date,
        appointmentRecurrenceMonths: 3,
      );

      final restored = Procedure.fromJson(procedure.toJson());

      expect(restored.nextAppointmentDate, date);
      expect(restored.appointmentRecurrenceMonths, 3);
      expect(restored.appointmentReminderEnabled, isTrue);
    });

    test('legacy JSON with no appointment keys deserializes safely', () {
      final legacyJson = {
        'id': 'proc_legacy',
        'type': 'Botox / Dysport / Xeomin',
        'provider': 'Test Clinic',
        'startDate': DateTime(2025, 1, 1).toIso8601String(),
        'numSessions': 1,
      };

      final restored = Procedure.fromJson(legacyJson);

      expect(restored.nextAppointmentDate, isNull);
      expect(restored.appointmentRecurrenceMonths, isNull);
      expect(restored.appointmentReminderEnabled, isTrue);
    });

    test('copyWith(clearNextAppointment: true) removes date and recurrence', () {
      final procedure = _baseProcedure(
        nextAppointmentDate: DateTime(2026, 4, 1),
        appointmentRecurrenceMonths: 6,
      );

      final cleared = procedure.copyWith(clearNextAppointment: true);

      expect(cleared.nextAppointmentDate, isNull);
      expect(cleared.appointmentRecurrenceMonths, isNull);
    });

    test('copyWith can set an appointment on a procedure that had none', () {
      final procedure = _baseProcedure();
      final date = DateTime(2026, 7, 15);

      final updated = procedure.copyWith(
        nextAppointmentDate: date,
        appointmentRecurrenceMonths: 3,
      );

      expect(updated.nextAppointmentDate, date);
      expect(updated.appointmentRecurrenceMonths, 3);
    });
  });

  group('advanceAppointmentDate', () {
    test('advances by exactly the recurrence interval within the same year', () {
      final result = advanceAppointmentDate(DateTime(2026, 1, 15, 10, 0), 3);
      expect(result, DateTime(2026, 4, 15, 10, 0));
    });

    test('rolls over into the next year when the month overflows', () {
      final result = advanceAppointmentDate(DateTime(2026, 11, 1, 8, 0), 3);
      expect(result, DateTime(2027, 2, 1, 8, 0));
    });

    test('a 12-month recurrence lands on the same date next year', () {
      final result = advanceAppointmentDate(DateTime(2026, 6, 10, 12, 0), 12);
      expect(result, DateTime(2027, 6, 10, 12, 0));
    });

    test('a 1-month recurrence just advances one month', () {
      final result = advanceAppointmentDate(DateTime(2026, 3, 5), 1);
      expect(result, DateTime(2026, 4, 5));
    });
  });
}
