import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/procedure.dart' as legacy_procedure;
import '../models/product_tracker.dart' as legacy_product;
import '../models/scan_history.dart' as legacy_scan;
import '../models/skin_profile.dart' as legacy_profile;
import '../models/skincare/skincare_models.dart';
import '../utils/app_prefs.dart';
import 'skincare_repository.dart';

/// Local `AppPrefs` implementation of the unified skincare data layer.
///
/// This class is intentionally Riverpod-friendly: it has no widget dependency,
/// exposes a small immutable repository contract, and can be wrapped later by a
/// Provider/Notifier without changing call sites.
///
/// Migration note: the repository currently writes both a canonical
/// `UserSkinProfile` JSON payload and the existing legacy `AppPrefs` records.
/// When moving to Hive, Isar, Supabase, or a HIPAA-scoped backend, keep this
/// class as the adapter boundary and replace only the persistence internals.
/// Server-backed implementations should add encryption at rest, tenant
/// isolation, consent-aware redaction, audit logging, and least-privilege reads.
class SkincareRepositoryImpl implements SkincareRepository {
  static const String defaultUserId = 'local_user';
  static const String _profileKeyPrefix = 'skincare_core_profile_';
  static const String _activeRoutineKeyPrefix = 'skincare_active_routine_';
  static const String _routineHistoryKeyPrefix = 'skincare_routine_history_';

  final Map<String, UserSkinProfile?> _profileCache = {};
  final StreamController<UserSkinProfile?> _profileController =
      StreamController<UserSkinProfile?>.broadcast();

  SkincareRepositoryImpl();

  @override
  Future<UserSkinProfile?> getUserSkinProfile(String userId) async {
    final key = _cleanUserId(userId);
    if (_profileCache.containsKey(key)) return _profileCache[key];

    final profile = await _guard('load user skin profile', () async {
      final prefs = await SharedPreferences.getInstance();
      final canonical = _decodeMap(prefs.getString(_profileKey(key)));
      final legacy = await buildUserSkinProfileFromLegacyData(userId: key);
      if (canonical == null) return legacy;

      final saved = UserSkinProfile.fromJson(canonical);
      return _mergeWithLegacy(saved, legacy);
    });

    _profileCache[key] = profile;
    return profile;
  }

  @override
  Stream<UserSkinProfile?> watchUserSkinProfile(String userId) async* {
    yield await getUserSkinProfile(userId);
    yield* _profileController.stream;
  }

  @override
  Future<void> saveUserSkinProfile(UserSkinProfile profile) async {
    await _guard('save user skin profile', () async {
      final userId = _cleanUserId(profile.id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileKey(userId), jsonEncode(profile.toJson()));
      await _writeLegacyProfile(profile);
      await _writeLegacyProducts(profile.currentProducts);
      await _writeLegacyProcedures(profile.procedureHistory);
      await _writeCoreScanHistory(profile.scanHistory);
      if (profile.activeRoutine != null) {
        await saveActiveRoutine(userId, profile.activeRoutine!);
      }
      if (profile.routineHistory.isNotEmpty) {
        await _writeRoutineHistory(userId, profile.routineHistory);
      }
      _cacheAndNotify(userId, profile);
    });
  }

  @override
  Future<void> deleteUserSkinProfile(String userId) async {
    await _guard('delete user skin profile', () async {
      final key = _cleanUserId(userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey(key));
      await prefs.remove(_activeRoutineKey(key));
      await prefs.remove(_routineHistoryKey(key));
      _profileCache.remove(key);
      _profileController.add(null);
    });
  }

  @override
  Future<List<LoggedProduct>> getLoggedProducts(String userId) async {
    final profile = await getUserSkinProfile(userId);
    return profile?.currentProducts ?? const [];
  }

  @override
  Future<void> upsertLoggedProduct(String userId, LoggedProduct product) async {
    await _guard('upsert logged product', () async {
      final key = _cleanUserId(userId);
      await AppPrefs.updateTrackedProduct(_toLegacyProduct(product));
      final profile = await _freshProfile(key);
      final products = [...profile.currentProducts];
      final index = products.indexWhere((item) => item.id == product.id);
      if (index == -1) {
        products.add(product);
      } else {
        products[index] = product;
      }
      await _saveCanonicalOnly(
        profile.copyWith(currentProducts: products, updatedAt: DateTime.now()),
      );
    });
  }

  Future<void> addLoggedProduct(String userId, LoggedProduct product) =>
      upsertLoggedProduct(userId, product);

  Future<void> updateLoggedProduct(String userId, LoggedProduct product) =>
      upsertLoggedProduct(userId, product);

  @override
  Future<void> removeLoggedProduct(String userId, String productId) async {
    await _guard('remove logged product', () async {
      final key = _cleanUserId(userId);
      await AppPrefs.removeTrackedProduct(productId);
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(
          currentProducts: profile.currentProducts
              .where((item) => item.id != productId)
              .toList(growable: false),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<List<ProcedureRecord>> getProcedureHistory(String userId) async {
    final profile = await getUserSkinProfile(userId);
    return profile?.procedureHistory ?? const [];
  }

  @override
  Future<void> upsertProcedureRecord(
    String userId,
    ProcedureRecord procedure,
  ) async {
    await _guard('upsert procedure record', () async {
      final key = _cleanUserId(userId);
      final history = await AppPrefs.getProcedureEntries();
      final updatedEntry = _toLegacyProcedureEntry(procedure);
      final index = history.indexWhere((item) => item['id'] == procedure.id);
      if (index == -1) {
        history.add(updatedEntry);
      } else {
        history[index] = updatedEntry;
      }
      await AppPrefs.saveProcedureHistory(history);

      final profile = await _freshProfile(key);
      final procedures = [...profile.procedureHistory];
      final procedureIndex = procedures.indexWhere(
        (item) => item.id == procedure.id,
      );
      if (procedureIndex == -1) {
        procedures.add(procedure);
      } else {
        procedures[procedureIndex] = procedure;
      }
      procedures.sort((a, b) => b.date.compareTo(a.date));
      await _saveCanonicalOnly(
        profile.copyWith(
          procedureHistory: procedures,
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  Future<void> addProcedureRecord(String userId, ProcedureRecord procedure) =>
      upsertProcedureRecord(userId, procedure);

  Future<void> updateProcedureRecord(
    String userId,
    ProcedureRecord procedure,
  ) => upsertProcedureRecord(userId, procedure);

  @override
  Future<void> removeProcedureRecord(String userId, String procedureId) async {
    await _guard('remove procedure record', () async {
      final key = _cleanUserId(userId);
      await AppPrefs.removeProcedureFromHistory(procedureId);
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(
          procedureHistory: profile.procedureHistory
              .where((item) => item.id != procedureId)
              .toList(growable: false),
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<List<ScanRecord>> getScanHistory(String userId) async {
    final profile = await getUserSkinProfile(userId);
    return profile?.scanHistory ?? const [];
  }

  @override
  Future<void> upsertScanRecord(String userId, ScanRecord scan) async {
    await _guard('upsert scan record', () async {
      final key = _cleanUserId(userId);
      final scans = await getScanHistory(key);
      final updated = [...scans];
      final index = updated.indexWhere((item) => item.id == scan.id);
      if (index == -1) {
        updated.add(scan);
      } else {
        updated[index] = scan;
      }
      updated.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      await _writeCoreScanHistory(updated);
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(scanHistory: updated, updatedAt: DateTime.now()),
      );
    });
  }

  Future<void> addScanRecord(String userId, ScanRecord scan) =>
      upsertScanRecord(userId, scan);

  Future<void> updateScanRecord(String userId, ScanRecord scan) =>
      upsertScanRecord(userId, scan);

  @override
  Future<void> removeScanRecord(String userId, String scanId) async {
    await _guard('remove scan record', () async {
      final key = _cleanUserId(userId);
      final scans = (await getScanHistory(
        key,
      )).where((item) => item.id != scanId).toList(growable: false);
      await _writeCoreScanHistory(scans);
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(scanHistory: scans, updatedAt: DateTime.now()),
      );
    });
  }

  @override
  Future<DailyRoutine?> getActiveRoutine(String userId) async {
    final key = _cleanUserId(userId);
    final prefs = await SharedPreferences.getInstance();
    final saved = _decodeMap(prefs.getString(_activeRoutineKey(key)));
    if (saved != null) return DailyRoutine.fromJson(saved);
    return (await getUserSkinProfile(key))?.activeRoutine;
  }

  Future<DailyRoutine?> getCurrentRoutine(String userId) =>
      getActiveRoutine(userId);

  @override
  Future<void> saveActiveRoutine(String userId, DailyRoutine routine) async {
    await _guard('save active routine', () async {
      final key = _cleanUserId(userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _activeRoutineKey(key),
        jsonEncode(routine.toJson()),
      );
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(activeRoutine: routine, updatedAt: DateTime.now()),
      );
    });
  }

  Future<void> updateRoutine(String userId, DailyRoutine routine) =>
      saveActiveRoutine(userId, routine);

  @override
  Future<List<DailyRoutine>> getRoutineHistory(String userId) async {
    final key = _cleanUserId(userId);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_routineHistoryKey(key));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DailyRoutine.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint(
        'SkincareRepositoryImpl routine history decode failed: $error',
      );
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'skincare_repository_impl',
          context: ErrorDescription('decoding routine history'),
        ),
      );
      return const [];
    }
  }

  @override
  Future<void> addRoutineToHistory(String userId, DailyRoutine routine) async {
    await _guard('add routine to history', () async {
      final key = _cleanUserId(userId);
      final history = [...await getRoutineHistory(key), routine];
      await _writeRoutineHistory(key, history);
      final profile = await _freshProfile(key);
      await _saveCanonicalOnly(
        profile.copyWith(routineHistory: history, updatedAt: DateTime.now()),
      );
    });
  }

  @override
  Future<UserSkinProfile?> getAiCoachContext(String userId) async {
    return getUserSkinProfile(userId);
  }

  /// Builds the canonical model from the existing local stores.
  ///
  /// This is the compatibility bridge for the current app. Future storage
  /// backends should keep the same output shape so AI, onboarding, products,
  /// procedures, and scans all keep sharing one profile contract.
  Future<UserSkinProfile> buildUserSkinProfileFromLegacyData({
    String userId = defaultUserId,
  }) async {
    final now = DateTime.now();
    final name = await AppPrefs.getUserName();
    final age = await AppPrefs.getUserAgeRange();
    final concerns = await AppPrefs.getUserSkinConcerns();
    final procedure = await AppPrefs.getProcedureType();
    final skinProfile = await AppPrefs.getSkinProfile();
    final products = (await AppPrefs.getTrackedProducts())
        .map(_toCoreLoggedProduct)
        .toList(growable: false);
    final procedures = await _readCoreProcedureHistory(products);
    final scans = await _readCoreScanHistory();
    final activeRoutine = await _buildActiveRoutineFromLegacy(
      skinProfile,
      products,
    );
    final routineHistory = await getRoutineHistory(userId);
    final goals = skinProfile.goals.isNotEmpty
        ? skinProfile.goals
        : <String>[if (procedure.trim().isNotEmpty) procedure.trim()];
    final mergedConcerns = skinProfile.mainConcerns.isNotEmpty
        ? skinProfile.mainConcerns
        : concerns;

    return UserSkinProfile(
      id: _cleanUserId(userId),
      displayName: name.trim(),
      onboarding: OnboardingSkinData(
        skinType: _toCoreSkinType(skinProfile.skinType),
        ageRange: age.trim(),
        location: skinProfile.location,
        climate: skinProfile.climate,
        humidity: skinProfile.humidity,
      ),
      sensitivityLevel: _toCoreSensitivityLevel(skinProfile.sensitivityLevel),
      goals: goals,
      concerns: mergedConcerns,
      preferences: [
        if (skinProfile.productPreference.trim().isNotEmpty)
          _productPreferenceLabel(skinProfile.productPreference.trim()),
      ],
      ingredientsToAvoid: skinProfile.ingredientsToAvoid,
      favoriteIngredients: skinProfile.favoriteIngredients,
      currentProducts: products,
      procedureHistory: procedures,
      scanHistory: scans,
      activeRoutine: activeRoutine,
      routineHistory: routineHistory,
      aiCoachNotes: skinProfile.notes,
      whiteLabelMetadata: const {'source': 'app_prefs_repository_bridge'},
      createdAt: skinProfile.updatedAt ?? now,
      updatedAt: now,
    );
  }

  Future<UserSkinProfile> _freshProfile(String userId) async {
    _profileCache.remove(_cleanUserId(userId));
    return await getUserSkinProfile(userId) ??
        UserSkinProfile.empty(id: _cleanUserId(userId));
  }

  Future<void> _saveCanonicalOnly(UserSkinProfile profile) async {
    final userId = _cleanUserId(profile.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey(userId), jsonEncode(profile.toJson()));
    _cacheAndNotify(userId, profile);
  }

  UserSkinProfile _mergeWithLegacy(
    UserSkinProfile saved,
    UserSkinProfile legacy,
  ) {
    return saved.copyWith(
      displayName: legacy.displayName.isNotEmpty
          ? legacy.displayName
          : saved.displayName,
      onboarding: legacy.onboarding,
      sensitivityLevel: legacy.sensitivityLevel,
      goals: legacy.goals.isNotEmpty ? legacy.goals : saved.goals,
      concerns: legacy.concerns.isNotEmpty ? legacy.concerns : saved.concerns,
      preferences: legacy.preferences.isNotEmpty
          ? legacy.preferences
          : saved.preferences,
      ingredientsToAvoid: legacy.ingredientsToAvoid.isNotEmpty
          ? legacy.ingredientsToAvoid
          : saved.ingredientsToAvoid,
      favoriteIngredients: legacy.favoriteIngredients.isNotEmpty
          ? legacy.favoriteIngredients
          : saved.favoriteIngredients,
      currentProducts: legacy.currentProducts.isNotEmpty
          ? legacy.currentProducts
          : saved.currentProducts,
      procedureHistory: legacy.procedureHistory.isNotEmpty
          ? legacy.procedureHistory
          : saved.procedureHistory,
      scanHistory: legacy.scanHistory.isNotEmpty
          ? legacy.scanHistory
          : saved.scanHistory,
      activeRoutine: saved.activeRoutine ?? legacy.activeRoutine,
      routineHistory: saved.routineHistory.isNotEmpty
          ? saved.routineHistory
          : legacy.routineHistory,
      aiCoachNotes: legacy.aiCoachNotes.isNotEmpty
          ? legacy.aiCoachNotes
          : saved.aiCoachNotes,
      updatedAt: DateTime.now(),
    );
  }

  void _cacheAndNotify(String userId, UserSkinProfile profile) {
    final key = _cleanUserId(userId);
    _profileCache[key] = profile;
    if (!_profileController.isClosed) _profileController.add(profile);
  }

  Future<void> _writeLegacyProfile(UserSkinProfile profile) async {
    final legacy = legacy_profile.SkinProfile(
      skinType: _toLegacySkinType(profile.onboarding.skinType),
      sensitivityLevel: _toLegacySensitivity(profile.sensitivityLevel),
      mainConcerns: profile.concerns,
      currentRoutine: _legacyRoutineMap(profile.activeRoutine),
      productPreference: profile.preferences.isEmpty
          ? ''
          : profile.preferences.first,
      favoriteIngredients: profile.favoriteIngredients,
      ingredientsToAvoid: profile.ingredientsToAvoid,
      pastProcedures: profile.procedureHistory
          .map(
            (procedure) => legacy_profile.SkinProcedureHistoryEntry(
              procedureName: _procedureLabel(procedure.type),
              date: procedure.date,
              outcome: procedure.notes,
            ),
          )
          .toList(growable: false),
      location: profile.onboarding.location,
      climate: profile.onboarding.climate,
      humidity: profile.onboarding.humidity,
      goals: profile.goals,
      notes: profile.aiCoachNotes,
      updatedAt: profile.updatedAt,
    );
    await AppPrefs.saveSkinProfile(legacy);
    if (profile.displayName.trim().isNotEmpty) {
      await AppPrefs.setUserName(profile.displayName.trim());
    }
    if (profile.onboarding.ageRange.trim().isNotEmpty) {
      await AppPrefs.setUserAgeRange(profile.onboarding.ageRange.trim());
    }
    await AppPrefs.setUserSkinConcerns(profile.concerns);
  }

  Future<void> _writeLegacyProducts(List<LoggedProduct> products) async {
    await AppPrefs.saveTrackedProducts(
      products.map(_toLegacyProduct).toList(growable: false),
    );
  }

  Future<void> _writeLegacyProcedures(List<ProcedureRecord> procedures) async {
    await AppPrefs.saveProcedureHistory(
      procedures.map(_toLegacyProcedureEntry).toList(growable: false),
    );
  }

  Future<void> _writeCoreScanHistory(List<ScanRecord> scans) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = scans
        .map(_toUnifiedScanHistoryStorageMap)
        .toList(growable: false);
    await prefs.setString(AppPrefs.scanHistoryKey, jsonEncode(entries));
    await prefs.reload();
  }

  Future<void> _writeRoutineHistory(
    String userId,
    List<DailyRoutine> history,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _routineHistoryKey(_cleanUserId(userId)),
      jsonEncode(history.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<ProcedureRecord>> _readCoreProcedureHistory(
    List<LoggedProduct> products,
  ) async {
    final entries = await AppPrefs.getProcedureEntries();
    final procedures = <ProcedureRecord>[];
    for (final entry in entries) {
      final coreJson = entry['coreProcedureRecord'];
      if (coreJson is Map) {
        procedures.add(
          ProcedureRecord.fromJson(Map<String, dynamic>.from(coreJson)),
        );
        continue;
      }
      try {
        final procedure = legacy_procedure.Procedure.fromJson(entry);
        procedures.add(_toCoreProcedureRecord(procedure, products));
      } catch (error) {
        procedures.add(_fallbackProcedureRecord(entry));
      }
    }
    procedures.sort((a, b) => b.date.compareTo(a.date));
    return procedures;
  }

  Future<List<ScanRecord>> _readCoreScanHistory() async {
    final rawMaps = await _readRawScanMaps();
    final coreById = <String, ScanRecord>{};
    for (final raw in rawMaps) {
      final coreJson = raw['coreScanRecord'];
      if (coreJson is Map) {
        final scan = ScanRecord.fromJson(Map<String, dynamic>.from(coreJson));
        coreById[scan.id] = scan;
      }
    }

    final scans = await AppPrefs.getScanEntries();
    final mapped = scans
      .map((scan) => coreById[scan.id] ?? _toScanRecord(scan))
        .toList();
    mapped.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return mapped;
  }

  Future<List<Map<String, dynamic>>> _readRawScanMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppPrefs.scanHistoryKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<DailyRoutine?> _buildActiveRoutineFromLegacy(
    legacy_profile.SkinProfile profile,
    List<LoggedProduct> products,
  ) async {
    final routine = profile.currentRoutine;
    if (routine.isEmpty && products.isEmpty) return null;
    final now = DateTime.now();
    return DailyRoutine(
      id: 'active_routine',
      effectiveFrom: profile.updatedAt ?? now,
      morningSteps: _routineStepsFor(
        routine['morning'] ?? routine['Morning'] ?? const <String>[],
        RoutineTimeOfDay.morning,
        products,
        now,
      ),
      eveningSteps: _routineStepsFor(
        routine['evening'] ?? routine['Evening'] ?? const <String>[],
        RoutineTimeOfDay.evening,
        products,
        now,
      ),
      asNeededSteps: routine.isEmpty
          ? products
                .take(6)
                .map(
                  (product) => RoutineStep(
                    id: 'product_${product.id}',
                    title: product.name,
                    type: _routineStepTypeForProduct(product),
                    timeOfDay: RoutineTimeOfDay.asNeeded,
                    productId: product.id,
                    productSnapshot: product,
                    createdAt: product.createdAt,
                    updatedAt: product.updatedAt,
                  ),
                )
                .toList(growable: false)
          : const [],
      createdAt: profile.updatedAt ?? now,
      updatedAt: now,
    );
  }

  LoggedProduct _toCoreLoggedProduct(legacy_product.TrackedProduct product) {
    final ingredients = _splitIngredients(product.keyIngredients);
    return LoggedProduct(
      id: product.id,
      name: product.name,
      brand: product.brand,
      category: _productCategoryFor(product.name, product.keyIngredients),
      status: product.endDate == null
          ? ProductStatus.active
          : ProductStatus.completed,
      keyIngredients: ingredients,
      concernsTargeted: _concernsForProduct(
        product.name,
        product.keyIngredients,
        product.notes,
        ingredients,
      ),
      startDate: product.startDate,
      endDate: product.endDate,
      notes: product.notes,
      rating: product.rating == 0 ? null : product.rating,
      photoPath: product.photoPath,
      createdAt: product.startDate,
      updatedAt: product.endDate ?? DateTime.now(),
    );
  }

  legacy_product.TrackedProduct _toLegacyProduct(LoggedProduct product) {
    return legacy_product.TrackedProduct(
      id: product.id,
      name: product.name,
      brand: product.brand,
      keyIngredients: product.keyIngredients.join(', '),
      startDate: product.startDate,
      endDate: product.status == ProductStatus.active
          ? product.endDate
          : product.endDate ?? product.updatedAt,
      notes: [
        product.instructions,
        product.notes,
      ].where((item) => item.trim().isNotEmpty).join(' | '),
      rating: product.rating ?? 0,
      photoPath: product.photoPath,
    );
  }

  ProcedureRecord _toCoreProcedureRecord(
    legacy_procedure.Procedure procedure,
    List<LoggedProduct> products,
  ) {
    final notesText = _procedureSearchText(procedure);
    final appliedProducts = products
        .where((product) {
          final haystack = notesText.toLowerCase();
          final name = product.name.toLowerCase();
          final brand = product.brand.toLowerCase();
          return (name.isNotEmpty && haystack.contains(name)) ||
              (brand.isNotEmpty && haystack.contains(brand)) ||
              product.keyIngredients.any(
                (ingredient) =>
                    ingredient.trim().isNotEmpty &&
                    haystack.contains(ingredient.toLowerCase()),
              );
        })
        .toList(growable: false);

    return ProcedureRecord(
      id: procedure.id,
      type: _procedureTypeFor(procedure.type),
      setting: _procedureSettingFor(procedure.type),
      date: procedure.startDate,
      providerName: procedure.provider,
      appliedProducts: appliedProducts,
      appliedProductIds: appliedProducts.map((product) => product.id).toList(),
      appliedPeptides: _extractAppliedPeptides(notesText, appliedProducts),
      depthMm: _extractDepthMm(notesText),
      treatmentArea: procedure.focusArea ?? '',
      healingPhotoPaths: procedure.taggedPhotos,
      notes: [procedure.customDescription, procedure.notes]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' | '),
      recoveryStatus: procedure.isCompleted
          ? ProcedureRecoveryStatus.completed
          : ProcedureRecoveryStatus.healing,
      createdAt: procedure.startDate,
      updatedAt: procedure.completedAt ?? DateTime.now(),
    );
  }

  ProcedureRecord _fallbackProcedureRecord(Map<String, dynamic> entry) {
    final now = DateTime.now();
    return ProcedureRecord(
      id: entry['id']?.toString() ?? 'procedure_${now.millisecondsSinceEpoch}',
      type: _procedureTypeFor(entry['type']?.toString() ?? ''),
      setting: _procedureSettingFor(entry['type']?.toString() ?? ''),
      date: DateTime.tryParse(entry['startDate']?.toString() ?? '') ?? now,
      notes: entry['notes']?.toString() ?? '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> _toLegacyProcedureEntry(ProcedureRecord procedure) {
    final type = _procedureLabel(procedure.type);
    return {
      'id': procedure.id,
      'type': type,
      'category': procedure.setting == ProcedureSetting.atHome
          ? 'At-Home Skincare Procedures'
          : 'Aesthetic Procedures',
      'provider': procedure.providerName,
      'startDate': procedure.date.toIso8601String(),
      'isCompleted':
          procedure.recoveryStatus == ProcedureRecoveryStatus.completed,
      'completedAt':
          procedure.recoveryStatus == ProcedureRecoveryStatus.completed
          ? procedure.updatedAt.toIso8601String()
          : null,
      'numSessions': 1,
      'focusArea': procedure.treatmentArea.isEmpty
          ? null
          : procedure.treatmentArea,
      'customDescription': procedure.deviceName.isEmpty
          ? null
          : procedure.deviceName,
      'notes': _procedureNotesForLegacy(procedure),
      'customReminders': <String>[],
      'milestoneDates': <String>[],
      'timelineMilestones': <Map<String, dynamic>>[],
      'taggedPhotos': procedure.healingPhotoPaths,
      'journalEntries': <Map<String, dynamic>>[],
      'coreProcedureRecord': procedure.toJson(),
    };
  }

  String _procedureNotesForLegacy(ProcedureRecord procedure) {
    final parts = <String>[
      procedure.notes,
      if (procedure.appliedPeptides.isNotEmpty)
        'Applied peptides: ${procedure.appliedPeptides.join(', ')}',
      if (procedure.appliedProductIds.isNotEmpty)
        'Applied product IDs: ${procedure.appliedProductIds.join(', ')}',
      if (procedure.depthMm != null) 'Depth: ${procedure.depthMm}mm',
      if (procedure.passes != null) 'Passes: ${procedure.passes}',
    ];
    return parts.where((item) => item.trim().isNotEmpty).join(' | ');
  }

  ScanRecord _toScanRecord(legacy_scan.ScanHistoryEntry scan) {
    final skin = scan.toSkinMetrics();
    final visibleFindings = _readVisibleFindings(scan);
    final aiSummary = _readSummary(scan);
    return ScanRecord(
      id: scan.id,
      capturedAt: scan.timestamp,
      source: _scanSourceFromEntry(scan),
      imagePath: scan.imagePath,
      procedureId: scan.procedureId,
      productIds: [
        if ((scan.peptideId ?? '').trim().isNotEmpty) scan.peptideId!,
      ],
      metrics: SkinMetricSet(
        redness: skin.redness,
        texture: skin.texture,
        fineLines: skin.wrinkle,
        pores: skin.pore,
        pigmentation: skin.darkSpots,
        firmness: skin.elasticity,
      ),
      visibleFindings: visibleFindings,
      aiSummary: aiSummary,
      poseTemplate: scan.poseTemplate ?? '',
      focusArea: scan.focusArea ?? '',
      makeupPresent: scan.makeupPresent,
      lightingConfidence: scan.lightingConfidence,
      expressionConfidence: scan.expressionConfidence,
      distanceEstimate: scan.distanceEstimate,
      captureQuality: scan.captureQuality,
      isBaseline: scan.isBaseline,
      preferredReference: scan.preferredReference,
      notes: scan.customDescription ?? '',
      createdAt: scan.timestamp,
    );
  }

  Map<String, dynamic> _toUnifiedScanHistoryStorageMap(ScanRecord scan) {
    final metrics = {
      'redness': scan.metrics.redness,
      'texture': scan.metrics.texture,
      'wrinkle': scan.metrics.fineLines,
      'wrinkles': scan.metrics.fineLines,
      'pore': scan.metrics.pores,
      'pores': scan.metrics.pores,
      'pigment': scan.metrics.pigmentation,
      'pigmentation': scan.metrics.pigmentation,
      'darkSpots': scan.metrics.pigmentation,
      'firmness': scan.metrics.firmness,
      'elasticity': scan.metrics.firmness,
      // Unified 0-100 canonical keys for Luxe metric consumers.
      'localized_redness': (scan.metrics.redness * 10).clamp(0.0, 100.0),
      'texture_smoothness': ((10 - scan.metrics.texture) * 10).clamp(0.0, 100.0),
      'wrinkle_load': (scan.metrics.fineLines * 10).clamp(0.0, 100.0),
      'pigment_load': (scan.metrics.pigmentation * 10).clamp(0.0, 100.0),
      'structural_firmness_elasticity':
          (scan.metrics.firmness * 10).clamp(0.0, 100.0),
    };

    final map = legacy_scan.ScanHistoryEntry(
      id: scan.id,
      timestamp: scan.capturedAt,
      imagePath: scan.imagePath,
      procedureId: scan.procedureId,
      scanType: _scanTypeForSource(scan.source),
      peptideId: scan.productIds.isEmpty ? null : scan.productIds.first,
      estimatedSkinAge: 0,
      metrics: metrics,
      customDescription: scan.notes.isNotEmpty ? scan.notes : scan.aiSummary,
      poseTemplate: scan.poseTemplate.isEmpty ? null : scan.poseTemplate,
      focusArea: scan.focusArea.isEmpty ? null : scan.focusArea,
      lightingConfidence: scan.lightingConfidence,
      preferredReference: scan.preferredReference,
      isBaseline: scan.isBaseline,
      makeupPresent: scan.makeupPresent,
      distanceEstimate: scan.distanceEstimate,
      captureQuality: scan.captureQuality,
      expressionConfidence: scan.expressionConfidence,
    ).toJson();
    map['coreScanRecord'] = scan.toJson();
    return map;
  }

  Map<String, List<String>> _legacyRoutineMap(DailyRoutine? routine) {
    if (routine == null) return const {};
    return {
      if (routine.morningSteps.isNotEmpty)
        'morning': routine.morningSteps.map((step) => step.title).toList(),
      if (routine.eveningSteps.isNotEmpty)
        'evening': routine.eveningSteps.map((step) => step.title).toList(),
      if (routine.weeklySteps.isNotEmpty)
        'weekly': routine.weeklySteps.map((step) => step.title).toList(),
      if (routine.asNeededSteps.isNotEmpty)
        'asNeeded': routine.asNeededSteps.map((step) => step.title).toList(),
    };
  }

  List<RoutineStep> _routineStepsFor(
    List<String> names,
    RoutineTimeOfDay timeOfDay,
    List<LoggedProduct> products,
    DateTime now,
  ) {
    return names
        .asMap()
        .entries
        .map((entry) {
          final name = entry.value.trim();
          final product = products.cast<LoggedProduct?>().firstWhere(
            (candidate) =>
                candidate != null &&
                candidate.name.toLowerCase().contains(name.toLowerCase()),
            orElse: () => null,
          );
          return RoutineStep(
            id: '${timeOfDay.jsonValue}_${entry.key}_$name',
            order: entry.key,
            title: name,
            type: product == null
                ? RoutineStepType.product
                : _routineStepTypeForProduct(product),
            timeOfDay: timeOfDay,
            productId: product?.id,
            productSnapshot: product,
            requiresCalmBarrier:
                name.toLowerCase().contains('ghk') ||
                name.toLowerCase().contains('retinol') ||
                name.toLowerCase().contains('acid'),
            createdAt: now,
            updatedAt: now,
          );
        })
        .toList(growable: false);
  }

  RoutineStepType _routineStepTypeForProduct(LoggedProduct product) {
    return switch (product.category) {
      ProductCategory.cleanser => RoutineStepType.cleanser,
      ProductCategory.toner => RoutineStepType.toner,
      ProductCategory.essence => RoutineStepType.essence,
      ProductCategory.peptide => RoutineStepType.peptide,
      ProductCategory.moisturizer => RoutineStepType.moisturizer,
      ProductCategory.sunscreen => RoutineStepType.sunscreen,
      ProductCategory.device => RoutineStepType.device,
      _ => RoutineStepType.product,
    };
  }

  ProductCategory _productCategoryFor(String name, String ingredients) {
    final text = '$name $ingredients'.toLowerCase();
    if (text.contains('cleanser') || text.contains('wash')) {
      return ProductCategory.cleanser;
    }
    if (text.contains('toner')) return ProductCategory.toner;
    if (text.contains('essence')) return ProductCategory.essence;
    if (text.contains('ghk') ||
        text.contains('copper tripeptide') ||
        text.contains('matrixyl') ||
        text.contains('peptide')) {
      return ProductCategory.peptide;
    }
    if (text.contains('serum')) return ProductCategory.serum;
    if (text.contains('retinol') || text.contains('retinoid')) {
      return ProductCategory.retinoid;
    }
    if (text.contains('acid') || text.contains('exfol')) {
      return ProductCategory.exfoliant;
    }
    if (text.contains('moistur') || text.contains('cream')) {
      return ProductCategory.moisturizer;
    }
    if (text.contains('spf') || text.contains('sunscreen')) {
      return ProductCategory.sunscreen;
    }
    if (text.contains('led') ||
        text.contains('red light') ||
        text.contains('gua sha')) {
      return ProductCategory.device;
    }
    return ProductCategory.other;
  }

  List<String> _concernsForProduct(
    String name,
    String keyIngredients,
    String notes,
    List<String> ingredients,
  ) {
    final text = '$name $keyIngredients $notes'.toLowerCase();
    final concerns = <String>{};
    if (text.contains('ghk') || text.contains('peptide')) {
      concerns.addAll(['firmness', 'texture', 'fine lines']);
    }
    if (text.contains('ceramide') ||
        text.contains('panthenol') ||
        text.contains('centella') ||
        text.contains('heartleaf')) {
      concerns.addAll(['barrier support', 'redness', 'sensitivity']);
    }
    if (text.contains('spf') || text.contains('sunscreen')) {
      concerns.addAll(['pigmentation', 'collagen protection', 'redness']);
    }
    if (text.contains('niacinamide') || text.contains('azelaic')) {
      concerns.addAll(['uneven tone', 'redness', 'pores']);
    }
    if (concerns.isEmpty && ingredients.isNotEmpty) {
      concerns.add('general skin support');
    }
    return concerns.toList(growable: false);
  }

  String _procedureSearchText(legacy_procedure.Procedure procedure) {
    final journalText = procedure.journalEntries
        .map((entry) => '${entry.title} ${entry.content}')
        .join(' ');
    return [
      procedure.type,
      procedure.customDescription,
      procedure.notes,
      journalText,
    ].whereType<String>().join(' ');
  }

  List<String> _extractAppliedPeptides(
    String searchText,
    List<LoggedProduct> appliedProducts,
  ) {
    final text = searchText.toLowerCase();
    final peptides = <String>{};
    if (text.contains('ghk') || text.contains('copper tripeptide')) {
      peptides.add('GHK-Cu Copper Tripeptide-1');
    }
    if (text.contains('matrixyl 3000')) peptides.add('Matrixyl 3000');
    if (text.contains('synthe') || text.contains('matrixyl synthe')) {
      peptides.add("Matrixyl Synthe'6");
    }
    for (final product in appliedProducts) {
      final combined = '${product.name} ${product.keyIngredients.join(' ')}'
          .toLowerCase();
      if (combined.contains('ghk') || combined.contains('copper tripeptide')) {
        peptides.add('GHK-Cu Copper Tripeptide-1');
      }
      if (combined.contains('matrixyl 3000')) peptides.add('Matrixyl 3000');
      if (combined.contains('synthe')) peptides.add("Matrixyl Synthe'6");
    }
    return peptides.toList(growable: false);
  }

  double? _extractDepthMm(String searchText) {
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*mm',
      caseSensitive: false,
    ).firstMatch(searchText);
    return match == null ? null : double.tryParse(match.group(1) ?? '');
  }

  ProcedureType _procedureTypeFor(String value) {
    final text = value.toLowerCase();
    if (text.contains('skinpen') || text.contains('skin pen')) {
      return ProcedureType.skinPen;
    }
    if (text.contains('morpheus') ||
        text.contains('rf microneed') ||
        text.contains('radiofrequency')) {
      return ProcedureType.rfMicroneedling;
    }
    if (text.contains('at-home microneed') ||
        text.contains('at home microneed') ||
        text.contains('home microneed')) {
      return ProcedureType.atHomeMicroneedling;
    }
    if (text.contains('halo')) return ProcedureType.halo;
    if (text == 'bbl' || text.contains('broadband light')) {
      return ProcedureType.bbl;
    }
    if (text.contains('ipl')) return ProcedureType.ipl;
    if (text.contains('laser')) return ProcedureType.laserResurfacing;
    if (text.contains('peel')) return ProcedureType.chemicalPeel;
    if (text.contains('hydrafacial')) return ProcedureType.hydraFacial;
    if (text.contains('red light') || text.contains('led')) {
      return ProcedureType.ledLightTherapy;
    }
    if (text.contains('gua sha')) return ProcedureType.guaSha;
    if (text.contains('facial')) return ProcedureType.facial;
    if (text.contains('inject')) return ProcedureType.injectable;
    return ProcedureType.other;
  }

  ProcedureSetting _procedureSettingFor(String value) {
    final text = value.toLowerCase();
    if (text.contains('at-home') ||
        text.contains('at home') ||
        text.contains('home microneed') ||
        text.contains('gua sha') ||
        text.contains('red light') ||
        text.contains('led')) {
      return ProcedureSetting.atHome;
    }
    return ProcedureSetting.professional;
  }

  String _procedureLabel(ProcedureType type) {
    return switch (type) {
      ProcedureType.skinPen => 'SkinPen',
      ProcedureType.rfMicroneedling => 'RF Microneedling/Morpheus8',
      ProcedureType.atHomeMicroneedling => 'At-Home Microneedling',
      ProcedureType.halo => 'Halo',
      ProcedureType.bbl => 'BBL',
      ProcedureType.ipl => 'IPL',
      ProcedureType.laserResurfacing => 'Laser Resurfacing',
      ProcedureType.chemicalPeel => 'Chemical Peel',
      ProcedureType.hydraFacial => 'HydraFacial',
      ProcedureType.ledLightTherapy => 'LED Light Therapy',
      ProcedureType.guaSha => 'Gua Sha',
      ProcedureType.facial => 'Facial',
      ProcedureType.injectable => 'Injectable',
      ProcedureType.other => 'Other',
    };
  }

  ScanSource _scanSourceFromEntry(legacy_scan.ScanHistoryEntry scan) {
    if (scan.isAiAnalysisScan) return ScanSource.aiAnalysis;
    if (scan.isSkincareScan) return ScanSource.routine;
    if (scan.isProcedureScan) return ScanSource.procedure;
    return ScanSource.progress;
  }

  String _scanTypeForSource(ScanSource source) {
    return switch (source) {
      ScanSource.procedure => legacy_scan.ScanHistoryEntry.scanTypeProcedure,
      ScanSource.routine => legacy_scan.ScanHistoryEntry.scanTypeSkincare,
      ScanSource.aiAnalysis => legacy_scan.ScanHistoryEntry.scanTypeAiAnalysis,
      _ => legacy_scan.ScanHistoryEntry.scanTypeAiAnalysis,
    };
  }

  List<String> _readVisibleFindings(legacy_scan.ScanHistoryEntry scan) {
    final payload = scan.rawPayload;
    if (payload != null) {
      final fromPayload = payload['visibleFindings'] ?? payload['visible_findings'];
      if (fromPayload is Iterable) {
        return fromPayload
            .map((item) => item?.toString().trim() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    }

    final skin = scan.toSkinMetrics();
    final findings = <String>[];
    if (skin.redness >= 6) findings.add('visible redness');
    if (skin.texture >= 6) findings.add('texture unevenness');
    if (skin.pore >= 6) findings.add('visible pores');
    if (skin.wrinkle >= 6) findings.add('fine lines/wrinkles');
    if (skin.darkSpots >= 6) findings.add('uneven pigment');
    if ((scan.focusArea ?? '').trim().isNotEmpty) {
      findings.add('focus area: ${scan.focusArea}');
    }
    return findings;
  }

  String _readSummary(legacy_scan.ScanHistoryEntry scan) {
    final payload = scan.rawPayload;
    if (payload != null) {
      final value = payload['summary'] ?? payload['aiSummary'] ?? payload['ai_summary'];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    final notes = scan.customDescription?.trim() ?? '';
    if (notes.isNotEmpty) return notes;
    return 'Scan saved.';
  }

  SkinType _toCoreSkinType(legacy_profile.SkinType skinType) {
    return switch (skinType) {
      legacy_profile.SkinType.dry => SkinType.dry,
      legacy_profile.SkinType.oily => SkinType.oily,
      legacy_profile.SkinType.combination => SkinType.combination,
      legacy_profile.SkinType.normal => SkinType.normal,
      legacy_profile.SkinType.sensitive => SkinType.sensitive,
    };
  }

  SkinSensitivityLevel _toCoreSensitivityLevel(
    legacy_profile.SensitivityLevel sensitivity,
  ) {
    return switch (sensitivity) {
      legacy_profile.SensitivityLevel.low => SkinSensitivityLevel.low,
      legacy_profile.SensitivityLevel.moderate => SkinSensitivityLevel.moderate,
      legacy_profile.SensitivityLevel.high => SkinSensitivityLevel.high,
      legacy_profile.SensitivityLevel.veryHigh => SkinSensitivityLevel.veryHigh,
    };
  }

  legacy_profile.SkinType _toLegacySkinType(SkinType skinType) {
    return switch (skinType) {
      SkinType.dry => legacy_profile.SkinType.dry,
      SkinType.oily => legacy_profile.SkinType.oily,
      SkinType.combination => legacy_profile.SkinType.combination,
      SkinType.normal => legacy_profile.SkinType.normal,
      SkinType.sensitive => legacy_profile.SkinType.sensitive,
    };
  }

  legacy_profile.SensitivityLevel _toLegacySensitivity(
    SkinSensitivityLevel sensitivity,
  ) {
    return switch (sensitivity) {
      SkinSensitivityLevel.low => legacy_profile.SensitivityLevel.low,
      SkinSensitivityLevel.moderate => legacy_profile.SensitivityLevel.moderate,
      SkinSensitivityLevel.high => legacy_profile.SensitivityLevel.high,
      SkinSensitivityLevel.veryHigh => legacy_profile.SensitivityLevel.veryHigh,
    };
  }

  String _productPreferenceLabel(String preference) {
    if (preference.startsWith('other:')) {
      final detail = preference.substring('other:'.length).trim();
      return detail.isEmpty ? 'Other' : 'Other: $detail';
    }
    return switch (preference) {
      'korean' => 'Korean (K-beauty)',
      'natural' => 'Natural / Organic',
      'western' => 'Western / Pharmacy',
      'clean_beauty' => 'Clean Beauty',
      'luxury' => 'Luxury / Medical-grade',
      'mixed' => 'Mixed',
      'other' => 'Other',
      _ => preference,
    };
  }

  List<String> _splitIngredients(String ingredients) {
    return ingredients
        .split(RegExp(r'[,;/]'))
        .map((ingredient) => ingredient.trim())
        .where((ingredient) => ingredient.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  String _cleanUserId(String userId) {
    final clean = userId.trim();
    return clean.isEmpty ? defaultUserId : clean;
  }

  String _profileKey(String userId) => '$_profileKeyPrefix$userId';
  String _activeRoutineKey(String userId) => '$_activeRoutineKeyPrefix$userId';
  String _routineHistoryKey(String userId) =>
      '$_routineHistoryKeyPrefix$userId';

  Future<T> _guard<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      debugPrint('SkincareRepositoryImpl failed to $operation: $error');
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'skincare_repository_impl',
          context: ErrorDescription(operation),
        ),
      );
      rethrow;
    }
  }

  @visibleForTesting
  void clearMemoryCache() {
    _profileCache.clear();
  }

  Future<void> dispose() async {
    await _profileController.close();
  }
}
