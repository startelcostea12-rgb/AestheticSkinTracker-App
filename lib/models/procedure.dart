import 'dart:typed_data';
import 'journal_entry.dart'; // Shared rich JournalEntry model

const Set<String> _cosmeticProcedureTypeNames = {
  'Botox / Dysport / Xeomin',
  'Dermal Fillers',
  'Lip Augmentation',
  'Thread Lift',
  'BBL',
  'Liposuction',
  'Tummy Tuck',
  'Arm Contouring',
  'Thigh Lift',
  'Hair Transplant',
  'Rhinoplasty',
  'Blepharoplasty',
  'Facelift',
  'Neck Lift',
  'Brow Lift',
  'Chin / Jawline Contouring',
  'Buccal Fat Removal',
};

const Set<String> _multiSessionProcedureTypeNames = {
  'Botox / Dysport / Xeomin',
  'Dermal Fillers',
  'Lip Augmentation',
  'Thread Lift',
  'Microneedling',
  'RF Microneedling',
  'Halo Laser',
  'Fractional Laser',
  'CO2 Laser Resurfacing',
  'IPL',
  'Chemical Peel',
  'Morpheus8',
};

const String customProcedureDisplayName = 'Custom Procedure';

const Set<String> _bodyCameraGuideProcedureTypeNames = {
  'BBL',
  'Liposuction',
  'Tummy Tuck',
  'Arm Contouring',
  'Thigh Lift',
};

const Set<String> _facialCameraGuideProcedureTypeNames = {
  'Rhinoplasty',
  'Blepharoplasty',
  'Facelift',
  'Neck Lift',
  'Brow Lift',
  'Chin / Jawline Contouring',
  'Buccal Fat Removal',
  'Botox / Dysport / Xeomin',
  'Dermal Fillers',
  'Lip Augmentation',
  'Thread Lift',
};

const List<String> _bodyCameraGuideKeywords = [
  'body',
  'bbl',
  'butt',
  'glute',
  'abdomen',
  'stomach',
  'waist',
  'flank',
  'thigh',
  'arm',
  'hip',
  'lipo',
  'liposuction',
  'tummy',
  'abdominoplasty',
  'brachioplasty',
  'arm contouring',
  'arm lift',
  'thigh lift',
];

const List<String> _facialCameraGuideKeywords = [
  'face',
  'facial',
  'nose',
  'rhinoplasty',
  'eyelid',
  'bleph',
  'facelift',
  'neck lift',
  'brow lift',
  'jawline',
  'chin',
  'buccal',
  'lip',
  'filler',
  'botox',
  'dysport',
  'xeomin',
  'thread lift',
];

const Map<String, List<String>> _procedureTypeAliases = {
  'Botox / Dysport / Xeomin': ['botox', 'dysport', 'xeomin', 'neuromodulator'],
  'Dermal Fillers': ['dermal filler', 'fillers', 'filler'],
  'Lip Augmentation': [
    'lip augmentation',
    'lip filler',
    'lip fillers',
    'lip flip',
  ],
  'Thread Lift': ['thread lift', 'pdo thread'],
  'BBL': [
    'bbl',
    'brazilian butt lift',
    'brazilian butt-lift',
    'butt lift',
    'gluteal fat grafting',
    'fat transfer butt',
  ],
  'Liposuction': ['liposuction', 'lipo', 'body contouring liposuction'],
  'Tummy Tuck': ['tummy tuck', 'abdominoplasty', 'mini tummy tuck'],
  'Arm Contouring': ['arm contouring', 'brachioplasty', 'arm lift'],
  'Thigh Lift': ['thigh lift', 'inner thigh lift', 'outer thigh lift'],
  'Hair Transplant': [
    'hair transplant',
    'hair restoration',
    'fue',
    'fut',
    'follicular unit extraction',
    'follicular unit transplantation',
    'hair graft',
  ],
  'Rhinoplasty': ['rhinoplasty', 'nose job', 'nose surgery'],
  'Blepharoplasty': [
    'blepharoplasty',
    'eyelid surgery',
    'upper bleph',
    'lower bleph',
  ],
  'Facelift': ['facelift', 'face lift', 'rhytidectomy'],
  'Neck Lift': ['neck lift'],
  'Brow Lift': ['brow lift', 'forehead lift'],
  'Chin / Jawline Contouring': [
    'jawline contouring',
    'chin contouring',
    'jaw contouring',
    'chin implant',
  ],
  'Buccal Fat Removal': ['buccal fat removal', 'buccal lipectomy'],
  'Microneedling': ['microneedling', 'skinpen'],
  'RF Microneedling': ['rf microneedling', 'radiofrequency microneedling'],
  'Halo Laser': ['halo laser', 'halo'],
  'Fractional Laser': ['fractional laser', 'fraxel'],
  'CO2 Laser Resurfacing': [
    'co2 laser resurfacing',
    'co2 laser',
    'co2 resurfacing',
  ],
  'IPL': ['ipl', 'intense pulsed light', 'photofacial'],
  'Chemical Peel': [
    'chemical peel',
    'vi peel',
    'glycolic peel',
    'salicylic peel',
  ],
  'Morpheus8': ['morpheus8', 'morpheus 8'],
};

String canonicalProcedureType(String procedureType) {
  final clean = procedureType.trim();
  if (clean.isEmpty) return '';

  for (final entry in _procedureTypeAliases.entries) {
    if (entry.key.toLowerCase() == clean.toLowerCase()) {
      return entry.key;
    }
  }

  final lower = clean.toLowerCase();
  for (final entry in _procedureTypeAliases.entries) {
    for (final alias in entry.value) {
      if (lower == alias || lower.contains(alias)) {
        return entry.key;
      }
    }
  }

  return clean;
}

String inferProcedureCategory(String procedureType) {
  final canonical = canonicalProcedureType(procedureType);
  return _cosmeticProcedureTypeNames.contains(canonical)
      ? 'Cosmetic Procedures'
      : 'Medical Procedures';
}

bool supportsMultipleSessions(String procedureType) {
  final canonical = canonicalProcedureType(procedureType);
  if (canonical.isEmpty) return false;
  return _multiSessionProcedureTypeNames.contains(canonical);
}

bool usesBodyCameraGuide(String procedureType) {
  final trimmed = procedureType.trim();
  if (trimmed.isEmpty) return false;

  final canonical = canonicalProcedureType(trimmed);
  if (_bodyCameraGuideProcedureTypeNames.contains(canonical)) {
    return true;
  }

  final lower = trimmed.toLowerCase();
  return _bodyCameraGuideKeywords.any(lower.contains);
}

enum ProcedureCameraGuideType { facial, body, general }

enum ProcedureBodyRegion { face, body, general }

ProcedureCameraGuideType procedureCameraGuideType(String procedureType) {
  final trimmed = procedureType.trim();
  if (trimmed.isEmpty) return ProcedureCameraGuideType.general;

  final canonical = canonicalProcedureType(trimmed);
  if (_bodyCameraGuideProcedureTypeNames.contains(canonical)) {
    return ProcedureCameraGuideType.body;
  }

  if (_facialCameraGuideProcedureTypeNames.contains(canonical)) {
    return ProcedureCameraGuideType.facial;
  }

  final lower = trimmed.toLowerCase();
  if (_bodyCameraGuideKeywords.any(lower.contains)) {
    return ProcedureCameraGuideType.body;
  }

  if (_facialCameraGuideKeywords.any(lower.contains)) {
    return ProcedureCameraGuideType.facial;
  }

  return ProcedureCameraGuideType.general;
}

ProcedureBodyRegion procedureBodyRegionForType(String procedureType) {
  switch (procedureCameraGuideType(procedureType)) {
    case ProcedureCameraGuideType.facial:
      return ProcedureBodyRegion.face;
    case ProcedureCameraGuideType.body:
      return ProcedureBodyRegion.body;
    case ProcedureCameraGuideType.general:
      return ProcedureBodyRegion.general;
  }
}

String procedureBodyRegionToJson(ProcedureBodyRegion region) {
  switch (region) {
    case ProcedureBodyRegion.face:
      return 'face';
    case ProcedureBodyRegion.body:
      return 'body';
    case ProcedureBodyRegion.general:
      return 'general';
  }
}

ProcedureBodyRegion procedureBodyRegionFromJson(dynamic value, String type) {
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'face':
        return ProcedureBodyRegion.face;
      case 'body':
        return ProcedureBodyRegion.body;
      case 'general':
        return ProcedureBodyRegion.general;
    }
  }
  return procedureBodyRegionForType(type);
}

String? normalizedCustomDescription(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.length <= 140 ? trimmed : trimmed.substring(0, 140).trim();
}

bool isCustomProcedureType(String? procedureType) {
  final trimmed = procedureType?.trim();
  if (trimmed == null || trimmed.isEmpty) return false;
  if (trimmed.toLowerCase() == 'other') return true;
  return !_procedureTypeAliases.keys.any(
    (type) => type.toLowerCase() == trimmed.toLowerCase(),
  );
}

String procedureContextLabel({
  String? procedureType,
  String? customDescription,
  String? focusArea,
}) {
  final description = normalizedCustomDescription(customDescription);
  if (description != null) return description;

  final type = procedureType?.trim();
  if (type != null && type.isNotEmpty && !isCustomProcedureType(type)) {
    return type;
  }

  final isOtherFocus = focusArea?.trim().toLowerCase() == 'other';
  if (isOtherFocus || isCustomProcedureType(type)) {
    final guideType = procedureCameraGuideType(type ?? '');
    return guideType == ProcedureCameraGuideType.body
        ? 'your custom body contouring procedure'
        : 'your custom procedure';
  }

  return type?.isNotEmpty == true ? type! : customProcedureDisplayName;
}

bool usesBodyContouringContext({
  String? procedureType,
  String? customDescription,
  String? focusArea,
}) {
  final type = procedureType?.trim() ?? '';
  if (procedureCameraGuideType(type) == ProcedureCameraGuideType.body) {
    return true;
  }
  final combined = [
    procedureType,
    customDescription,
    focusArea,
  ].whereType<String>().join(' ');
  return procedureCameraGuideType(combined) == ProcedureCameraGuideType.body;
}

String procedureMetricContextType({
  String? procedureType,
  String? customDescription,
  String? focusArea,
}) {
  if (usesBodyContouringContext(
        procedureType: procedureType,
        customDescription: customDescription,
        focusArea: focusArea,
      ) &&
      isCustomProcedureType(procedureType)) {
    return 'Liposuction';
  }
  return procedureType?.trim().isNotEmpty == true
      ? procedureType!.trim()
      : customProcedureDisplayName;
}

class ProcedureTimelineMilestone {
  final String id;
  final String label;
  final String description;
  final DateTime expectedDate;
  final int displayOrder;

  const ProcedureTimelineMilestone({
    required this.id,
    required this.label,
    required this.description,
    required this.expectedDate,
    this.displayOrder = 0,
  });

  factory ProcedureTimelineMilestone.fromJson(Map<String, dynamic> json) {
    return ProcedureTimelineMilestone(
      id:
          json['id'] as String? ??
          'milestone_${DateTime.now().microsecondsSinceEpoch}',
      label: json['label'] as String? ?? 'Milestone',
      description: json['description'] as String? ?? '',
      expectedDate:
          DateTime.tryParse(json['expectedDate'] as String? ?? '') ??
          DateTime.now(),
      displayOrder: json['displayOrder'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'description': description,
    'expectedDate': expectedDate.toIso8601String(),
    'displayOrder': displayOrder,
  };

  ProcedureTimelineMilestone copyWith({
    String? id,
    String? label,
    String? description,
    DateTime? expectedDate,
    int? displayOrder,
  }) {
    return ProcedureTimelineMilestone(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      expectedDate: expectedDate ?? this.expectedDate,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }
}

class Procedure {
  final String id;
  final String type;
  final String category;
  final ProcedureBodyRegion bodyRegion;
  final String provider;
  final DateTime startDate;
  final bool isCompleted;
  final DateTime? completedAt;
  final int numSessions;
  final String? focusArea;
  final String? customDescription;
  final String notes; // kept for backward compatibility
  final List<String> customReminders;
  final List<DateTime> milestoneDates;
  final List<ProcedureTimelineMilestone> timelineMilestones;
  final List<String> taggedPhotos; // kept for mobile backward compatibility
  final String? recoveryPlanId;
  final Uint8List? beforePhotoBytes;
  final Uint8List? afterPhotoBytes;

  /// Optional photo of the surgeon's printed/handwritten recovery plan,
  /// captured directly from the camera or imported from an image file.
  /// Stored as raw image bytes alongside [notes] for fast in-app viewing.
  final Uint8List? surgeonPlanPhotoBytes;

  /// Opt-in next appointment reminder. Null means no reminder is scheduled
  /// and behavior is identical to a procedure with no appointment tracking.
  final DateTime? nextAppointmentDate;

  /// Recurrence interval in months (e.g. 3 for quarterly Botox touch-ups).
  /// Null means the appointment reminder is one-time only.
  final int? appointmentRecurrenceMonths;

  final bool appointmentReminderEnabled;

  // Healing Journey support - uses the shared rich JournalEntry
  final List<JournalEntry> journalEntries;

  Procedure({
    required this.id,
    required this.type,
    this.category = '',
    ProcedureBodyRegion? bodyRegion,
    required this.provider,
    required this.startDate,
    this.isCompleted = false,
    this.completedAt,
    required this.numSessions,
    this.focusArea,
    this.customDescription,
    this.notes = '',
    this.customReminders = const [],
    this.milestoneDates = const [],
    this.timelineMilestones = const [],
    this.taggedPhotos = const [],
    this.recoveryPlanId,
    this.nextAppointmentDate,
    this.appointmentRecurrenceMonths,
    this.appointmentReminderEnabled = true,
    this.beforePhotoBytes,
    this.afterPhotoBytes,
    this.surgeonPlanPhotoBytes,
    this.journalEntries = const [], // default to empty list
  }) : bodyRegion = bodyRegion ?? procedureBodyRegionForType(type);

  factory Procedure.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final savedBodyRegionValue = json['bodyRegion'];
    final inferredBodyRegion = procedureBodyRegionForType(type);

    return Procedure(
      id: json['id'] as String,
      type: type,
      category: (json['category'] as String?)?.trim().isNotEmpty == true
          ? (json['category'] as String).trim()
          : inferProcedureCategory(type),
      bodyRegion: savedBodyRegionValue == null
          ? inferredBodyRegion
          : procedureBodyRegionFromJson(savedBodyRegionValue, type),
      provider: json['provider'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: (json['completedAt'] as String?)?.isNotEmpty == true
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      numSessions: json['numSessions'] as int,
      focusArea: (json['focusArea'] as String?)?.trim().isNotEmpty == true
          ? (json['focusArea'] as String).trim()
          : null,
      customDescription: normalizedCustomDescription(
        json['customDescription'] as String?,
      ),
      notes: json['notes'] as String? ?? '',
      customReminders:
          (json['customReminders'] as List<dynamic>?)?.cast<String>() ?? [],
      milestoneDates:
          (json['milestoneDates'] as List<dynamic>?)
              ?.map((d) => DateTime.parse(d as String))
              .toList() ??
          [],
      timelineMilestones:
          (json['timelineMilestones'] as List<dynamic>?)
              ?.map(
                (e) => ProcedureTimelineMilestone.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
      taggedPhotos:
          (json['taggedPhotos'] as List<dynamic>?)?.cast<String>() ?? [],
        recoveryPlanId: (json['recoveryPlanId'] as String?)?.trim().isNotEmpty == true
          ? (json['recoveryPlanId'] as String).trim()
          : null,
      beforePhotoBytes: json['beforePhotoBytes'] != null
          ? Uint8List.fromList(List<int>.from(json['beforePhotoBytes']))
          : null,
      afterPhotoBytes: json['afterPhotoBytes'] != null
          ? Uint8List.fromList(List<int>.from(json['afterPhotoBytes']))
          : null,
      surgeonPlanPhotoBytes: json['surgeonPlanPhotoBytes'] != null
          ? Uint8List.fromList(List<int>.from(json['surgeonPlanPhotoBytes']))
          : null,
      journalEntries:
          (json['journalEntries'] as List<dynamic>?)
              ?.map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextAppointmentDate: (json['nextAppointmentDate'] as String?)?.isNotEmpty == true
          ? DateTime.tryParse(json['nextAppointmentDate'] as String)
          : null,
      appointmentRecurrenceMonths: (json['appointmentRecurrenceMonths'] as num?)?.toInt(),
      appointmentReminderEnabled: json['appointmentReminderEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'category': category.isEmpty ? inferProcedureCategory(type) : category,
    'bodyRegion': procedureBodyRegionToJson(bodyRegion),
    'provider': provider,
    'startDate': startDate.toIso8601String(),
    'isCompleted': isCompleted,
    'completedAt': completedAt?.toIso8601String(),
    'numSessions': numSessions,
    'focusArea': focusArea,
    'customDescription': customDescription,
    'notes': notes,
    'customReminders': customReminders,
    'milestoneDates': milestoneDates.map((d) => d.toIso8601String()).toList(),
    'timelineMilestones': timelineMilestones.map((e) => e.toJson()).toList(),
    'taggedPhotos': taggedPhotos,
    'recoveryPlanId': recoveryPlanId,
    'beforePhotoBytes': beforePhotoBytes,
    'afterPhotoBytes': afterPhotoBytes,
    'surgeonPlanPhotoBytes': surgeonPlanPhotoBytes,
    'journalEntries': journalEntries.map((e) => e.toJson()).toList(),
    'nextAppointmentDate': nextAppointmentDate?.toIso8601String(),
    'appointmentRecurrenceMonths': appointmentRecurrenceMonths,
    'appointmentReminderEnabled': appointmentReminderEnabled,
  };

  Procedure copyWith({
    String? id,
    String? type,
    String? category,
    ProcedureBodyRegion? bodyRegion,
    String? provider,
    DateTime? startDate,
    bool? isCompleted,
    DateTime? completedAt,
    int? numSessions,
    String? focusArea,
    String? customDescription,
    String? notes,
    List<String>? customReminders,
    List<DateTime>? milestoneDates,
    List<ProcedureTimelineMilestone>? timelineMilestones,
    List<String>? taggedPhotos,
    String? recoveryPlanId,
    bool clearRecoveryPlan = false,
    Uint8List? beforePhotoBytes,
    Uint8List? afterPhotoBytes,
    Uint8List? surgeonPlanPhotoBytes,
    bool clearSurgeonPlanPhoto = false,
    List<JournalEntry>? journalEntries,
    DateTime? nextAppointmentDate,
    bool clearNextAppointment = false,
    int? appointmentRecurrenceMonths,
    bool? appointmentReminderEnabled,
  }) {
    return Procedure(
      id: id ?? this.id,
      type: type ?? this.type,
      category: category ?? this.category,
      bodyRegion: bodyRegion ?? this.bodyRegion,
      provider: provider ?? this.provider,
      startDate: startDate ?? this.startDate,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      numSessions: numSessions ?? this.numSessions,
      focusArea: focusArea ?? this.focusArea,
      customDescription: customDescription ?? this.customDescription,
      notes: notes ?? this.notes,
      customReminders: customReminders ?? this.customReminders,
      milestoneDates: milestoneDates ?? this.milestoneDates,
      timelineMilestones: timelineMilestones ?? this.timelineMilestones,
      taggedPhotos: taggedPhotos ?? this.taggedPhotos,
        recoveryPlanId: clearRecoveryPlan
          ? null
          : (recoveryPlanId ?? this.recoveryPlanId),
      beforePhotoBytes: beforePhotoBytes ?? this.beforePhotoBytes,
      afterPhotoBytes: afterPhotoBytes ?? this.afterPhotoBytes,
      surgeonPlanPhotoBytes: clearSurgeonPlanPhoto
          ? null
          : (surgeonPlanPhotoBytes ?? this.surgeonPlanPhotoBytes),
      journalEntries: journalEntries ?? this.journalEntries,
      nextAppointmentDate: clearNextAppointment
          ? null
          : (nextAppointmentDate ?? this.nextAppointmentDate),
      appointmentRecurrenceMonths: clearNextAppointment
          ? null
          : (appointmentRecurrenceMonths ?? this.appointmentRecurrenceMonths),
      appointmentReminderEnabled:
          appointmentReminderEnabled ?? this.appointmentReminderEnabled,
    );
  }
}
