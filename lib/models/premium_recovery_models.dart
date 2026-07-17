import 'package:flutter/foundation.dart';

import 'procedure.dart';

class RecoveryCoachMessage {
  const RecoveryCoachMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.imageRef,
  });

  final String id;
  final String role;
  final String text;
  final DateTime createdAt;
  final String? imageRef;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'imageRef': imageRef,
  };

  factory RecoveryCoachMessage.fromJson(Map<String, dynamic> json) {
    return RecoveryCoachMessage(
      id: (json['id'] ?? '').toString(),
      role: (json['role'] ?? 'assistant').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      imageRef: (json['imageRef'] ?? '').toString().trim().isEmpty
          ? null
          : (json['imageRef'] ?? '').toString(),
    );
  }
}

class ProgressPhotoInsight {
  const ProgressPhotoInsight({
    required this.id,
    required this.summary,
    required this.highlights,
    required this.createdAt,
    this.procedureType,
    this.productName,
    this.latestScanId,
    this.previousScanId,
  });

  final String id;
  final String summary;
  final List<String> highlights;
  final DateTime createdAt;
  final String? procedureType;
  final String? productName;
  final String? latestScanId;
  final String? previousScanId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'summary': summary,
    'highlights': highlights,
    'createdAt': createdAt.toIso8601String(),
    'procedureType': procedureType,
    'productName': productName,
    'latestScanId': latestScanId,
    'previousScanId': previousScanId,
  };

  factory ProgressPhotoInsight.fromJson(Map<String, dynamic> json) {
    return ProgressPhotoInsight(
      id: (json['id'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      highlights: ((json['highlights'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      procedureType: (json['procedureType'] ?? '').toString().trim().isEmpty
          ? null
          : (json['procedureType'] ?? '').toString(),
      productName: (json['productName'] ?? '').toString().trim().isEmpty
          ? null
          : (json['productName'] ?? '').toString(),
      latestScanId: (json['latestScanId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['latestScanId'] ?? '').toString(),
      previousScanId: (json['previousScanId'] ?? '').toString().trim().isEmpty
          ? null
          : (json['previousScanId'] ?? '').toString(),
    );
  }
}

class CustomRecoveryPlan {
  const CustomRecoveryPlan({
    required this.id,
    required this.title,
    required this.procedureType,
    required this.surgeonNotes,
    required this.startDate,
    required this.timelineMilestones,
    required this.createdAt,
    this.uploadedInstructionImageRef,
  });

  final String id;
  final String title;
  final String procedureType;
  final String surgeonNotes;
  final DateTime startDate;
  final List<ProcedureTimelineMilestone> timelineMilestones;
  final DateTime createdAt;
  final String? uploadedInstructionImageRef;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'procedureType': procedureType,
    'surgeonNotes': surgeonNotes,
    'startDate': startDate.toIso8601String(),
    'timelineMilestones': timelineMilestones.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'uploadedInstructionImageRef': uploadedInstructionImageRef,
  };

  factory CustomRecoveryPlan.fromJson(Map<String, dynamic> json) {
    final timelineRaw = (json['timelineMilestones'] as List?) ?? const [];
    return CustomRecoveryPlan(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Recovery Plan').toString(),
      procedureType: (json['procedureType'] ?? '').toString(),
      surgeonNotes: (json['surgeonNotes'] ?? '').toString(),
      startDate:
          DateTime.tryParse((json['startDate'] ?? '').toString()) ??
          DateTime.now(),
      timelineMilestones: timelineRaw
          .whereType<Map>()
          .map(
            (e) => ProcedureTimelineMilestone.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      uploadedInstructionImageRef:
          (json['uploadedInstructionImageRef'] ?? '').toString().trim().isEmpty
          ? null
          : (json['uploadedInstructionImageRef'] ?? '').toString(),
    );
  }
}

class ScarHealingEntry {
  const ScarHealingEntry({
    required this.id,
    required this.note,
    required this.severity,
    required this.createdAt,
    this.photoRef,
  });

  final String id;
  final String note;
  final double severity;
  final DateTime createdAt;
  final String? photoRef;

  Map<String, dynamic> toJson() => {
    'id': id,
    'note': note,
    'severity': severity,
    'createdAt': createdAt.toIso8601String(),
    'photoRef': photoRef,
  };

  factory ScarHealingEntry.fromJson(Map<String, dynamic> json) {
    return ScarHealingEntry(
      id: (json['id'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      severity: (json['severity'] is num)
          ? (json['severity'] as num).toDouble()
          : 3.0,
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      photoRef: (json['photoRef'] ?? '').toString().trim().isEmpty
          ? null
          : (json['photoRef'] ?? '').toString(),
    );
  }
}

class FutureAppearancePrediction {
  const FutureAppearancePrediction({
    required this.id,
    required this.createdAt,
    required this.procedureType,
    required this.basedOnScanId,
    required this.checkpoints,
    required this.summary,
  });

  final String id;
  final DateTime createdAt;
  final String procedureType;
  final String basedOnScanId;
  final Map<String, String> checkpoints;
  final String summary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'procedureType': procedureType,
    'basedOnScanId': basedOnScanId,
    'checkpoints': checkpoints,
    'summary': summary,
  };

  factory FutureAppearancePrediction.fromJson(Map<String, dynamic> json) {
    final checkpointsRaw = (json['checkpoints'] as Map?) ?? const {};
    final parsed = <String, String>{};
    checkpointsRaw.forEach((key, value) {
      parsed[key.toString()] = value.toString();
    });

    return FutureAppearancePrediction(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      procedureType: (json['procedureType'] ?? '').toString(),
      basedOnScanId: (json['basedOnScanId'] ?? '').toString(),
      checkpoints: parsed,
      summary: (json['summary'] ?? '').toString(),
    );
  }
}

class ProfessionalReportRecord {
  const ProfessionalReportRecord({
    required this.id,
    required this.createdAt,
    required this.reportDate,
    required this.title,
    required this.summary,
    required this.procedureName,
    required this.keyMetrics,
    this.pdfBase64,
    this.pdfFileName,
    this.fileRef,
  });

  final String id;
  final DateTime createdAt;
  final DateTime reportDate;
  final String title;
  final String summary;
  final String procedureName;
  final Map<String, dynamic> keyMetrics;
  final String? pdfBase64;
  final String? pdfFileName;
  final String? fileRef;

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'reportDate': reportDate.toIso8601String(),
    'title': title,
    'summary': summary,
    'procedureName': procedureName,
    'keyMetrics': keyMetrics,
    'pdfBase64': pdfBase64,
    'pdfFileName': pdfFileName,
    'fileRef': fileRef,
  };

  factory ProfessionalReportRecord.fromJson(Map<String, dynamic> json) {
    final rawKeyMetrics = json['keyMetrics'];
    final parsedKeyMetrics = rawKeyMetrics is Map
        ? Map<String, dynamic>.from(rawKeyMetrics)
        : <String, dynamic>{};

    return ProfessionalReportRecord(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      reportDate:
          DateTime.tryParse(
            (json['reportDate'] ?? json['createdAt'] ?? '').toString(),
          ) ??
          DateTime.now(),
      title: (json['title'] ?? 'Professional Report').toString(),
      summary: (json['summary'] ?? '').toString(),
      procedureName: (json['procedureName'] ?? '').toString(),
      keyMetrics: parsedKeyMetrics,
      pdfBase64: (json['pdfBase64'] ?? '').toString().trim().isEmpty
          ? null
          : (json['pdfBase64'] ?? '').toString(),
      pdfFileName: (json['pdfFileName'] ?? '').toString().trim().isEmpty
          ? null
          : (json['pdfFileName'] ?? '').toString(),
      fileRef: (json['fileRef'] ?? '').toString().trim().isEmpty
          ? null
          : (json['fileRef'] ?? '').toString(),
    );
  }
}

class SmartReminderPrediction {
  const SmartReminderPrediction({
    required this.id,
    required this.title,
    required this.description,
    required this.dueAt,
    required this.createdAt,
    this.completed = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime dueAt;
  final DateTime createdAt;
  final bool completed;

  SmartReminderPrediction copyWith({bool? completed}) {
    return SmartReminderPrediction(
      id: id,
      title: title,
      description: description,
      dueAt: dueAt,
      createdAt: createdAt,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'dueAt': dueAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'completed': completed,
  };

  factory SmartReminderPrediction.fromJson(Map<String, dynamic> json) {
    return SmartReminderPrediction(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueAt:
          DateTime.tryParse((json['dueAt'] ?? '').toString()) ?? DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      completed: json['completed'] == true,
    );
  }
}

class VoiceJournalEntry {
  const VoiceJournalEntry({
    required this.id,
    required this.transcript,
    required this.createdAt,
    this.procedureType,
  });

  final String id;
  final String transcript;
  final DateTime createdAt;
  final String? procedureType;

  Map<String, dynamic> toJson() => {
    'id': id,
    'transcript': transcript,
    'createdAt': createdAt.toIso8601String(),
    'procedureType': procedureType,
  };

  factory VoiceJournalEntry.fromJson(Map<String, dynamic> json) {
    return VoiceJournalEntry(
      id: (json['id'] ?? '').toString(),
      transcript: (json['transcript'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      procedureType: (json['procedureType'] ?? '').toString().trim().isEmpty
          ? null
          : (json['procedureType'] ?? '').toString(),
    );
  }
}

String premiumEntityId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${UniqueKey().hashCode.abs()}';
}
