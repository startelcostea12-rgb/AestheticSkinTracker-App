import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:before_after/before_after.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../utils/app_prefs.dart';
import '../utils/web_blob_bytes.dart';
import 'scar_ai_analysis_sheet.dart';

// ── Scar-specific metrics ─────────────────────────────────────────────────────
class ScarMetrics {
  final double redness; // 0�10 (10 = very red)
  final double elevation; // 0�10 (10 = very raised)
  final double colorMatch; // 0�10 (10 = perfect match)
  final double texture; // 0�10 (10 = perfectly smooth)
  final double pliability; // 0�10 (10 = very flexible/soft)
  final double itchiness; // 0�10 (10 = severe)
  final double pain; // 0�10 (10 = severe)

  const ScarMetrics({
    this.redness = 7.0, // typical fresh scar
    this.elevation = 4.0, // slightly raised
    this.colorMatch = 2.0, // noticeably different from skin
    this.texture = 2.0, // rough early on
    this.pliability = 2.0, // stiff early on
    this.itchiness = 3.0, // minor itch during healing
    this.pain = 4.0, // moderate early pain
  });

  Map<String, dynamic> toJson() => {
    'redness': redness,
    'elevation': elevation,
    'colorMatch': colorMatch,
    'texture': texture,
    'pliability': pliability,
    'itchiness': itchiness,
    'pain': pain,
  };

  factory ScarMetrics.fromJson(Map<String, dynamic> j) => ScarMetrics(
    redness: (j['redness'] as num?)?.toDouble() ?? 7.0,
    elevation: (j['elevation'] as num?)?.toDouble() ?? 4.0,
    colorMatch: (j['colorMatch'] as num?)?.toDouble() ?? 2.0,
    texture: (j['texture'] as num?)?.toDouble() ?? 2.0,
    pliability: (j['pliability'] as num?)?.toDouble() ?? 2.0,
    itchiness: (j['itchiness'] as num?)?.toDouble() ?? 3.0,
    pain: (j['pain'] as num?)?.toDouble() ?? 4.0,
  );

  /// 0�100: higher = better healing (Scar Maturity Score)
  double get healingScore {
    // All metrics are 1�10. Normalise each to 0�1 then average ? 0�100.
    // Positive metrics (higher = better): colorMatch, texture, pliability.
    // Negative metrics (lower = better): redness, elevation, itchiness, pain.
    final posNorm = [
      (colorMatch - 1.0) / 9.0,
      (texture - 1.0) / 9.0,
      (pliability - 1.0) / 9.0,
    ];
    final negNorm = [
      (10.0 - redness) / 9.0,
      (10.0 - elevation) / 9.0,
      (10.0 - itchiness) / 9.0,
      (10.0 - pain) / 9.0,
    ];
    final avg = ([...posNorm, ...negNorm].reduce((a, b) => a + b)) / 7.0;
    return (avg * 100.0).clamp(0.0, 100.0);
  }

  ScarMetrics copyWith({
    double? redness,
    double? elevation,
    double? colorMatch,
    double? texture,
    double? pliability,
    double? itchiness,
    double? pain,
  }) {
    return ScarMetrics(
      redness: redness ?? this.redness,
      elevation: elevation ?? this.elevation,
      colorMatch: colorMatch ?? this.colorMatch,
      texture: texture ?? this.texture,
      pliability: pliability ?? this.pliability,
      itchiness: itchiness ?? this.itchiness,
      pain: pain ?? this.pain,
    );
  }
}

// -- Journal Note (text or voice, one per entry, list stored on ScarPhotoEntry) -
class ScarJournalNote {
  final String id;
  final DateTime createdAt;
  final String text;
  final bool isVoice;

  const ScarJournalNote({
    required this.id,
    required this.createdAt,
    required this.text,
    this.isVoice = false,
  });

  ScarJournalNote copyWithText(String newText) => ScarJournalNote(
    id: id,
    createdAt: createdAt,
    text: newText,
    isVoice: isVoice,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
    'isVoice': isVoice,
  };

  factory ScarJournalNote.fromJson(Map<String, dynamic> j) => ScarJournalNote(
    id: j['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    text: j['text'] as String? ?? '',
    isVoice: j['isVoice'] as bool? ?? false,
  );
}

class ScarPhotoEntry {
  final String? procedureId; // links to Procedure.id
  final String? procedureName; // denormalized label for display
  final String?
  procedureTag; // optional free-text procedure tag logged at photo time
  final Uint8List? image;
  final DateTime date;
  final int concernLevel;
  final ScarMetrics metrics;
  final Uint8List? audio;
  final String? transcript;
  final List<ScarJournalNote>
  notes; // text + voice journal entries for this photo

  ScarPhotoEntry({
    this.procedureId,
    this.procedureName,
    this.procedureTag,
    this.image,
    required this.date,
    required this.concernLevel,
    ScarMetrics? metrics,
    this.audio,
    this.transcript,
    List<ScarJournalNote>? notes,
  }) : metrics = metrics ?? const ScarMetrics(),
       notes = notes ?? const [];

  ScarPhotoEntry copyWith({
    String? procedureId,
    String? procedureName,
    String? procedureTag,
    Uint8List? image,
    DateTime? date,
    int? concernLevel,
    ScarMetrics? metrics,
    Uint8List? audio,
    String? transcript,
    List<ScarJournalNote>? notes,
  }) {
    return ScarPhotoEntry(
      procedureId: procedureId ?? this.procedureId,
      procedureName: procedureName ?? this.procedureName,
      procedureTag: procedureTag ?? this.procedureTag,
      image: image ?? this.image,
      date: date ?? this.date,
      concernLevel: concernLevel ?? this.concernLevel,
      metrics: metrics ?? this.metrics,
      audio: audio ?? this.audio,
      transcript: transcript ?? this.transcript,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'procedureId': procedureId,
    'procedureName': procedureName,
    'procedureTag': procedureTag,
    'image': image != null ? base64Encode(image!) : null,
    'date': date.toIso8601String(),
    'concernLevel': concernLevel,
    'metrics': metrics.toJson(),
    'audio': audio != null ? base64Encode(audio!) : null,
    'transcript': transcript,
    'notes': notes.map((n) => n.toJson()).toList(),
  };

  factory ScarPhotoEntry.fromJson(Map<String, dynamic> j) {
    Uint8List? img;
    Uint8List? aud;
    try {
      if (j['image'] != null) img = base64Decode(j['image'] as String);
    } catch (_) {}
    try {
      if (j['audio'] != null) aud = base64Decode(j['audio'] as String);
    } catch (_) {}
    final rawNotes = j['notes'];
    final notesList = (rawNotes is List)
        ? rawNotes
              .whereType<Map<String, dynamic>>()
              .map(ScarJournalNote.fromJson)
              .toList()
        : <ScarJournalNote>[];
    return ScarPhotoEntry(
      procedureId: j['procedureId'] as String?,
      procedureName: j['procedureName'] as String?,
      procedureTag: j['procedureTag'] as String?,
      image: img,
      date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      concernLevel: (j['concernLevel'] as num?)?.toInt() ?? 5,
      metrics: j['metrics'] != null
          ? ScarMetrics.fromJson(j['metrics'] as Map<String, dynamic>)
          : const ScarMetrics(),
      audio: aud,
      transcript: j['transcript'] as String?,
      notes: notesList,
    );
  }
}

class _ScarImageFeatures {
  final double
  rednessSignal; // 0�1: erythema strength (combined raw-channel + HSV hue-weighted)
  final double
  textureRoughness; // 0�1: surface irregularity (gradient mean + STD)
  final double
  elevationProxy; // 0�1: raised-profile estimate (center-periph heterogeneity + lum STD)
  final double
  colorVariance; // 0�1: overall colour spread (saturation + lum STD)
  final double saturationLevel; // 0�1: HSV mean saturation across all pixels
  final double heterogeneity; // 0�1: center vs. periphery luminance contrast

  const _ScarImageFeatures({
    required this.rednessSignal,
    required this.textureRoughness,
    required this.elevationProxy,
    required this.colorVariance,
    required this.saturationLevel,
    required this.heterogeneity,
  });
}

// ── Healing stage (clinical) ──────────────────────────────────────────────────
enum HealingStage { inflammatory, proliferative, remodeling, mature }

extension HealingStageExt on HealingStage {
  String get label {
    switch (this) {
      case HealingStage.inflammatory:
        return 'Early Inflammatory';
      case HealingStage.proliferative:
        return 'Proliferative';
      case HealingStage.remodeling:
        return 'Remodeling';
      case HealingStage.mature:
        return 'Mature';
    }
  }

  String get description {
    switch (this) {
      case HealingStage.inflammatory:
        return 'Day 0�21 � Active inflammation drives angiogenesis and neutrophil/macrophage recruitment. '
            'Redness, oedema, and warmth are expected. Wound contraction begins.';
      case HealingStage.proliferative:
        return 'Day 22�60 � Fibroblasts lay down type-III collagen and new vasculature forms. '
            'Scar may appear raised, pink, and firm � this is normal proliferative activity.';
      case HealingStage.remodeling:
        return 'Day 61�180 � Type-III collagen remodels to stronger type-I fibrils. '
            'Elevation and redness should progressively reduce; pliability and texture improve.';
      case HealingStage.mature:
        return 'Day 180+ � Scar maturation. Collagen alignment optimises and vascularity regresses. '
            'Colour and texture approach surrounding skin tone over 12�24 months.';
    }
  }

  Color get colour {
    switch (this) {
      case HealingStage.inflammatory:
        return const Color(0xFFE57373);
      case HealingStage.proliferative:
        return const Color(0xFFFFB74D);
      case HealingStage.remodeling:
        return const Color(0xFF4FC3F7);
      case HealingStage.mature:
        return const Color(0xFF81C784);
    }
  }

  IconData get icon {
    switch (this) {
      case HealingStage.inflammatory:
        return Icons.local_fire_department_outlined;
      case HealingStage.proliferative:
        return Icons.autorenew_rounded;
      case HealingStage.remodeling:
        return Icons.tune_rounded;
      case HealingStage.mature:
        return Icons.verified_outlined;
    }
  }
}

HealingStage healingStageFromDays(int days) {
  if (days <= 21) return HealingStage.inflammatory;
  if (days <= 60) return HealingStage.proliferative;
  if (days <= 180) return HealingStage.remodeling;
  return HealingStage.mature;
}

// ══════════════════════════════════════════════════════════════════════════════
class ScarHealingTrackerScreen extends StatefulWidget {
  const ScarHealingTrackerScreen({super.key});

  @override
  State<ScarHealingTrackerScreen> createState() =>
      _ScarHealingTrackerScreenState();
}

class _ScarHealingTrackerScreenState extends State<ScarHealingTrackerScreen> {
  final List<ScarPhotoEntry> _entries = [];
  double _compareSliderValue = 0.5;
  bool _metricsExpanded = false;

  // Procedure state
  List<Map<String, dynamic>> _procedures = [];
  String? _activeProcedureId; // null = show unlinked entries

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _loadProcedures();
  }

  Future<void> _loadProcedures() async {
    final procs = await AppPrefs.getProcedureEntries();
    if (mounted) {
      setState(() {
        _procedures = procs;
        // Auto-select the first procedure that has entries, or the first procedure overall
        if (_activeProcedureId == null && procs.isNotEmpty) {
          // prefer whichever procedure has scar entries; stay null if none do yet
        }
      });
    }
  }

  Future<void> _loadEntries() async {
    try {
      final raw = await AppPrefs.getScarHealingEntriesRaw();
      final loaded = raw
          .map((s) {
            try {
              return ScarPhotoEntry.fromJson(s);
            } catch (_) {
              return null;
            }
          })
          .whereType<ScarPhotoEntry>()
          .toList();
      if (loaded.isNotEmpty && mounted) setState(() => _entries.addAll(loaded));
    } catch (_) {}
  }

  Future<void> _saveEntries() async {
    try {
      await AppPrefs.saveScarHealingEntriesRaw(
        _entries.map((entry) => entry.toJson()).toList(growable: false),
      );
    } catch (_) {}
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  // -- Active entries (filtered to the selected procedure) ------------------
  List<ScarPhotoEntry> get _activeEntries {
    if (_activeProcedureId == null) return List.unmodifiable(_entries);
    return _entries.where((e) => e.procedureId == _activeProcedureId).toList();
  }

  /// Procedure IDs that have at least one scar entry, in insertion order
  List<String> get _procedureIdsWithEntries {
    final seen = <String>[];
    for (final e in _entries) {
      if (e.procedureId != null && !seen.contains(e.procedureId)) {
        seen.add(e.procedureId!);
      }
    }
    return seen;
  }

  int get _journalCount => _activeEntries.fold(0, (sum, e) {
    int count = 0;
    if (e.transcript?.trim().isNotEmpty ?? false) count++;
    count += e.notes.length;
    return sum + count;
  });

  bool get _isDesktopPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  HealingStage get _currentStage {
    final active = _activeEntries;
    if (active.isEmpty) return HealingStage.inflammatory;
    final days = DateTime.now().difference(active.first.date).inDays;
    return healingStageFromDays(days);
  }

  ScarMetrics get _latestMetrics {
    final active = _activeEntries;
    return active.isEmpty ? const ScarMetrics() : active.last.metrics;
  }

  // "Day-0 untreated" fallback reference � used when only 1 entry exists
  static const ScarMetrics _freshScarRef = ScarMetrics(
    redness: 9.0,
    elevation: 8.0,
    colorMatch: 1.0,
    texture: 1.0,
    pliability: 1.0,
    itchiness: 8.0,
    pain: 8.0,
  );

  // The FIRST photo of the active procedure is the permanent baseline.
  // With a single entry, baseline == latest so delta = 0 and no arrows render
  // (correct � nothing to compare against yet).
  ScarMetrics get _baselineMetrics {
    final active = _activeEntries;
    return active.isNotEmpty ? active.first.metrics : _freshScarRef;
  }

  ScarMetrics get _insightsBaseline => _baselineMetrics;

  ScarPhotoEntry? _resolveBaselineEntryForProcedure(
    String? procedureId, {
    int? excludingGlobalIndex,
  }) {
    final candidates = <ScarPhotoEntry>[];
    for (var i = 0; i < _entries.length; i++) {
      if (excludingGlobalIndex != null && i == excludingGlobalIndex) continue;
      final entry = _entries[i];
      if (entry.procedureId == procedureId) {
        candidates.add(entry);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.date.compareTo(b.date));
    return candidates.first;
  }

  double _clampMetric(double value) => value.clamp(1.0, 10.0).toDouble();

  ScarMetrics _blendMetrics(ScarMetrics a, ScarMetrics b, double weightA) {
    final wA = weightA.clamp(0.0, 1.0).toDouble();
    final wB = 1.0 - wA;
    return ScarMetrics(
      redness: _clampMetric((a.redness * wA) + (b.redness * wB)),
      elevation: _clampMetric((a.elevation * wA) + (b.elevation * wB)),
      colorMatch: _clampMetric((a.colorMatch * wA) + (b.colorMatch * wB)),
      texture: _clampMetric((a.texture * wA) + (b.texture * wB)),
      pliability: _clampMetric((a.pliability * wA) + (b.pliability * wB)),
      itchiness: _clampMetric((a.itchiness * wA) + (b.itchiness * wB)),
      pain: _clampMetric((a.pain * wA) + (b.pain * wB)),
    );
  }

  _ScarImageFeatures? _extractScarImageFeatures(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final sampled = img.copyResize(
      decoded,
      width: 112,
      height: 112,
      interpolation: img.Interpolation.average,
    );

    final w = sampled.width;
    final h = sampled.height;
    if (w < 8 || h < 8) return null;

    var count = 0;
    var rednessRawAccum = 0.0; // R - avg(G,B) surplus
    var hueRedWtAccum = 0.0; // hue proximity to red, weighted by saturation
    var lumTotal = 0.0;
    var lumSqTotal = 0.0;
    var satAccum = 0.0;
    var topLum = 0.0;
    var bottomLum = 0.0;
    var topCount = 0;
    var bottomCount = 0;
    var centerLum = 0.0;
    var peripheryLum = 0.0;
    var centerCount = 0;
    var peripheryCount = 0;

    final lum = List.generate(h, (_) => List.filled(w, 0.0));
    final cx = w / 2.0;
    final cy = h / 2.0;
    // inner circle = central 30% of image width (typically the scar core)
    final innerR2 = (w * 0.30) * (w * 0.30);

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = sampled.getPixel(x, y);
        final rN = p.r.toDouble() / 255.0;
        final gN = p.g.toDouble() / 255.0;
        final bN = p.b.toDouble() / 255.0;

        // Photometric luminance (0�1)
        final l = 0.299 * rN + 0.587 * gN + 0.114 * bN;
        lum[y][x] = l * 255.0; // store 0�255 for gradient

        // Raw redness: R channel surplus over average of G+B
        rednessRawAccum += math.max(0.0, rN - (gN + bN) / 2.0);

        // HSV saturation & hue for erythema characterisation
        final maxC = math.max(rN, math.max(gN, bN));
        final minC = math.min(rN, math.min(gN, bN));
        final delta = maxC - minC;
        final sat = maxC > 0.001 ? delta / maxC : 0.0;
        satAccum += sat;

        // Hue (0�360�); scar erythema typically 0�25� or 335�360� (red-pink-orange)
        double hue = 0.0;
        if (delta > 0.001) {
          if (maxC == rN) {
            hue = 60.0 * (((gN - bN) / delta) % 6.0);
          } else if (maxC == gN) {
            hue = 60.0 * ((bN - rN) / delta + 2.0);
          } else {
            hue = 60.0 * ((rN - gN) / delta + 4.0);
          }
          if (hue < 0) hue += 360.0;
        }
        // Proximity to red: 0� = pure red ? signal 1.0; 180� = cyan ? 0.0
        final hueToRed = math.min(hue, 360.0 - hue) / 180.0;
        hueRedWtAccum +=
            (1.0 - hueToRed) * sat; // hue-erythema weighted by saturation

        lumTotal += l;
        lumSqTotal += l * l;
        count++;

        // Vertical asymmetry (top/bottom luminance split)
        if (y < h ~/ 2) {
          topLum += l;
          topCount++;
        } else {
          bottomLum += l;
          bottomCount++;
        }

        // Center vs. periphery heterogeneity (circular mask)
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= innerR2) {
          centerLum += l;
          centerCount++;
        } else {
          peripheryLum += l;
          peripheryCount++;
        }
      }
    }

    // Gradient analysis (texture roughness)
    var gradAccum = 0.0;
    var gradSqAccum = 0.0;
    var gradCount = 0;
    for (var y = 0; y < h - 1; y++) {
      for (var x = 0; x < w - 1; x++) {
        final gx = (lum[y][x + 1] - lum[y][x]).abs();
        final gy = (lum[y + 1][x] - lum[y][x]).abs();
        final g = (gx + gy) / 2.0;
        gradAccum += g;
        gradSqAccum += g * g;
        gradCount++;
      }
    }

    if (count == 0 || gradCount == 0) return null;

    final meanLum = lumTotal / count;
    final varianceLum = math.max(
      0.0,
      (lumSqTotal / count) - (meanLum * meanLum),
    );
    final stdLum = math.sqrt(varianceLum) / 255.0;

    final avgGrad = gradAccum / gradCount;
    final gradVariance = math.max(
      0.0,
      (gradSqAccum / gradCount) - (avgGrad * avgGrad),
    );
    final gradStd = math.sqrt(gradVariance);
    // Roughness: combine mean gradient (border sharpness) + gradient STD (irregular surface)
    final textureRoughness = ((avgGrad / 255.0) * 1.5 + (gradStd / 255.0) * 0.9)
        .clamp(0.0, 1.0);

    final avgSat = satAccum / count;
    final avgRednessRaw = rednessRawAccum / count;
    final avgHueWt = hueRedWtAccum / count;
    // Combined redness: raw channel surplus (55%) + hue-erythema chroma signal (45%)
    final combinedRedness = (avgRednessRaw * 0.55 + avgHueWt * 0.45).clamp(
      0.0,
      1.0,
    );

    // Vertical asymmetry
    final topMean = topCount == 0 ? meanLum : topLum / topCount;
    final bottomMean = bottomCount == 0 ? meanLum : bottomLum / bottomCount;
    final vertAsym = (topMean - bottomMean).abs() / 255.0;

    // Center-periph heterogeneity (raised scar has brighter/darker core vs. surrounding skin)
    final centerMean = centerCount == 0 ? meanLum : centerLum / centerCount;
    final periMean = peripheryCount == 0
        ? meanLum
        : peripheryLum / peripheryCount;
    final heterogeneity =
        ((centerMean - periMean).abs() / 255.0 * 1.4 + vertAsym * 0.6).clamp(
          0.0,
          1.0,
        );

    return _ScarImageFeatures(
      rednessSignal: combinedRedness,
      textureRoughness: textureRoughness,
      elevationProxy: (heterogeneity * 0.65 + stdLum * 0.55).clamp(0.0, 1.0),
      colorVariance: (avgSat * 0.55 + stdLum * 1.1).clamp(0.0, 1.0),
      saturationLevel: avgSat.clamp(0.0, 1.0),
      heterogeneity: heterogeneity.clamp(0.0, 1.0),
    );
  }

  ScarMetrics _metricsFromSinglePhoto(Uint8List imageBytes) {
    final f = _extractScarImageFeatures(imageBytes);
    if (f == null) return const ScarMetrics();

    // Each formula maps the relevant feature signal(s) across the full 1�10 scale.
    // Scaling anchors are calibrated to typical scar photo signal ranges:
    //   rednessSignal  � 0.01�0.28  (near-healed ? actively inflamed)
    //   textureRoughness � 0.02�0.50  (smooth intact skin ? rough fibrous surface)
    //   elevationProxy � 0.02�0.45  (flat ? visibly raised)
    //   colorVariance  � 0.05�0.45  (uniform ? highly variable pigmentation)
    //   saturationLevel � 0.05�0.70  (desaturated/pale ? vivid erythema)

    // -- Redness (1=minimal, 10=severe erythema) � lower is better
    final redness = _clampMetric(
      1.0 + (f.rednessSignal / 0.24).clamp(0.0, 1.0) * 9.0,
    );

    // -- Elevation / Height (1=flat/resolved, 10=hypertrophic) � lower is better
    final elevation = _clampMetric(
      1.0 +
          (f.elevationProxy / 0.38).clamp(0.0, 1.0) * 6.5 +
          f.textureRoughness * 2.0,
    );

    // -- Texture / Smoothness (1=very rough, 10=smooth) � HIGHER is better; inverted
    final texture = _clampMetric(
      9.8 - (f.textureRoughness / 0.46).clamp(0.0, 1.0) * 8.5,
    );

    // -- Colour Match (1=strong mismatch, 10=matches skin) � HIGHER is better; inverted
    final colorMatch = _clampMetric(
      9.5 -
          (f.colorVariance / 0.42).clamp(0.0, 1.0) * 5.5 -
          (f.rednessSignal / 0.24).clamp(0.0, 1.0) * 3.0,
    );

    // -- Pliability / Softness (1=stiff/bound, 10=pliable) � HIGHER is better; inverted
    // Rough surface + elevated center-periph heterogeneity ? stiff fibrotic scar
    final pliability = _clampMetric(
      9.2 -
          f.textureRoughness * 4.8 -
          f.heterogeneity * 3.8 -
          f.elevationProxy * 1.8,
    );

    // -- Itchiness (1=none, 10=severe) � lower is better
    // Erythema + high saturation correlates with neurogenic inflammatory itch
    final itchiness = _clampMetric(
      1.0 +
          (f.rednessSignal / 0.24).clamp(0.0, 1.0) * 6.0 +
          f.saturationLevel * 4.5,
    );

    // -- Pain Level (1=painless, 10=severe tenderness) � lower is better
    // Elevation + redness infer touch tenderness and nociceptive activity
    final pain = _clampMetric(
      1.0 +
          (f.elevationProxy / 0.38).clamp(0.0, 1.0) * 5.0 +
          (f.rednessSignal / 0.24).clamp(0.0, 1.0) * 3.5,
    );

    return ScarMetrics(
      redness: redness,
      elevation: elevation,
      colorMatch: colorMatch,
      texture: texture,
      pliability: pliability,
      itchiness: itchiness,
      pain: pain,
    );
  }

  ScarMetrics _computeAutoMetrics({
    required Uint8List currentImageBytes,
    Uint8List? baselineImageBytes,
    ScarMetrics? baselineMetrics,
    ScarMetrics? fallback,
  }) {
    if (currentImageBytes.isEmpty) {
      return fallback ?? const ScarMetrics();
    }

    final currentAbsolute = _metricsFromSinglePhoto(currentImageBytes);
    if (baselineImageBytes == null || baselineImageBytes.isEmpty) {
      return currentAbsolute;
    }

    final baseFeatures = _extractScarImageFeatures(baselineImageBytes);
    final currentFeatures = _extractScarImageFeatures(currentImageBytes);
    if (baseFeatures == null || currentFeatures == null) {
      return currentAbsolute;
    }

    final base = baselineMetrics ?? _metricsFromSinglePhoto(baselineImageBytes);

    // Raw feature deltas (positive = signal increased from baseline)
    final rednessDelta =
        currentFeatures.rednessSignal - baseFeatures.rednessSignal;
    final textureDelta =
        currentFeatures.textureRoughness - baseFeatures.textureRoughness;
    final elevationDelta =
        currentFeatures.elevationProxy - baseFeatures.elevationProxy;
    final colorVarDelta =
        currentFeatures.colorVariance - baseFeatures.colorVariance;
    final satDelta =
        currentFeatures.saturationLevel - baseFeatures.saturationLevel;
    final heteroDelta =
        currentFeatures.heterogeneity - baseFeatures.heterogeneity;

    // Convert feature deltas ? metric-unit deltas.
    // Scale factors convert unitless feature offsets to 1�10 scale points.
    // Per-metric cap (�3.0) prevents single-session noise from producing implausible jumps.
    double cap(double v) => v.clamp(-3.0, 3.0);

    final compared = ScarMetrics(
      redness: _clampMetric(
        base.redness + cap(rednessDelta * 12.5 + colorVarDelta * 2.0),
      ),
      elevation: _clampMetric(
        base.elevation + cap(elevationDelta * 10.5 + heteroDelta * 3.5),
      ),
      colorMatch: _clampMetric(
        base.colorMatch + cap(-colorVarDelta * 9.0 - rednessDelta * 3.5),
      ),
      texture: _clampMetric(base.texture + cap(-textureDelta * 10.5)),
      pliability: _clampMetric(
        base.pliability +
            cap(-textureDelta * 5.5 - elevationDelta * 4.5 - heteroDelta * 2.5),
      ),
      itchiness: _clampMetric(
        base.itchiness + cap(rednessDelta * 8.5 + satDelta * 5.0),
      ),
      pain: _clampMetric(
        base.pain + cap(rednessDelta * 5.0 + elevationDelta * 5.5),
      ),
    );

    // Blend differential signal (70%) with absolute visual estimate (30%) for stability.
    // The absolute component anchors scores against cumulative drift over many sessions.
    return _blendMetrics(compared, currentAbsolute, 0.70);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_monthShort(d.month)} ${d.year}';

  String _monthShort(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  Future<Uint8List?> _readPickedPhotoBytes(XFile picked) async {
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {
      // Continue to web fallback.
    }

    if (kIsWeb) {
      final path = picked.path;
      if (path.startsWith('data:image')) {
        try {
          final parts = path.split(',');
          if (parts.length > 1) return base64Decode(parts[1]);
        } catch (_) {}
      }

      if (path.startsWith('blob:') || path.startsWith('http')) {
        try {
          return await readWebBlobBytes(path);
        } catch (_) {}
      }
    }

    return null;
  }

  String _photoProcessingError() {
    return 'We could not process the selected photo. '
        'Please choose a JPG/PNG image and try again.';
  }

  // ── photo picking ──────────────────────────────────────────────────────────
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await _readPickedPhotoBytes(picked);
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_photoProcessingError())));
        return;
      }
      _showMetricsEntryDialog(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_photoProcessingError())));
    }
  }

  Future<void> _addScarPhoto() async {
    if (kIsWeb || _isDesktopPlatform) {
      await _pickPhoto(ImageSource.gallery);
      return;
    }
    final src = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Scar Photo'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Camera'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Gallery'),
          ),
        ],
      ),
    );
    if (src != null) await _pickPhoto(src);
  }

  // ── metrics entry dialog ───────────────────────────────────────────────────
  void _showMetricsEntryDialog(Uint8List imageBytes, {int? editIndex}) {
    final existing = editIndex != null ? _entries[editIndex] : null;
    final initProcId = existing?.procedureId ?? _activeProcedureId;
    final initProcName =
        existing?.procedureName ??
        (_activeProcedureId == null
            ? null
            : _procedures.cast<Map<String, dynamic>?>().firstWhere(
                    (p) => p!['id'] == _activeProcedureId,
                    orElse: () => null,
                  )?['type']
                  as String?);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MetricsEntryDialog(
        imageBytes: imageBytes,
        initialConcernLevel: existing?.concernLevel ?? 5,
        initialProcedureId: initProcId,
        initialProcedureName: initProcName,
        initialProcedureTag: existing?.procedureTag,
        procedures: _procedures,
        editIndex: editIndex,
        isBaseline: editIndex == null
            ? (initProcId == null
                  ? _entries.isEmpty
                  : _entries.where((e) => e.procedureId == initProcId).isEmpty)
            : false,
        onSave: (concernLevel, procedureId, procedureName, procedureTag) {
          final existingImage = existing?.image;
          final effectiveBytes = imageBytes.isNotEmpty
              ? imageBytes
              : (existingImage ?? Uint8List(0));
          final baselineEntry = _resolveBaselineEntryForProcedure(
            procedureId,
            excludingGlobalIndex: editIndex,
          );
          final computedMetrics = _computeAutoMetrics(
            currentImageBytes: effectiveBytes,
            baselineImageBytes: baselineEntry?.image,
            baselineMetrics: baselineEntry?.metrics,
            fallback: existing?.metrics,
          );

          setState(() {
            if (editIndex != null) {
              _entries[editIndex] = _entries[editIndex].copyWith(
                metrics: computedMetrics,
                concernLevel: concernLevel,
                procedureId: procedureId,
                procedureName: procedureName,
                procedureTag: procedureTag,
              );
            } else {
              _entries.add(
                ScarPhotoEntry(
                  image: imageBytes,
                  date: DateTime.now(),
                  concernLevel: concernLevel,
                  metrics: computedMetrics,
                  procedureId: procedureId,
                  procedureName: procedureName,
                  procedureTag: procedureTag,
                ),
              );
              if (procedureId != null) _activeProcedureId = procedureId;
            }
          });
          _saveEntries();
        },
      ),
    );
  }

  void _showBaselineProtectedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              color: MyApp.goldShimmer,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('Baseline Photo'),
          ],
        ),
        content: const Text(
          'The first photo is permanently locked as your baseline reference.\n\n'
          'All future progress photos are compared against it. '
          'To update your baseline, delete all entries and start fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showVoiceJournalModal({int? globalEntryIndex}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _VoiceJournalRecorder(
        onSave: (transcript, audioBytes) {
          final idx =
              globalEntryIndex ??
              (_entries.isNotEmpty ? _entries.length - 1 : null);
          if (idx != null && idx >= 0 && idx < _entries.length) {
            final note = ScarJournalNote(
              id: '${DateTime.now().millisecondsSinceEpoch}',
              createdAt: DateTime.now(),
              text: transcript.isNotEmpty ? transcript : '?? Voice recording',
              isVoice: true,
            );
            setState(() {
              final entry = _entries[idx];
              _entries[idx] = entry.copyWith(
                audio: audioBytes ?? entry.audio,
                transcript: transcript.isNotEmpty
                    ? transcript
                    : entry.transcript,
                notes: [...entry.notes, note],
              );
            });
            _saveEntries();
          }
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final gold = MyApp.goldShimmer;
    final champagne = MyApp.champagne;
    final stage = _currentStage;
    final active = _activeEntries;
    final hasBoth = active.length >= 2;

    return Scaffold(
      backgroundColor: champagne,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Scar Healing Tracker',
          eyebrow: 'Tissue recovery',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: gold,
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.mic_none_rounded),
              tooltip: 'Voice Journal',
              onPressed: _showVoiceJournalModal,
            ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: MyApp.goldShimmer.withValues(alpha: 0.42),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _addScarPhoto,
          backgroundColor: MyApp.goldShimmer,
          foregroundColor: AppColors.onChampagneGold,
          elevation: 0,
          icon: const Icon(Icons.add_a_photo),
          label: Text(
            active.isEmpty ? 'Add Baseline Photo' : 'Add Progress Photo',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              champagne,
              gold.withValues(alpha: 0.05),
              MyApp.surface.withValues(alpha: 0.97),
            ],
          ),
        ),
        child: Column(
          children: [
            // Procedure switcher chip bar
            if (_procedures.isNotEmpty || _procedureIdsWithEntries.isNotEmpty)
              _buildProcedureSwitcher(),
            Expanded(
              child: active.isEmpty && _entries.isEmpty
                  ? _buildEmptyState()
                  : active.isEmpty
                  ? _buildNoProcedureEntries()
                  : _buildContent(stage, hasBoth),
            ),
          ],
        ),
      ),
    );
  }

  // ── empty state ────────────────────────────────────────────────────────────
  // -- Procedure switcher chip bar -------------------------------------------
  Widget _buildProcedureSwitcher() {
    // Merge: procedures with entries + procedures from AppPrefs (may have none yet)
    // Show one chip per procedure that has at least one scar entry, plus all loaded procedures
    final idsWithEntries = _procedureIdsWithEntries;
    final allProcIds = {
      ...idsWithEntries,
      ..._procedures.map((p) => p['id'] as String),
    }.toList();

    if (allProcIds.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'Tracking Scar For',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MyApp.textBrown.withValues(alpha: 0.5),
                letterSpacing: 0.5,
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: allProcIds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final id = allProcIds[i];
                final proc = _procedures
                    .cast<Map<String, dynamic>?>()
                    .firstWhere((p) => p!['id'] == id, orElse: () => null);
                final label =
                    proc?['type'] as String? ??
                    _entries
                        .firstWhere(
                          (e) => e.procedureId == id,
                          orElse: () => ScarPhotoEntry(
                            date: DateTime.now(),
                            concernLevel: 5,
                          ),
                        )
                        .procedureName ??
                    'Procedure';
                final entryCount = _entries
                    .where((e) => e.procedureId == id)
                    .length;
                final isSelected = _activeProcedureId == id;

                return GestureDetector(
                  onTap: () => setState(() => _activeProcedureId = id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? MyApp.goldShimmer
                          : MyApp.goldShimmer.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? MyApp.goldShimmer
                            : MyApp.goldShimmer.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.healing_outlined,
                          size: 13,
                          color: isSelected ? Colors.white : MyApp.goldShimmer,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label.length > 22
                              ? '${label.substring(0, 20)}�'
                              : label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : MyApp.goldShimmer,
                          ),
                        ),
                        if (entryCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : MyApp.goldShimmer.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$entryCount',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : MyApp.goldShimmer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade200),
        ],
      ),
    );
  }

  // -- Shown when a procedure chip is selected but has no photos yet ---------
  Widget _buildNoProcedureEntries() {
    final proc = _procedures.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p!['id'] == _activeProcedureId,
      orElse: () => null,
    );
    final name = proc?['type'] as String? ?? 'this procedure';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 64,
              color: MyApp.goldShimmer.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 20),
            Text(
              'No photos yet for $name',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: MyApp.textBrown,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add your first photo to establish the permanent baseline for this procedure. All future photos will be compared to it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: MyApp.textBrown.withValues(alpha: 0.60),
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 116,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.14),
                  width: 1.2,
                ),
              ),
              child: Container(
                width: 100,
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MyApp.goldShimmer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: MyApp.goldShimmer.withValues(alpha: 0.24),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.healing_outlined,
                  size: 52,
                  color: MyApp.goldShimmer,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Start Your Scar Recovery Journal',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: MyApp.textBrown,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Track healing with clinical precision. Add your first scar photo to unlock before/after comparison, 7-metric scar scoring, trend analysis, and actionable recovery insights.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                color: MyApp.textBrown.withValues(alpha: 0.66),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 28),
            // Feature pills
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _featurePill(Icons.compare_outlined, 'Before / After'),
                _featurePill(Icons.bar_chart_outlined, '7-Metric Scoring'),
                _featurePill(Icons.trending_up_rounded, 'Trend Arrows'),
                _featurePill(Icons.lightbulb_outline_rounded, 'Insights'),
                _featurePill(Icons.timeline_outlined, 'Photo Timeline'),
                _featurePill(Icons.mic_none_rounded, 'Voice Journal'),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addScarPhoto,
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Add First Scar Photo'),
                style: MyApp.primaryGoldButton,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featurePill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MyApp.goldShimmer.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MyApp.goldShimmer),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: MyApp.goldShimmer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── main content ───────────────────────────────────────────────────────────
  Widget _buildContent(HealingStage stage, bool hasBoth) {
    final active = _activeEntries;
    final latest = _latestMetrics;
    final baseline =
        _baselineMetrics; // first photo of procedure (permanent baseline)
    final insightsBase = _insightsBaseline;
    final daysSinceFirst = active.length > 1
        ? active.last.date.difference(active.first.date).inDays
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 1. Healing Stage Banner + Progression ─────────────────────────
          _buildStageBanner(stage),
          const SizedBox(height: 12),
          _buildStageProgressBar(stage),
          const SizedBox(height: 20),

          // ── 2. Stat Cards ─────────────────────────────────────────────────
          _buildStatCards(daysSinceFirst, active.length),
          const SizedBox(height: 22),

          // ── 3. Before / After Comparison ─────────────────────────────────
          _sectionHeader(
            'Before / After Comparison',
            Icons.compare_outlined,
            'Visual evidence',
          ),
          const SizedBox(height: 10),
          _buildBeforeAfterSection(hasBoth, active),
          const SizedBox(height: 26),

          // ── 4. Scar Maturity Score + Metrics ─────────────────────────────
          _buildCollapsibleMetricsSection(
            latest,
            baseline,
            hasBoth,
            onEditLatest: hasBoth
                ? () {
                    final active = _activeEntries;
                    if (active.isNotEmpty) {
                      final lastEntry = active.last;
                      final globalIdx = _entries.indexOf(lastEntry);
                      _showMetricsEntryDialog(
                        lastEntry.image ?? Uint8List(0),
                        editIndex: globalIdx,
                      );
                    }
                  }
                : null,
          ),
          const SizedBox(height: 26),

          // -- 5. AI Scar Analysis & Product Recommendations ---------------------
          if (hasBoth) ...[
            _sectionHeader(
              'AI Scar Analysis',
              Icons.biotech_outlined,
              'Clinical interpretation',
            ),
            const SizedBox(height: 12),
            _buildAiAnalysisSection(latest, baseline, stage, active),
            const SizedBox(height: 26),
          ],

          // ── 5. Actionable Insights ────────────────────────────────────────
          if (hasBoth) ...[
            _sectionHeader(
              'Recovery Insights',
              Icons.lightbulb_outline_rounded,
              'Actionable guidance',
            ),
            const SizedBox(height: 12),
            _buildInsightsCard(latest, insightsBase),
            const SizedBox(height: 26),
          ],

          // ── 6. Photo Timeline ─────────────────────────────────────────────
          _sectionHeader(
            'Healing Timeline',
            Icons.timeline_outlined,
            'Photo progression',
          ),
          const SizedBox(height: 12),
          _buildTimeline(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Healing Stage Banner ───────────────────────────────────────────────────
  Widget _buildStageBanner(HealingStage stage) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: stage.colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stage.colour.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: stage.colour.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(stage.icon, color: stage.colour, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      stage.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: stage.colour,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: stage.colour.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Stage ${HealingStage.values.indexOf(stage) + 1}/4',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: stage.colour,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stage.description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: MyApp.textBrown.withValues(alpha: 0.70),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stage progression bar ──────────────────────────────────────────────────
  Widget _buildStageProgressBar(HealingStage stage) {
    const stages = HealingStage.values;
    final currentIdx = stages.indexOf(stage);
    return Row(
      children: List.generate(stages.length * 2 - 1, (i) {
        if (i.isOdd) {
          // connector line
          final idx = i ~/ 2;
          final done = idx < currentIdx;
          return Expanded(
            child: Container(
              height: 3,
              color: done ? stages[idx].colour : Colors.grey.shade200,
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx <= currentIdx;
        final current = idx == currentIdx;
        final s = stages[idx];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: current ? 36 : 26,
              height: current ? 36 : 26,
              decoration: BoxDecoration(
                color: done ? s.colour : Colors.grey.shade200,
                shape: BoxShape.circle,
                border: current
                    ? Border.all(color: s.colour, width: 2.5)
                    : null,
                boxShadow: current
                    ? [
                        BoxShadow(
                          color: s.colour.withValues(alpha: 0.4),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                s.icon,
                size: current ? 18 : 14,
                color: done ? Colors.white : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 66,
              child: Text(
                s.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: current ? FontWeight.bold : FontWeight.w500,
                  color: done ? s.colour : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  // ── Stat Cards ─────────────────────────────────────────────────────────────
  Widget _buildStatCards(int daysSinceFirst, int entryCount) {
    final cards = [
      _statCard('Photos', '$entryCount', Icons.photo_library_outlined),
      _statCard('Journal Entries', '$_journalCount', Icons.edit_note_rounded),
      _statCard(
        'Days Tracked',
        entryCount > 1 ? '$daysSinceFirst' : '�',
        Icons.calendar_today_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (_, c) {
        final narrow = c.maxWidth < 560;
        if (narrow) {
          return Column(
            children: cards
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: w,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  // ── Before / After ─────────────────────────────────────────────────────────
  Widget _buildBeforeAfterSection(bool hasBoth, List<ScarPhotoEntry> active) {
    if (!hasBoth) {
      return Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: MyApp.goldShimmer.withValues(alpha: 0.22),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compare_outlined,
                color: MyApp.goldShimmer.withValues(alpha: 0.4),
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                'Add a progress photo to unlock comparison',
                style: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.58),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final baselineEntry = active.first;
    final latestEntry = active.last;
    final daysBetween = latestEntry.date.difference(baselineEntry.date).inDays;

    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06).copyWith(
        boxShadow: [
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.52 < 320
                ? 320
                : MediaQuery.of(context).size.height * 0.52 > 520
                ? 520
                : MediaQuery.of(context).size.height * 0.52,
            child: BeforeAfter(
              value: _compareSliderValue,
              onValueChanged: (v) => setState(() => _compareSliderValue = v),
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              thumbDecoration: BoxDecoration(
                color: MyApp.goldShimmer,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.goldShimmer.withValues(alpha: 0.45),
                    blurRadius: 10,
                  ),
                ],
              ),
              // before_after package: 'before' renders on the right, 'after' on the left.
              // Assign accordingly so baseline (older) appears on left and progress on right.
              before: Stack(
                fit: StackFit.expand,
                children: [
                  _photoWidget(
                    latestEntry.image,
                    width: double.infinity,
                    height: (MediaQuery.of(context).size.height * 0.52).clamp(
                      320,
                      520,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _photoLabel('DAY +$daysBetween'),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: _photoLabel(_fmt(latestEntry.date)),
                  ),
                ],
              ),
              after: Stack(
                fit: StackFit.expand,
                children: [
                  _photoWidget(
                    baselineEntry.image,
                    width: double.infinity,
                    height: (MediaQuery.of(context).size.height * 0.52).clamp(
                      320,
                      520,
                    ),
                  ),
                  Positioned(top: 10, left: 10, child: _photoLabel('BASELINE')),
                  Positioned(
                    bottom: 10,
                    left: 10,
                    child: _photoLabel(_fmt(baselineEntry.date)),
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.swipe_rounded,
                  size: 15,
                  color: MyApp.goldShimmer.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 6),
                Text(
                  'Drag to compare Baseline vs Day +$daysBetween',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: MyApp.textBrown.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 14, color: Colors.grey.shade300),
                const SizedBox(width: 16),
                Icon(
                  Icons.photo_library_outlined,
                  size: 14,
                  color: MyApp.goldShimmer.withValues(alpha: 0.55),
                ),
                const SizedBox(width: 5),
                Text(
                  '${active.length} photos',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: MyApp.textBrown.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Metrics Card ───────────────────────────────────────────────────────────
  bool _metricsIdentical(ScarMetrics a, ScarMetrics b) =>
      (a.redness - b.redness).abs() < 0.05 &&
      (a.elevation - b.elevation).abs() < 0.05 &&
      (a.colorMatch - b.colorMatch).abs() < 0.05 &&
      (a.texture - b.texture).abs() < 0.05 &&
      (a.pliability - b.pliability).abs() < 0.05 &&
      (a.itchiness - b.itchiness).abs() < 0.05 &&
      (a.pain - b.pain).abs() < 0.05;

  // -- Collapsible Metrics Section -------------------------------------------
  Widget _buildCollapsibleMetricsSection(
    ScarMetrics latest,
    ScarMetrics baseline,
    bool hasBoth, {
    VoidCallback? onEditLatest,
  }) {
    // Build 3 "at-a-glance" mini badges shown even when collapsed.
    Widget glanceBadge(
      String label,
      double current,
      double base,
      bool lowerIsBetter,
    ) {
      final delta = current - base;
      final improved = lowerIsBetter ? delta < -0.05 : delta > 0.05;
      final worsened = lowerIsBetter ? delta > 0.05 : delta < -0.05;
      final colour = improved
          ? const Color(0xFF2E7D32)
          : worsened
          ? const Color(0xFFB71C1C)
          : Colors.grey.shade600;
      final bg = improved
          ? const Color(0xFFC8E6C9)
          : worsened
          ? const Color(0xFFFFCDD2)
          : Colors.grey.shade200;
      final arrow = improved
          ? '?'
          : worsened
          ? '?'
          : '?';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colour.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Text(
          '$label $arrow',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: colour,
          ),
        ),
      );
    }

    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06).copyWith(
        boxShadow: [
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // -- Tappable header -----------------------------------------------
          InkWell(
            onTap: () => setState(() => _metricsExpanded = !_metricsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.bar_chart_outlined,
                    size: 20,
                    color: MyApp.goldShimmer.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Scar Metrics vs Baseline',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: MyApp.textBrown,
                      ),
                    ),
                  ),
                  if (hasBoth) ...[
                    const SizedBox(width: 8),
                    _healingScoreRing(latest.healingScore),
                    const SizedBox(width: 10),
                  ],
                  AnimatedRotation(
                    turns: _metricsExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: MyApp.goldShimmer.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // -- At-a-glance badges (always visible) --------------------------
          if (hasBoth)
            Padding(
              padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
              child: Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  glanceBadge(
                    'Redness',
                    latest.redness,
                    baseline.redness,
                    true,
                  ),
                  glanceBadge(
                    'Elevation',
                    latest.elevation,
                    baseline.elevation,
                    true,
                  ),
                  glanceBadge(
                    'Texture',
                    latest.texture,
                    baseline.texture,
                    false,
                  ),
                  glanceBadge(
                    'Colour',
                    latest.colorMatch,
                    baseline.colorMatch,
                    false,
                  ),
                  glanceBadge(
                    'Pliability',
                    latest.pliability,
                    baseline.pliability,
                    false,
                  ),
                  glanceBadge(
                    'Itch',
                    latest.itchiness,
                    baseline.itchiness,
                    true,
                  ),
                  glanceBadge('Pain', latest.pain, baseline.pain, true),
                ],
              ),
            ),
          // -- Expandable detail ---------------------------------------------
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            child: _metricsExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                    child: _buildMetricsCard(
                      latest,
                      baseline,
                      hasBoth,
                      onEditLatest: onEditLatest,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (!_metricsExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () =>
                    setState(() => _metricsExpanded = !_metricsExpanded),
                child: Text(
                  'Tap to see full metric breakdown',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.goldShimmer.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricsCard(
    ScarMetrics latest,
    ScarMetrics baseline,
    bool hasBoth, {
    VoidCallback? onEditLatest,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06).copyWith(
        boxShadow: [
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          if (hasBoth && _metricsIdentical(latest, baseline)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    color: Color(0xFFE65100),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'All metrics unchanged from baseline',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: MyApp.textBrown,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Move sliders in your latest entry to see real ? ? trend arrows.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: MyApp.textBrown.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEditLatest != null)
                    TextButton(
                      onPressed: onEditLatest,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE65100),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Edit Latest'),
                    ),
                ],
              ),
            ),
          ],
          if (hasBoth) ...[
            Row(
              children: [
                Text(
                  'Latest vs Baseline',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.textBrown.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _legendDot(const Color(0xFF66BB6A), 'Improved'),
                const SizedBox(width: 10),
                _legendDot(const Color(0xFFEF5350), 'Worsened'),
              ],
            ),
            const SizedBox(height: 14),
          ],
          // Negative (lower = better)
          _metricBar('Redness', latest.redness, baseline.redness, true),
          _metricBar(
            'Elevation / Height',
            latest.elevation,
            baseline.elevation,
            true,
          ),
          _metricBar('Itchiness', latest.itchiness, baseline.itchiness, true),
          _metricBar('Pain Level', latest.pain, baseline.pain, true),
          Divider(color: Colors.grey.shade200, height: 18),
          // Positive (higher = better)
          _metricBar(
            'Colour Match',
            latest.colorMatch,
            baseline.colorMatch,
            false,
          ),
          _metricBar(
            'Texture / Smoothness',
            latest.texture,
            baseline.texture,
            false,
          ),
          _metricBar(
            'Pliability / Softness',
            latest.pliability,
            baseline.pliability,
            false,
          ),
        ],
      ),
    );
  }

  // ── Insights Card ──────────────────────────────────────────────────────────
  // -- AI Scar Analysis Section ----------------------------------------------
  Widget _buildAiAnalysisSection(
    ScarMetrics latest,
    ScarMetrics baseline,
    HealingStage stage,
    List<ScarPhotoEntry> active,
  ) {
    final daysSince = active.length > 1
        ? active.last.date.difference(active.first.date).inDays
        : 0;
    final result = ScarAiAnalysisEngine.analyze(
      redness: latest.redness,
      elevation: latest.elevation,
      colorMatch: latest.colorMatch,
      texture: latest.texture,
      pliability: latest.pliability,
      itchiness: latest.itchiness,
      pain: latest.pain,
      healingScore: latest.healingScore,
      baseRedness: baseline.redness,
      baseElevation: baseline.elevation,
      baseColorMatch: baseline.colorMatch,
      baseTexture: baseline.texture,
      basePliability: baseline.pliability,
      baseItchiness: baseline.itchiness,
      basePain: baseline.pain,
      baseHealingScore: baseline.healingScore,
      daysSinceBaseline: daysSince,
      healingStageLabel: stage.label,
    );
    return ScarAiAnalysisBannerCard(
      result: result,
      onTap: () => ScarAiAnalysisSheet.show(
        context,
        result: result,
        latestImage: active.isNotEmpty ? active.last.image : null,
        baselineImage: active.isNotEmpty ? active.first.image : null,
      ),
    );
  }

  Widget _buildInsightsCard(ScarMetrics latest, ScarMetrics baseline) {
    final insights = _generateInsights(latest, baseline);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05).copyWith(
        border: Border.all(
          color: const Color(0xFFFFB74D).withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB74D).withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: insights
            .map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: insight.colour.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        insight.icon,
                        size: 15,
                        color: insight.colour,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: MyApp.textBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            insight.body,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: MyApp.textBrown.withValues(alpha: 0.68),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  List<_Insight> _generateInsights(ScarMetrics latest, ScarMetrics baseline) {
    final insights = <_Insight>[];

    // Infer broad clinical phase from current metric profile.
    // This drives stage-appropriate recommendation language.
    final bool isEarlyPhase =
        latest.redness >= 6.5 ||
        latest.elevation >= 6.0 ||
        latest.itchiness >= 6.5;
    final bool isLatePhase =
        latest.redness < 3.5 &&
        latest.elevation < 3.5 &&
        latest.healingScore >= 60;

    // -- Redness / Erythema ----------------------------------------------------
    final rdDelta = baseline.redness - latest.redness;
    final rdPct = baseline.redness > 0.5
        ? (rdDelta.abs() / baseline.redness * 100).round()
        : 0;
    if (rdDelta >= 1.5) {
      insights.add(
        _Insight(
          icon: Icons.trending_down_rounded,
          colour: const Color(0xFF2E7D32),
          title: 'Erythema resolving � on track',
          body:
              'Redness reduced by ${rdDelta.toStringAsFixed(1)} pts (�$rdPct%). '
              'This reflects progressive microvascular regression as the inflammatory cascade subsides. '
              '${isLatePhase ? 'Maintain daily SPF 50+ � even low UV exposure can trigger post-inflammatory erythema (PIE) relapse in maturing scars.' : 'Continue topical silicone therapy; it reduces transepidermal water loss and inhibits fibroblast-driven neovascularisation.'}',
        ),
      );
    } else if (latest.redness >= 7.5 && rdDelta <= 0.5) {
      insights.add(
        _Insight(
          icon: Icons.warning_amber_outlined,
          colour: const Color(0xFFB71C1C),
          title: 'Persistent high erythema',
          body:
              'Erythema score remains at ${latest.redness.toStringAsFixed(1)}/10 with minimal change. '
              'If unchanged beyond 8 weeks, first-line options include occlusive silicone sheeting (=12 h/day) '
              'or vascular-targeting laser (595 nm pulsed-dye or Nd:YAG), which reduces microvascular density '
              'by 40�60% in controlled trials. Rule out contact sensitisation to topical agents.',
        ),
      );
    } else if (latest.redness >= 5.5 && isEarlyPhase) {
      insights.add(
        const _Insight(
          icon: Icons.info_outline_rounded,
          colour: Color(0xFFE65100),
          title: 'Inflammatory-phase erythema � expected',
          body:
              'Moderate redness is physiologically normal in weeks 1�6 as angiogenesis supplies the healing tissue. '
              'Avoid friction, heat, and topical NSAIDs. Begin silicone sheeting as soon as epidermal closure is confirmed.',
        ),
      );
    }

    // -- Elevation / Scar Height -----------------------------------------------
    final elDelta = baseline.elevation - latest.elevation;
    final elPct = baseline.elevation > 0.5
        ? (elDelta.abs() / baseline.elevation * 100).round()
        : 0;
    if (latest.elevation >= 6.5 && elDelta < 1.0) {
      insights.add(
        _Insight(
          icon: Icons.layers_outlined,
          colour: const Color(0xFFE65100),
          title: 'Elevated profile � consider compression',
          body:
              'Raised scar height (${latest.elevation.toStringAsFixed(1)}/10) with limited flattening suggests '
              'active type-III collagen deposition and hypertrophic risk. '
              'Scar massage (4�5 min, circular cross-friction, twice daily) combined with compression garments '
              'reduces hypertrophic progression by >50% in prospective trials. '
              'Intralesional corticosteroid (triamcinolone 10�40 mg/mL) is the standard second-line intervention.',
        ),
      );
    } else if (elDelta >= 1.2) {
      insights.add(
        _Insight(
          icon: Icons.trending_down_rounded,
          colour: const Color(0xFF2E7D32),
          title: 'Scar profile flattening',
          body:
              'Elevation reduced by ${elDelta.toStringAsFixed(1)} pts (�$elPct%) � consistent with '
              'collagen bundle reorientation from random cross-linked to parallel alignment. '
              'Maintain massage volume; the remodelling phase responds best to sustained mechanical loading.',
        ),
      );
    }

    // -- Texture / Surface Quality ---------------------------------------------
    final txDelta = latest.texture - baseline.texture;
    if (txDelta >= 1.5) {
      insights.add(
        _Insight(
          icon: Icons.auto_fix_high_outlined,
          colour: const Color(0xFF2E7D32),
          title: 'Surface texture improving',
          body:
              'Texture score improved by ${txDelta.toStringAsFixed(1)} pts, indicating smoother epidermal '
              'architecture and reduced surface fibrosis. '
              '${isLatePhase ? 'Consider microneedling (1.5�2.0 mm depth) or fractional ablative laser once fully mature (6+ months) to further optimise surface quality.' : 'Continue current protocol � surface quality responds well during the active remodelling window.'}',
        ),
      );
    } else if (latest.texture <= 3.5) {
      insights.add(
        _Insight(
          icon: Icons.texture_outlined,
          colour: const Color(0xFFFF8F00),
          title: 'Surface irregularity � support epidermal renewal',
          body:
              'Low texture score (${latest.texture.toStringAsFixed(1)}/10) reflects surface roughness consistent '
              'with early fibrotic activity or keratinised wound margin. '
              'Low-potency retinoid (tretinoin 0.025% every other night from week 10�12) accelerates '
              'keratinocyte turnover. Avoid exfoliation until scar is fully closed.',
        ),
      );
    }

    // -- Colour Match / Pigmentation -------------------------------------------
    final cmDelta = latest.colorMatch - baseline.colorMatch;
    if (cmDelta >= 1.5) {
      insights.add(
        _Insight(
          icon: Icons.palette_outlined,
          colour: const Color(0xFF2E7D32),
          title: 'Pigmentation normalising',
          body:
              'Colour match improved by ${cmDelta.toStringAsFixed(1)} pts � post-inflammatory pigment is resolving. '
              'UV exposure activates melanocytes in healing dermis and can arrest pigment normalisation for months. '
              'Apply mineral SPF 50+ daily for at least 12 months post-injury regardless of perceived healing.',
        ),
      );
    } else if (latest.colorMatch <= 3.0) {
      insights.add(
        _Insight(
          icon: Icons.palette_outlined,
          colour: const Color(0xFFEF6C00),
          title: 'Significant colour mismatch',
          body:
              'Colour score of ${latest.colorMatch.toStringAsFixed(1)}/10 may reflect post-inflammatory '
              'hyperpigmentation (PIH) or hypopigmentation. '
              'SPF 50+ is the single most evidence-based intervention. '
              'If PIH is confirmed, topical azelaic acid 20% or hydroquinone 4% under physician supervision '
              'can accelerate normalisation within 8�12 weeks.',
        ),
      );
    }

    // -- Pliability / Scar Softness --------------------------------------------
    final plDelta = latest.pliability - baseline.pliability;
    if (latest.pliability <= 3.5 && plDelta < 0.5) {
      insights.add(
        _Insight(
          icon: Icons.compress_outlined,
          colour: const Color(0xFFFF8F00),
          title: 'Reduced pliability � massage & mobilise',
          body:
              'Stiffness at ${latest.pliability.toStringAsFixed(1)}/10 indicates dense cross-linked collagen with '
              'restricted extensibility � a precursor to contracture. '
              'Daily cross-friction massage with silicone oil is first-line. '
              'Pulsed therapeutic ultrasound (1 MHz, 1.0 W/cm�, 5 min) performed by a physiotherapist '
              'can penetrate deep fibrosis and improve collagen extensibility.',
        ),
      );
    } else if (plDelta >= 1.5) {
      insights.add(
        _Insight(
          icon: Icons.check_circle_outline,
          colour: const Color(0xFF2E7D32),
          title: 'Pliability improving',
          body:
              'Softness increased by ${plDelta.toStringAsFixed(1)} pts � evidence of collagen fibre reorientation '
              'from cross-linked random bundles towards parallel alignment. '
              'Maintain massage volume and stretching range to consolidate progress.',
        ),
      );
    }

    // -- Itchiness -------------------------------------------------------------
    final itDelta = baseline.itchiness - latest.itchiness;
    if (latest.itchiness >= 7.0) {
      insights.add(
        _Insight(
          icon: Icons.back_hand_outlined,
          colour: const Color(0xFFB71C1C),
          title: 'Elevated itch � neurogenic inflammatory phase',
          body:
              'Intense pruritus (${latest.itchiness.toStringAsFixed(1)}/10) is consistent with C-fibre nerve '
              'regeneration and histamine release through the healing dermis. '
              'Avoid scratching � it triggers mast-cell degranulation and amplifies itch via neurogenic feedback. '
              'Cool compress or 1% hydrocortisone cream temporarily breaks the itch�scratch cycle. '
              'Oral cetirizine (10 mg nocte) or loratadine can reduce systemic histamine load. '
              'TENS has emerging evidence for chronic scar itch.',
        ),
      );
    } else if (itDelta >= 2.0) {
      insights.add(
        _Insight(
          icon: Icons.check_circle_outline,
          colour: const Color(0xFF2E7D32),
          title: 'Itch burden reducing',
          body:
              'Itch score down ${itDelta.toStringAsFixed(1)} pts � nerve fibre reinnervation through the '
              'scar dermis is normalising. This transition typically marks movement from the proliferative into the remodelling phase.',
        ),
      );
    }

    // -- Composite Score -------------------------------------------------------
    final scoreDelta = latest.healingScore - baseline.healingScore;
    if (scoreDelta >= 8) {
      insights.add(
        _Insight(
          icon: Icons.star_outline_rounded,
          colour: const Color(0xFF2E7D32),
          title: 'Strong composite recovery progress',
          body:
              'Scar Maturity Score improved by ${scoreDelta.round()} pts across redness, texture, and pliability domains � '
              'consistent with healthy healing kinetics. '
              '${isLatePhase ? 'This is the optimal window for aesthetic refinement procedures (fractional CO2 resurfacing, microneedling-RF) if desired.' : 'Continue your current protocol � all indicators are trending well.'}',
        ),
      );
    } else if (scoreDelta <= -5) {
      insights.add(
        _Insight(
          icon: Icons.info_outline_rounded,
          colour: const Color(0xFFB71C1C),
          title: 'Score regression � review care protocol',
          body:
              'Maturity Score declined by ${scoreDelta.abs().round()} pts. '
              'Common causes: UV exposure, topical sensitiser, friction, or missed therapy sessions. '
              'Inspect for localised erythema, warmth, or exudate suggesting early infection. '
              'If regression persists across two recorded sessions, schedule a clinical review.',
        ),
      );
    }

    // -- Fallback (no specific flags triggered) --------------------------------
    if (insights.isEmpty) {
      if (isLatePhase) {
        insights.add(
          const _Insight(
            icon: Icons.verified_outlined,
            colour: Color(0xFF2E7D32),
            title: 'Scar maturing within normal parameters',
            body:
                'All seven domains are stable in the late-remodelling range. '
                'This is the optimal window for aesthetic refinement if desired: '
                'fractional ablative laser, microneedling, or RF microneedling can further reduce '
                'residual texture and colour variation. Continue SPF 50+ for at least 12 months post-injury.',
          ),
        );
      } else if (isEarlyPhase) {
        insights.add(
          const _Insight(
            icon: Icons.schedule_outlined,
            colour: Color(0xFFFF8F00),
            title: 'Early healing phase � consistency is key',
            body:
                'Current metrics reflect expected early-inflammatory activity. '
                'The most impactful interventions at this stage are consistent wound moisture management '
                'and UV protection. Initiate silicone occlusion therapy as soon as the wound surface is fully epithielialised.',
          ),
        );
      } else {
        insights.add(
          const _Insight(
            icon: Icons.check_circle_outline,
            colour: Color(0xFF2E7D32),
            title: 'All metrics within expected range',
            body:
                'No significant deviation detected across the 7-domain scar assessment. '
                'Continue your established care routine and log the next photo in 2�4 weeks '
                'to capture the next measurable change window.',
          ),
        );
      }
    }

    return insights;
  }

  // ── Photo Timeline ─────────────────────────────────────────────────────────

  // Text Note Dialog
  void _showTextNoteDialog(int globalIdx, {ScarJournalNote? editing}) {
    final ctrl = TextEditingController(text: editing?.text ?? '');
    final isEdit = editing != null;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 28,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  color: MyApp.goldShimmer,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  isEdit ? 'Edit Note' : 'Add Text Note',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: MyApp.goldShimmer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: 500,
              decoration: InputDecoration(
                hintText:
                    'e.g. Applied silicone gel today, skin felt less itchy...',
                hintStyle: TextStyle(
                  color: MyApp.textBrown.withValues(alpha: 0.40),
                  fontSize: 13.5,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: MyApp.goldShimmer.withValues(alpha: 0.35),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: MyApp.goldShimmer, width: 1.8),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(
                  isEdit ? Icons.save_outlined : Icons.add_circle_outline,
                ),
                label: Text(isEdit ? 'Save Changes' : 'Add Note'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyApp.goldShimmer,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    final entry = _entries[globalIdx];
                    List<ScarJournalNote> updated;
                    if (isEdit) {
                      updated = entry.notes
                          .map(
                            (n) =>
                                n.id == editing.id ? n.copyWithText(text) : n,
                          )
                          .toList();
                    } else {
                      final newNote = ScarJournalNote(
                        id: '${DateTime.now().millisecondsSinceEpoch}',
                        createdAt: DateTime.now(),
                        text: text,
                      );
                      updated = [...entry.notes, newNote];
                    }
                    _entries[globalIdx] = entry.copyWith(notes: updated);
                  });
                  _saveEntries();
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteNote(int globalIdx, String noteId) {
    setState(() {
      final entry = _entries[globalIdx];
      _entries[globalIdx] = entry.copyWith(
        notes: entry.notes.where((n) => n.id != noteId).toList(),
      );
    });
    _saveEntries();
  }

  // Per-entry journal section widget
  Widget _buildEntryJournalSection(ScarPhotoEntry entry, int globalIdx) {
    final legacyTranscript = (entry.transcript?.trim().isNotEmpty ?? false)
        ? entry.transcript!.trim()
        : null;
    final hasAny = legacyTranscript != null || entry.notes.isNotEmpty;
    final totalCount = (legacyTranscript != null ? 1 : 0) + entry.notes.length;

    return StatefulBuilder(
      builder: (ctx, setOuter) {
        bool expanded = false;
        return StatefulBuilder(
          builder: (ctx2, setExpanded) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note_rounded, size: 15),
                      label: const Text('Add Text Note'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.goldShimmer,
                        side: BorderSide(
                          color: MyApp.goldShimmer.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _showTextNoteDialog(globalIdx),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.mic_none_rounded, size: 15),
                      label: const Text('Voice Note'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.goldShimmer,
                        side: BorderSide(
                          color: MyApp.goldShimmer.withValues(alpha: 0.45),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () =>
                          _showVoiceJournalModal(globalEntryIndex: globalIdx),
                    ),
                  ),
                ],
              ),
              if (hasAny) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setExpanded(() => expanded = !expanded),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: MyApp.goldShimmer.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          expanded
                              ? 'Hide journal'
                              : '$totalCount journal entr${totalCount == 1 ? "y" : "ies"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: MyApp.goldShimmer.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOut,
                  child: expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            if (legacyTranscript != null)
                              _noteChip(
                                text: legacyTranscript,
                                date: entry.date,
                                isVoice: true,
                                onEdit: null,
                                onDelete: null,
                              ),
                            ...entry.notes.map(
                              (note) => _noteChip(
                                text: note.text,
                                date: note.createdAt,
                                isVoice: note.isVoice,
                                onEdit: note.isVoice
                                    ? null
                                    : () => _showTextNoteDialog(
                                        globalIdx,
                                        editing: note,
                                      ),
                                onDelete: () => _deleteNote(globalIdx, note.id),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _noteChip({
    required String text,
    required DateTime date,
    required bool isVoice,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: isVoice
            ? MyApp.goldShimmer.withValues(alpha: 0.06)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVoice
              ? MyApp.goldShimmer.withValues(alpha: 0.22)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isVoice ? Icons.mic_none_rounded : Icons.notes_rounded,
            size: 14,
            color: isVoice
                ? MyApp.goldShimmer.withValues(alpha: 0.7)
                : MyApp.textBrown.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: MyApp.textBrown.withValues(alpha: 0.78),
                    fontStyle: isVoice ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_fmt(date)}  -  ${isVoice ? "Voice" : "Text"}',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: MyApp.textBrown.withValues(alpha: 0.38),
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            GestureDetector(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: MyApp.textBrown.withValues(alpha: 0.4),
                ),
              ),
            ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 14,
                  color: Colors.red.shade300,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final active = _activeEntries;
    if (active.isEmpty) return const SizedBox.shrink();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: active.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final entry = active[i];
        // Find the global index in _entries for edit callback
        final globalIdx = _entries.indexOf(entry);
        final isBaseline = i == 0;
        final isLatest = i == active.length - 1 && active.length > 1;
        final dayOffset = isBaseline
            ? 0
            : entry.date.difference(active.first.date).inDays;
        final stageForEntry = healingStageFromDays(dayOffset);

        // Baseline card gets rose gold border, latest card gets green, others muted
        final accentColor = isBaseline
            ? MyApp.goldShimmer
            : isLatest
            ? const Color(0xFF66BB6A)
            : Colors.grey.shade300;

        return Container(
          decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06).copyWith(
            border: Border.all(
              color: accentColor.withValues(alpha: 0.50),
              width: isBaseline ? 2.0 : 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: _photoWidget(entry.image, width: 76, height: 76),
                      ),
                    ),
                    // "BASELINE" pin on first photo
                    if (isBaseline)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(
                            color: MyApp.goldShimmer.withValues(alpha: 0.88),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'BASELINE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        children: [
                          // Badge: BASELINE or DAY +N
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              isBaseline ? 'Baseline' : 'Day +$dayOffset',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: accentColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: stageForEntry.colour.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              stageForEntry.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: stageForEntry.colour,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Edit button (disabled for baseline to protect it)
                          GestureDetector(
                            onTap: isBaseline
                                ? () => _showBaselineProtectedDialog()
                                : () => _showMetricsEntryDialog(
                                    entry.image ?? Uint8List(0),
                                    editIndex: globalIdx,
                                  ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isBaseline
                                    ? Colors.grey.shade100
                                    : MyApp.goldShimmer.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isBaseline
                                      ? Colors.grey.shade300
                                      : MyApp.goldShimmer.withValues(
                                          alpha: 0.24,
                                        ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isBaseline
                                        ? Icons.lock_outline_rounded
                                        : Icons.edit_outlined,
                                    size: 11,
                                    color: isBaseline
                                        ? Colors.grey
                                        : MyApp.goldShimmer,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isBaseline ? 'Locked' : 'Edit',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isBaseline
                                          ? Colors.grey
                                          : MyApp.goldShimmer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fmt(entry.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: MyApp.textBrown.withValues(alpha: 0.55),
                        ),
                      ),
                      // Procedure tag (if any)
                      if (entry.procedureTag != null &&
                          entry.procedureTag!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              Icon(
                                Icons.medical_services_outlined,
                                size: 11,
                                color: MyApp.goldShimmer.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  entry.procedureTag!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: MyApp.goldShimmer.withValues(
                                      alpha: 0.85,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      // Metric pills
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _metricPill(
                            'Concern',
                            '${entry.concernLevel}/10',
                            MyApp.goldShimmer,
                          ),
                          _metricPill(
                            'Score',
                            '${entry.metrics.healingScore.round()}',
                            const Color(0xFF66BB6A),
                          ),
                          _metricPill(
                            'Redness',
                            entry.metrics.redness.toStringAsFixed(1),
                            const Color(0xFFEF5350),
                          ),
                          _metricPill(
                            'Elev.',
                            entry.metrics.elevation.toStringAsFixed(1),
                            const Color(0xFFFFB74D),
                          ),
                        ],
                      ),
                      // Journal section
                      const SizedBox(height: 10),
                      _buildEntryJournalSection(entry, globalIdx),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Metric bar with % trend ────────────────────────────────────────────────
  Widget _metricBar(
    String label,
    double current,
    double baseline,
    bool lowerIsBetter,
  ) {
    final delta = current - baseline;
    // Threshold 0.05 catches any real slider move (step = 0.5) while
    // ignoring floating-point noise.
    final improved = lowerIsBetter ? delta < 0 : delta > 0;
    final worsened = lowerIsBetter ? delta > 0 : delta < 0;
    final unchanged = !improved && !worsened;

    // Strong, saturated colours so they are impossible to miss.
    final Color trendColour = improved
        ? const Color(0xFF1B5E20) // even deeper green
        : worsened
        ? const Color(0xFFB71C1C) // even deeper red
        : Colors.grey.shade600;
    final Color badgeBg = improved
        ? const Color(0xFFC8E6C9)
        : worsened
        ? const Color(0xFFFFCDD2)
        : Colors.grey.shade200;
    final Color barColour = improved
        ? const Color(0xFF43A047)
        : worsened
        ? const Color(0xFFE53935)
        : MyApp.goldShimmer.withValues(alpha: 0.55);

    // Unicode arrows � guaranteed to render on every platform/browser.
    final String arrow = improved
        ? '?'
        : worsened
        ? '?'
        : '?';

    // Always show real %, even for unchanged (0%).
    final int pct = baseline.abs() > 0.01
        ? (delta.abs() / baseline * 100).round()
        : 0;

    // Badge text: "7.0  ?  28%" or "4.0  ?  12%" or "7.0  ?  ="
    final String badgeText = unchanged
        ? '${current.toStringAsFixed(1)}  $arrow  ='
        : '${current.toStringAsFixed(1)}  $arrow  $pct%';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  color: MyApp.textBrown,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: trendColour.withValues(alpha: 0.85),
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: trendColour.withValues(alpha: 0.13),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: trendColour,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ((current - 1.0) / 9.0).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              color: barColour,
            ),
          ),
        ],
      ),
    );
  }

  // ── Healing score ring ─────────────────────────────────────────────────────
  Widget _healingScoreRing(double score) {
    final pct = score / 100.0;
    final colour = score >= 70
        ? const Color(0xFF66BB6A)
        : score >= 40
        ? const Color(0xFFFFB74D)
        : const Color(0xFFEF5350);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Maturity Score',
          style: TextStyle(
            fontSize: 10.5,
            color: MyApp.textBrown.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: pct,
                strokeWidth: 9,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(colour),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score.round().toString(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colour,
                    ),
                  ),
                  Text(
                    '/100',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: MyApp.textBrown.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _photoWidget(
    Uint8List? bytes, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) =>
            _photoPlaceholder(width: width, height: height),
      );
    }
    return _photoPlaceholder(width: width, height: height);
  }

  Widget _photoPlaceholder({double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade100,
      child: Center(
        child: Icon(
          Icons.photo_outlined,
          color: MyApp.goldShimmer.withValues(alpha: 0.32),
          size: 34,
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, [String? eyebrow]) {
    return ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow);
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05).copyWith(
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: MyApp.goldShimmer.withValues(alpha: 0.11),
            ),
            child: Icon(icon, color: MyApp.goldShimmer, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: MyApp.textBrown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricPill(String label, String value, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colour.withValues(alpha: 0.24)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(color: MyApp.textBrown.withValues(alpha: 0.60)),
            ),
            TextSpan(
              text: value,
              style: TextStyle(fontWeight: FontWeight.bold, color: colour),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color colour, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: MyApp.textBrown.withValues(alpha: 0.60),
          ),
        ),
      ],
    );
  }

  Widget _photoLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Insight model ─────────────────────────────────────────────────────────────
// -- Metrics Entry Dialog -----------------------------------------------------
class _MetricsEntryDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final int initialConcernLevel;
  final String? initialProcedureId;
  final String? initialProcedureName;
  final String? initialProcedureTag;
  final List<Map<String, dynamic>> procedures;
  final bool isBaseline; // true = first photo for this procedure
  final int? editIndex;
  final void Function(
    int concernLevel,
    String? procedureId,
    String? procedureName,
    String? procedureTag,
  )
  onSave;

  const _MetricsEntryDialog({
    required this.imageBytes,
    required this.initialConcernLevel,
    required this.onSave,
    required this.procedures,
    this.initialProcedureId,
    this.initialProcedureName,
    this.initialProcedureTag,
    this.isBaseline = false,
    this.editIndex,
  });

  @override
  State<_MetricsEntryDialog> createState() => _MetricsEntryDialogState();
}

class _MetricsEntryDialogState extends State<_MetricsEntryDialog> {
  late int _concernLevel;
  String? _selectedProcedureId;
  String? _selectedProcedureName;
  late TextEditingController _tagController;

  @override
  void initState() {
    super.initState();
    _concernLevel = widget.initialConcernLevel;
    _selectedProcedureId = widget.initialProcedureId;
    _selectedProcedureName = widget.initialProcedureName;
    _tagController = TextEditingController(
      text: widget.initialProcedureTag ?? '',
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MyApp.goldShimmer.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.healing_outlined,
                    color: MyApp.goldShimmer,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isBaseline
                            ? 'Establish Baseline'
                            : 'Log Scar Metrics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: MyApp.textBrown,
                        ),
                      ),
                      Text(
                        widget.isBaseline
                            ? 'This will be locked as your permanent baseline'
                            : widget.editIndex != null
                            ? 'Recalculate metrics from this entry photo'
                            : 'Metrics are auto-calculated from photo comparison',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: MyApp.textBrown.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(
              color: MyApp.goldShimmer.withValues(alpha: 0.15),
              height: 20,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA5D6A7)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isBaseline
                          ? 'Baseline metrics will be generated automatically from this photo.'
                          : 'No manual sliders. Metrics and trend arrows are generated from visual differences between baseline and this photo.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: MyApp.textBrown.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // -- Procedure selector ------------------------------------------
            if (widget.procedures.isNotEmpty && widget.editIndex == null) ...[
              Text(
                'Link to Procedure',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: MyApp.textBrown,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: MyApp.goldShimmer.withValues(alpha: 0.30),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedProcedureId,
                    hint: const Text('Select a procedure (optional)'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None / Unlinked'),
                      ),
                      ...widget.procedures.map((p) {
                        final id = p['id'] as String;
                        final type = p['type'] as String? ?? 'Procedure';
                        final rawDate = p['startDate'] as String?;
                        final date = rawDate != null
                            ? DateTime.tryParse(rawDate)
                            : null;
                        final label = date != null
                            ? '$type (${date.day}/${date.month}/${date.year})'
                            : type;
                        return DropdownMenuItem<String?>(
                          value: id,
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedProcedureId = val;
                        if (val != null) {
                          final proc = widget.procedures
                              .cast<Map<String, dynamic>?>()
                              .firstWhere(
                                (p) => p!['id'] == val,
                                orElse: () => null,
                              );
                          _selectedProcedureName = proc?['type'] as String?;
                        } else {
                          _selectedProcedureName = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // -- Procedure tag (free text: what was done today) --------------
            Text(
              'Procedure / Treatment Tag',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: MyApp.textBrown,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional: note any treatment done at this session',
              style: TextStyle(
                fontSize: 11.5,
                color: MyApp.textBrown.withValues(alpha: 0.50),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _tagController,
              decoration: InputDecoration(
                hintText:
                    'e.g. Silicone gel applied, Scar massage, IPL session',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade400,
                ),
                prefixIcon: Icon(
                  Icons.medical_services_outlined,
                  size: 18,
                  color: MyApp.goldShimmer.withValues(alpha: 0.6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: MyApp.goldShimmer.withValues(alpha: 0.30),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: MyApp.goldShimmer.withValues(alpha: 0.20),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: MyApp.goldShimmer, width: 1.5),
                ),
              ),
            ),
            Divider(
              color: MyApp.goldShimmer.withValues(alpha: 0.15),
              height: 24,
            ),
            Text(
              'The scar profile (redness, texture, elevation proxy, color match, pliability, itchiness proxy, pain proxy) will be generated on save using image processing.',
              style: TextStyle(
                fontSize: 12,
                color: MyApp.textBrown.withValues(alpha: 0.68),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Overall Concern Level',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: MyApp.textBrown,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(10, (i) {
                final n = i + 1;
                final sel = _concernLevel == n;
                final clr = n <= 3
                    ? const Color(0xFF66BB6A)
                    : n <= 6
                    ? const Color(0xFFFFB74D)
                    : const Color(0xFFEF5350);
                return GestureDetector(
                  onTap: () => setState(() => _concernLevel = n),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: sel ? clr : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: sel ? clr : Colors.grey.shade300,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white : MyApp.textBrown,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: MyApp.goldShimmer.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: MyApp.goldShimmer),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.goldShimmer,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    onPressed: () {
                      widget.onSave(
                        _concernLevel,
                        _selectedProcedureId,
                        _selectedProcedureName,
                        _tagController.text.trim().isEmpty
                            ? null
                            : _tagController.text.trim(),
                      );
                      Navigator.pop(context);
                    },
                    child: Text(
                      widget.editIndex != null
                          ? 'Update Metrics'
                          : 'Save Entry',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Insight {
  final IconData icon;
  final Color colour;
  final String title;
  final String body;
  const _Insight({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
  });
}

// -- Voice Journal Recorder ----------------------------------------------------

enum _RecordState { idle, recording, paused, done }

class _VoiceJournalRecorder extends StatefulWidget {
  final void Function(String transcript, Uint8List? audioBytes) onSave;
  const _VoiceJournalRecorder({required this.onSave});

  @override
  State<_VoiceJournalRecorder> createState() => _VoiceJournalRecorderState();
}

class _VoiceJournalRecorderState extends State<_VoiceJournalRecorder>
    with SingleTickerProviderStateMixin {
  // -- Recording --------------------------------------------------------------
  final AudioRecorder _recorder = AudioRecorder();
  _RecordState _state = _RecordState.idle;
  int _elapsedSeconds = 0;
  Timer? _timer;
  Uint8List? _audioBytes;
  String? _error;
  bool _saving = false;

  // -- Waveform animation -----------------------------------------------------
  late AnimationController _waveCtrl;

  // -- Speech-to-text (bonus auto-transcribe) ---------------------------------
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _dictating = false;
  final TextEditingController _transcriptCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize(
      onError: (_) {},
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => _dictating = false);
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = ok);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveCtrl.dispose();
    _transcriptCtrl.dispose();
    _speech.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // -- Recording controls -----------------------------------------------------

  Future<void> _startRecording() async {
    setState(() => _error = null);
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 16000,
          bitRate: 64000,
        ),
        path: '', // web: path is ignored; stop() returns blob URL
      );
      setState(() {
        _state = _RecordState.recording;
        _elapsedSeconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
    } catch (e) {
      final msg = e.toString().toLowerCase();
      setState(() {
        _error =
            (msg.contains('permission') ||
                msg.contains('denied') ||
                msg.contains('notallowed'))
            ? 'Microphone access was denied.\nPlease allow microphone permission in your browser settings and try again.'
            : 'Could not start recording.\nCheck that your microphone is connected and try again.';
      });
    }
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    _timer?.cancel();
    setState(() => _state = _RecordState.paused);
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    setState(() => _state = _RecordState.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    // Fetch audio bytes from blob URL (web)
    if (path != null && path.isNotEmpty && kIsWeb) {
      try {
        final bytes = await readWebBlobBytes(path);
        if (mounted && bytes != null) _audioBytes = bytes;
      } catch (_) {
        // Audio bytes not critical � transcript is still saved
      }
    }
    if (mounted) setState(() => _state = _RecordState.done);
  }

  Future<void> _reRecord() async {
    _timer?.cancel();
    _speech.cancel();
    await _recorder.cancel();
    if (mounted) {
      setState(() {
        _state = _RecordState.idle;
        _elapsedSeconds = 0;
        _audioBytes = null;
        _error = null;
        _dictating = false;
        _transcriptCtrl.clear();
      });
    }
  }

  // -- Dictation (STT bonus) --------------------------------------------------

  Future<void> _startDictation() async {
    if (!_speechAvailable || _dictating) return;
    setState(() {
      _dictating = true;
      _error = null;
    });
    await _speech.listen(
      onResult: (result) {
        if (mounted) {
          setState(() => _transcriptCtrl.text = result.recognizedWords);
        }
      },
      listenFor: const Duration(minutes: 3),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _stopDictation() async {
    await _speech.stop();
    if (mounted) setState(() => _dictating = false);
  }

  // -- Helpers ----------------------------------------------------------------

  String get _timeLabel {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 28,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // -- Header ------------------------------------------------------
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: MyApp.goldShimmer.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    color: MyApp.goldShimmer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _state == _RecordState.done
                            ? 'Recording Complete'
                            : 'Voice Journal',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: MyApp.goldShimmer,
                        ),
                      ),
                      Text(
                        _state == _RecordState.idle
                            ? 'Tap the mic to start recording'
                            : _state == _RecordState.recording
                            ? 'Recording in progress�'
                            : _state == _RecordState.paused
                            ? 'Recording paused'
                            : 'Add a transcript and save',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: MyApp.textBrown.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // -- Error banner -------------------------------------------------
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mic_off_outlined,
                      color: Colors.red.shade400,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // -- Waveform -----------------------------------------------------
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: _state == _RecordState.recording
                    ? MyApp.goldShimmer.withValues(alpha: 0.05)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _state == _RecordState.recording
                      ? MyApp.goldShimmer.withValues(alpha: 0.25)
                      : Colors.grey.shade200,
                ),
              ),
              child: _buildWaveform(),
            ),

            const SizedBox(height: 14),

            // -- Timer --------------------------------------------------------
            Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 5,
                  color: _state == _RecordState.recording
                      ? MyApp.goldShimmer
                      : MyApp.textBrown.withValues(alpha: 0.4),
                ),
                child: Text(_timeLabel),
              ),
            ),

            const SizedBox(height: 20),

            // -- Control buttons ----------------------------------------------
            if (_state == _RecordState.idle) ...[
              _bigMicButton(
                icon: Icons.mic_rounded,
                label: 'Start Recording',
                onTap: _startRecording,
              ),
            ] else if (_state == _RecordState.recording) ...[
              Row(
                children: [
                  Expanded(
                    child: _controlButton(
                      icon: Icons.pause_rounded,
                      label: 'Pause',
                      onTap: _pauseRecording,
                      outlined: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _controlButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      onTap: _stopRecording,
                    ),
                  ),
                ],
              ),
            ] else if (_state == _RecordState.paused) ...[
              Row(
                children: [
                  Expanded(
                    child: _controlButton(
                      icon: Icons.fiber_manual_record_rounded,
                      label: 'Resume',
                      onTap: _resumeRecording,
                      outlined: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _controlButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      onTap: _stopRecording,
                    ),
                  ),
                ],
              ),
            ] else if (_state == _RecordState.done) ...[
              // -- Transcript -------------------------------------------------
              Row(
                children: [
                  Text(
                    'Transcript',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MyApp.textBrown.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  if (_speechAvailable)
                    GestureDetector(
                      onTap: _dictating ? _stopDictation : _startDictation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _dictating
                              ? MyApp.goldShimmer.withValues(alpha: 0.12)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _dictating
                                ? MyApp.goldShimmer.withValues(alpha: 0.45)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dictating
                                  ? Icons.stop_circle_outlined
                                  : Icons.record_voice_over_outlined,
                              size: 13,
                              color: _dictating
                                  ? MyApp.goldShimmer
                                  : MyApp.textBrown.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _dictating ? 'Stop' : 'Auto-Transcribe',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _dictating
                                    ? MyApp.goldShimmer
                                    : MyApp.textBrown.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _transcriptCtrl,
                decoration: InputDecoration(
                  hintText: _speechAvailable
                      ? 'Add notes, or tap Auto-Transcribe to dictate�'
                      : 'Add a transcript (optional)�',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: MyApp.textBrown.withValues(alpha: 0.35),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: MyApp.goldShimmer.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _reRecord,
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Re-record'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.textBrown.withValues(alpha: 0.6),
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() => _saving = true);
                              widget.onSave(
                                _transcriptCtrl.text.trim(),
                                _audioBytes,
                              );
                            },
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 16),
                      label: Text(_saving ? 'Saving�' : 'Save Voice Note'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.goldShimmer,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // -- Waveform widget --------------------------------------------------------

  Widget _buildWaveform() {
    return AnimatedBuilder(
      animation: _waveCtrl,
      builder: (_, __) {
        final t = _waveCtrl.value;
        final isRec = _state == _RecordState.recording;
        final isPaused = _state == _RecordState.paused;
        return Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(24, (i) {
              final double amp = isRec ? 0.58 : 0.07;
              final double speed = isRec ? 2.8 : 0.9;
              final double phase = i * 0.44;
              final double base = isRec ? 0.42 : 0.16;
              final double h =
                  (math.sin(t * speed * 2 * math.pi + phase) * amp + base)
                      .clamp(0.05, 1.0);
              final double barH = 64.0 * (isPaused ? 0.14 : h);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3.5,
                height: barH,
                decoration: BoxDecoration(
                  color: isRec
                      ? MyApp.goldShimmer.withValues(
                          alpha: (0.45 + h * 0.55).clamp(0.0, 1.0),
                        )
                      : MyApp.goldShimmer.withValues(
                          alpha: isPaused ? 0.28 : 0.20,
                        ),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // -- Button helpers ---------------------------------------------------------

  Widget _bigMicButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              MyApp.goldShimmer.withValues(alpha: 0.10),
              MyApp.goldShimmer.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.28)),
        ),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MyApp.goldShimmer.withValues(alpha: 0.14),
              ),
              child: Icon(icon, size: 34, color: MyApp.goldShimmer),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: MyApp.goldShimmer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool outlined = false,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: MyApp.goldShimmer,
          side: BorderSide(color: MyApp.goldShimmer.withValues(alpha: 0.55)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: MyApp.goldShimmer,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }
}
