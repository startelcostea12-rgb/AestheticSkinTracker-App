import 'dart:convert';

import 'package:hive/hive.dart';

import 'package:aesthetic_skin_tracker/models/product_tracker.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/procedure_log.dart';
import 'package:aesthetic_skin_tracker/models/journal_entry.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/services/skin_history_repository.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';

class AiContextRepository {
  AiContextRepository({SkinHistoryRepository? skinHistoryRepository})
    : _skinHistoryRepository = skinHistoryRepository ?? SkinHistoryRepository.instance;

  final SkinHistoryRepository _skinHistoryRepository;

  Future<Map<String, dynamic>> buildCoachPayload({
    int maxScans = 24,
    int maxProducts = 24,
    int maxProcedureLogs = 24,
    int maxJournalEntries = 80,
    int maxProviderNotes = 40,
  }) async {
    final results = await Future.wait<dynamic>([
      _skinHistoryRepository.getAllScans(),
      AppPrefs.getTrackedProducts(),
      AppPrefs.getProcedureEntries(),
      _loadProcedureLogs(),
      AppPrefs.getUserNameOrNull(),
      AppPrefs.getUserAgeRange(),
      AppPrefs.getUserSkinConcerns(),
      AppPrefs.getSelectedProcedureIdOrNull(),
      AppPrefs.getTrackedProcedure(),
      AppPrefs.getProcedureType(),
      AppPrefs.getActiveProductOrNull(),
      AppPrefs.getString('skincare_journal_entries'),
      AppPrefs.getGeneralJournalEntries(),
      AppPrefs.getScarHealingEntriesRaw(),
      AppPrefs.getString('provider_notes_v1'),
    ]);

    final scans = List<ScanHistoryEntry>.from(results[0] as List<ScanHistoryEntry>);
    final trackedProducts = List<TrackedProduct>.from(results[1] as List<TrackedProduct>);
    final procedureMaps =
        List<Map<String, dynamic>>.from(results[2] as List<Map<String, dynamic>>);
    final procedureLogs = List<ProcedureLog>.from(results[3] as List<ProcedureLog>);
    final userName = (results[4] as String?)?.trim();
    final ageRange = (results[5] as String).trim();
    final skinConcerns = List<String>.from(results[6] as List<String>);
    final selectedProcedureId = (results[7] as String?)?.trim();
    final trackedProcedure = (results[8] as String).trim();
    final procedureType = (results[9] as String).trim();
    final activeProduct = (results[10] as String?)?.trim();
    final skincareJournalRaw = results[11] as String?;
    final generalJournalEntries =
      List<JournalEntry>.from(results[12] as List<JournalEntry>);
    final scarHealingEntries =
      List<Map<String, dynamic>>.from(results[13] as List<Map<String, dynamic>>);
    final providerNotesRaw = results[14] as String?;

    final sortedScans = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final metricScans =
        sortedScans
            .where((scan) => scan.metrics.isNotEmpty)
            .toList(growable: false);

    final baselineScan = metricScans.isEmpty ? null : metricScans.first;
    final latestScan = metricScans.isEmpty ? null : metricScans.last;

    final recentScans =
        metricScans.reversed.take(maxScans).map(_scanToPayload).toList(growable: false);

    final activeTrackedProducts =
        trackedProducts
            .where((product) => product.endDate == null)
            .toList(growable: false)
          ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final recentProcedureLogs =
        List<ProcedureLog>.from(procedureLogs)
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final procedures =
        procedureMaps
            .map((raw) {
              try {
                return Procedure.fromJson(raw);
              } catch (_) {
                return null;
              }
            })
            .whereType<Procedure>()
            .toList(growable: false)
          ..sort((a, b) => b.startDate.compareTo(a.startDate));

    final procedureNotes = _collectProcedureNotes(procedures);
    final procedureJournalEntries = _collectProcedureJournalEntries(procedures);
    final skincareJournalEntries = _parseSkincareJournalEntries(skincareJournalRaw);
    final recentUserJournalNotes = _journalEntriesToPayload(generalJournalEntries);
    final scarHealingContext = _scarHealingContextToPayload(scarHealingEntries);
    final providerNotes = _parseProviderNotes(providerNotesRaw);

    final selectedProcedure =
        procedures.where((procedure) => procedure.id == selectedProcedureId).firstOrNull;

    return {
      'context_generated_at': DateTime.now().toIso8601String(),
      'user_profile': {
        'name': userName,
        'age_range': ageRange.isEmpty ? null : ageRange,
        'skin_concerns': skinConcerns,
      },
      'session_context': {
        'selected_procedure_id':
            selectedProcedureId == null || selectedProcedureId.isEmpty
                ? null
                : selectedProcedureId,
        'selected_procedure_type': selectedProcedure?.type,
        'tracked_procedure': trackedProcedure.isEmpty ? null : trackedProcedure,
        'procedure_type': procedureType.isEmpty ? null : procedureType,
        'active_product':
            activeProduct == null || activeProduct.isEmpty ? null : activeProduct,
      },
      'scan_metrics': {
        'baseline': baselineScan == null ? null : _scanToPayload(baselineScan),
        'latest': latestScan == null ? null : _scanToPayload(latestScan),
        'recent': recentScans,
        'counts': {
          'total_scans': scans.length,
          'metric_scans': metricScans.length,
        },
      },
      'tracked_products': {
        'active':
            activeTrackedProducts
                .take(maxProducts)
                .map(_trackedProductToPayload)
                .toList(growable: false),
        'counts': {
          'active': activeTrackedProducts.length,
          'total': trackedProducts.length,
        },
      },
      'procedure_logs': {
        'recent':
            recentProcedureLogs
                .take(maxProcedureLogs)
                .map(_procedureLogToPayload)
                .toList(growable: false),
        'counts': {'total': procedureLogs.length},
      },
      'journal_and_notes': {
        'recent_user_journal_notes':
          recentUserJournalNotes.take(maxJournalEntries).toList(growable: false),
        'procedure_journal_entries':
            procedureJournalEntries.take(maxJournalEntries).toList(growable: false),
        'skincare_journal_entries':
            skincareJournalEntries.take(maxJournalEntries).toList(growable: false),
        'scar_healing_entries':
            scarHealingContext.take(maxJournalEntries).toList(growable: false),
        'procedure_notes': procedureNotes,
        'provider_notes': providerNotes.take(maxProviderNotes).toList(growable: false),
        'counts': {
          'procedure_journal_entries': procedureJournalEntries.length,
          'recent_user_journal_notes': recentUserJournalNotes.length,
          'skincare_journal_entries': skincareJournalEntries.length,
          'scar_healing_entries': scarHealingContext.length,
          'procedure_notes': procedureNotes.length,
          'provider_notes': providerNotes.length,
        },
      },
    };
  }

  Future<List<ProcedureLog>> _loadProcedureLogs() async {
    const boxName = 'procedureLogs';
    try {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box<ProcedureLog>(boxName)
          : await Hive.openBox<ProcedureLog>(boxName);
      return box.values.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _scanToPayload(ScanHistoryEntry scan) {
    final sortedMetrics = Map<String, double>.fromEntries(
      scan.metrics.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return {
      'id': scan.id,
      'timestamp': scan.timestamp.toIso8601String(),
      'procedure_id': scan.procedureId,
      'procedure_type': scan.procedure,
      'scan_type': scan.resolvedScanType,
      'focus_area': scan.focusArea,
      'custom_description': scan.customDescription,
      'is_baseline': scan.isBaseline,
      'parent_baseline_id': scan.parentBaselineId,
      'estimated_skin_age': scan.estimatedSkinAge,
      'metrics': sortedMetrics,
    };
  }

  Map<String, dynamic> _trackedProductToPayload(TrackedProduct product) {
    return {
      'id': product.id,
      'name': product.name,
      'brand': product.brand,
      'key_ingredients': product.keyIngredients,
      'notes': product.notes,
      'rating': product.rating,
      'start_date': product.startDate.toIso8601String(),
      'end_date': product.endDate?.toIso8601String(),
      'active': product.endDate == null,
    };
  }

  Map<String, dynamic> _procedureLogToPayload(ProcedureLog log) {
    return {
      'id': log.id,
      'procedure_type': log.procedureType,
      'category': log.category,
      'date_time': log.dateTime.toIso8601String(),
      'notes': (log.notes ?? '').trim().isEmpty ? null : log.notes,
      'intensity': log.intensity,
      'settings': log.settings,
      'products_used': log.productsUsed,
      'reaction_score': log.reactionScore,
      'ai_feedback': log.aiFeedback,
      'photo_labels': log.photoLabels,
      'photo_count': log.photoPaths.length,
    };
  }

  List<Map<String, dynamic>> _collectProcedureNotes(List<Procedure> procedures) {
    final notes = <Map<String, dynamic>>[];
    for (final procedure in procedures) {
      final note = procedure.notes.trim();
      if (note.isEmpty) continue;
      notes.add({
        'procedure_id': procedure.id,
        'procedure_type': procedure.type,
        'start_date': procedure.startDate.toIso8601String(),
        'note': note,
      });
    }
    return notes;
  }

  List<Map<String, dynamic>> _collectProcedureJournalEntries(
    List<Procedure> procedures,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (final procedure in procedures) {
      for (final entry in procedure.journalEntries) {
        entries.add({
          'procedure_id': procedure.id,
          'procedure_type': procedure.type,
          'date': entry.date.toIso8601String(),
          'title': entry.title,
          'content': entry.content,
          'mood_rating': entry.moodRating,
          'swelling_level': entry.swellingLevel,
          'attached_image_path': entry.attachedImagePath,
        });
      }
    }
    entries.sort((a, b) {
      final aDate = DateTime.tryParse((a['date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = DateTime.tryParse((b['date'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return entries;
  }

  List<Map<String, dynamic>> _scarHealingContextToPayload(
    List<Map<String, dynamic>> entries,
  ) {
    final payload = <Map<String, dynamic>>[];
    for (final raw in entries) {
      final notes = raw['notes'] is List
          ? (raw['notes'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      final latestNote = notes.isNotEmpty ? notes.last : null;
      payload.add({
        'procedure_id': raw['procedureId'],
        'procedure_name': raw['procedureName'],
        'procedure_tag': raw['procedureTag'],
        'date': raw['date'],
        'concern_level': raw['concernLevel'],
        'note_count':
            notes.length +
            ((raw['transcript'] as String?)?.trim().isNotEmpty == true ? 1 : 0),
        'latest_transcript':
            (raw['transcript'] as String?)?.trim().isEmpty == true
            ? null
            : raw['transcript'],
        'latest_note': latestNote == null ? null : latestNote['text'],
        'metrics': raw['metrics'],
      });
    }
    payload.sort((a, b) {
      final left =
          DateTime.tryParse((a['date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          DateTime.tryParse((b['date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return payload;
  }

  List<Map<String, dynamic>> _parseSkincareJournalEntries(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];

      final output = <Map<String, dynamic>>[];
      for (final row in decoded.entries) {
        final productName = row.key.toString();
        final value = row.value;
        if (value is! List) continue;
        for (final item in value) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          output.add({
            'product_name': productName,
            'date': map['date'],
            'title': map['title'],
            'content': map['content'],
            'mood_rating': map['moodRating'],
            'swelling_level': map['swellingLevel'],
            'attached_image_path': map['attachedImagePath'],
          });
        }
      }

      output.sort((a, b) {
        final aDate = DateTime.tryParse((a['date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse((b['date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return output;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _parseProviderNotes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final notes = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        notes.add({
          'id': map['id'],
          'procedure_id': map['procedureId'],
          'date': map['date'],
          'title': map['title'],
          'content': map['content'],
          'created_at': map['createdAt'],
          'updated_at': map['updatedAt'],
        });
      }
      notes.sort((a, b) {
        final aDate = DateTime.tryParse((a['date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse((b['date'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return notes;
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _journalEntriesToPayload(
    List<JournalEntry> entries,
  ) {
    return entries
        .map(
          (entry) => {
            'date': entry.date.toIso8601String(),
            'title': entry.title,
            'content': entry.content,
            'mood_rating': entry.moodRating,
            'swelling_level': entry.swellingLevel,
            'attached_image_path': entry.attachedImagePath,
          },
        )
        .toList(growable: false);
  }
}
