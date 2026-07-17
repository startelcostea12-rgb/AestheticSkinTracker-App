import 'package:aesthetic_skin_tracker/models/skincare/skincare_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Skincare core models', () {
    test(
      'UserSkinProfile round-trips aggregate skincare intelligence context',
      () {
        final now = DateTime(2026, 6, 29, 12);
        final ghkCu = LoggedProduct(
          id: 'product_ghk_cu',
          name: 'GHK-Cu Copper Tripeptide-1 Serum',
          category: ProductCategory.peptide,
          keyIngredients: const ['GHK-Cu', 'Copper Tripeptide-1'],
          concernsTargeted: const ['firmness', 'texture', 'pores'],
          startDate: now,
          createdAt: now,
          updatedAt: now,
        );

        final procedure = ProcedureRecord(
          id: 'procedure_home_mn',
          type: ProcedureType.atHomeMicroneedling,
          setting: ProcedureSetting.atHome,
          date: now,
          appliedProducts: [ghkCu],
          appliedProductIds: const ['product_ghk_cu'],
          appliedPeptides: const ['GHK-Cu'],
          depthMm: 0.25,
          healingPhotoPaths: const ['local/healing-photo.jpg'],
          createdAt: now,
          updatedAt: now,
        );

        final scan = ScanRecord(
          id: 'scan_1',
          capturedAt: now,
          source: ScanSource.aiAnalysis,
          procedureId: procedure.id,
          productIds: const ['product_ghk_cu'],
          metrics: const SkinMetricSet(texture: 6.5, pores: 5.5),
          visibleFindings: const ['visible pores', 'uneven texture'],
          createdAt: now,
        );

        final routine = DailyRoutine(
          id: 'routine_1',
          effectiveFrom: now,
          eveningSteps: [
            RoutineStep(
              id: 'step_ghk_cu',
              order: 1,
              type: RoutineStepType.peptide,
              timeOfDay: RoutineTimeOfDay.evening,
              title: 'GHK-Cu anchor',
              productId: ghkCu.id,
              requiresCalmBarrier: true,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        );

        final profile = UserSkinProfile(
          id: 'user_1',
          displayName: 'Test User',
          onboarding: const OnboardingSkinData(
            skinType: SkinType.combination,
            climate: 'dry',
          ),
          sensitivityLevel: SkinSensitivityLevel.moderate,
          goals: const ['firmer skin', 'smoother texture'],
          concerns: const ['pores', 'fine lines'],
          currentProducts: [ghkCu],
          procedureHistory: [procedure],
          scanHistory: [scan],
          activeRoutine: routine,
          createdAt: now,
          updatedAt: now,
        );

        final roundTrip = UserSkinProfile.fromJson(profile.toJson());

        expect(roundTrip.id, 'user_1');
        expect(
          roundTrip.currentProducts.single.category,
          ProductCategory.peptide,
        );
        expect(
          roundTrip.procedureHistory.single.type,
          ProcedureType.atHomeMicroneedling,
        );
        expect(roundTrip.procedureHistory.single.depthMm, 0.25);
        expect(roundTrip.scanHistory.single.metrics.texture, 6.5);
        expect(
          roundTrip.activeRoutine?.eveningSteps.single.productId,
          'product_ghk_cu',
        );
        expect(roundTrip.hasProcedureHistory, isTrue);
        expect(roundTrip.hasScanHistory, isTrue);
      },
    );
  });
}
