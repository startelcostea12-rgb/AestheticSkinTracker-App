import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'procedure_log.g.dart';

@HiveType(
  typeId: 5,
) // Use next available typeId - confirm with existing models if possible
class ProcedureLog extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String procedureType;

  @HiveField(2)
  DateTime dateTime;

  @HiveField(3)
  String? notes;

  @HiveField(4)
  List<String> photoPaths;

  @HiveField(5)
  int? intensity;

  @HiveField(6)
  String? settings;

  @HiveField(7)
  List<String> productsUsed;

  @HiveField(8)
  int? reactionScore;

  @HiveField(9)
  String? aiFeedback;

  @HiveField(10)
  DateTime createdAt;

  @HiveField(11)
  String? category;

  @HiveField(12)
  String? expectedDuration;

  @HiveField(13)
  DateTime? nextReminderDate;

  @HiveField(14)
  bool reminderEnabled;

  /// Labels (e.g. "Before", "After", "Progress") aligned 1:1 with
  /// [photoPaths] by index so each photo keeps its role for this log only.
  @HiveField(15)
  List<String> photoLabels;

  ProcedureLog({
    String? id,
    required this.procedureType,
    required this.dateTime,
    this.notes,
    List<String> photoPaths = const [],
    this.intensity,
    this.settings,
    this.productsUsed = const [],
    this.reactionScore,
    this.aiFeedback,
    DateTime? createdAt,
    this.category,
    this.expectedDuration,
    this.nextReminderDate,
    bool? reminderEnabled,
    List<String> photoLabels = const [],
  }) : id = id ?? const Uuid().v4(),
       // Copy incoming lists so different logs never share the same
       // backing list instance (prevents cross-contamination of photos).
       photoPaths = List<String>.from(photoPaths),
       photoLabels = List<String>.from(photoLabels),
       createdAt = createdAt ?? DateTime.now(),
       reminderEnabled =
           reminderEnabled ?? _isInjectableProcedureType(procedureType);

  bool get isInjectable => _isInjectableProcedureType(procedureType);

  /// Returns this log's photos paired with their label (Before/After/Progress).
  /// Falls back to a generic "Photo" label when a label is missing so older
  /// logs saved before labels existed still render correctly.
  List<({String label, String path})> get labeledPhotos {
    return [
      for (var i = 0; i < photoPaths.length; i++)
        (
          label: i < photoLabels.length && photoLabels[i].trim().isNotEmpty
              ? photoLabels[i]
              : 'Photo',
          path: photoPaths[i],
        ),
    ];
  }

  /// First photo path matching [label] (case-insensitive), or null.
  String? photoForLabel(String label) {
    final target = label.trim().toLowerCase();
    for (final photo in labeledPhotos) {
      if (photo.label.trim().toLowerCase() == target) return photo.path;
    }
    return null;
  }

  ProcedureLog copyWith({
    String? id,
    String? procedureType,
    DateTime? dateTime,
    String? notes,
    List<String>? photoPaths,
    int? intensity,
    String? settings,
    List<String>? productsUsed,
    int? reactionScore,
    String? aiFeedback,
    DateTime? createdAt,
    String? category,
    String? expectedDuration,
    DateTime? nextReminderDate,
    bool? reminderEnabled,
    List<String>? photoLabels,
  }) {
    return ProcedureLog(
      id: id ?? this.id,
      procedureType: procedureType ?? this.procedureType,
      dateTime: dateTime ?? this.dateTime,
      notes: notes ?? this.notes,
      photoPaths: photoPaths ?? this.photoPaths,
      intensity: intensity ?? this.intensity,
      settings: settings ?? this.settings,
      productsUsed: productsUsed ?? this.productsUsed,
      reactionScore: reactionScore ?? this.reactionScore,
      aiFeedback: aiFeedback ?? this.aiFeedback,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      expectedDuration: expectedDuration ?? this.expectedDuration,
      nextReminderDate: nextReminderDate ?? this.nextReminderDate,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      photoLabels: photoLabels ?? this.photoLabels,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'procedureType': procedureType,
    'dateTime': dateTime.toIso8601String(),
    'notes': notes,
    'photoPaths': photoPaths,
    'intensity': intensity,
    'settings': settings,
    'productsUsed': productsUsed,
    'reactionScore': reactionScore,
    'aiFeedback': aiFeedback,
    'createdAt': createdAt.toIso8601String(),
    'category': category,
    'expectedDuration': expectedDuration,
    'nextReminderDate': nextReminderDate?.toIso8601String(),
    'reminderEnabled': reminderEnabled,
    'photoLabels': photoLabels,
  };

  factory ProcedureLog.fromJson(Map<String, dynamic> json) {
    final procedureType = json['procedureType']?.toString() ?? '';
    return ProcedureLog(
      id: json['id']?.toString(),
      procedureType: procedureType,
      dateTime: _parseDateTime(json['dateTime']) ?? DateTime.now(),
      notes: json['notes']?.toString(),
      photoPaths: _stringListFromJson(json['photoPaths']),
      intensity: _intFromJson(json['intensity']),
      settings: json['settings']?.toString(),
      productsUsed: _stringListFromJson(json['productsUsed']),
      reactionScore: _intFromJson(json['reactionScore']),
      aiFeedback: json['aiFeedback']?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
      category: json['category']?.toString(),
      expectedDuration: json['expectedDuration']?.toString(),
      nextReminderDate: _parseDateTime(json['nextReminderDate']),
      reminderEnabled: json['reminderEnabled'] is bool
          ? json['reminderEnabled'] as bool
          : _isInjectableProcedureType(procedureType),
      photoLabels: _stringListFromJson(json['photoLabels']),
    );
  }

  static List<String> getCommonProcedures() {
    return [
      "RF Microneedling",
      "SkinPen Microneedling",
      "GHK-Cu Serum Application",
      "Chemical Peel (TCA)",
      "LED Light Therapy",
      "At-Home Dermaplaning",
      "Custom Procedure",
    ];
  }

  static bool _isInjectableProcedureType(String procedureType) {
    final lower = procedureType.toLowerCase();
    return lower.contains("botox") ||
        lower.contains("filler") ||
        lower.contains("dysport") ||
        lower.contains("xeomin");
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }
    return null;
  }

  static int? _intFromJson(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _stringListFromJson(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }
}
