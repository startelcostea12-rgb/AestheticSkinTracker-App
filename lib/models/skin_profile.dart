import 'package:json_annotation/json_annotation.dart';

part 'skin_profile.g.dart';

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum SkinType { dry, oily, combination, normal, sensitive }

@JsonEnum(fieldRename: FieldRename.screamingSnake)
enum SensitivityLevel { low, moderate, high, veryHigh }

@JsonSerializable(explicitToJson: true)
class SkinProcedureHistoryEntry {
  final String procedureName;
  final DateTime? date;
  final String outcome;

  const SkinProcedureHistoryEntry({
    required this.procedureName,
    this.date,
    this.outcome = '',
  });

  factory SkinProcedureHistoryEntry.fromJson(Map<String, dynamic> json) =>
      _$SkinProcedureHistoryEntryFromJson(json);

  Map<String, dynamic> toJson() => _$SkinProcedureHistoryEntryToJson(this);

  SkinProcedureHistoryEntry copyWith({
    String? procedureName,
    DateTime? date,
    bool clearDate = false,
    String? outcome,
  }) {
    return SkinProcedureHistoryEntry(
      procedureName: procedureName ?? this.procedureName,
      date: clearDate ? null : date ?? this.date,
      outcome: outcome ?? this.outcome,
    );
  }
}

@JsonSerializable(explicitToJson: true)
class SkinProfile {
  final SkinType skinType;
  final SensitivityLevel sensitivityLevel;
  final List<String> mainConcerns;
  final Map<String, List<String>> currentRoutine;
  final String productPreference;
  final List<String> favoriteIngredients;
  final List<String> ingredientsToAvoid;
  final List<SkinProcedureHistoryEntry> pastProcedures;
  final String location;
  final String climate;
  final String humidity;
  final List<String> goals;
  final String notes;
  final DateTime? updatedAt;

  const SkinProfile({
    this.skinType = SkinType.normal,
    this.sensitivityLevel = SensitivityLevel.moderate,
    this.mainConcerns = const [],
    this.currentRoutine = const {},
    this.productPreference = '',
    this.favoriteIngredients = const [],
    this.ingredientsToAvoid = const [],
    this.pastProcedures = const [],
    this.location = '',
    this.climate = '',
    this.humidity = '',
    this.goals = const [],
    this.notes = '',
    this.updatedAt,
  });

  factory SkinProfile.fromJson(Map<String, dynamic> json) =>
      _$SkinProfileFromJson(json);

  Map<String, dynamic> toJson() => _$SkinProfileToJson(this);

  SkinProfile copyWith({
    SkinType? skinType,
    SensitivityLevel? sensitivityLevel,
    List<String>? mainConcerns,
    Map<String, List<String>>? currentRoutine,
    String? productPreference,
    List<String>? favoriteIngredients,
    List<String>? ingredientsToAvoid,
    List<SkinProcedureHistoryEntry>? pastProcedures,
    String? location,
    String? climate,
    String? humidity,
    List<String>? goals,
    String? notes,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return SkinProfile(
      skinType: skinType ?? this.skinType,
      sensitivityLevel: sensitivityLevel ?? this.sensitivityLevel,
      mainConcerns: mainConcerns ?? this.mainConcerns,
      currentRoutine: currentRoutine ?? this.currentRoutine,
      productPreference: productPreference ?? this.productPreference,
      favoriteIngredients: favoriteIngredients ?? this.favoriteIngredients,
      ingredientsToAvoid: ingredientsToAvoid ?? this.ingredientsToAvoid,
      pastProcedures: pastProcedures ?? this.pastProcedures,
      location: location ?? this.location,
      climate: climate ?? this.climate,
      humidity: humidity ?? this.humidity,
      goals: goals ?? this.goals,
      notes: notes ?? this.notes,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }
}
