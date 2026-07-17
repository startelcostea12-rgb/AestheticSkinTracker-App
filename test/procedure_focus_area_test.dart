import 'package:aesthetic_skin_tracker/utils/procedure_focus_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('procedure focus areas', () {
    test('BBL uses body zones and defaults to Buttocks', () {
      expect(usesBodyFocusAreas('BBL'), true);
      expect(focusAreasForProcedure('BBL'), bodyProcedureFocusAreas);
      expect(defaultFocusAreaForProcedure('BBL'), 'Buttocks');
    });

    test('Thigh Lift uses body zones and defaults to Buttocks', () {
      expect(usesBodyFocusAreas('Thigh Lift'), true);
      expect(focusAreasForProcedure('Thigh Lift'), bodyProcedureFocusAreas);
      expect(defaultFocusAreaForProcedure('Thigh Lift'), 'Buttocks');
    });

    test('Tummy Tuck defaults to Abdomen', () {
      expect(usesBodyFocusAreas('Tummy Tuck'), true);
      expect(focusAreasForProcedure('Tummy Tuck'), bodyProcedureFocusAreas);
      expect(defaultFocusAreaForProcedure('Tummy Tuck'), 'Abdomen');
    });

    test('facial procedures use face zones and default to Full Face', () {
      expect(usesBodyFocusAreas('Facelift'), false);
      expect(focusAreasForProcedure('Facelift'), facialProcedureFocusAreas);
      expect(defaultFocusAreaForProcedure('Facelift'), 'Full Face');
    });
  });
}
