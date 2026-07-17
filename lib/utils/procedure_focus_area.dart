import '../models/procedure.dart';
import 'procedure_intelligence.dart';

const bodyProcedureFocusAreas = <String>[
  'Abdomen',
  'Thighs (Left)',
  'Thighs (Right)',
  'Buttocks',
  'Flanks/Love Handles',
  'Arms',
  'Chest',
  'Full Torso',
  'Other',
];

const facialProcedureFocusAreas = <String>[
  'Full Face',
  'Forehead',
  'Cheeks',
  'Jawline / Chin',
  'Nose',
  'Perioral',
  'Other',
];

bool usesBodyFocusAreas(String? procedureType) {
  return ProcedureIntelligence.categoryFor(procedureType) ==
          ProcedureCategory.bodyContouring ||
      procedureCameraGuideType(procedureType ?? '') ==
          ProcedureCameraGuideType.body;
}

List<String> focusAreasForProcedure(String? procedureType) {
  return usesBodyFocusAreas(procedureType)
      ? bodyProcedureFocusAreas
      : facialProcedureFocusAreas;
}

String defaultFocusAreaForProcedure(String? procedureType) {
  if (!usesBodyFocusAreas(procedureType)) return 'Full Face';

  final type = (procedureType ?? '').toLowerCase();
  if (type.contains('bbl') ||
      type.contains('butt') ||
      type.contains('glute') ||
      type.contains('thigh lift')) {
    return 'Buttocks';
  }
  if (type.contains('thigh')) return 'Thighs (Left)';
  if (type.contains('arm')) return 'Arms';
  if (type.contains('chest')) return 'Chest';
  if (type.contains('abdomen') ||
      type.contains('abdominoplasty') ||
      type.contains('tummy tuck') ||
      type.contains('tummy') ||
      type.contains('lipo')) {
    return 'Abdomen';
  }
  return 'Full Torso';
}
