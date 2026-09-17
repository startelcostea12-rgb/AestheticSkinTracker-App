import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/utils/procedure_focus_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Procedure focus area', () {
    test('BBL stores default focus area', () {
      final procedure = Procedure(
        id: 'proc_bbl',
        type: 'BBL',
        category: 'Cosmetic Procedures',
        provider: 'Test Clinic',
        startDate: DateTime(2026, 6, 16),
        numSessions: 1,
        focusArea: defaultFocusAreaForProcedure('BBL'),
      );

      final json = procedure.toJson();
      expect(json['focusArea'], 'Buttocks');

      final roundTrip = Procedure.fromJson(json);
      expect(roundTrip.focusArea, 'Buttocks');
    });

    test('Tummy Tuck stores abdomen focus area', () {
      final procedure = Procedure(
        id: 'proc_tummy_tuck',
        type: 'Tummy Tuck',
        category: 'Cosmetic Procedures',
        provider: 'Test Clinic',
        startDate: DateTime(2026, 6, 16),
        numSessions: 1,
        focusArea: defaultFocusAreaForProcedure('Tummy Tuck'),
      );

      final json = procedure.toJson();
      expect(json['focusArea'], 'Abdomen');

      final roundTrip = Procedure.fromJson(json);
      expect(roundTrip.focusArea, 'Abdomen');
    });

    test('custom procedure stores short description', () {
      final procedure = Procedure(
        id: 'proc_custom',
        type: 'Body Contouring - Other',
        category: 'Cosmetic Procedures',
        provider: 'Test Clinic',
        startDate: DateTime(2026, 6, 16),
        numSessions: 1,
        focusArea: 'Other',
        customDescription: 'Brazilian Butt Lift with fat transfer to hips',
      );

      final json = procedure.toJson();
      expect(
        json['customDescription'],
        'Brazilian Butt Lift with fat transfer to hips',
      );

      final roundTrip = Procedure.fromJson(json);
      expect(roundTrip.focusArea, 'Other');
      expect(
        roundTrip.customDescription,
        'Brazilian Butt Lift with fat transfer to hips',
      );
    });

    test('procedure persists bodyRegion and legacy data infers it', () {
      final procedure = Procedure(
        id: 'proc_body_region',
        type: 'BBL',
        category: 'Cosmetic Procedures',
        provider: 'Test Clinic',
        startDate: DateTime(2026, 6, 16),
        numSessions: 1,
        bodyRegion: ProcedureBodyRegion.body,
      );

      final json = procedure.toJson();
      expect(json['bodyRegion'], 'body');

      final roundTrip = Procedure.fromJson(json);
      expect(roundTrip.bodyRegion, ProcedureBodyRegion.body);

      final legacyJson = {
        'id': 'legacy_proc',
        'type': 'Botox / Dysport / Xeomin',
        'category': 'Cosmetic Procedures',
        'provider': 'Test Clinic',
        'startDate': DateTime(2026, 6, 16).toIso8601String(),
        'numSessions': 1,
      };

      final legacyRoundTrip = Procedure.fromJson(legacyJson);
      expect(legacyRoundTrip.bodyRegion, ProcedureBodyRegion.face);
    });
  });
}
