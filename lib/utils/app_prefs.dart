import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';

import '../models/product_tracker.dart';
import '../models/product_feedback.dart';
import '../models/acne_rosacea_log.dart';
import '../models/scan_history.dart';
import '../models/skin_profile.dart';
import '../models/procedure_log.dart';
import 'app_logger.dart';

class AppPrefs {
  // ── Keys ──
  static const String onboardingCompleteKey = 'onboarding_complete';
  static const String tourCompletedKey = 'tour_completed';
  static const String userNameKey = 'user_name';
  static const String userAgeRangeKey = 'user_age_range';
  static const String userSkinConcernsKey = 'user_skin_concerns';
  static const String userClinicKey = 'user_clinic';
  static const String userZipCodeKey = 'user_zip_code';
  static const String userProfilePictureKey = 'user_profile_picture';
  static const String skinProfileKey = 'skin_profile';
  static const String skinProfileSkippedNote =
      'Onboarding skipped before all profile details were added.';
  static const String trackedProcedureKey = 'tracked_procedure';
  static const String procedureTypeKey = 'procedure_type';
  static const String scanHistoryKey = 'scan_history';
  static const String legacyScanHistoryKey = 'scan_history_v1';
  static const String procedurePhotoComparisonKey =
      'procedure_photo_comparison';
  static const String procedureHistoryKey = 'procedure_history';
  static const String selectedProcedureIdKey = 'selected_procedure_id';
  static const String activeSkincareProductKey = 'active_skincare_product_name';
  static const String trackedProductsKey = 'tracked_products';
  static const String productFeedbackKey = 'product_feedback_entries';
  static const String acneRosaceaLogsKey = 'acne_rosacea_logs';
  static const String peptideStackNameKey = 'peptide_stack_name';
  static const String scanHistoryStorageWarningKey =
      'scan_history_storage_warning';
  static const String verboseDiagnosticsKey = 'verbose_diagnostics_enabled';
  static const int maxStoredScans = 50;
  static const int minStoredScansOnQuotaRetry = 30;
  static const int maxStoredScanImages = 12;
  static const int scanHistoryWarningBytes = 3000000;

  static Future<bool> getVerboseDiagnosticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(verboseDiagnosticsKey) ?? false;
    AppLogger.setVerboseEnabled(enabled);
    return enabled;
  }

  static Future<void> setVerboseDiagnosticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(verboseDiagnosticsKey, enabled);
    AppLogger.setVerboseEnabled(enabled);
  }

  static Future<void> loadVerboseDiagnosticsSetting() async {
    await getVerboseDiagnosticsEnabled();
  }

  // ── Journal Support Methods (getString / setString) ──
  static Future<String?> getString(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> setString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> getPeptideStackNameOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(peptideStackNameKey)?.trim();
    if (saved == null || saved.isEmpty) return null;
    return saved;
  }

  static Future<void> setPeptideStackName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = name?.trim();
    if (clean == null || clean.isEmpty) {
      await prefs.remove(peptideStackNameKey);
      return;
    }
    await prefs.setString(peptideStackNameKey, clean);
  }

  // ── Active Skincare Product Methods ──
  static Future<void> setActiveProduct(String? productName) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = productName?.trim();
    if (clean == null || clean.isEmpty) {
      await prefs.remove(activeSkincareProductKey);
      debugPrint('Cleared active skincare product');
    } else {
      await prefs.setString(activeSkincareProductKey, clean);
      debugPrint('Set active skincare product: $clean');
    }
  }

  static Future<String?> getActiveProductOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(activeSkincareProductKey)?.trim();
    debugPrint('Got active skincare product: $saved');
    return saved;
  }

  static Future<String> getActiveProduct() async {
    return await getActiveProductOrNull() ?? '';
  }

  // ── Product Tracker Functions ──
  static Future<void> addTrackedProduct(TrackedProduct product) async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint('addTrackedProduct called for: ${product.name}');

    final currentJson = prefs.getStringList(trackedProductsKey) ?? [];
    debugPrint(
      'Current stored products count before save: ${currentJson.length}',
    );

    final current = currentJson
        .map((jsonStr) {
          try {
            return jsonDecode(jsonStr) as Map<String, dynamic>;
          } catch (e) {
            debugPrint('Error decoding existing product: $e');
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    current.add(product.toJson());
    final updatedJson = current.map((map) => jsonEncode(map)).toList();

    final success = await prefs.setStringList(trackedProductsKey, updatedJson);
    debugPrint('Save success: $success | Total now: ${updatedJson.length}');
  }

  static Future<List<TrackedProduct>> getTrackedProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(trackedProductsKey) ?? [];
    debugPrint(
      'getTrackedProducts called | Raw stored count: ${jsonList.length}',
    );

    final products = jsonList
        .map((jsonStr) {
          try {
            final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
            return TrackedProduct.fromJson(jsonMap);
          } catch (e) {
            debugPrint('Error decoding product: $e | Raw: $jsonStr');
            return null;
          }
        })
        .whereType<TrackedProduct>()
        .toList();

    debugPrint('Successfully loaded ${products.length} products');
    return products;
  }

  static Future<void> saveTrackedProducts(List<TrackedProduct> products) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = products
        .map((product) => jsonEncode(product.toJson()))
        .toList();
    await prefs.setStringList(trackedProductsKey, jsonList);
  }

  static Future<void> updateTrackedProduct(
    TrackedProduct updatedProduct,
  ) async {
    final products = await getTrackedProducts();
    final index = products.indexWhere(
      (product) => product.id == updatedProduct.id,
    );
    if (index == -1) {
      products.add(updatedProduct);
    } else {
      products[index] = updatedProduct;
    }
    await saveTrackedProducts(products);
  }

  static Future<void> removeTrackedProduct(String productId) async {
    final products = await getTrackedProducts();
    products.removeWhere((product) => product.id == productId);
    await saveTrackedProducts(products);
  }

  // ── Scan Entries for Specific Product ──
  static Future<List<ScanHistoryEntry>> getScanEntriesForProduct(
    String productName,
  ) async {
    final allEntries = await getScanEntries();
    return allEntries
        .where(
          (entry) => (entry.productName ?? '').trim() == productName.trim(),
        )
        .toList();
  }

  // ── Product Feedback Functions ──
  static Future<List<ProductFeedbackEntry>> getProductFeedback({
    String? productId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
        prefs.getStringList(productFeedbackKey) ?? const <String>[];
    final entries = jsonList
        .map((jsonStr) {
          try {
            return ProductFeedbackEntry.fromJson(
              jsonDecode(jsonStr) as Map<String, dynamic>,
            );
          } catch (e) {
            debugPrint('Error decoding product feedback entry: $e');
            return null;
          }
        })
        .whereType<ProductFeedbackEntry>()
        .toList();

    final filtered = productId == null
        ? entries
        : entries.where((e) => e.productId == productId).toList();

    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  static Future<void> saveProductFeedbackList(
    List<ProductFeedbackEntry> entries,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = entries
        .map((e) => jsonEncode(e.toJson()))
        .toList(growable: false);
    await prefs.setStringList(productFeedbackKey, jsonList);
  }

  static Future<void> addProductFeedback(ProductFeedbackEntry entry) async {
    final all = await getProductFeedback();
    all.add(entry);
    await saveProductFeedbackList(all);
  }

  static Future<void> removeProductFeedback(String entryId) async {
    final all = await getProductFeedback();
    all.removeWhere((e) => e.id == entryId);
    await saveProductFeedbackList(all);
  }

  // ── Acne & Rosacea Tracker logs ─────────────────────────────────────────
  //
  // Stored as a JSON map keyed by SkinMetricRegistry key. Each entry is an
  // AcneRosaceaLog (timestamp / value 0-10 / optional free-text note).
  // Lists per metric are capped at 90 entries to avoid unbounded growth.

  static Future<Map<String, List<AcneRosaceaLog>>> getAcneRosaceaLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(acneRosaceaLogsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, List<AcneRosaceaLog>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            final list = v
                .whereType<Map>()
                .map(
                  (e) => AcneRosaceaLog.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList();
            list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            out[k.toString()] = list;
          }
        });
        return out;
      }
    } catch (_) {}
    return {};
  }

  static Future<List<AcneRosaceaLog>> getAcneRosaceaLogsForMetric(
    String metricKey,
  ) async {
    final all = await getAcneRosaceaLogs();
    return all[metricKey] ?? const [];
  }

  static Future<List<AcneRosaceaLog>> getRecentAcneRosaceaLogs({
    int limit = 12,
  }) async {
    final all = await getAcneRosaceaLogs();
    final merged = <AcneRosaceaLog>[];
    for (final list in all.values) {
      merged.addAll(list);
    }
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return merged.take(limit).toList();
  }

  static Future<bool> hasAnyAcneRosaceaLogs() async {
    final all = await getAcneRosaceaLogs();
    for (final list in all.values) {
      if (list.isNotEmpty) return true;
    }
    return false;
  }

  static Future<void> addAcneRosaceaLog(
    String metricKey,
    int value, {
    String note = '',
    String imagePath = '',
  }) async {
    final entry = AcneRosaceaLog(
      timestamp: DateTime.now(),
      metricKey: metricKey,
      value: value.clamp(0, 10),
      note: note.trim(),
      imagePath: imagePath.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    final current = await getAcneRosaceaLogs();
    final list = List<AcneRosaceaLog>.from(current[metricKey] ?? const []);
    list.add(entry);
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    while (list.length > 90) {
      list.removeLast();
    }
    current[metricKey] = list;
    final encoded = <String, dynamic>{};
    current.forEach(
      (k, v) => encoded[k] = v.map((e) => e.toJson()).toList(growable: false),
    );
    await prefs.setString(acneRosaceaLogsKey, jsonEncode(encoded));
    await prefs.reload();
  }

  static Future<void> removeAcneRosaceaLog(
    String metricKey,
    DateTime timestamp,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getAcneRosaceaLogs();
    final list = List<AcneRosaceaLog>.from(current[metricKey] ?? const []);
    list.removeWhere(
      (e) => e.timestamp.toIso8601String() == timestamp.toIso8601String(),
    );
    current[metricKey] = list;
    final encoded = <String, dynamic>{};
    current.forEach(
      (k, v) => encoded[k] = v.map((e) => e.toJson()).toList(growable: false),
    );
    await prefs.setString(acneRosaceaLogsKey, jsonEncode(encoded));
    await prefs.reload();
  }

  // ── Onboarding & User Profile ──
  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onboardingCompleteKey) ?? false;
  }

  static Future<bool> isSkinProfileComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool(onboardingCompleteKey) ?? false;
    if (!onboardingComplete) return false;

    final profile = await getSkinProfileOrNull();
    if (profile == null) return false;
    if (profile.updatedAt == null) return false;
    if (profile.notes.contains(skinProfileSkippedNote)) return false;

    return true;
  }

  static Future<void> saveOnboarding({
    required String userName,
    required String procedureType,
    String? ageRange,
    List<String>? skinConcerns,
    String? clinic,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanName = userName.trim();
    final cleanProcedure = procedureType.trim();
    final cleanAgeRange = (ageRange ?? '').trim();
    final cleanConcerns = (skinConcerns ?? const <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final cleanClinic = (clinic ?? '').trim();

    if (cleanName.isEmpty) {
      await prefs.remove(userNameKey);
    } else {
      await prefs.setString(userNameKey, cleanName);
    }
    await prefs.setString(trackedProcedureKey, cleanProcedure);
    await prefs.setString(procedureTypeKey, cleanProcedure);
    await prefs.setString(userAgeRangeKey, cleanAgeRange);
    await prefs.setStringList(userSkinConcernsKey, cleanConcerns);
    await prefs.setString(userClinicKey, cleanClinic);
    await prefs.setBool(onboardingCompleteKey, true);
  }

  static Future<void> saveSkinProfile(
    SkinProfile profile, {
    bool markOnboardingComplete = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = profile.copyWith(updatedAt: DateTime.now());

    await prefs.setString(skinProfileKey, jsonEncode(normalized.toJson()));
    await prefs.setStringList(userSkinConcernsKey, normalized.mainConcerns);

    if (normalized.pastProcedures.isNotEmpty) {
      final latestProcedure = normalized.pastProcedures.last.procedureName
          .trim();
      if (latestProcedure.isNotEmpty) {
        await prefs.setString(procedureTypeKey, latestProcedure);
        await prefs.setString(trackedProcedureKey, latestProcedure);
      }
    }

    if (markOnboardingComplete) {
      await prefs.setBool(onboardingCompleteKey, true);
    }
  }

  static Future<SkinProfile?> getSkinProfileOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(skinProfileKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return SkinProfile.fromJson(decoded);
    } catch (e) {
      debugPrint('Error decoding skin profile: $e');
      return null;
    }
  }

  static Future<SkinProfile> getSkinProfile() async {
    return await getSkinProfileOrNull() ?? const SkinProfile();
  }

  static Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(userNameKey);
    final clean = stored?.trim();
    return clean == null || clean.isEmpty ? 'Guest' : clean;
  }

  static Future<String> getUserAgeRange() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(userAgeRangeKey);
    return stored?.trim() ?? '';
  }

  static Future<void> setUserAgeRange(String ageRange) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userAgeRangeKey, ageRange.trim());
  }

  static Future<List<String>> getUserSkinConcerns() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(userSkinConcernsKey);
    return stored ?? [];
  }

  static Future<void> setUserSkinConcerns(List<String> concerns) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      userSkinConcernsKey,
      concerns.map((e) => e.trim()).toList(),
    );
  }

  static Future<String> getUserClinic() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(userClinicKey);
    return stored?.trim() ?? '';
  }

  static Future<void> setUserClinic(String clinic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userClinicKey, clinic.trim());
  }

  static Future<String> getUserZipCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(userZipCodeKey)?.trim() ?? '';
  }

  static Future<void> setUserZipCode(String zip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userZipCodeKey, zip.trim());
  }

  static Future<String?> getUserProfilePictureOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(userProfilePictureKey)?.trim();
  }

  static Future<void> setUserProfilePicture(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = reference.trim();
    if (clean.isEmpty) {
      await prefs.remove(userProfilePictureKey);
    } else {
      await prefs.setString(userProfilePictureKey, clean);
    }
  }

  static Future<void> removeUserProfilePicture() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userProfilePictureKey);
    debugPrint('Removed user profile picture');
  }

  // ── Procedures ──
  static Future<List<Map<String, dynamic>>> getProcedureEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs
        .reload(); // ← CRITICAL FIX: Ensures latest journal entries are read
    final raw = prefs.getString(procedureHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = decoded.cast<Map<String, dynamic>>();

      list.sort((a, b) {
        final dateA = DateTime.parse(a['startDate'] as String);
        final dateB = DateTime.parse(b['startDate'] as String);
        return dateB.compareTo(dateA);
      });

      debugPrint(
        '[getProcedureEntries] loaded ${list.length} procedures: '
        '${list.map((p) => "${p['id']}:${p['type']}").join(', ')}',
      );
      return list;
    } catch (e) {
      debugPrint('[getProcedureEntries] ERROR: $e');
      return [];
    }
  }

  static Future<void> saveProcedureHistory(
    List<Map<String, dynamic>> procedures,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint(
      '[saveProcedureHistory] saving ${procedures.length} procedures: '
      '${procedures.map((p) => "${p['id']}:${p['type']}").join(', ')}',
    );
    await prefs.setString(procedureHistoryKey, jsonEncode(procedures));
    await prefs.reload(); // Extra safety after write
  }

  static Future<String?> getSelectedProcedureIdOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(selectedProcedureIdKey)?.trim();
    debugPrint('[getSelectedProcedureId] selectedProcedureId=$id');
    return id;
  }

  static Future<void> setSelectedProcedureId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.trim().isEmpty) {
      await prefs.remove(selectedProcedureIdKey);
      debugPrint('[setSelectedProcedureId] cleared');
    } else {
      await prefs.setString(selectedProcedureIdKey, id.trim());
      debugPrint('[setSelectedProcedureId] set to ${id.trim()}');
    }
  }

  static Future<String> getTrackedProcedure() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(trackedProcedureKey) ?? '';
  }

  static Future<void> setTrackedProcedure(String procedureType) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = procedureType.trim();
    if (clean.isEmpty) {
      await prefs.remove(trackedProcedureKey);
    } else {
      await prefs.setString(trackedProcedureKey, clean);
    }
  }

  // ── Scans ──
  static Future<List<ScanHistoryEntry>> getScanEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // ← Added for consistency
    final raw = prefs.getString(scanHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final history = decoded
          .map((e) => ScanHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      final normalized = _normalizeScanHistory(history);
      if (!_scanListsEquivalent(history, normalized)) {
        await _saveScanEntries(normalized);
      }
      return normalized;
    } catch (_) {
      return [];
    }
  }

  static Future<List<ScanHistoryEntry>> addScanEntry(
    ScanHistoryEntry entry,
  ) async {
    final history = await getScanEntries();
    history.add(entry);
    final normalized = _normalizeScanHistory(history);
    await _saveScanEntries(normalized);
    debugPrint('Added scan entry | Total scans now: ${normalized.length}');
    return normalized;
  }

  static Future<String?> consumeScanStorageWarning() async {
    final prefs = await SharedPreferences.getInstance();
    final message = prefs.getString(scanHistoryStorageWarningKey);
    if (message != null && message.isNotEmpty) {
      await prefs.remove(scanHistoryStorageWarningKey);
    }
    return message;
  }

  static Future<List<ScanHistoryEntry>> addScanMetric(
    SkinMetrics current, {
    String? procedureId,
    String? productName,
    String? imagePath,
    String? poseTemplate,
    String? focusArea,
    String? customDescription,
    double? lightingConfidence,
    bool preferredReference = false,
    Map<String, double>? extraMetrics,
    bool makeupPresent = false,
    double? distanceEstimate,
    double? headTiltAngle,
    double? expressionConfidence,
  }) async {
    final activeProduct = productName ?? await getActiveProduct();
    final now = DateTime.now();

    // Determine if this is the baseline photo: first photo for this procedure.
    // Also resolve the procedure type string so every scan carries it.
    bool isBaseline = false;
    String? resolvedProcedureType = current.procedure?.trim().isNotEmpty == true
        ? current.procedure!.trim()
        : null;
    String? resolvedCustomDescription =
        customDescription?.trim().isNotEmpty == true
        ? customDescription!.trim()
        : null;

    if (procedureId != null && procedureId.isNotEmpty) {
      // Simple check: baseline = first upload ever for this procedure (no existing scans)
      final existingScans = await getScanEntries();
      final procedureScans = existingScans
          .where((e) => e.procedureId == procedureId)
          .toList();
      isBaseline = procedureScans.isEmpty; // true only for the FIRST photo
      debugPrint(
        '[addScanMetric] procedureId=$procedureId | existingScans=${procedureScans.length} | isBaseline=$isBaseline',
      );

      // Tag the scan with the procedure's type so downstream screens can resolve
      // the correct procedure even without a selectedProcedureId in scope.
      try {
        final procedures = await getProcedureEntries();
        final match = procedures.firstWhere(
          (p) => (p['id']?.toString() ?? '') == procedureId,
        );
        if (resolvedProcedureType == null) {
          final t = (match['type']?.toString() ?? '').trim();
          if (t.isNotEmpty) resolvedProcedureType = t;
        }
        final custom = (match['customDescription']?.toString() ?? '').trim();
        if (resolvedCustomDescription == null && custom.isNotEmpty) {
          resolvedCustomDescription = custom;
        }
      } catch (_) {}
      debugPrint(
        '[addScanMetric] resolvedProcedureType=$resolvedProcedureType',
      );
    }

    final entry = ScanHistoryEntry(
      id: ScanHistoryEntry.generateId(now, imagePath),
      timestamp: now,
      procedureId: procedureId,
      scanType: procedureId?.trim().isNotEmpty == true
          ? ScanHistoryEntry.scanTypeProcedure
          : activeProduct.isNotEmpty
          ? ScanHistoryEntry.scanTypeSkincare
          : ScanHistoryEntry.scanTypeSkincare,
      productName: activeProduct.isNotEmpty ? activeProduct : null,
      imagePath: imagePath,
      metrics: {
        'redness': current.redness,
        'texture': current.texture,
        'wrinkles': current.wrinkle,
        'pores': current.pore,
        'darkSpots': current.darkSpots,
        'elasticity': current.elasticity,
        ...?extraMetrics,
      },
      estimatedSkinAge: estimateVisualSkinAge(current),
      procedure: resolvedProcedureType,
      poseTemplate: poseTemplate,
      focusArea: focusArea?.trim().isNotEmpty == true
          ? focusArea!.trim()
          : null,
      customDescription: resolvedCustomDescription,
      lightingConfidence: lightingConfidence,
      preferredReference: preferredReference,
      isBaseline: isBaseline,
      makeupPresent: makeupPresent,
      distanceEstimate: distanceEstimate,
      headTiltAngle: headTiltAngle,
      expressionConfidence: expressionConfidence,
    );
    debugPrint(
      'Added scan for product: ${entry.productName ?? "none"} | isBaseline=$isBaseline | procedureId=$procedureId | procedureType=${entry.procedure} | makeup=$makeupPresent',
    );
    final history = await addScanEntry(entry);
    await _updateProcedurePhotoComparison(entry, history);
    return history;
  }

  static Future<void> clearScanHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(scanHistoryKey);
    await prefs.remove(legacyScanHistoryKey);
    await prefs.remove(procedurePhotoComparisonKey);
    await prefs.remove(scanHistoryStorageWarningKey);
    await prefs.remove(acneRosaceaLogsKey);
    debugPrint('Cleared scan history');
  }

  /// NUCLEAR CLEAR - removes ALL scan, procedure, and product data
  /// Deletes Hive boxes and all SharedPreferences keys
  /// Use this for complete profile reset with no leftovers
  static Future<void> clearAllDataAggressively() async {
    debugPrint('🔥 NUCLEAR CLEAR STARTED - Deleting ALL data...');

    final prefs = await SharedPreferences.getInstance();

    // ── VERIFY BEFORE CLEAR ──
    final beforeScanData = prefs.getString(scanHistoryKey);
    final beforeProcedureData = prefs.getString(procedureHistoryKey);
    debugPrint('Before clear - Scan data exists: ${beforeScanData != null}');
    debugPrint(
      'Before clear - Procedure data exists: ${beforeProcedureData != null}',
    );

    // ── HIVE BOXES ──
    // Fully wipe the typed procedureLogs box (clear + delete + reopen empty),
    // then delete every other box that could hold scan/procedure/photo data.
    await clearAllProcedureData();
    await _deleteHiveBoxes(const [
      'scans',
      'skin_analysis',
      'scan_history',
      'photos',
      'procedures',
    ]);

    // ── SHARED PREFERENCES - SCAN HISTORY ──
    debugPrint('Clearing scan history keys...');
    await prefs.remove(scanHistoryKey);
    await prefs.remove(legacyScanHistoryKey);
    await prefs.remove(procedurePhotoComparisonKey);
    await prefs.remove(scanHistoryStorageWarningKey);
    await prefs.remove(acneRosaceaLogsKey);
    debugPrint('✓ Scan history keys removed');

    // ── PROCEDURE HISTORY ──
    debugPrint('Clearing procedure history keys...');
    await prefs.remove(procedureHistoryKey);
    await prefs.remove(selectedProcedureIdKey);
    await prefs.remove(trackedProcedureKey);
    await prefs.remove(procedureTypeKey);
    debugPrint('✓ Procedure history keys removed');

    // ── PRODUCT TRACKING ──
    debugPrint('Clearing product tracking keys...');
    await prefs.remove(trackedProductsKey);
    await prefs.remove(productFeedbackKey);
    await prefs.remove(activeSkincareProductKey);
    await prefs.remove('skincare_journal_entries'); // Journal entries
    debugPrint('✓ Product tracking keys removed');

    // ── PEPTIDE STACK ──
    await prefs.remove(peptideStackNameKey);
    debugPrint('✓ Peptide stack removed');

    // ── ADDITIONAL CLEANUP ──
    // Remove any other tracking data that might exist
    await prefs.remove('last_scan_metrics'); // Legacy metrics
    await prefs.remove('baseline_scan'); // Legacy baseline
    debugPrint('✓ Legacy keys removed');

    // ── FORCE RELOAD FROM DISK ──
    // Force reload from disk to clear any in-memory caches
    await prefs.reload();
    debugPrint('✓ SharedPreferences reloaded from disk');

    // ── VERIFY AFTER CLEAR ──
    final afterScanData = prefs.getString(scanHistoryKey);
    final afterProcedureData = prefs.getString(procedureHistoryKey);
    final afterTrackedProducts = prefs.getStringList(trackedProductsKey);

    debugPrint('After clear - Scan data exists: ${afterScanData != null}');
    debugPrint(
      'After clear - Procedure data exists: ${afterProcedureData != null}',
    );
    debugPrint(
      'After clear - Products exist: ${afterTrackedProducts != null && afterTrackedProducts.isNotEmpty}',
    );

    // Verify actual deletion
    if (afterScanData != null || afterProcedureData != null) {
      debugPrint('⚠️ WARNING: Some data still exists after clear!');
      debugPrint(
        '   Scan data: ${afterScanData != null ? "STILL EXISTS" : "cleared"}',
      );
      debugPrint(
        '   Procedure data: ${afterProcedureData != null ? "STILL EXISTS" : "cleared"}',
      );
    }

    debugPrint(
      '🔥 NUCLEAR CLEAR COMPLETE: All Hive boxes and SharedPreferences data removed',
    );
    debugPrint('   - Hive procedureLogs: DELETED');
    debugPrint('   - Scan history: DELETED');
    debugPrint('   - Procedure history: DELETED');
    debugPrint('   - Product tracking: DELETED');
    debugPrint('   - Journal entries: DELETED');
    debugPrint('   - All legacy data: DELETED');
  }

  /// HARD RESET - the most aggressive reset possible.
  /// Wipes EVERY SharedPreferences key (including onboarding/profile) AND
  /// deletes every Hive box from disk. After calling this the app holds zero
  /// persisted state. Pair with RestartWidget.restartApp() to show the user a
  /// completely empty state immediately.
  static Future<void> hardResetEverything() async {
    debugPrint('💣 HARD RESET STARTED - Wiping EVERYTHING...');

    // ── HIVE: fully wipe the typed procedureLogs box (clear+delete+reopen) ──
    await clearAllProcedureData();

    // ── HIVE: close + delete all remaining boxes from disk ──
    await _deleteHiveBoxes(const [
      'scans',
      'skin_analysis',
      'scan_history',
      'photos',
      'procedures',
    ]);

    // ── SHARED PREFERENCES: nuke every key ──
    final prefs = await SharedPreferences.getInstance();
    final keyCountBefore = prefs.getKeys().length;
    debugPrint('SharedPreferences keys before wipe: $keyCountBefore');

    final cleared = await prefs.clear();
    debugPrint('prefs.clear() returned: $cleared');

    await prefs.reload();
    final keyCountAfter = prefs.getKeys().length;
    debugPrint('SharedPreferences keys after wipe: $keyCountAfter');

    if (keyCountAfter > 0) {
      debugPrint(
        '⚠️ WARNING: $keyCountAfter keys still present after clear(): '
        '${prefs.getKeys().join(', ')}',
      );
    }

    debugPrint('💣 HARD RESET COMPLETE: All persisted data destroyed.');
  }

  /// Closes (if open) and deletes the named Hive boxes from disk.
  /// Missing boxes are skipped safely. Logs every action.
  static Future<void> _deleteHiveBoxes(List<String> boxNames) async {
    for (final name in boxNames) {
      try {
        if (Hive.isBoxOpen(name)) {
          final box = Hive.box(name);
          final count = box.length;
          await box.clear();
          await box.close();
          debugPrint('✓ Hive box "$name": cleared & closed ($count entries)');
        }
        await Hive.deleteBoxFromDisk(name);
        debugPrint('✓ Hive box "$name": deleted from disk');
      } catch (e) {
        debugPrint('⚠️ Hive box "$name": error during delete: $e');
      }
    }
  }

  /// Fully wipes the typed `procedureLogs` Hive box so no old logs can survive
  /// a reset. This clears the open box, deletes the box file from disk,
  /// re-registers the adapter, and re-opens a fresh empty box so the app
  /// immediately has a usable (empty) box again.
  static Future<void> clearAllProcedureData() async {
    const boxName = 'procedureLogs';
    try {
      // 1. Clear + close the box if it is currently open in memory.
      if (Hive.isBoxOpen(boxName)) {
        final box = Hive.box<ProcedureLog>(boxName);
        final count = box.length;
        await box.clear();
        await box.close();
        debugPrint('✓ procedureLogs: cleared & closed ($count entries)');
      }

      // 2. Delete the box file from disk (removes any persisted data).
      await Hive.deleteBoxFromDisk(boxName);
      debugPrint('✓ procedureLogs: deleted from disk');

      // 3. Ensure the adapter is registered before re-opening.
      if (!Hive.isAdapterRegistered(5)) {
        Hive.registerAdapter(ProcedureLogAdapter());
        debugPrint('✓ ProcedureLogAdapter re-registered');
      }

      // 4. Re-open a fresh, empty box so callers get a clean, usable box.
      await Hive.openBox<ProcedureLog>(boxName);
      debugPrint('✓ procedureLogs: re-opened (empty)');
    } catch (e) {
      debugPrint('⚠️ clearAllProcedureData error: $e');
    }
  }

  static Future<Map<String, String?>> getProcedurePhotoComparison(
    String procedureId,
  ) async {
    final cleanProcedureId = procedureId.trim();
    if (cleanProcedureId.isEmpty) {
      return const {
        'baselineScanId': null,
        'baselineImagePath': null,
        'latestScanId': null,
        'latestImagePath': null,
      };
    }

    final comparisonMap = await _getProcedurePhotoComparisonMap();
    final existing = comparisonMap[cleanProcedureId];
    if (existing is Map<String, dynamic>) {
      return {
        'baselineScanId': existing['baselineScanId']?.toString(),
        'baselineImagePath': existing['baselineImagePath']?.toString(),
        'latestScanId': existing['latestScanId']?.toString(),
        'latestImagePath': existing['latestImagePath']?.toString(),
      };
    }

    final history = await getScanEntries();
    final derived = _buildProcedurePhotoComparisonFromHistory(
      cleanProcedureId,
      history,
    );
    if (derived.values.any((value) => value != null && value.isNotEmpty)) {
      final updatedMap = Map<String, dynamic>.from(comparisonMap);
      updatedMap[cleanProcedureId] = derived;
      await _saveProcedurePhotoComparisonMap(updatedMap);
    }
    return derived;
  }

  static List<ScanHistoryEntry> _normalizeScanHistory(
    List<ScanHistoryEntry> history,
  ) {
    return _normalizeScanHistoryForStorage(
      history,
      maxScans: maxStoredScans,
      keepImageCount: maxStoredScanImages,
    );
  }

  static List<ScanHistoryEntry> _normalizeScanHistoryForStorage(
    List<ScanHistoryEntry> history, {
    required int maxScans,
    required int keepImageCount,
  }) {
    final sorted = List<ScanHistoryEntry>.from(history)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final retained = sorted.take(maxScans).toList();
    final keepImageIds = retained.take(keepImageCount).map((e) => e.id).toSet();

    final oldestProcedureScanById = <String, ScanHistoryEntry>{};
    for (final entry in retained.reversed) {
      final procedureId = entry.procedureId?.trim();
      if (procedureId == null || procedureId.isEmpty) continue;
      oldestProcedureScanById.putIfAbsent(procedureId, () => entry);
    }

    return retained.map((entry) {
      final procedureId = entry.procedureId?.trim();
      final baselineEntry = oldestProcedureScanById[procedureId];
      final shouldBeBaseline = procedureId != null && procedureId.isNotEmpty
          ? baselineEntry != null && baselineEntry.id == entry.id
          : entry.isBaseline;
      final imagePath = keepImageIds.contains(entry.id)
          ? entry.imagePath
          : _prunedScanImagePath(entry.imagePath);
      if (entry.isBaseline == shouldBeBaseline &&
          entry.imagePath == imagePath) {
        return entry;
      }

      return ScanHistoryEntry(
        id: entry.id,
        timestamp: entry.timestamp,
        imagePath: imagePath,
        procedureId: entry.procedureId,
        scanType: entry.resolvedScanType,
        peptideId: entry.peptideId,
        estimatedSkinAge: entry.estimatedSkinAge,
        metrics: Map<String, double>.from(entry.metrics),
        procedure: entry.procedure,
        productName: entry.productName,
        poseTemplate: entry.poseTemplate,
        focusArea: entry.focusArea,
        customDescription: entry.customDescription,
        lightingConfidence: entry.lightingConfidence,
        preferredReference: entry.preferredReference,
        isBaseline: shouldBeBaseline,
        makeupPresent: entry.makeupPresent,
        distanceEstimate: entry.distanceEstimate,
        headTiltAngle: entry.headTiltAngle,
        expressionConfidence: entry.expressionConfidence,
      );
    }).toList();
  }

  static String? _prunedScanImagePath(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return imagePath;
    final clean = imagePath.trimLeft();
    if (clean.startsWith('data:image') || (kIsWeb && clean.length > 2048)) {
      return null;
    }
    return imagePath;
  }

  static int _inlineImageCount(List<ScanHistoryEntry> entries) {
    return entries
        .where(
          (entry) =>
              (entry.imagePath ?? '').trimLeft().startsWith('data:image'),
        )
        .length;
  }

  static bool _scanListsEquivalent(
    List<ScanHistoryEntry> a,
    List<ScanHistoryEntry> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (!a[index].isEquivalentTo(b[index])) {
        return false;
      }
    }
    return true;
  }

  static Future<void> _saveScanEntries(List<ScanHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    var entriesToSave = _normalizeScanHistory(entries);
    var encoded = jsonEncode(entriesToSave.map((e) => e.toJson()).toList());
    final trimmedScans = entries.length - entriesToSave.length;
    final trimmedImages =
        _inlineImageCount(entries) - _inlineImageCount(entriesToSave);
    if (trimmedScans > 0 ||
        trimmedImages > 0 ||
        encoded.length > scanHistoryWarningBytes) {
      await prefs.setString(
        scanHistoryStorageWarningKey,
        'Scan storage is getting full, so older scan photos were trimmed while keeping your recent metrics and timeline.',
      );
    }

    try {
      final saved = await prefs.setString(scanHistoryKey, encoded);
      if (!saved) {
        throw StateError('SharedPreferences rejected scan history write');
      }
    } catch (e) {
      entriesToSave = _normalizeScanHistoryForStorage(
        entries,
        maxScans: minStoredScansOnQuotaRetry,
        keepImageCount: 0,
      );
      encoded = jsonEncode(entriesToSave.map((e) => e.toJson()).toList());
      await prefs.setString(
        scanHistoryStorageWarningKey,
        'Scan storage was almost full, so older photos were removed. Your latest scan metrics were saved safely.',
      );
      final saved = await prefs.setString(scanHistoryKey, encoded);
      if (!saved) rethrow;
    }
    await prefs.reload();
  }

  /// Merges [extraMetrics] into the metrics map of the scan identified by
  /// [scanId]. If the scan is not found this is a no-op. Used to attach
  /// body-composition measurements (weight, body-fat %, waist, etc.) to a
  /// scan entry that was created by the camera (which only produces skin
  /// metrics).
  static Future<void> patchScanMetrics(
    String scanId,
    Map<String, double> extraMetrics,
  ) async {
    if (scanId.isEmpty || extraMetrics.isEmpty) return;
    final history = await getScanEntries();
    final idx = history.indexWhere((e) => e.id == scanId);
    if (idx < 0) return;
    final old = history[idx];
    final updated = ScanHistoryEntry(
      id: old.id,
      timestamp: old.timestamp,
      procedureId: old.procedureId,
      scanType: old.resolvedScanType,
      peptideId: old.peptideId,
      productName: old.productName,
      imagePath: old.imagePath,
      metrics: {...old.metrics, ...extraMetrics},
      estimatedSkinAge: old.estimatedSkinAge,
      procedure: old.procedure,
      poseTemplate: old.poseTemplate,
      focusArea: old.focusArea,
      customDescription: old.customDescription,
      lightingConfidence: old.lightingConfidence,
      preferredReference: old.preferredReference,
      isBaseline: old.isBaseline,
      makeupPresent: old.makeupPresent,
      distanceEstimate: old.distanceEstimate,
      headTiltAngle: old.headTiltAngle,
      expressionConfidence: old.expressionConfidence,
    );
    history[idx] = updated;
    await _saveScanEntries(history);
    debugPrint(
      '[patchScanMetrics] patched scan $scanId with ${extraMetrics.keys.join(', ')}',
    );
  }

  /// Tags the scan identified by [scanId] with [peptideId] so it belongs
  /// exclusively to that peptide's history. Called after the camera flow
  /// to bind the new scan to the specific peptide that initiated the scan.
  static Future<void> patchScanPeptideId(
    String scanId,
    String peptideId,
  ) async {
    if (scanId.isEmpty || peptideId.isEmpty) return;
    final history = await getScanEntries();
    final idx = history.indexWhere((e) => e.id == scanId);
    if (idx < 0) return;
    final old = history[idx];
    final updated = ScanHistoryEntry(
      id: old.id,
      timestamp: old.timestamp,
      procedureId: old.procedureId,
      scanType: old.resolvedScanType,
      peptideId: peptideId,
      productName: old.productName,
      imagePath: old.imagePath,
      metrics: Map<String, double>.from(old.metrics),
      estimatedSkinAge: old.estimatedSkinAge,
      procedure: old.procedure,
      poseTemplate: old.poseTemplate,
      focusArea: old.focusArea,
      customDescription: old.customDescription,
      lightingConfidence: old.lightingConfidence,
      preferredReference: old.preferredReference,
      isBaseline: old.isBaseline,
      makeupPresent: old.makeupPresent,
      distanceEstimate: old.distanceEstimate,
      headTiltAngle: old.headTiltAngle,
      expressionConfidence: old.expressionConfidence,
    );
    history[idx] = updated;
    await _saveScanEntries(history);
    debugPrint('[patchScanPeptideId] tagged scan $scanId → peptide $peptideId');
  }

  static Future<Map<String, dynamic>> _getProcedurePhotoComparisonMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(procedurePhotoComparisonKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _saveProcedurePhotoComparisonMap(
    Map<String, dynamic> comparisonMap,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      procedurePhotoComparisonKey,
      jsonEncode(comparisonMap),
    );
    await prefs.reload();
  }

  static Future<void> _updateProcedurePhotoComparison(
    ScanHistoryEntry entry,
    List<ScanHistoryEntry> history,
  ) async {
    final procedureId = entry.procedureId?.trim();
    if (procedureId == null || procedureId.isEmpty) return;

    // Derive baseline and latest purely from the (already-normalized) history.
    // Baseline = OLDEST scan with an image; Latest = NEWEST scan with an image.
    final procedureScans =
        history
            .where(
              (e) =>
                  e.procedureId == procedureId &&
                  (e.imagePath ?? '').trim().isNotEmpty,
            )
            .toList()
          ..sort(
            (a, b) => a.timestamp.compareTo(b.timestamp),
          ); // oldest → newest

    if (procedureScans.isEmpty) {
      debugPrint(
        '[COMPARISON] No scans with images for $procedureId — skipping',
      );
      return;
    }

    final baselineScan = procedureScans.first; // OLDEST = permanent baseline
    final latestScan = procedureScans.last; // NEWEST = latest progress photo

    debugPrint(
      '[COMPARISON] proc=$procedureId | count=${procedureScans.length}'
      ' | baseline=${baselineScan.id} (${baselineScan.timestamp})'
      ' | latest=${latestScan.id} (${latestScan.timestamp})'
      ' | samePhoto=${baselineScan.id == latestScan.id}',
    );

    final comparison = <String, String?>{
      'baselineScanId': baselineScan.id,
      'baselineImagePath': baselineScan.imagePath,
      'latestScanId': latestScan.id,
      'latestImagePath': latestScan.imagePath,
    };

    final comparisonMap = await _getProcedurePhotoComparisonMap();
    final updatedMap = Map<String, dynamic>.from(comparisonMap);
    updatedMap[procedureId] = comparison;
    await _saveProcedurePhotoComparisonMap(updatedMap);
    debugPrint(
      '[COMPARISON] Saved — baseline≠latest: ${baselineScan.id != latestScan.id}',
    );
  }

  static Map<String, String?> _buildProcedurePhotoComparisonFromHistory(
    String procedureId,
    List<ScanHistoryEntry> history,
  ) {
    final procedureScans =
        history
            .where((entry) => entry.procedureId == procedureId)
            .where((entry) => (entry.imagePath ?? '').trim().isNotEmpty)
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (procedureScans.isEmpty) {
      return const {
        'baselineScanId': null,
        'baselineImagePath': null,
        'latestScanId': null,
        'latestImagePath': null,
      };
    }

    ScanHistoryEntry baselineEntry;
    try {
      baselineEntry = procedureScans.firstWhere((entry) => entry.isBaseline);
    } catch (_) {
      baselineEntry = procedureScans.last;
    }

    final latestEntry = procedureScans.first;
    return {
      'baselineScanId': baselineEntry.id,
      'baselineImagePath': baselineEntry.imagePath,
      'latestScanId': latestEntry.id,
      'latestImagePath': latestEntry.imagePath,
    };
  }

  // ── Legacy & Utility Methods for Compatibility ──
  static Future<List<ScanHistoryEntry>> getScanHistory() async {
    return getScanEntries();
  }

  static Future<String> getProcedureType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(procedureTypeKey) ?? '';
  }

  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = name.trim();
    if (clean.isEmpty) {
      await prefs.remove(userNameKey);
      return;
    }
    await prefs.setString(userNameKey, clean);
  }

  static Future<String?> getUserNameOrNull() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(userNameKey)?.trim();
    return stored == null || stored.isEmpty ? null : stored;
  }

  static Future<bool> hasUserName() async {
    final name = await getUserNameOrNull();
    return name != null && name.isNotEmpty;
  }

  static Future<bool> isTourCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(tourCompletedKey) ?? false;
  }

  static Future<void> setTourCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(tourCompletedKey, completed);
  }

  static Future<void> clearUserProfileForRetest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(userNameKey);
    await prefs.remove(userAgeRangeKey);
    await prefs.remove(userSkinConcernsKey);
    await prefs.remove(userClinicKey);
    await prefs.remove(userProfilePictureKey);
    await prefs.remove(skinProfileKey);
    await prefs.setBool(tourCompletedKey, false);
    await prefs.setBool(onboardingCompleteKey, false);
  }

  static Future<void> clearProcedureHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(procedureHistoryKey);
  }

  static Future<List<Map<String, dynamic>>> addProcedureToHistory(
    Map<String, dynamic> procedure,
  ) async {
    final history = await getProcedureEntries();
    history.add(procedure);
    await saveProcedureHistory(history);
    return history;
  }

  static Future<List<Map<String, dynamic>>> updateProcedureInHistory(
    String id,
    Map<String, dynamic> updated,
  ) async {
    final history = await getProcedureEntries();
    final idx = history.indexWhere((e) => e['id'] == id);
    if (idx != -1) {
      history[idx] = updated;
      await saveProcedureHistory(history);
    }
    return history;
  }

  static Future<List<Map<String, dynamic>>> removeProcedureFromHistory(
    String id,
  ) async {
    final history = await getProcedureEntries();
    history.removeWhere((e) => e['id'] == id);
    await saveProcedureHistory(history);
    return history;
  }

  static Future<String?> resolveActiveProcedureId() async {
    return getSelectedProcedureIdOrNull();
  }

  // ── BBL Recovery Assessment (per-procedure manual metrics log) ──────────────
  static String _bblAssessmentKey(String procedureId) =>
      'bbl_assessment_$procedureId';
  static String _bblHistoryKey(String procedureId) =>
      'bbl_history_$procedureId';
  static const int _maxBblHistoryEntries = 30;

  /// Returns the stored BBL recovery assessment for the given procedure, or null.
  static Future<Map<String, double>?> getBBLAssessment(
    String procedureId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_bblAssessmentKey(procedureId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Returns the full history of BBL assessments, ordered oldest→newest.
  /// Each entry: {'timestamp': ISO-8601 string, 'metrics': {key: value}}
  static Future<List<Map<String, dynamic>>> getBBLAssessmentHistory(
    String procedureId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_bblHistoryKey(procedureId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return List<Map<String, dynamic>>.from(
          decoded.map((e) => Map<String, dynamic>.from(e as Map)),
        );
      }
    } catch (_) {}
    return [];
  }

  /// Saves a BBL recovery assessment and appends it to the timestamped history.
  static Future<void> saveBBLAssessment(
    String procedureId,
    Map<String, double> metrics,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    // Persist latest snapshot
    await prefs.setString(_bblAssessmentKey(procedureId), jsonEncode(metrics));
    // Append to history list (capped at _maxBblHistoryEntries)
    final histKey = _bblHistoryKey(procedureId);
    List<Map<String, dynamic>> history = [];
    final rawHist = prefs.getString(histKey);
    if (rawHist != null && rawHist.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHist);
        if (decoded is List) {
          history = List<Map<String, dynamic>>.from(
            decoded.map((e) => Map<String, dynamic>.from(e as Map)),
          );
        }
      } catch (_) {}
    }
    history.add({
      'timestamp': DateTime.now().toIso8601String(),
      'metrics': metrics,
    });
    if (history.length > _maxBblHistoryEntries) {
      history = history.sublist(history.length - _maxBblHistoryEntries);
    }
    await prefs.setString(histKey, jsonEncode(history));
    await prefs.reload();
  }

  AppPrefs._(); // private constructor

  // ── BBL Per-Metric Journaling (notes attached to each recovery metric) ────
  static String _bblMetricNotesKey(String procedureId) =>
      'bbl_metric_notes_$procedureId';

  /// Returns a map of metricKey → ordered list of notes (oldest → newest).
  /// Each note: {'timestamp': ISO-8601 string, 'note': free text}.
  static Future<Map<String, List<Map<String, String>>>> getBBLMetricNotes(
    String procedureId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_bblMetricNotesKey(procedureId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, List<Map<String, String>>>{};
        decoded.forEach((k, v) {
          if (v is List) {
            out[k.toString()] = v
                .whereType<Map>()
                .map(
                  (e) => e.map(
                    (kk, vv) => MapEntry(kk.toString(), vv?.toString() ?? ''),
                  ),
                )
                .toList();
          }
        });
        return out;
      }
    } catch (_) {}
    return {};
  }

  /// Appends a note to the given metric. No-op if both text and photo are
  /// empty/null. [photo] is an optional reference string (file path on native
  /// or a `data:image/...;base64,...` URL on web).
  static Future<void> addBBLMetricNote(
    String procedureId,
    String metricKey,
    String note, {
    String? photo,
  }) async {
    final trimmed = note.trim();
    final hasPhoto = photo != null && photo.isNotEmpty;
    if (trimmed.isEmpty && !hasPhoto) return;
    final current = await getBBLMetricNotes(procedureId);
    final list = List<Map<String, String>>.from(current[metricKey] ?? const []);
    final entry = <String, String>{
      'timestamp': DateTime.now().toIso8601String(),
      'note': trimmed,
    };
    if (hasPhoto) entry['photo'] = photo;
    list.add(entry);
    // Cap per-metric notes at 60 to avoid unbounded growth.
    while (list.length > 60) {
      list.removeAt(0);
    }
    current[metricKey] = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bblMetricNotesKey(procedureId), jsonEncode(current));
    await prefs.reload();
  }

  /// Updates the note text and/or photo for an existing entry (matched by
  /// [timestamp]). Pass [clearPhoto] = true to remove the attached photo.
  /// No-op if the entry cannot be found.
  static Future<void> updateBBLMetricNote(
    String procedureId,
    String metricKey,
    String timestamp, {
    required String note,
    String? photo,
    bool clearPhoto = false,
  }) async {
    final current = await getBBLMetricNotes(procedureId);
    final list = List<Map<String, String>>.from(current[metricKey] ?? const []);
    final idx = list.indexWhere((e) => e['timestamp'] == timestamp);
    if (idx < 0) return;
    final updated = Map<String, String>.from(list[idx]);
    updated['note'] = note.trim();
    if (clearPhoto) {
      updated.remove('photo');
    } else if (photo != null && photo.isNotEmpty) {
      updated['photo'] = photo;
    }
    list[idx] = updated;
    current[metricKey] = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bblMetricNotesKey(procedureId), jsonEncode(current));
    await prefs.reload();
  }

  /// Removes a single note (matched by timestamp) for a given metric.
  static Future<void> deleteBBLMetricNote(
    String procedureId,
    String metricKey,
    String timestamp,
  ) async {
    final current = await getBBLMetricNotes(procedureId);
    final list = List<Map<String, String>>.from(current[metricKey] ?? const []);
    list.removeWhere((e) => e['timestamp'] == timestamp);
    current[metricKey] = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bblMetricNotesKey(procedureId), jsonEncode(current));
    await prefs.reload();
  }
}
