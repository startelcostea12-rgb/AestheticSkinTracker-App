// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skin_profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SkinProcedureHistoryEntry _$SkinProcedureHistoryEntryFromJson(
  Map<String, dynamic> json,
) => SkinProcedureHistoryEntry(
  procedureName: json['procedureName'] as String,
  date: json['date'] == null ? null : DateTime.parse(json['date'] as String),
  outcome: json['outcome'] as String? ?? '',
);

Map<String, dynamic> _$SkinProcedureHistoryEntryToJson(
  SkinProcedureHistoryEntry instance,
) => <String, dynamic>{
  'procedureName': instance.procedureName,
  'date': instance.date?.toIso8601String(),
  'outcome': instance.outcome,
};

SkinProfile _$SkinProfileFromJson(Map<String, dynamic> json) => SkinProfile(
  skinType:
      $enumDecodeNullable(_$SkinTypeEnumMap, json['skinType']) ??
      SkinType.normal,
  sensitivityLevel:
      $enumDecodeNullable(
        _$SensitivityLevelEnumMap,
        json['sensitivityLevel'],
      ) ??
      SensitivityLevel.moderate,
  mainConcerns:
      (json['mainConcerns'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  currentRoutine:
      (json['currentRoutine'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
      ) ??
      const {},
  productPreference: json['productPreference'] as String? ?? 'mixed',
  favoriteIngredients:
      (json['favoriteIngredients'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  ingredientsToAvoid:
      (json['ingredientsToAvoid'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  pastProcedures:
      (json['pastProcedures'] as List<dynamic>?)
          ?.map(
            (e) =>
                SkinProcedureHistoryEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const [],
  location: json['location'] as String? ?? '',
  climate: json['climate'] as String? ?? '',
  humidity: json['humidity'] as String? ?? '',
  goals:
      (json['goals'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  notes: json['notes'] as String? ?? '',
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$SkinProfileToJson(SkinProfile instance) =>
    <String, dynamic>{
      'skinType': _$SkinTypeEnumMap[instance.skinType]!,
      'sensitivityLevel': _$SensitivityLevelEnumMap[instance.sensitivityLevel]!,
      'mainConcerns': instance.mainConcerns,
      'currentRoutine': instance.currentRoutine,
      'productPreference': instance.productPreference,
      'favoriteIngredients': instance.favoriteIngredients,
      'ingredientsToAvoid': instance.ingredientsToAvoid,
      'pastProcedures': instance.pastProcedures.map((e) => e.toJson()).toList(),
      'location': instance.location,
      'climate': instance.climate,
      'humidity': instance.humidity,
      'goals': instance.goals,
      'notes': instance.notes,
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };

const _$SkinTypeEnumMap = {
  SkinType.dry: 'DRY',
  SkinType.oily: 'OILY',
  SkinType.combination: 'COMBINATION',
  SkinType.normal: 'NORMAL',
  SkinType.sensitive: 'SENSITIVE',
};

const _$SensitivityLevelEnumMap = {
  SensitivityLevel.low: 'LOW',
  SensitivityLevel.moderate: 'MODERATE',
  SensitivityLevel.high: 'HIGH',
  SensitivityLevel.veryHigh: 'VERY_HIGH',
};
