import 'logged_product.dart';

/// A unified procedure record for professional treatments and at-home actions.
///
/// This model intentionally stores product references and optional snapshots.
/// In HIPAA-scoped or white-label deployments, prefer product IDs plus an
/// encrypted audit trail over duplicated free-text notes.
class ProcedureRecord {
  final String id;
  final ProcedureType type;
  final ProcedureSetting setting;
  final DateTime date;
  final String providerName;
  final String locationName;
  final List<LoggedProduct> appliedProducts;
  final List<String> appliedProductIds;
  final List<String> appliedPeptides;
  final double? depthMm;
  final int? passes;
  final String deviceName;
  final String treatmentArea;
  final List<String> healingPhotoPaths;
  final List<String> scanIds;
  final String notes;
  final ProcedureRecoveryStatus recoveryStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProcedureRecord({
    required this.id,
    this.type = ProcedureType.other,
    this.setting = ProcedureSetting.professional,
    required this.date,
    this.providerName = '',
    this.locationName = '',
    this.appliedProducts = const [],
    this.appliedProductIds = const [],
    this.appliedPeptides = const [],
    this.depthMm,
    this.passes,
    this.deviceName = '',
    this.treatmentArea = '',
    this.healingPhotoPaths = const [],
    this.scanIds = const [],
    this.notes = '',
    this.recoveryStatus = ProcedureRecoveryStatus.notStarted,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isAtHome => setting == ProcedureSetting.atHome;
  bool get isProfessional => setting == ProcedureSetting.professional;
  bool get isMicroneedling =>
      type == ProcedureType.skinPen ||
      type == ProcedureType.rfMicroneedling ||
      type == ProcedureType.atHomeMicroneedling;

  factory ProcedureRecord.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ProcedureRecord(
      id: _readString(json['id']),
      type: ProcedureTypeX.fromJson(json['type']),
      setting: ProcedureSettingX.fromJson(json['setting']),
      date: _readDate(json['date']) ?? now,
      providerName: _readString(json['providerName']),
      locationName: _readString(json['locationName']),
      appliedProducts: _readMapList(
        json['appliedProducts'],
      ).map(LoggedProduct.fromJson).toList(growable: false),
      appliedProductIds: _readStringList(json['appliedProductIds']),
      appliedPeptides: _readStringList(json['appliedPeptides']),
      depthMm: _readDouble(json['depthMm']),
      passes: _readInt(json['passes']),
      deviceName: _readString(json['deviceName']),
      treatmentArea: _readString(json['treatmentArea']),
      healingPhotoPaths: _readStringList(json['healingPhotoPaths']),
      scanIds: _readStringList(json['scanIds']),
      notes: _readString(json['notes']),
      recoveryStatus: ProcedureRecoveryStatusX.fromJson(json['recoveryStatus']),
      createdAt: _readDate(json['createdAt']) ?? now,
      updatedAt: _readDate(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.jsonValue,
    'setting': setting.jsonValue,
    'date': date.toIso8601String(),
    'providerName': providerName,
    'locationName': locationName,
    'appliedProducts': appliedProducts.map((item) => item.toJson()).toList(),
    'appliedProductIds': appliedProductIds,
    'appliedPeptides': appliedPeptides,
    'depthMm': depthMm,
    'passes': passes,
    'deviceName': deviceName,
    'treatmentArea': treatmentArea,
    'healingPhotoPaths': healingPhotoPaths,
    'scanIds': scanIds,
    'notes': notes,
    'recoveryStatus': recoveryStatus.jsonValue,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  ProcedureRecord copyWith({
    String? id,
    ProcedureType? type,
    ProcedureSetting? setting,
    DateTime? date,
    String? providerName,
    String? locationName,
    List<LoggedProduct>? appliedProducts,
    List<String>? appliedProductIds,
    List<String>? appliedPeptides,
    double? depthMm,
    bool clearDepthMm = false,
    int? passes,
    bool clearPasses = false,
    String? deviceName,
    String? treatmentArea,
    List<String>? healingPhotoPaths,
    List<String>? scanIds,
    String? notes,
    ProcedureRecoveryStatus? recoveryStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProcedureRecord(
      id: id ?? this.id,
      type: type ?? this.type,
      setting: setting ?? this.setting,
      date: date ?? this.date,
      providerName: providerName ?? this.providerName,
      locationName: locationName ?? this.locationName,
      appliedProducts: appliedProducts ?? this.appliedProducts,
      appliedProductIds: appliedProductIds ?? this.appliedProductIds,
      appliedPeptides: appliedPeptides ?? this.appliedPeptides,
      depthMm: clearDepthMm ? null : depthMm ?? this.depthMm,
      passes: clearPasses ? null : passes ?? this.passes,
      deviceName: deviceName ?? this.deviceName,
      treatmentArea: treatmentArea ?? this.treatmentArea,
      healingPhotoPaths: healingPhotoPaths ?? this.healingPhotoPaths,
      scanIds: scanIds ?? this.scanIds,
      notes: notes ?? this.notes,
      recoveryStatus: recoveryStatus ?? this.recoveryStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum ProcedureType {
  skinPen,
  rfMicroneedling,
  atHomeMicroneedling,
  halo,
  bbl,
  ipl,
  laserResurfacing,
  chemicalPeel,
  hydraFacial,
  ledLightTherapy,
  guaSha,
  facial,
  injectable,
  other,
}

extension ProcedureTypeX on ProcedureType {
  String get jsonValue => name;

  static ProcedureType fromJson(Object? value) =>
      _enumFromName(ProcedureType.values, value, ProcedureType.other);
}

enum ProcedureSetting { professional, atHome }

extension ProcedureSettingX on ProcedureSetting {
  String get jsonValue => name;

  static ProcedureSetting fromJson(Object? value) => _enumFromName(
    ProcedureSetting.values,
    value,
    ProcedureSetting.professional,
  );
}

enum ProcedureRecoveryStatus {
  notStarted,
  healing,
  stable,
  completed,
  paused,
  needsProviderReview,
}

extension ProcedureRecoveryStatusX on ProcedureRecoveryStatus {
  String get jsonValue => name;

  static ProcedureRecoveryStatus fromJson(Object? value) => _enumFromName(
    ProcedureRecoveryStatus.values,
    value,
    ProcedureRecoveryStatus.notStarted,
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

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
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

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! Iterable) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
