import 'package:aesthetic_skin_tracker/models/skincare/skincare_models.dart';
import 'package:aesthetic_skin_tracker/repositories/skincare_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SkincareRepositoryImpl', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves and reloads canonical AI coach context', () async {
      final now = DateTime(2026, 6, 29, 12);
      final product = LoggedProduct(
        id: 'ghk_cu_serum',
        name: 'GHK-Cu Copper Tripeptide-1 Serum',
        brand: 'Coach Lab',
        category: ProductCategory.peptide,
        keyIngredients: const ['GHK-Cu', 'Copper Tripeptide-1'],
        concernsTargeted: const ['firmness', 'texture'],
        startDate: now,
        createdAt: now,
        updatedAt: now,
      );
      final scan = ScanRecord(
        id: 'scan_1',
        capturedAt: now,
        source: ScanSource.aiAnalysis,
        imagePath: 'progress/photo.jpg',
        metrics: const SkinMetricSet(redness: 4, texture: 6),
        visibleFindings: const ['texture unevenness'],
        aiSummary: 'Texture is the main visible theme.',
        createdAt: now,
      );
      final profile = UserSkinProfile(
        id: SkincareRepositoryImpl.defaultUserId,
        displayName: 'Avery',
        onboarding: const OnboardingSkinData(
          skinType: SkinType.combination,
          ageRange: '35-44',
          climate: 'dry',
        ),
        sensitivityLevel: SkinSensitivityLevel.moderate,
        goals: const ['firmer skin'],
        concerns: const ['fine lines', 'texture'],
        currentProducts: [product],
        scanHistory: [scan],
        createdAt: now,
        updatedAt: now,
      );

      final repository = SkincareRepositoryImpl();
      await repository.saveUserSkinProfile(profile);
      repository.clearMemoryCache();

      final loaded = await repository.getAiCoachContext(
        SkincareRepositoryImpl.defaultUserId,
      );

      expect(loaded, isNotNull);
      expect(loaded!.displayName, 'Avery');
      expect(loaded.onboarding.skinType, SkinType.combination);
      expect(loaded.currentProducts.single.category, ProductCategory.peptide);
      expect(loaded.scanHistory.single.metrics.texture, 6);
      expect(loaded.concerns, contains('fine lines'));
      await repository.dispose();
    });
  });
}
