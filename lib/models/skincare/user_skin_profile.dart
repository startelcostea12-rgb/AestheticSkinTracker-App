import 'daily_routine.dart';
import 'logged_product.dart';
import 'procedure_record.dart';
import 'scan_record.dart';

/// The single source of truth for personalization, AI Coach context, routines,
/// progress analysis, and future repository sync.
///
/// Privacy note: this aggregate may contain sensitive wellness data, images,
/// and user-authored notes. For HIPAA or white-label deployments, persist it
/// behind an access-controlled repository, encrypt local caches, and avoid
/// storing direct identifiers in free-text fields.
class UserSkinProfile {
  final String id;
  final String displayName;
  final OnboardingSkinData onboarding;
  final SkinSensitivityLevel sensitivityLevel;
  final List<String> goals;
  final List<String> concerns;
  final List<String> preferences;
  final List<String> ingredientsToAvoid;
  final List<String> favoriteIngredients;
  final List<LoggedProduct> currentProducts;
  final List<ProcedureRecord> procedureHistory;
  final List<ScanRecord> scanHistory;
  final DailyRoutine? activeRoutine;
  final List<DailyRoutine> routineHistory;
  final String aiCoachNotes;
  final Map<String, String> whiteLabelMetadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserSkinProfile({
    required this.id,
    this.displayName = '',
    this.onboarding = const OnboardingSkinData(),
    this.sensitivityLevel = SkinSensitivityLevel.moderate,
    this.goals = const [],
    this.concerns = const [],
    this.preferences = const [],
    this.ingredientsToAvoid = const [],
    this.favoriteIngredients = const [],
    this.currentProducts = const [],
    this.procedureHistory = const [],
    this.scanHistory = const [],
    this.activeRoutine,
    this.routineHistory = const [],
    this.aiCoachNotes = '',
    this.whiteLabelMetadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasProcedureHistory => procedureHistory.isNotEmpty;
  bool get hasScanHistory => scanHistory.isNotEmpty;
  bool get isSensitive =>
      sensitivityLevel == SkinSensitivityLevel.high ||
      sensitivityLevel == SkinSensitivityLevel.veryHigh;

  factory UserSkinProfile.empty({required String id, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return UserSkinProfile(id: id, createdAt: timestamp, updatedAt: timestamp);
  }

  factory UserSkinProfile.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return UserSkinProfile(
      id: _readString(json['id']),
      displayName: _readString(json['displayName']),
      onboarding: json['onboarding'] is Map
          ? OnboardingSkinData.fromJson(
              Map<String, dynamic>.from(json['onboarding']),
            )
          : const OnboardingSkinData(),
      sensitivityLevel: SkinSensitivityLevelX.fromJson(
        json['sensitivityLevel'],
      ),
      goals: _readStringList(json['goals']),
      concerns: _readStringList(json['concerns']),
      preferences: _readStringList(json['preferences']),
      ingredientsToAvoid: _readStringList(json['ingredientsToAvoid']),
      favoriteIngredients: _readStringList(json['favoriteIngredients']),
      currentProducts: _readMapList(
        json['currentProducts'],
      ).map(LoggedProduct.fromJson).toList(growable: false),
      procedureHistory: _readMapList(
        json['procedureHistory'],
      ).map(ProcedureRecord.fromJson).toList(growable: false),
      scanHistory: _readMapList(
        json['scanHistory'],
      ).map(ScanRecord.fromJson).toList(growable: false),
      activeRoutine: json['activeRoutine'] is Map
          ? DailyRoutine.fromJson(
              Map<String, dynamic>.from(json['activeRoutine']),
            )
          : null,
      routineHistory: _readMapList(
        json['routineHistory'],
      ).map(DailyRoutine.fromJson).toList(growable: false),
      aiCoachNotes: _readString(json['aiCoachNotes']),
      whiteLabelMetadata: _readStringMap(json['whiteLabelMetadata']),
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'onboarding': onboarding.toJson(),
    'sensitivityLevel': sensitivityLevel.jsonValue,
    'goals': goals,
    'concerns': concerns,
    'preferences': preferences,
    'ingredientsToAvoid': ingredientsToAvoid,
    'favoriteIngredients': favoriteIngredients,
    'currentProducts': currentProducts.map((item) => item.toJson()).toList(),
    'procedureHistory': procedureHistory.map((item) => item.toJson()).toList(),
    'scanHistory': scanHistory.map((item) => item.toJson()).toList(),
    'activeRoutine': activeRoutine?.toJson(),
    'routineHistory': routineHistory.map((item) => item.toJson()).toList(),
    'aiCoachNotes': aiCoachNotes,
    'whiteLabelMetadata': whiteLabelMetadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  UserSkinProfile copyWith({
    String? id,
    String? displayName,
    OnboardingSkinData? onboarding,
    SkinSensitivityLevel? sensitivityLevel,
    List<String>? goals,
    List<String>? concerns,
    List<String>? preferences,
    List<String>? ingredientsToAvoid,
    List<String>? favoriteIngredients,
    List<LoggedProduct>? currentProducts,
    List<ProcedureRecord>? procedureHistory,
    List<ScanRecord>? scanHistory,
    DailyRoutine? activeRoutine,
    bool clearActiveRoutine = false,
    List<DailyRoutine>? routineHistory,
    String? aiCoachNotes,
    Map<String, String>? whiteLabelMetadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserSkinProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      onboarding: onboarding ?? this.onboarding,
      sensitivityLevel: sensitivityLevel ?? this.sensitivityLevel,
      goals: goals ?? this.goals,
      concerns: concerns ?? this.concerns,
      preferences: preferences ?? this.preferences,
      ingredientsToAvoid: ingredientsToAvoid ?? this.ingredientsToAvoid,
      favoriteIngredients: favoriteIngredients ?? this.favoriteIngredients,
      currentProducts: currentProducts ?? this.currentProducts,
      procedureHistory: procedureHistory ?? this.procedureHistory,
      scanHistory: scanHistory ?? this.scanHistory,
      activeRoutine: clearActiveRoutine
          ? null
          : activeRoutine ?? this.activeRoutine,
      routineHistory: routineHistory ?? this.routineHistory,
      aiCoachNotes: aiCoachNotes ?? this.aiCoachNotes,
      whiteLabelMetadata: whiteLabelMetadata ?? this.whiteLabelMetadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class OnboardingSkinData {
  final SkinType skinType;
  final String ageRange;
  final String location;
  final String climate;
  final String humidity;
  final String fitzpatrickType;
  final bool usesPrescriptionProducts;
  final bool pregnantOrNursing;
  final List<String> knownAllergies;
  final List<String> lifestyleFactors;
  final DateTime? completedAt;

  const OnboardingSkinData({
    this.skinType = SkinType.normal,
    this.ageRange = '',
    this.location = '',
    this.climate = '',
    this.humidity = '',
    this.fitzpatrickType = '',
    this.usesPrescriptionProducts = false,
    this.pregnantOrNursing = false,
    this.knownAllergies = const [],
    this.lifestyleFactors = const [],
    this.completedAt,
  });

  factory OnboardingSkinData.fromJson(Map<String, dynamic> json) {
    return OnboardingSkinData(
      skinType: SkinTypeX.fromJson(json['skinType']),
      ageRange: _readString(json['ageRange']),
      location: _readString(json['location']),
      climate: _readString(json['climate']),
      humidity: _readString(json['humidity']),
      fitzpatrickType: _readString(json['fitzpatrickType']),
      usesPrescriptionProducts:
          json['usesPrescriptionProducts'] as bool? ?? false,
      pregnantOrNursing: json['pregnantOrNursing'] as bool? ?? false,
      knownAllergies: _readStringList(json['knownAllergies']),
      lifestyleFactors: _readStringList(json['lifestyleFactors']),
      completedAt: _readDate(json['completedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'skinType': skinType.jsonValue,
    'ageRange': ageRange,
    'location': location,
    'climate': climate,
    'humidity': humidity,
    'fitzpatrickType': fitzpatrickType,
    'usesPrescriptionProducts': usesPrescriptionProducts,
    'pregnantOrNursing': pregnantOrNursing,
    'knownAllergies': knownAllergies,
    'lifestyleFactors': lifestyleFactors,
    'completedAt': completedAt?.toIso8601String(),
  };
}

enum SkinType { dry, oily, combination, normal, sensitive }

extension SkinTypeX on SkinType {
  String get jsonValue => name;

  static SkinType fromJson(Object? value) =>
      _enumFromName(SkinType.values, value, SkinType.normal);
}

enum SkinSensitivityLevel { low, moderate, high, veryHigh }

extension SkinSensitivityLevelX on SkinSensitivityLevel {
  String get jsonValue => name;

  static SkinSensitivityLevel fromJson(Object? value) => _enumFromName(
    SkinSensitivityLevel.values,
    value,
    SkinSensitivityLevel.moderate,
  );
}

T _enumFromName<T extends Enum>(List<T> values, Object? value, T fallback) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return fallback;
  final normalized = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
  for (final candidate in values) {
    if (candidate.name.toLowerCase() == normalized) return candidate;
  }
  return fallback;
}

String _readString(Object? value) => value?.toString().trim() ?? '';

DateTime? _readDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

List<String> _readStringList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

Map<String, String> _readStringMap(Object? value) {
  if (value is! Map) return const {};
  return value.map(
    (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
  );
}
