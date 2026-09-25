import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers resolveCameraGuideType -- the fix for the AI Skin Analysis
/// capture flow's guide type being incidental (falling back to whatever
/// "active procedure" happened to be stored in AppPrefs, or `general` if
/// none). For capturePurpose == aiSkinAnalysis (with isSkincareScan), it
/// must always resolve to facial, regardless of any stored active
/// procedure's label or body region.
void main() {
  group('resolveCameraGuideType', () {
    test(
      'aiSkinAnalysis capture, no active procedure -> facial',
      () {
        final result = resolveCameraGuideType(
          isSkincareScan: true,
          capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
          procedureBodyRegion: null,
          effectiveGuideProcedureType: '', // no active procedure resolved
        );
        expect(result, ProcedureCameraGuideType.facial);
      },
    );

    test(
      'aiSkinAnalysis capture, a facial active procedure -> still facial',
      () {
        // Sanity: 'Facelift' is itself a recognized facial procedure type,
        // so this would resolve facial even without the override -- the
        // real proof of the fix is the body case below.
        expect(procedureCameraGuideType('Facelift'), ProcedureCameraGuideType.facial);

        final result = resolveCameraGuideType(
          isSkincareScan: true,
          capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
          procedureBodyRegion: null,
          effectiveGuideProcedureType: 'Facelift',
        );
        expect(result, ProcedureCameraGuideType.facial);
      },
    );

    test(
      'aiSkinAnalysis capture, a BODY active procedure -> still facial '
      '(the override actually overrides, not just coincides)',
      () {
        // Sanity: 'BBL' alone resolves to body -- proves the override is
        // doing real work below, not just agreeing by chance.
        expect(procedureCameraGuideType('BBL'), ProcedureCameraGuideType.body);

        final result = resolveCameraGuideType(
          isSkincareScan: true,
          capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
          procedureBodyRegion: null,
          effectiveGuideProcedureType: 'BBL',
        );
        expect(result, ProcedureCameraGuideType.facial);
      },
    );

    test(
      'aiSkinAnalysis capture, a stored body ProcedureBodyRegion -> still '
      'facial (override wins even over an attached Procedure.bodyRegion)',
      () {
        final result = resolveCameraGuideType(
          isSkincareScan: true,
          capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
          procedureBodyRegion: ProcedureBodyRegion.body,
          effectiveGuideProcedureType: 'BBL',
        );
        expect(result, ProcedureCameraGuideType.facial);
      },
    );

    test(
      'not an aiSkinAnalysis capture: behavior is unchanged -- a body '
      'active procedure still resolves to body',
      () {
        final result = resolveCameraGuideType(
          isSkincareScan: false,
          capturePurpose: CameraCapturePurpose.trackProcedure,
          procedureBodyRegion: null,
          effectiveGuideProcedureType: 'BBL',
        );
        expect(result, ProcedureCameraGuideType.body);
      },
    );

    test(
      'isSkincareScan without aiSkinAnalysis purpose: override does not '
      'apply (both conditions are required)',
      () {
        final result = resolveCameraGuideType(
          isSkincareScan: true,
          capturePurpose: CameraCapturePurpose.skincareTracking,
          procedureBodyRegion: null,
          effectiveGuideProcedureType: 'BBL',
        );
        expect(result, ProcedureCameraGuideType.body);
      },
    );

    test(
      'a stored Procedure.bodyRegion is still honored outside the '
      'aiSkinAnalysis override',
      () {
        final result = resolveCameraGuideType(
          isSkincareScan: false,
          capturePurpose: CameraCapturePurpose.trackProcedure,
          procedureBodyRegion: ProcedureBodyRegion.body,
          effectiveGuideProcedureType: 'irrelevant label',
        );
        expect(result, ProcedureCameraGuideType.body);
      },
    );
  });
}
