import '../models/skincare/skincare_models.dart';

/// Repository contract for the unified skincare intelligence layer.
///
/// Implementations can be local-only, encrypted device storage, Firebase,
/// enterprise white-label storage, or a HIPAA-aware backend. Keep this boundary
/// responsible for access control, audit logging, encryption, conflict
/// resolution, and tenant isolation rather than leaking those concerns into UI
/// or AI prompt code.
abstract class SkincareRepository {
  Future<UserSkinProfile?> getUserSkinProfile(String userId);

  Stream<UserSkinProfile?> watchUserSkinProfile(String userId);

  Future<void> saveUserSkinProfile(UserSkinProfile profile);

  Future<void> deleteUserSkinProfile(String userId);

  Future<List<LoggedProduct>> getLoggedProducts(String userId);

  Future<void> upsertLoggedProduct(String userId, LoggedProduct product);

  Future<void> removeLoggedProduct(String userId, String productId);

  Future<List<ProcedureRecord>> getProcedureHistory(String userId);

  Future<void> upsertProcedureRecord(String userId, ProcedureRecord procedure);

  Future<void> removeProcedureRecord(String userId, String procedureId);

  Future<List<ScanRecord>> getScanHistory(String userId);

  Future<void> upsertScanRecord(String userId, ScanRecord scan);

  Future<void> removeScanRecord(String userId, String scanId);

  Future<DailyRoutine?> getActiveRoutine(String userId);

  Future<void> saveActiveRoutine(String userId, DailyRoutine routine);

  Future<List<DailyRoutine>> getRoutineHistory(String userId);

  Future<void> addRoutineToHistory(String userId, DailyRoutine routine);

  /// Returns the fully hydrated context the AI Coach should use.
  ///
  /// Implementations may redact or minimize fields based on user consent,
  /// jurisdiction, tenant policy, or model-provider requirements.
  Future<UserSkinProfile?> getAiCoachContext(String userId);
}
