import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/procedure_focus_area.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Procedure history persistence', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await AppPrefs.clearProcedureHistory();
    });

    test('create persists and loads sorted descending by startDate', () async {
      final first = <String, dynamic>{
        'procedureId': 'proc_1',
        'type': 'Microneedling',
        'startDate': DateTime(2026, 2, 1).toIso8601String(),
        'plannedSessions': 3,
        'clinicName': 'Clinic A',
        'notes': 'First course',
      };
      final second = <String, dynamic>{
        'procedureId': 'proc_2',
        'type': 'Halo Laser',
        'startDate': DateTime(2026, 3, 1).toIso8601String(), // newer date
        'plannedSessions': 2,
        'clinicName': 'Clinic B',
        'notes': 'Second course',
      };

      await AppPrefs.addProcedureToHistory(first);
      await AppPrefs.addProcedureToHistory(second);

      final entries = await AppPrefs.getProcedureEntries();
      expect(entries.length, 2);
      expect(entries.first['procedureId'], 'proc_2'); // newest first
      expect(entries.last['procedureId'], 'proc_1');
    });

    test('edit persists updated fields', () async {
      final initial = <String, dynamic>{
        'procedureId': 'proc_3',
        'type': 'IPL',
        'startDate': DateTime(2026, 1, 15).toIso8601String(),
        'plannedSessions': 4,
        'clinicName': 'Clinic C',
        'notes': 'Initial',
      };
      await AppPrefs.addProcedureToHistory(initial);

      final edited = <String, dynamic>{
        ...initial,
        'plannedSessions': 6,
        'notes': 'Updated',
      };
      await AppPrefs.saveProcedureHistory(<Map<String, dynamic>>[edited]);

      final entries = await AppPrefs.getProcedureEntries();
      expect(entries.length, 1);
      expect(entries.first['plannedSessions'], 6);
      expect(entries.first['notes'], 'Updated');
    });

    test('create persists procedure focus area', () async {
      final bbl = Procedure(
        id: 'proc_bbl',
        type: 'BBL',
        category: 'Cosmetic Procedures',
        provider: 'Clinic B',
        startDate: DateTime(2026, 4, 1),
        numSessions: 1,
        focusArea: defaultFocusAreaForProcedure('BBL'),
        customDescription: 'Brazilian Butt Lift with fat transfer to hips',
      );
      final tummyTuck = Procedure(
        id: 'proc_tummy_tuck',
        type: 'Tummy Tuck',
        category: 'Cosmetic Procedures',
        provider: 'Clinic T',
        startDate: DateTime(2026, 5, 1),
        numSessions: 1,
        focusArea: defaultFocusAreaForProcedure('Tummy Tuck'),
      );

      await AppPrefs.saveProcedureHistory(<Map<String, dynamic>>[
        bbl.toJson(),
        tummyTuck.toJson(),
      ]);

      final entries = await AppPrefs.getProcedureEntries();
      expect(entries.first['id'], 'proc_tummy_tuck');
      expect(entries.first['focusArea'], 'Abdomen');
      expect(entries.last['id'], 'proc_bbl');
      expect(entries.last['focusArea'], 'Buttocks');
      expect(
        entries.last['customDescription'],
        'Brazilian Butt Lift with fat transfer to hips',
      );
    });

    test('delete persists removal', () async {
      await AppPrefs.saveProcedureHistory(<Map<String, dynamic>>[
        <String, dynamic>{
          'procedureId': 'proc_4',
          'type': 'RF Microneedling',
          'startDate': DateTime(2026, 1, 1).toIso8601String(),
          'plannedSessions': 3,
          'clinicName': 'Clinic D',
          'notes': '',
        },
        <String, dynamic>{
          'procedureId': 'proc_5',
          'type': 'Chemical Peel',
          'startDate': DateTime(2026, 1, 2).toIso8601String(),
          'plannedSessions': 1,
          'clinicName': 'Clinic E',
          'notes': '',
        },
      ]);

      final current = await AppPrefs.getProcedureEntries();
      final afterDelete = current
          .where((item) => item['procedureId'] != 'proc_4')
          .toList();
      await AppPrefs.saveProcedureHistory(afterDelete);

      final reloaded = await AppPrefs.getProcedureEntries();
      expect(reloaded.length, 1);
      expect(reloaded.first['procedureId'], 'proc_5');
    });
  });
}
