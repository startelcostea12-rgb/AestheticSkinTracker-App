import 'logged_product.dart';

/// A single action inside a skincare routine.
///
/// Steps can reference a logged product by ID, embed a product snapshot, or be
/// instruction-only for actions such as red light therapy or gua sha.
class RoutineStep {
  final String id;
  final int order;
  final RoutineStepType type;
  final RoutineTimeOfDay timeOfDay;
  final String title;
  final String instructions;
  final String frequency;
  final String? productId;
  final LoggedProduct? productSnapshot;
  final List<String> targetConcerns;
  final bool isActive;
  final bool requiresCalmBarrier;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoutineStep({
    required this.id,
    this.order = 0,
    this.type = RoutineStepType.product,
    this.timeOfDay = RoutineTimeOfDay.morning,
    required this.title,
    this.instructions = '',
    this.frequency = 'daily',
    this.productId,
    this.productSnapshot,
    this.targetConcerns = const [],
    this.isActive = true,
    this.requiresCalmBarrier = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoutineStep.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return RoutineStep(
      id: _readString(json['id']),
      order: _readInt(json['order']) ?? 0,
      type: RoutineStepTypeX.fromJson(json['type']),
      timeOfDay: RoutineTimeOfDayX.fromJson(json['timeOfDay']),
      title: _readString(json['title']),
      instructions: _readString(json['instructions']),
      frequency: _readString(json['frequency']).isEmpty
          ? 'daily'
          : _readString(json['frequency']),
      productId: _readNullableString(json['productId']),
      productSnapshot: json['productSnapshot'] is Map
          ? LoggedProduct.fromJson(
              Map<String, dynamic>.from(json['productSnapshot']),
            )
          : null,
      targetConcerns: _readStringList(json['targetConcerns']),
      isActive: json['isActive'] as bool? ?? true,
      requiresCalmBarrier: json['requiresCalmBarrier'] as bool? ?? false,
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order': order,
    'type': type.jsonValue,
    'timeOfDay': timeOfDay.jsonValue,
    'title': title,
    'instructions': instructions,
    'frequency': frequency,
    'productId': productId,
    'productSnapshot': productSnapshot?.toJson(),
    'targetConcerns': targetConcerns,
    'isActive': isActive,
    'requiresCalmBarrier': requiresCalmBarrier,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  RoutineStep copyWith({
    String? id,
    int? order,
    RoutineStepType? type,
    RoutineTimeOfDay? timeOfDay,
    String? title,
    String? instructions,
    String? frequency,
    String? productId,
    bool clearProductId = false,
    LoggedProduct? productSnapshot,
    bool clearProductSnapshot = false,
    List<String>? targetConcerns,
    bool? isActive,
    bool? requiresCalmBarrier,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RoutineStep(
      id: id ?? this.id,
      order: order ?? this.order,
      type: type ?? this.type,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      title: title ?? this.title,
      instructions: instructions ?? this.instructions,
      frequency: frequency ?? this.frequency,
      productId: clearProductId ? null : productId ?? this.productId,
      productSnapshot: clearProductSnapshot
          ? null
          : productSnapshot ?? this.productSnapshot,
      targetConcerns: targetConcerns ?? this.targetConcerns,
      isActive: isActive ?? this.isActive,
      requiresCalmBarrier: requiresCalmBarrier ?? this.requiresCalmBarrier,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DailyRoutine {
  final String id;
  final DateTime effectiveFrom;
  final List<RoutineStep> morningSteps;
  final List<RoutineStep> eveningSteps;
  final List<RoutineStep> weeklySteps;
  final List<RoutineStep> asNeededSteps;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DailyRoutine({
    required this.id,
    required this.effectiveFrom,
    this.morningSteps = const [],
    this.eveningSteps = const [],
    this.weeklySteps = const [],
    this.asNeededSteps = const [],
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  List<RoutineStep> get allSteps => [
    ...morningSteps,
    ...eveningSteps,
    ...weeklySteps,
    ...asNeededSteps,
  ];

  factory DailyRoutine.empty({required String id, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return DailyRoutine(
      id: id,
      effectiveFrom: timestamp,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  factory DailyRoutine.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return DailyRoutine(
      id: _readString(json['id']),
      effectiveFrom: _readDate(json['effectiveFrom']) ?? now,
      morningSteps: _readStepList(json['morningSteps']),
      eveningSteps: _readStepList(json['eveningSteps']),
      weeklySteps: _readStepList(json['weeklySteps']),
      asNeededSteps: _readStepList(json['asNeededSteps']),
      notes: _readString(json['notes']),
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'effectiveFrom': effectiveFrom.toIso8601String(),
    'morningSteps': morningSteps.map((item) => item.toJson()).toList(),
    'eveningSteps': eveningSteps.map((item) => item.toJson()).toList(),
    'weeklySteps': weeklySteps.map((item) => item.toJson()).toList(),
    'asNeededSteps': asNeededSteps.map((item) => item.toJson()).toList(),
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

enum RoutineTimeOfDay { morning, evening, weekly, asNeeded }

extension RoutineTimeOfDayX on RoutineTimeOfDay {
  String get jsonValue => name;

  static RoutineTimeOfDay fromJson(Object? value) =>
      _enumFromName(RoutineTimeOfDay.values, value, RoutineTimeOfDay.morning);
}

enum RoutineStepType {
  cleanser,
  toner,
  essence,
  serum,
  peptide,
  moisturizer,
  sunscreen,
  device,
  procedurePrep,
  recovery,
  habit,
  product,
  other,
}

extension RoutineStepTypeX on RoutineStepType {
  String get jsonValue => name;

  static RoutineStepType fromJson(Object? value) =>
      _enumFromName(RoutineStepType.values, value, RoutineStepType.product);
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

String? _readNullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

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

List<RoutineStep> _readStepList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((item) => RoutineStep.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}
