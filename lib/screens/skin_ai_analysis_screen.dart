// lib/screens/skin_ai_analysis_screen.dart
//
// Dedicated "Skin AI Analysis" experience — a clean, full-page flow
// launched directly from the home shortcut row. Intentionally NOT
// nested inside the Acne & Rosacea Tracker so that users get a fast,
// focused capture → analyze → results experience without the tabbed
// tracker context.
//
// Stages:
//   1. capture   — photo source picker (camera, gallery, latest scan),
//                  minimal region/context selector, "Run AI Analysis"
//                  button.
//   2. analyzing — loader with progress copy.
//   3. results   — clinical results view rendering analyzer output.
//
// The analysis engine itself is the shared `AcneRosaceaPhotoAnalyzer`,
// so derivations and scoring stay consistent with the tracker.

import 'dart:convert' show base64Decode, base64Encode, jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/acne_rosacea_log.dart';
import '../models/scan_history.dart';
import '../services/skin_history_repository.dart';
import '../utils/acne_rosacea_photo_analysis.dart';
import '../utils/ai/skin_analysis_model.dart';
import '../utils/ai/skin_analysis_runner.dart';
import '../utils/ai/skin_detections.dart';
import '../utils/app_logger.dart';
import '../utils/app_prefs.dart';
import '../utils/skin_analysis_service.dart' as remote_analysis;
import '../utils/procedure_intelligence.dart' as procedure_intel;
import '../utils/procedure_metric_set.dart';
import '../utils/skin_metric_labels.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/image_crop_dialog.dart';
import '../widgets/luxe_report_layout.dart';
import '../widgets/skin_heatmap_overlay.dart';
import '../widgets/smart_narrative_container.dart';

class SkinAiAnalysisScreen extends StatefulWidget {
  const SkinAiAnalysisScreen({super.key});

  @override
  State<SkinAiAnalysisScreen> createState() => _SkinAiAnalysisScreenState();
}

enum _Stage { capture, analyzing, results }

class _SkinAiAnalysisScreenState extends State<SkinAiAnalysisScreen> {
  static const String _manualBaselinePrefsKey =
      'skin_ai_manual_baseline_metric_matrix_v1';

  _Stage _stage = _Stage.capture;

  String? _imagePath;

  /// Cropped JPEG bytes from the mandatory crop step (camera/gallery). When
  /// non-null these exact bytes are what the analyzer receives — never the
  /// uncropped original. A "latest scan" selection leaves this null and is
  /// read from its stored path instead.
  Uint8List? _croppedBytes;

  /// The user must explicitly accept the pre-analysis disclaimer before the
  /// "Run AI Analysis" button unlocks. This is a hard gate, not a checkbox
  /// that can be skipped.
  bool _consentAccepted = false;
  FacialRegion? _region;
  bool _cycleRelated = false;
  bool _adultOnset = false;

  /// Validation message shown beneath the focus-area chips when the user
  /// attempts to run analysis without first selecting a focus area.
  String? _focusAreaError;

  PhotoAnalysisResult? _result;
  ModelInfo _modelInfo = ModelInfo.fallback;
  double? _modelConfidence;
  Set<String> _modelOwnedMetrics = const {};
  bool _meshUsed = false;
  double? _symmetryScore;
  double? _faceCoverage;
  bool _yoloUsed = false;
  List<Detection> _detections = const [];
  bool _efficientNetUsed = false;
  SkinQualityScores? _qualityScores;
  String? _analysisError;
  ScanHistoryEntry? _latestScan;
  ScanHistoryEntry? _ghostReferenceScan;
  bool _loadingLatest = true;
  bool _saved = false;
  bool? _timelineSaved = false;
  bool _ghostOverlayEnabled = true;
  String? _selectedProcedureId;
  String? _selectedProcedureType;
  String? _selectedProcedureFocusArea;
  String? _selectedProcedureCustomDescription;
  static const double _ghostOverlayOpacity = 0.20;

  /// Canonical metric map used by timeline/result rendering. In the
  /// server-first flow this is populated from backend metric-matrix
  /// values and normalized to 0-1 for shared timeline math.
  Map<String, double> _fullMetrics = const {};

  /// The 6 metrics from the most recent PREVIOUS scan, captured before
  /// the current scan is persisted. Used to draw improvement/worsening
  /// trend indicators in the results card. Empty when there is no prior
  /// scan to compare against (first-ever analysis).
  Map<String, double> _previousMetrics = const {};
  ScanHistoryEntry? _previousFocusAreaScan;
  ScanHistoryEntry? _baselineFocusAreaScan;
  bool _hasPriorFocusAreaScan = false;
  bool _explicitBaselineSelection = false;
  Map<String, double> _serverTrendDeltas = const {};
  Map<String, double>? _manualBaselineMetricMatrix;
  bool _awaitingBaselineOnboarding = true;

  @override
  void initState() {
    super.initState();
    _loadLatestScan();
    _loadProcedureContext();
    _loadPersistedManualBaseline();
    _refreshFocusAreaPhaseHint();
  }

  Future<void> _refreshFocusAreaPhaseHint() async {
    try {
      final focus = _normalizeFocus(_resolvedFocusArea());
      final scans = await SkinHistoryRepository.instance.getAllScans();
      final hasAny = scans.any((scan) {
        final scanFocus = _normalizeFocus(scan.focusArea);
        if (focus.isNotEmpty && scanFocus != focus) return false;
        final raw = scan.metrics;
        return SkinHistoryRepository.allMetricKeys.any(raw.containsKey) ||
            const [
              'fatRetention',
              'swelling',
              'firmness',
              'smoothness',
              'scarringBruising',
              'hyperpigmentation',
              'overallHealingScore',
            ].any(raw.containsKey);
      });
      if (!mounted) return;
      setState(() {
        _hasPriorFocusAreaScan = hasAny;
      });
    } catch (_) {
      // Keep existing phase hint if history lookup fails.
    }
  }

  Future<void> _loadPersistedManualBaseline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_manualBaselinePrefsKey)?.trim();
      if (raw == null || raw.isEmpty) {
        if (!mounted) return;
        setState(() {
          _manualBaselineMetricMatrix = null;
          _awaitingBaselineOnboarding = true;
        });
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        if (!mounted) return;
        setState(() {
          _manualBaselineMetricMatrix = null;
          _awaitingBaselineOnboarding = true;
        });
        return;
      }

      final matrix = <String, double>{};
      decoded.forEach((key, value) {
        final parsed = _safeToDouble(value);
        if (parsed == null) return;
        matrix[key.toString()] = parsed;
      });

      if (!mounted) return;
      setState(() {
        _manualBaselineMetricMatrix = matrix.isEmpty ? null : matrix;
        _awaitingBaselineOnboarding = matrix.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _manualBaselineMetricMatrix = null;
        _awaitingBaselineOnboarding = true;
      });
    }
  }

  double? _safeToDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Future<void> _persistManualBaselineMetricMatrix(
    Map<String, double> matrix,
  ) async {
    if (matrix.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_manualBaselinePrefsKey, jsonEncode(matrix));
    if (!mounted) return;
    setState(() {
      _manualBaselineMetricMatrix = Map<String, double>.from(matrix);
      _awaitingBaselineOnboarding = false;
    });
  }

  Future<void> _handleBaselineReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_manualBaselinePrefsKey);
    if (!mounted) return;
    setState(() {
      _manualBaselineMetricMatrix = null;
      _awaitingBaselineOnboarding = true;
      _serverTrendDeltas = const {};
    });
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Skin Baseline?'),
          content: const Text(
            'This will set your next scan as your new permanent benchmark. '
            'Future scans will measure progress from this point forward.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: MyApp.clinicalSlate),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _handleBaselineReset();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.softTerracotta,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset Baseline'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadProcedureContext() async {
    try {
      final selectedId = (await AppPrefs.getSelectedProcedureIdOrNull())
          ?.trim();
      final entries = await AppPrefs.getProcedureEntries();
      String? procedureType;
      if (selectedId?.isNotEmpty == true) {
        for (final entry in entries) {
          final id = (entry['id'] ?? entry['procedureId'] ?? '')
              .toString()
              .trim();
          if (id != selectedId) continue;
          final type = (entry['type'] ?? entry['procedure'] ?? '')
              .toString()
              .trim();
          if (type.isNotEmpty) {
            procedureType = type;
          }
          final focusArea = (entry['focusArea'] ?? '').toString().trim();
          final customDescription = (entry['customDescription'] ?? '')
              .toString()
              .trim();
          if (!mounted) return;
          setState(() {
            _selectedProcedureId = selectedId;
            _selectedProcedureType = procedureType;
            _selectedProcedureFocusArea = focusArea.isNotEmpty
                ? focusArea
                : null;
            _selectedProcedureCustomDescription = customDescription.isNotEmpty
                ? customDescription
                : null;
          });
          _refreshFocusAreaPhaseHint();
          return;
        }
      }
      final storedProcedureType = (await AppPrefs.getProcedureType()).trim();
      procedureType ??= storedProcedureType.isNotEmpty
          ? storedProcedureType
          : null;
      if (!mounted) return;
      setState(() {
        _selectedProcedureId = selectedId?.isNotEmpty == true
            ? selectedId
            : null;
        _selectedProcedureType = procedureType;
      });
      _refreshFocusAreaPhaseHint();
    } catch (_) {
      // Procedure context is optional; facial Skin AI remains the fallback.
    }
  }

  bool get _isBodyProcedure =>
      procedure_intel.ProcedureIntelligence.categoryFor(
        _selectedProcedureType,
      ) ==
      procedure_intel.ProcedureCategory.bodyContouring;

  bool get _isFullFaceFocusSelected {
    if (_region == FacialRegion.fullFace) return true;
    final focus = _normalizeFocus(_resolvedFocusArea());
    return focus == 'full face';
  }

  bool get _showCoreFaceMetricSetOnly =>
      !_isBodyProcedure && _isFullFaceFocusSelected;

  Future<void> _loadLatestScan() async {
    try {
      final scans = await AppPrefs.getScanEntries();
      final withPhoto =
          scans.where((s) => (s.imagePath ?? '').isNotEmpty).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _latestScan = withPhoto.isNotEmpty ? withPhoto.first : null;
        _ghostReferenceScan = withPhoto.isNotEmpty ? withPhoto.first : null;
        _loadingLatest = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLatest = false);
    }
  }

  // ── Photo source actions ──────────────────────────────────────────

  Future<void> _pickFromCamera() async {
    await _pickAndCrop(ImageSource.camera, 'Camera unavailable');
  }

  Future<void> _pickFromGallery() async {
    await _pickAndCrop(ImageSource.gallery, 'Could not open photo');
  }

  /// Picks an image then forces the shared [ImageCropDialog]. The analyzer
  /// only ever sees the cropped patch: on success [_croppedBytes] and a
  /// displayable [_imagePath] are set together; on cancel both are cleared
  /// so the "Run AI Analysis" button stays disabled.
  Future<void> _pickAndCrop(ImageSource source, String errorLabel) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2400,
      );
      if (picked == null || !mounted) return;

      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ImageCropDialog(imageBytes: rawBytes),
      );
      if (!mounted) return;
      if (cropped == null) {
        // User cancelled the cropper — keep everything cleared.
        setState(() {
          _imagePath = null;
          _croppedBytes = null;
        });
        return;
      }

      final stored = await _persistCroppedImage(cropped);
      if (!mounted) return;
      setState(() {
        _croppedBytes = cropped;
        _imagePath = stored;
        _explicitBaselineSelection = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$errorLabel: $e')));
    }
  }

  /// Persists cropped bytes to a displayable reference: a data URI on web
  /// (consumed by `Image.network`) or a durable file path on native
  /// (consumed by `Image.file`).
  Future<String> _persistCroppedImage(Uint8List bytes) async {
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final scansDir = Directory(
        '${docsDir.path}${Platform.pathSeparator}scans',
      );
      if (!await scansDir.exists()) {
        await scansDir.create(recursive: true);
      }

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final entropy = math.Random().nextInt(1 << 32);
      final filename = 'scan_${timestamp}_${entropy.toRadixString(16)}.jpg';
      final file = File('${scansDir.path}${Platform.pathSeparator}$filename');

      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on FileSystemException catch (e) {
      throw Exception(
        'Could not save scan photo to local storage. '
        'Please check app permissions and available disk space. '
        'Details: ${e.message}',
      );
    } catch (e) {
      throw Exception('Could not save scan photo: $e');
    }
  }

  void _useLatestAsBaseline() {
    final s = _latestScan;
    if (s == null || (s.imagePath ?? '').isEmpty) return;
    setState(() {
      _ghostReferenceScan = s;
      _explicitBaselineSelection = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Baseline reference updated from latest saved scan.'),
      ),
    );
  }

  ImageProvider<Object>? _ghostReferenceImageProvider() {
    if (!_ghostOverlayEnabled) return null;
    final referencePath = (_ghostReferenceScan?.imagePath ?? '').trim();
    final selectedPath = (_imagePath ?? '').trim();
    if (referencePath.isEmpty || referencePath == selectedPath) {
      return null;
    }
    return _imageProviderForPath(referencePath);
  }

  Widget _ghostSilhouetteLayer(ImageProvider<Object> provider) {
    return Opacity(
      opacity: _ghostOverlayOpacity,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Image(image: provider, fit: BoxFit.cover),
      ),
    );
  }

  // ── Run analysis ──────────────────────────────────────────────────

  /// Validates required inputs (focus area) before kicking off analysis.
  /// Surfaces an inline error instead of silently doing nothing so the
  /// user understands why the button did not proceed.
  void _onRunPressed() {
    if (_region == null) {
      setState(() {
        _focusAreaError =
            'Please select a focus area before generating your progress report.';
      });
      return;
    }
    setState(() => _focusAreaError = null);
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final path = _imagePath;
    if (path == null || path.isEmpty) return;
    setState(() {
      _stage = _Stage.analyzing;
      _analysisError = null;
    });

    try {
      PhotoFeatures features;
      Uint8List? imageBytes;
      try {
        // Prefer the in-memory cropped bytes; fall back to reading the path
        // (used by the "latest scan" source, which is already a capture).
        imageBytes = _croppedBytes ?? await XFile(path).readAsBytes();
        features = PhotoFeatureExtractor.extract(imageBytes);
      } catch (_) {
        features = PhotoFeatures.neutral();
      }

      var input = PhotoAnalysisInput.fromFeatures(
        imagePath: path,
        capturedAt: DateTime.now(),
        region: _region ?? FacialRegion.fullFace,
        features: features,
        cycleRelatedFlare: _cycleRelated,
        adultOnset: _adultOnset,
      );

      // ── Real AI inference (ML Kit Face Mesh + TFLite / TF.js) ──
      // FaceMesh crops to the face (Android/iOS only — passthrough on
      // web/desktop). TFLite then runs the ACNE04 classifier on the
      // cropped bytes. On any failure the rule engine still owns every
      // metric and the badge reflects which engines actually fired.
      final aug = await SkinAnalysisRunner.augment(
        baseInput: input,
        imageBytes: imageBytes,
      );
      input = aug.input;
      final ModelInfo modelInfo = aug.modelInfo;
      final double? modelConf = aug.modelConfidence;
      final Set<String> modelOwned = aug.modelOwnedMetrics;

      // Optional baseline from existing photo logs (for comparison block).
      AcneRosaceaLog? baseline;
      final Map<String, List<AcneRosaceaLog>> history =
          await AppPrefs.getAcneRosaceaLogs();
      final allWithPhotos =
          history.values
              .expand((x) => x)
              .where(
                (e) =>
                    e.hasPhoto &&
                    e.timestamp.isBefore(
                      input.capturedAt.subtract(const Duration(hours: 1)),
                    ),
              )
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (allWithPhotos.isNotEmpty) baseline = allWithPhotos.first;

      final report = AcneRosaceaPhotoAnalyzer.analyze(
        input: input,
        baselineSnapshot: baseline,
        history: history,
        confidence: SkinAnalysisRunner.resolveConfidence(
          featureConfidence: features.confidence,
          modelConfidence: modelConf,
        ),
        features: features,
      );

      final Map<String, double> previousMetrics = await _getPreviousMetrics();

      // Server-first execution: route this scan through the backend multipart
      // endpoint and parse canonical metrics + trend deltas from the payload.
      final backendBytes = imageBytes ?? await XFile(path).readAsBytes();
      final backendFile = XFile.fromData(
        backendBytes,
        name: 'skin_ai_analysis_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );
      final backendFields = <String, String>{
        if ((_selectedProcedureType ?? '').trim().isNotEmpty)
          'procedure_type': (_selectedProcedureType ?? '').trim(),
        if ((_selectedProcedureCustomDescription ?? '').trim().isNotEmpty)
          'skin_profile_note': (_selectedProcedureCustomDescription ?? '')
              .trim(),
        if (_resolvedFocusArea().trim().isNotEmpty)
          'selected_skin_profile_note': _resolvedFocusArea().trim(),
      };

      final backendResponse =
          await remote_analysis.SkinAnalysisService.uploadSingleImageFile(
            image: backendFile,
            fields: backendFields,
            baselineMetricMatrix:
                _manualBaselineMetricMatrix ??
                _baselineMetricMatrixForBackend(previousMetrics),
          );
      final parsedBackend = _parseBackendAnalysisPayload(backendResponse);
      final Map<String, double> fullMetrics = parsedBackend.fullMetrics;
      final Map<String, double> serverTrendDeltas =
          parsedBackend.serverTrendDeltas;

      if (_awaitingBaselineOnboarding || _manualBaselineMetricMatrix == null) {
        final seed = _extractBackendMetricMatrixSeed(backendResponse);
        if (seed.isNotEmpty) {
          await _persistManualBaselineMetricMatrix(seed);
        }
      }

      // Capture the most recent PREVIOUS scan's metrics BEFORE we
      // persist the current one, so the results card can show trend
      // arrows (improved / worsened) against the prior analysis.
      final timelineMetrics = _withTrendDeltaMetrics(
        _timelineMetricsFor(report, unifiedMetrics: fullMetrics),
        previousMetrics,
        serverTrendDeltas: serverTrendDeltas,
      );

      // Persist the full analysis to the Skin Tracker (and, via the
      // shared scan store, the Recovery Timeline). Falls back to the
      // rule-engine detections when the TFLite models produced nothing.
      bool savedToHistory = false;
      try {
        await SkinHistoryRepository.instance.saveScan(
          metrics: timelineMetrics,
          imagePath: path,
          timestamp: input.capturedAt,
          procedureId: _selectedProcedureId,
          procedure: _selectedProcedureType ?? 'AI Skin Analysis',
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          focusArea: _resolvedFocusArea(),
          customDescription: _selectedProcedureCustomDescription,
          estimatedSkinAge:
              estimateVisualSkinAgeFromAiMetrics(timelineMetrics) ?? 0,
        );
        savedToHistory = true;
      } catch (_) {
        // Non-fatal — the analysis still surfaces to the user.
      }

      if (!mounted) return;
      setState(() {
        _fullMetrics = fullMetrics;
        _previousMetrics = previousMetrics;
        _serverTrendDeltas = serverTrendDeltas;
        _result = report;
        _modelInfo = modelInfo;
        _modelConfidence = modelConf;
        _modelOwnedMetrics = modelOwned;
        _meshUsed = aug.meshUsed;
        _symmetryScore = aug.symmetryScore;
        _faceCoverage = aug.faceCoverage;
        _yoloUsed = aug.yoloUsed;
        _detections = aug.detections;
        _efficientNetUsed = aug.efficientNetUsed;
        _qualityScores = aug.qualityScores;
        _timelineSaved = savedToHistory;
        _stage = _Stage.results;
      });

      if (savedToHistory) {
        final storageWarning = await AppPrefs.consumeScanStorageWarning();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: storageWarning == null
                ? MyApp.clinicalTeal
                : const Color(0xFFBF8A30),
            content: Text(
              storageWarning ?? 'Saved to Skin Tracker & Recovery Timeline',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.capture;
        _analysisError = 'Analysis failed: $e';
      });
    }
  }

  // ── Save results to Acne & Rosacea Tracker ────────────────────────

  Future<void> _saveToTracker() async {
    final r = _result;
    if (r == null) return;
    final detected = r.detected;
    final imagePath = r.input.imagePath;
    final saveTrackerMetrics = !_saved;
    int saved = 0;
    bool addedToTimeline = false;
    if (saveTrackerMetrics) {
      for (final key in detected.keys) {
        final value = detected[key];
        if (value <= 0) continue;
        try {
          // Only attach the photo to the dominant (highest) metric so we
          // don't bloat storage with N copies of the same image path.
          final dominantKey = detected.values.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key;
          await AppPrefs.addAcneRosaceaLog(
            key,
            value,
            note: 'Saved from Skin AI Analysis',
            imagePath: key == dominantKey ? imagePath : '',
          );
          saved++;
        } catch (_) {}
      }
    }
    if (_timelineSaved != true) {
      try {
        // Recovery Timeline reads ScanHistoryEntry records. Skin AI Analysis
        // is not launched from a procedure flow, so we tag every saved scan
        // with a consistent, dedicated source id/label. The timeline's AI
        // Skin Analysis section keys off this id (and the legacy
        // `sourceSkinAiAnalysis` metric flag) so scans reliably appear after
        // pull-to-refresh via AppPrefs.getScanEntries().
        final timelineMetrics = _timelineMetricsFor(r);
        await AppPrefs.addScanEntry(
          ScanHistoryEntry(
            id: 'skinai_timeline_${DateTime.now().millisecondsSinceEpoch}',
            timestamp: r.input.capturedAt,
            imagePath: imagePath,
            procedureId: _selectedProcedureId,
            scanType: ScanHistoryEntry.scanTypeAiAnalysis,
            procedure: _selectedProcedureType ?? 'AI Skin Analysis',
            focusArea: _resolvedFocusArea(),
            customDescription: _selectedProcedureCustomDescription,
            estimatedSkinAge:
                estimateVisualSkinAgeFromAiMetrics(timelineMetrics) ?? 0,
            metrics: timelineMetrics,
          ),
        );
        addedToTimeline = true;
      } catch (_) {
        // Non-fatal: tracker save should still succeed even if timeline sync
        // cannot resolve a procedure target.
      }
    }
    if (!mounted) return;
    final storageWarning = await AppPrefs.consumeScanStorageWarning();
    if (!mounted) return;
    setState(() {
      _saved = true;
      _timelineSaved = (_timelineSaved ?? false) || addedToTimeline;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: storageWarning == null
            ? MyApp.clinicalTeal
            : const Color(0xFFBF8A30),
        content: Text(
          storageWarning ??
              (addedToTimeline
                  ? 'Saved to My Skin Tracker. Added to Recovery Timeline.'
                  : saved == 0
                  ? 'No detected metrics to save.'
                  : 'Saved $saved metric${saved == 1 ? '' : 's'} to My Skin Tracker.'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Map<String, double> _timelineMetricsFor(
    PhotoAnalysisResult r, {
    Map<String, double>? unifiedMetrics,
  }) {
    // Returns the strongest rule-engine score (0–10) for the given keys,
    // or null when none of them were detected/derived for this scan.
    double? detectedScore(List<String> keys) {
      double? best;
      for (final key in keys) {
        final raw = r.detected[key].toDouble();
        final score = raw.clamp(0, 10).toDouble();
        if (best == null || score > best) best = score;
      }
      return best;
    }

    final redness =
        detectedScore([
          'rosaceaSeverity',
          'rosaceaFlushing',
          'visibleBloodVessels',
        ]) ??
        0.0;
    final pigment =
        detectedScore(['postAcneScarring', 'visibleBloodVessels']) ?? 0.0;
    final texture =
        ((_qualityScores?.texture != null)
                ? (1 - _qualityScores!.texture!) * 10
                : detectedScore(['skinSensitivity', 'postAcneScarring']) ?? 0.0)
            .clamp(0, 10)
            .toDouble();
    final wrinkle = ((_qualityScores?.wrinkles ?? 0) * 10)
        .clamp(0, 10)
        .toDouble();

    // Prefer the unified 6-metric TFLite output when available (stored on
    // a 0–1 scale → ×10 for the timeline's 0–10 scale); otherwise fall
    // back to the rule-engine derived value so web / model-less scans
    // still populate every metric.
    double metric(String key, double fallback) {
      final v = unifiedMetrics?[key] ?? _fullMetrics[key];
      if (v == null) return fallback.clamp(0, 10).toDouble();
      return (v * 10).clamp(0, 10).toDouble();
    }

    final pigmentFinal = metric('pigment', pigment);
    final rednessFinal = metric('redness', redness);
    final textureFinal = metric('texture', texture);
    final wrinkleFinal = metric('wrinkle', wrinkle);
    // Fall back to the rule-engine inflammatory scores when the TFLite
    // models are unavailable (e.g. on web) so acne/rosacea don't save as 0.
    final acne = metric(
      'acne_severity',
      detectedScore([
            'acneSeverity',
            'cysticAcneSeverity',
            'hormonalAcneSeverity',
            'activeBreakouts',
            'acneCount',
          ]) ??
          0.0,
    );

    final rosacea = metric(
      'rosacea_intensity',
      detectedScore([
            'rosaceaSeverity',
            'rosaceaFlushing',
            'visibleBloodVessels',
            'erythema',
          ]) ??
          0.0,
    );

    final swelling =
        (rednessFinal * 0.50 + textureFinal * 0.30 + pigmentFinal * 0.20)
            .clamp(0, 10)
            .toDouble();
    final firmness =
        (10 - (textureFinal * 0.45 + wrinkleFinal * 0.20 + swelling * 0.15))
            .clamp(0, 10)
            .toDouble();
    final smoothness = (10 - textureFinal).clamp(0, 10).toDouble();
    final scarringBruising =
        (pigmentFinal * 0.45 + rednessFinal * 0.35 + textureFinal * 0.20)
            .clamp(0, 10)
            .toDouble();
    final fatRetention =
        (10 - (swelling * 0.30 + scarringBruising * 0.20 + textureFinal * 0.15))
            .clamp(0, 10)
            .toDouble();
    final overallHealing =
        ((10 - swelling) * 0.22 +
                firmness * 0.18 +
                smoothness * 0.16 +
                (10 - scarringBruising) * 0.18 +
                (10 - pigmentFinal) * 0.12 +
                fatRetention * 0.14)
            .clamp(0, 10)
            .toDouble();

    return {
      // Primary four requested timeline metrics.
      'pigment': pigmentFinal,
      'redness': rednessFinal,
      'texture': textureFinal,
      'wrinkle': wrinkleFinal,
      // Aliases consumed by existing recovery timeline insight helpers.
      'pigmentation': pigmentFinal,
      'darkSpots': pigmentFinal,
      'erythema': rednessFinal,
      'roughness': textureFinal,
      'wrinkles': wrinkleFinal,
      'rhytids': wrinkleFinal,
      // Inflammatory conditions — always written so the timeline can
      // render all six metrics (0.0 when the models produced nothing).
      'acne_severity': acne,
      'acneSeverity': acne,
      'rosacea_intensity': rosacea,
      'rosaceaSeverity': rosacea,
      'fatRetention': fatRetention,
      'fat_retention': fatRetention,
      'swelling': swelling,
      'edema': swelling,
      'firmness': firmness,
      'bodyFirmness': firmness,
      'skinLaxityFirmness': firmness,
      'smoothness': smoothness,
      'bodySmoothness': smoothness,
      'textureSmoothness': smoothness,
      'scarringBruising': scarringBruising,
      'scarring_bruising': scarringBruising,
      'bruising': scarringBruising,
      'hyperpigmentation': pigmentFinal,
      'overallHealingScore': overallHealing,
      'overall_healing_score': overallHealing,
      'bodyHealingScore': overallHealing,
      'sourceSkinAiAnalysis': 1,
    };
  }

  double? _trendMetricValueFromMap(Map<String, double> metrics, String key) {
    switch (key) {
      case 'localized_redness':
        return metrics['redness']?.clamp(0, 10).toDouble();
      case 'texture_smoothness':
        final texture = metrics['texture'];
        return texture == null ? null : (10 - texture).clamp(0, 10).toDouble();
      case 'pigment_load':
        return metrics['pigment']?.clamp(0, 10).toDouble();
      case 'wrinkle_load':
        return metrics['wrinkle']?.clamp(0, 10).toDouble();
      case 'overall_healing':
        return metrics['overallHealingScore']?.clamp(0, 10).toDouble();
      case 'swelling':
        return metrics['swelling']?.clamp(0, 10).toDouble();
      case 'smoothness':
        return metrics['smoothness']?.clamp(0, 10).toDouble();
      case 'scarring_bruising':
        return metrics['scarringBruising']?.clamp(0, 10).toDouble();
    }
    return metrics[key]?.clamp(0, 10).toDouble();
  }

  double? _percentDelta(double current, double? previous) {
    if (previous == null) return null;
    final denominator = previous.abs() < 0.1 ? 0.1 : previous.abs();
    return ((current - previous) / denominator) * 100.0;
  }

  Map<String, double> _withTrendDeltaMetrics(
    Map<String, double> current,
    Map<String, double> previous, {
    Map<String, double> serverTrendDeltas = const <String, double>{},
  }) {
    final enriched = <String, double>{...current};

    void writeDelta(String storageKey) {
      final currentValue = _trendMetricValueFromMap(current, storageKey);
      final previousValue = _trendMetricValueFromMap(previous, storageKey);
      if (currentValue == null || previousValue == null) return;
      final delta = _percentDelta(currentValue, previousValue);
      if (delta == null) return;
      enriched['trend_delta_${storageKey}_pct'] = delta;
    }

    if (_isBodyProcedure) {
      for (final key in const [
        'overall_healing',
        'swelling',
        'smoothness',
        'scarring_bruising',
      ]) {
        writeDelta(key);
      }
    } else {
      for (final key in const [
        'localized_redness',
        'texture_smoothness',
        'pigment_load',
        'wrinkle_load',
      ]) {
        writeDelta(key);
      }
    }

    if (serverTrendDeltas.isNotEmpty) {
      final keyMap = <String, String>{
        'localized_redness': 'trend_delta_localized_redness_pct',
        'texture_smoothness': 'trend_delta_texture_smoothness_pct',
        'pore_visibility': 'trend_delta_pore_visibility_pct',
        'breakout_activity': 'trend_delta_breakout_activity_pct',
        'pigment_load': 'trend_delta_pigment_load_pct',
        'wrinkle_load': 'trend_delta_wrinkle_load_pct',
        'overall_healing': 'trend_delta_overall_healing_pct',
        'swelling': 'trend_delta_swelling_pct',
        'smoothness': 'trend_delta_smoothness_pct',
        'scarring_bruising': 'trend_delta_scarring_bruising_pct',
      };
      for (final entry in keyMap.entries) {
        final value = serverTrendDeltas[entry.key];
        if (value == null) continue;
        enriched[entry.value] = value;
      }
    }

    return enriched;
  }

  Map<String, dynamic>? _asDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, double> _extractBackendMetricMatrixSeed(
    Map<String, dynamic> payload,
  ) {
    final metricsNode = _asDynamicMap(payload['metrics']) ?? payload;
    final metricMatrix =
        _asDynamicMap(payload['metric_matrix']) ??
        _asDynamicMap(metricsNode['metric_matrix']) ??
        const <String, dynamic>{};

    if (metricMatrix.isEmpty) return const {};

    final out = <String, double>{};
    for (final entry in metricMatrix.entries) {
      final parsed = _safeToDouble(entry.value);
      if (parsed == null || parsed.isNaN || parsed.isInfinite) continue;
      out[entry.key] = parsed.clamp(0.0, 100.0).toDouble();
    }
    return out;
  }

  ({Map<String, double> fullMetrics, Map<String, double> serverTrendDeltas})
  _parseBackendAnalysisPayload(Map<String, dynamic> payload) {
    final metricsNode = _asDynamicMap(payload['metrics']) ?? payload;
    final metricMatrix =
        _asDynamicMap(payload['metric_matrix']) ??
        _asDynamicMap(metricsNode['metric_matrix']) ??
        const <String, dynamic>{};
    final trendNode =
        _asDynamicMap(payload['trend_deltas']) ??
        _asDynamicMap(metricsNode['trend_deltas']) ??
        const <String, dynamic>{};

    double? number(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    final fullMetrics = <String, double>{};

    final rednessConcern = (() {
      final fromMatrix = number(metricMatrix['localized_redness']);
      if (fromMatrix != null) return (fromMatrix / 100).clamp(0.0, 1.0);
      final calibrated = number(metricsNode['calibrated_redness_score']);
      if (calibrated != null) {
        return ((100.0 - calibrated) / 100.0).clamp(0.0, 1.0);
      }
      return null;
    })();
    if (rednessConcern != null) {
      fullMetrics['redness'] = rednessConcern;
    }

    final textureConcern = (() {
      final smoothness = number(metricMatrix['texture_smoothness']);
      if (smoothness != null) {
        return ((100.0 - smoothness) / 100.0).clamp(0.0, 1.0);
      }
      final calibrated = number(metricsNode['calibrated_smoothness_score']);
      if (calibrated != null) {
        return ((100.0 - calibrated) / 100.0).clamp(0.0, 1.0);
      }
      return null;
    })();
    if (textureConcern != null) {
      fullMetrics['texture'] = textureConcern;
    }

    final poreConcern = number(metricMatrix['pore_visibility']);
    if (poreConcern != null) {
      fullMetrics['pore'] = (poreConcern / 100).clamp(0.0, 1.0);
    }

    final breakoutConcern = number(metricMatrix['breakout_activity']);
    if (breakoutConcern != null) {
      fullMetrics['acne_severity'] = (breakoutConcern / 100).clamp(0.0, 1.0);
    }

    final pigmentConcern = number(metricMatrix['pigment_load']);
    if (pigmentConcern != null) {
      fullMetrics['pigment'] = (pigmentConcern / 100).clamp(0.0, 1.0);
    }

    final wrinkleConcern = number(metricMatrix['wrinkle_load']);
    if (wrinkleConcern != null) {
      fullMetrics['wrinkle'] = (wrinkleConcern / 100).clamp(0.0, 1.0);
    }

    final mappedTrend = <String, double>{};
    for (final entry in trendNode.entries) {
      final parsed = number(entry.value);
      if (parsed == null) continue;
      mappedTrend[entry.key] = parsed;
    }

    return (fullMetrics: fullMetrics, serverTrendDeltas: mappedTrend);
  }

  Map<String, dynamic>? _baselineMetricMatrixForBackend(
    Map<String, double> previous,
  ) {
    if (previous.isEmpty) return null;

    final out = <String, dynamic>{};
    final redness = previous['redness'];
    if (redness != null) {
      out['localized_redness'] = (redness * 10).clamp(0.0, 100.0);
    }
    final texture = previous['texture'];
    if (texture != null) {
      out['texture_smoothness'] = ((10 - texture) * 10).clamp(0.0, 100.0);
    }
    final pore = previous['pore'];
    if (pore != null) {
      out['pore_visibility'] = (pore * 10).clamp(0.0, 100.0);
    }
    final acne = previous['acne_severity'];
    if (acne != null) {
      out['breakout_activity'] = (acne * 10).clamp(0.0, 100.0);
    }
    final pigment = previous['pigment'];
    if (pigment != null) {
      out['pigment_load'] = (pigment * 10).clamp(0.0, 100.0);
    }
    final wrinkle = previous['wrinkle'];
    if (wrinkle != null) {
      out['wrinkle_load'] = (wrinkle * 10).clamp(0.0, 100.0);
    }
    return out.isEmpty ? null : out;
  }

  Map<String, double> _bodyRecoveryScoresFor(Map<String, double> scores) {
    final pigment = (scores['pigment'] ?? 0).clamp(0, 10).toDouble();
    final redness = (scores['redness'] ?? 0).clamp(0, 10).toDouble();
    final texture = (scores['texture'] ?? 0).clamp(0, 10).toDouble();
    final wrinkle = (scores['wrinkle'] ?? 0).clamp(0, 10).toDouble();

    final swelling = (redness * 0.50 + texture * 0.30 + pigment * 0.20)
        .clamp(0, 10)
        .toDouble();
    final firmness = (10 - (texture * 0.45 + wrinkle * 0.20 + swelling * 0.15))
        .clamp(0, 10)
        .toDouble();
    final smoothness = (10 - texture).clamp(0, 10).toDouble();
    final scarringBruising = (pigment * 0.45 + redness * 0.35 + texture * 0.20)
        .clamp(0, 10)
        .toDouble();
    final fatRetention =
        (10 - (swelling * 0.30 + scarringBruising * 0.20 + texture * 0.15))
            .clamp(0, 10)
            .toDouble();
    final overallHealing =
        ((10 - swelling) * 0.22 +
                firmness * 0.18 +
                smoothness * 0.16 +
                (10 - scarringBruising) * 0.18 +
                (10 - pigment) * 0.12 +
                fatRetention * 0.14)
            .clamp(0, 10)
            .toDouble();

    return {
      'fatRetention': fatRetention,
      'fat_retention': fatRetention,
      'swelling': swelling,
      'edema': swelling,
      'firmness': firmness,
      'bodyFirmness': firmness,
      'skinLaxityFirmness': firmness,
      'smoothness': smoothness,
      'bodySmoothness': smoothness,
      'textureSmoothness': smoothness,
      'scarringBruising': scarringBruising,
      'scarring_bruising': scarringBruising,
      'bruising': scarringBruising,
      'hyperpigmentation': pigment,
      'overallHealingScore': overallHealing,
      'overall_healing_score': overallHealing,
      'bodyHealingScore': overallHealing,
    };
  }

  String _bodyMetricStorageKey(String label) {
    switch (label) {
      case 'Fat Retention':
        return 'fatRetention';
      case 'Swelling':
        return 'swelling';
      case 'Skin Laxity / Firmness':
        return 'firmness';
      case 'Texture / Smoothness':
        return 'smoothness';
      case 'Scarring / Bruising':
        return 'scarringBruising';
      case 'Hyperpigmentation':
        return 'hyperpigmentation';
      case 'Overall Healing Score':
        return 'overallHealingScore';
      default:
        return label;
    }
  }

  void _startOver() {
    setState(() {
      _stage = _Stage.capture;
      _imagePath = null;
      _croppedBytes = null;
      _result = null;
      _saved = false;
      _timelineSaved = false;
      _analysisError = null;
      _fullMetrics = const {};
      _previousMetrics = const {};
      _previousFocusAreaScan = null;
      _baselineFocusAreaScan = null;
      _explicitBaselineSelection = false;
    });
    _refreshFocusAreaPhaseHint();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground,
        elevation: 0.5,
        iconTheme: IconThemeData(color: MyApp.clinicalNavy),
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.26),
                    AppColors.cardBackground,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.42),
                  width: 0.6,
                ),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.champagneGold,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Skin Progress Tracking',
              style: TextStyle(
                color: MyApp.clinicalNavy,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actions: [
          if (_stage == _Stage.results)
            IconButton(
              tooltip: 'New progress report',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _startOver,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.capture => _buildCaptureStage(),
          _Stage.analyzing => _buildAnalyzingStage(),
          _Stage.results => _buildResultsStage(),
        },
      ),
    );
  }

  // ── Stage 1: capture ──────────────────────────────────────────────

  Widget _buildCaptureStage() {
    // Run stays disabled until BOTH a photo is ready (camera/gallery photos
    // always pass through the mandatory crop step) AND the user has accepted
    // the pre-analysis disclaimer.
    final canRun = (_imagePath ?? '').isNotEmpty && _consentAccepted;
    final actionLabel = _capturePrimaryActionLabel();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _heroIntro(),
        const SizedBox(height: 18),
        if (_analysisError != null) ...[
          _errorBanner(_analysisError!),
          const SizedBox(height: 14),
        ],
        _captureSectionCard(
          title: '1. Select Baseline Reference',
          eyebrow: 'Clinical setup',
          icon: Icons.history_toggle_off_rounded,
          child: _ghostReferenceScan?.imagePath?.trim().isNotEmpty == true
              ? _ghostOverlayCard()
              : _baselineSetupEmptyCard(),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '2. Capture Current Follow-Up Photo',
          eyebrow: 'Current scan input',
          icon: Icons.photo_camera_rounded,
          child: _photoPickerCard(),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '3. Tracking Scope & Context',
          eyebrow: 'Progress tracking settings',
          icon: Icons.tune_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _regionCard(),
              if (_focusAreaError != null) ...[
                const SizedBox(height: 8),
                _focusAreaErrorNote(_focusAreaError!),
              ],
              const SizedBox(height: 10),
              _contextCard(),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _captureSectionCard(
          title: '4. Clinical Context & Consent',
          eyebrow: 'Required before report generation',
          icon: Icons.verified_user_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _consentGateCard(),
              const SizedBox(height: 12),
              _legalDisclaimerCard(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _runButton(canRun, actionLabel),
        const SizedBox(height: 14),
        _disclaimerFootnote(),
      ],
    );
  }

  String _capturePrimaryActionLabel() {
    final isBaselineMode =
        _explicitBaselineSelection ||
        _awaitingBaselineOnboarding ||
        !_hasPriorFocusAreaScan;
    return isBaselineMode ? 'Save as Baseline' : 'Generate Progress Report';
  }

  Widget _heroIntro() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warmAlabaster.withValues(alpha: 0.6),
                    width: 0.8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timeline_rounded,
                      size: 11,
                      color: AppColors.onChampagneGold,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'PROGRESS TRACKING',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        color: AppColors.onChampagneGold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Unified Clinical Skin Tracking',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.refinedSlate,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a baseline reference, capture a current follow-up photo, '
            'and generate one consistent clinical-style progress report with '
            'trend deltas, directional status, and before/after comparison.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD06B6B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD06B6B).withValues(alpha: 0.45),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFD06B6B),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFA84A4A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _captureSectionCard({
    required String title,
    required String eyebrow,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalSectionHeader(icon: icon, title: title, eyebrow: eyebrow),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _baselineSetupEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.26),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.history_rounded,
            size: 17,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _loadingLatest
                  ? 'Loading your latest saved scan for baseline reference...'
                  : 'No baseline reference selected yet. Use "Use Baseline" in the photo section to set your latest scan as the comparison baseline.',
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.84),
                fontSize: 11.3,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPickerCard() {
    final hasPhoto = (_imagePath ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhoto) _selectedPhotoPreview() else _photoPlaceholder(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _sourceTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Current Camera',
                  accent: AppColors.champagneGold,
                  filled: true,
                  onTap: _pickFromCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sourceTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Current Gallery',
                  accent: MyApp.clinicalTeal,
                  onTap: _pickFromGallery,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _sourceTile(
                  icon: Icons.history_toggle_off_rounded,
                  label: 'Use Baseline',
                  accent: MyApp.clinicalNavy,
                  enabled: !_loadingLatest && _latestScan != null,
                  onTap: _useLatestAsBaseline,
                ),
              ),
            ],
          ),
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: MyApp.clinicalTeal,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Current follow-up photo selected — ready for progress report.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: MyApp.clinicalTeal,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _imagePath = null;
                    _croppedBytes = null;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: MyApp.clinicalSlate,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text(
                    'Remove',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectedPhotoPreview() {
    final path = _imagePath!;
    final ghost = _ghostReferenceImageProvider();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            kIsWeb
                ? Image.network(path, fit: BoxFit.cover)
                : Image.file(File(path), fit: BoxFit.cover),
            if (ghost != null)
              IgnorePointer(child: _ghostSilhouetteLayer(ghost)),
            IgnorePointer(
              child: CustomPaint(
                painter: _ScanFramePainter(
                  color: AppColors.champagneGold.withValues(alpha: 0.85),
                  ringColor: AppColors.champagneGold.withValues(alpha: 0.10),
                ),
              ),
            ),
            if (ghost != null)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: const Text(
                    'Current follow-up',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() {
    final ghost = _ghostReferenceImageProvider();
    if (ghost == null) return const _PulsingScanFrame();

    return Container(
      height: 178,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.42),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.warmAlabaster),
            _ghostSilhouetteLayer(ghost),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.20),
                    AppColors.champagneGold.withValues(alpha: 0.10),
                  ],
                ),
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: _ScanFramePainter(
                  color: AppColors.champagneGold.withValues(alpha: 0.72),
                  ringColor: AppColors.champagneGold.withValues(alpha: 0.18),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Baseline silhouette ready',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Match eyes, nose, jaw, and distance',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: AppColors.refinedSlate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ghostOverlayCard() {
    final reference = _ghostReferenceScan;
    final provider =
        _ghostReferenceImageProvider() ??
        _imageProviderForPath(reference?.imagePath);
    if (reference == null || provider == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ghost silhouette overlay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ),
              Switch.adaptive(
                value: _ghostOverlayEnabled,
                onChanged: (value) => setState(() {
                  _ghostOverlayEnabled = value;
                }),
                activeThumbColor: AppColors.champagneGold,
              ),
            ],
          ),
          Text(
            'For follow-up and healing scans, reuse your most recent saved photo as a 20% silhouette guide so eye line, nose position, jaw width, and distance stay as repeatable as possible.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: AppColors.refinedSlate.withValues(alpha: 0.05),
                      ),
                      _ghostSilhouetteLayer(provider),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _ScanFramePainter(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.65,
                            ),
                            ringColor: AppColors.champagneGold.withValues(
                              alpha: 0.10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reference: ${reference.focusArea?.trim().isNotEmpty == true ? reference.focusArea!.trim() : 'previous saved scan'}\nTurn this on before a new capture to line up with your baseline image.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: MyApp.clinicalSlate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceTile({
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool enabled = true,
    bool filled = false,
  }) {
    final bg = filled ? accent : accent.withValues(alpha: 0.07);
    final fg = filled ? AppColors.onChampagneGold : accent;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: filled
                    ? AppColors.goldHover.withValues(alpha: 0.70)
                    : accent.withValues(alpha: 0.35),
                width: filled ? 1 : 0.7,
              ),
              boxShadow: filled
                  ? [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.34),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(icon, size: filled ? 22 : 20, color: fg),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: filled ? FontWeight.w900 : FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _regionCard() {
    const regions = FacialRegion.values;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in regions)
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: _region == r
                    ? [
                        BoxShadow(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.45,
                          ),
                          blurRadius: 14,
                          spreadRadius: 0.5,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: ChoiceChip(
                label: Text(_regionLabel(r)),
                selected: _region == r,
                onSelected: (_) {
                  setState(() {
                    _region = r;
                    _focusAreaError = null;
                  });
                  _refreshFocusAreaPhaseHint();
                },
                selectedColor: AppColors.champagneGold,
                backgroundColor: AppColors.cardBackground,
                side: BorderSide(
                  color: _region == r
                      ? AppColors.champagneGold
                      : AppColors.borders,
                  width: _region == r ? 1.8 : 0.8,
                ),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _region == r
                      ? AppColors.onChampagneGold
                      : AppColors.refinedSlate,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contextCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            value: _cycleRelated,
            onChanged: (v) => setState(() => _cycleRelated = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: MyApp.clinicalTeal,
            title: const Text(
              'Cycle-related flare',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Breakouts that follow your menstrual cycle.',
              style: TextStyle(fontSize: 11, color: MyApp.clinicalSlate),
            ),
          ),
          Divider(
            height: 1,
            color: MyApp.clinicalSlate.withValues(alpha: 0.15),
          ),
          SwitchListTile.adaptive(
            value: _adultOnset,
            onChanged: (v) => setState(() => _adultOnset = v),
            contentPadding: EdgeInsets.zero,
            activeThumbColor: MyApp.clinicalTeal,
            title: const Text(
              'Adult-onset acne',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              'Breakouts persisting past your mid-20s.',
              style: TextStyle(fontSize: 11, color: MyApp.clinicalSlate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _runButton(bool enabled, String label) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.goldHover,
              AppColors.champagneGold,
              AppColors.goldHover,
            ],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.55),
                    blurRadius: 28,
                    spreadRadius: 1,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? _onRunPressed : null,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timeline_rounded,
                    size: 20,
                    color: AppColors.onChampagneGold,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: AppColors.onChampagneGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _disclaimerFootnote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI-assisted observations — not a diagnosis and not a substitute '
            'for professional medical advice. Always consult a qualified '
            'healthcare professional for any concern, diagnosis, or treatment '
            'decision.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legalDisclaimerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.30),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.32),
              ),
            ),
            child: const Icon(
              Icons.health_and_safety_outlined,
              size: 16,
              color: AppColors.goldHover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Wellness tracking disclaimer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'AestheticSkinTracker is a personal wellness and tracking tool. '
                  'It is not a medical device, is not intended for diagnosis or '
                  'medical advice, and is not HIPAA compliant. Consult a qualified '
                  'healthcare professional for any medical concerns.',
                  style: TextStyle(
                    fontSize: 11.2,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.refinedSlate.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Non-dismissible pre-analysis consent. The user must explicitly accept
  /// before the "Run AI Analysis" button unlocks. Reinforces that this is
  /// not medical advice, not a diagnosis, and for personal tracking only.
  Future<void> _reviewConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.health_and_safety_outlined,
                  color: AppColors.champagneGold,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Before you continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _consentBullet(
                  Icons.info_outline_rounded,
                  'This is not medical advice',
                  'This tool does not diagnose any condition and is not a '
                      'substitute for a licensed dermatologist or physician.',
                ),
                _consentBullet(
                  Icons.auto_awesome_outlined,
                  'Educational & personal tracking only',
                  'Results are estimates generated from a photo to help you '
                      'observe and track changes over time — not to make '
                      'treatment decisions.',
                ),
                _consentBullet(
                  Icons.warning_amber_rounded,
                  'Photos can be misread',
                  'Lighting, angle, makeup and image quality all affect the '
                      'output. Findings may be incomplete or inaccurate.',
                ),
                _consentBullet(
                  Icons.local_hospital_outlined,
                  'Seek professional care',
                  'For any concern, changing or painful lesion, or a '
                      'persistent symptom, please consult a qualified '
                      'healthcare professional.',
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalSlate,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: MyApp.primaryGoldButton,
              child: const Text(
                'I Understand and Continue',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (accepted == true) setState(() => _consentAccepted = true);
  }

  Widget _consentBullet(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: MyApp.clinicalTeal),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Capture-stage gate: surfaces the consent requirement inline and unlocks
  /// the Run button only after the disclaimer is read and accepted.
  Widget _consentGateCard() {
    final accepted = _consentAccepted;
    final accent = accepted ? AppColors.mutedSage : AppColors.champagneGold;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: accepted ? null : _reviewConsent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 0.9,
            ),
          ),
          child: Row(
            children: [
              Icon(
                accepted ? Icons.verified_rounded : Icons.shield_outlined,
                color: accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accepted
                          ? 'Disclaimer accepted'
                          : 'Review the progress-tracking disclaimer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accepted
                          ? 'You can generate your progress report below. Tap “View” to read it again.'
                          : 'Required before report generation. Tap to read and accept.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: MyApp.textBrown.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              if (accepted)
                TextButton(
                  onPressed: _reviewConsent,
                  child: Text(
                    'View',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  /// Prominent top-of-results disclaimer. One of three repeated disclaimers
  /// (top, near the metrics banner, and footer) framing every result as a
  /// non-diagnostic, educational estimate.
  Widget _resultsTopDisclaimer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.mutedSage.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 18,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: MyApp.textBrown.withValues(alpha: 0.9),
                ),
                children: const [
                  TextSpan(
                    text:
                        'These are AI-assisted observations, not a diagnosis. ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'Results are estimates from a single photo and may be '
                        'inaccurate. They are for education and personal '
                        'tracking only — please consult a licensed '
                        'dermatologist for any medical concern.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stage 2: analyzing ────────────────────────────────────────────

  Widget _buildAnalyzingStage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LuxeScanningIndicator(),
            const SizedBox(height: 30),
            const Text(
              'Building your progress report…',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: AppColors.refinedSlate,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Reading redness, texture, pore and tone metrics for a unified '
              'clinical-style progress dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.refinedSlate.withValues(alpha: 0.66),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.champagneGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.30),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.goldHover,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'On-device AI · private & secure',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.refinedSlate.withValues(alpha: 0.80),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage 3: results ──────────────────────────────────────────────

  Widget _buildResultsStage() {
    final r = _result!;
    final isFollowUpPhase = _previousMetrics.isNotEmpty;
    final luxePayload = _buildLuxeResultsPayload(r);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _resultsTopDisclaimer(),
        const SizedBox(height: 14),
        _resultHeroCard(r),
        const SizedBox(height: 18),
        if (isFollowUpPhase) ...[
          ClinicalSectionHeader(
            icon: Icons.analytics_rounded,
            eyebrow: 'PROGRESS TRACKING',
            title: _isBodyProcedure
                ? 'Body recovery tracking dashboard'
                : _showCoreFaceMetricSetOnly
                ? 'Core skin-quality progress dashboard'
                : 'Skin progress dashboard',
          ),
          const SizedBox(height: 10),
          LuxeReportLayout(
            rawPayload: luxePayload,
            baselineImageProvider: _resultsBaselineImageProvider(r),
            currentImageProvider: _imageProviderForPath(r.input.imagePath),
            baselineLabel: 'Before Baseline',
            currentLabel: 'Current Follow-Up',
          ),
          const SizedBox(height: 18),
        ] else ...[
          const ClinicalSectionHeader(
            icon: Icons.flag_rounded,
            eyebrow: 'BASELINE SCAN',
            title: 'Clinical Baseline Summary',
          ),
          const SizedBox(height: 10),
          _baselinePhaseSummaryCard(),
          const SizedBox(height: 18),
        ],
        SmartNarrativeContainer(narrativeText: r.detectionSummary),
        const SizedBox(height: 18),
        if (r.isClear) ...[_clearStateCard(r), const SizedBox(height: 18)],
        if (!r.isClear) ...[
          const ClinicalSectionHeader(
            icon: Icons.assessment_rounded,
            eyebrow: 'PHOTO OBSERVATIONS',
            title: 'What the current scan highlighted',
          ),
          const SizedBox(height: 8),
          _aiModelBanner(),
          const SizedBox(height: 10),
          _scoreDirectionLegend(),
          const SizedBox(height: 10),
          _detectedMetricsCard(r),
          const SizedBox(height: 18),
        ],
        if (r.insights.isNotEmpty) ...[
          const ClinicalSectionHeader(
            icon: Icons.lightbulb_outline_rounded,
            eyebrow: 'EDUCATIONAL INSIGHTS',
            title: 'Progress-focused interpretation',
          ),
          const SizedBox(height: 10),
          _insightsCard(r),
          const SizedBox(height: 18),
        ],
        const ClinicalSectionHeader(
          icon: Icons.spa_rounded,
          eyebrow: 'PRODUCTS & ROUTINE',
          title: 'Recommended for Your Skin Today',
        ),
        const SizedBox(height: 10),
        _buildRecommendationsSection(r),
        const SizedBox(height: 18),
        if (r.procedures.isNotEmpty) ...[
          const ClinicalSectionHeader(
            icon: Icons.medical_services_outlined,
            eyebrow: 'GENERAL INFORMATION',
            title: 'Commonly Explored Procedures',
          ),
          const SizedBox(height: 10),
          _framingNote(
            'These are general options people commonly discuss with '
            'dermatologists. They are not personalized recommendations.',
          ),
          const SizedBox(height: 10),
          _proceduresCard(r),
          const SizedBox(height: 18),
        ],
        if (r.productCues.isNotEmpty) ...[
          const ClinicalSectionHeader(
            icon: Icons.science_outlined,
            eyebrow: 'GENERAL INFORMATION',
            title: 'Ingredients commonly discussed',
          ),
          const SizedBox(height: 10),
          _framingNote(
            'General educational information — not a personalised routine. '
            'Patch-test new products and check with a professional before '
            'combining actives.',
          ),
          const SizedBox(height: 10),
          _productCuesCard(r),
          const SizedBox(height: 18),
        ],
        if (isFollowUpPhase) _followUpActionsCard() else _baselineSaveCtaCard(),
        const SizedBox(height: 14),
        _disclaimerFootnote(),
      ],
    );
  }

  Widget _baselinePhaseSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.champagneGold,
              ),
              const SizedBox(width: 8),
              Text(
                'Baseline scan captured',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This scan establishes your reference point for this focus area. '
            'Take another scan in 2–4 weeks to unlock trend deltas, before/after comparison, and clinical progress curves.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _fullMetricsCard(),
        ],
      ),
    );
  }

  Widget _baselineSaveCtaCard() {
    final saved = _saved && (_timelineSaved ?? false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: saved ? null : _saveToTracker,
              icon: Icon(
                saved ? Icons.check_circle_rounded : Icons.bookmark_add_rounded,
                size: 17,
              ),
              label: Text(
                saved ? 'Baseline Saved' : 'Save as Baseline',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: saved
                    ? AppColors.mutedSage
                    : AppColors.champagneGold,
                foregroundColor: saved
                    ? Colors.white
                    : AppColors.onChampagneGold,
                disabledBackgroundColor: AppColors.mutedSage.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Take another photo in 2–4 weeks to unlock progress metrics, trend tracking, and before/after clinical comparison.',
            style: TextStyle(
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: MyApp.textBrown.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  Widget _followUpActionsCard() {
    final timelineSaved = _timelineSaved ?? false;
    final canRetryTimelineSave = _saved && !timelineSaved;
    final saveComplete = _saved && timelineSaved;
    final baselineDate = _baselineFocusAreaScan?.timestamp;
    final baselineLabel = baselineDate == null
        ? 'Baseline linked for this focus area.'
        : 'Baseline linked: ${baselineDate.toLocal().year}-${baselineDate.toLocal().month.toString().padLeft(2, '0')}-${baselineDate.toLocal().day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: saveComplete ? null : _saveToTracker,
              icon: Icon(
                saveComplete
                    ? Icons.check_circle_rounded
                    : Icons.update_rounded,
                size: 17,
              ),
              label: Text(
                saveComplete
                    ? 'Updated Scan Saved'
                    : canRetryTimelineSave
                    ? 'Save Updated Scan to Timeline'
                    : 'Save Updated Scan',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: saveComplete
                    ? AppColors.mutedSage
                    : AppColors.champagneGold,
                foregroundColor: saveComplete
                    ? Colors.white
                    : AppColors.onChampagneGold,
                disabledBackgroundColor: AppColors.mutedSage.withValues(
                  alpha: 0.75,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Before/After comparison above is linked to your baseline scan.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.compare_arrows_rounded, size: 16),
            label: const Text(
              'Compare to Baseline',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.clinicalNavy,
              side: BorderSide(
                color: AppColors.champagneGold.withValues(alpha: 0.45),
                width: 0.9,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            baselineLabel,
            style: TextStyle(
              fontSize: 11.2,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: MyApp.textBrown.withValues(alpha: 0.82),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _resultsBaselineImageProvider(PhotoAnalysisResult r) {
    final currentPath = r.input.imagePath.trim();

    final baselinePath = (_baselineFocusAreaScan?.imagePath ?? '').trim();
    if (baselinePath.isNotEmpty && baselinePath != currentPath) {
      return _imageProviderForPath(baselinePath);
    }

    final previousPath = (_previousFocusAreaScan?.imagePath ?? '').trim();
    if (previousPath.isNotEmpty && previousPath != currentPath) {
      return _imageProviderForPath(previousPath);
    }

    final ghostPath = (_ghostReferenceScan?.imagePath ?? '').trim();
    if (ghostPath.isNotEmpty && ghostPath != currentPath) {
      return _imageProviderForPath(ghostPath);
    }

    final latestPath = (_latestScan?.imagePath ?? '').trim();
    if (latestPath.isNotEmpty && latestPath != currentPath) {
      return _imageProviderForPath(latestPath);
    }

    return null;
  }

  Map<String, dynamic> _buildLuxeResultsPayload(PhotoAnalysisResult r) {
    final timeline = _timelineMetricsFor(r);

    double concern(String key) {
      return ((timeline[key] ?? 0) * 10).clamp(0.0, 100.0).toDouble();
    }

    final metricMatrix = <String, dynamic>{
      'localized_redness': concern('redness'),
      'texture_smoothness': (100 - concern('texture')).clamp(0.0, 100.0),
      'pigment_load': concern('pigment'),
      'wrinkle_load': concern('wrinkle'),
      'pore_visibility': concern('pore'),
      'breakout_activity': concern('acne_severity'),
    };

    final trendDeltas = <String, dynamic>{..._serverTrendDeltas};

    double? deltaPct(
      double current,
      double? baseline, {
      required bool lowerIsBetter,
    }) {
      if (baseline == null || baseline <= 0) return null;
      final raw = ((current - baseline) / baseline) * 100.0;
      return lowerIsBetter ? -raw : raw;
    }

    if (trendDeltas.isEmpty && _previousMetrics.isNotEmpty) {
      final currRedness = _trendMetricValueFromMap(
        timeline,
        'localized_redness',
      );
      final prevRedness = _trendMetricValueFromMap(
        _previousMetrics,
        'localized_redness',
      );
      final currTexture = _trendMetricValueFromMap(
        timeline,
        'texture_smoothness',
      );
      final prevTexture = _trendMetricValueFromMap(
        _previousMetrics,
        'texture_smoothness',
      );
      final currPigment = _trendMetricValueFromMap(timeline, 'pigment_load');
      final prevPigment = _trendMetricValueFromMap(
        _previousMetrics,
        'pigment_load',
      );
      final currWrinkle = _trendMetricValueFromMap(timeline, 'wrinkle_load');
      final prevWrinkle = _trendMetricValueFromMap(
        _previousMetrics,
        'wrinkle_load',
      );

      final dRedness = deltaPct(
        currRedness ?? 0,
        prevRedness,
        lowerIsBetter: true,
      );
      if (dRedness != null) trendDeltas['localized_redness'] = dRedness;
      final dTexture = deltaPct(
        currTexture ?? 0,
        prevTexture,
        lowerIsBetter: false,
      );
      if (dTexture != null) trendDeltas['texture_smoothness'] = dTexture;
      final dPigment = deltaPct(
        currPigment ?? 0,
        prevPigment,
        lowerIsBetter: true,
      );
      if (dPigment != null) trendDeltas['pigment_load'] = dPigment;
      final dWrinkle = deltaPct(
        currWrinkle ?? 0,
        prevWrinkle,
        lowerIsBetter: true,
      );
      if (dWrinkle != null) trendDeltas['wrinkle_load'] = dWrinkle;
    }

    return <String, dynamic>{
      'metric_matrix': metricMatrix,
      'trend_deltas': trendDeltas,
      'metrics': metricMatrix,
    };
  }

  // ── 6-metric breakdown (SkinAnalysisService) ──────────────────────

  /// Beautiful breakdown of the six unified metrics produced by
  /// [SkinAnalysisService]. Model outputs arrive on a 0–1 scale and are
  /// surfaced here on the app-wide 0–10 clinical scale, grouped into
  /// General Skin Quality (teal accents) and Inflammatory Conditions
  /// (red/pink accents to signal attention), topped with an overall
  /// skin-health score. When a previous scan exists, each metric shows a
  /// trend indicator (improved / worsened / stable) versus that scan.
  Widget _fullMetricsCard() {
    // Convert a stored 0–1 model output to the clinical 0–10 scale.
    double to10(String key) =>
        ((_fullMetrics[key] ?? 0) * 10).clamp(0, 10).toDouble();

    final pigment = to10('pigment');
    final redness = to10('redness');
    final texture = to10('texture');
    final wrinkle = to10('wrinkle');
    final acne = to10('acne_severity');
    final rosacea = to10('rosacea_intensity');
    final bool showCoreOnly = _showCoreFaceMetricSetOnly;
    final double? pore = _qualityScores?.pores == null
        ? null
        : ((1 - _qualityScores!.pores!) * 10).clamp(0, 10).toDouble();

    if (_isBodyProcedure) {
      final source = {
        'pigment': pigment,
        'redness': redness,
        'texture': texture,
        'wrinkle': wrinkle,
        'acne_severity': acne,
        'rosacea_intensity': rosacea,
      };
      final bodyScores = _bodyRecoveryScoresFor(source);
      final metricSet = getMetricsForProcedure(_selectedProcedureType);
      final skin = SkinMetrics(
        redness: redness,
        texture: texture,
        wrinkle: wrinkle,
        darkSpots: pigment,
        elasticity: (10 - (texture * 0.5 + wrinkle * 0.5))
            .clamp(0, 10)
            .toDouble(),
      );
      final healingScore = bodyScores['overallHealingScore'] ?? 0;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _overallHealthHeader(
              healingScore,
              title: 'OVERALL HEALING SCORE',
              description:
                  'Composite of swelling, firmness, smoothness, bruising, pigment, and contour stability.',
            ),
            const SizedBox(height: 18),
            _metricGroup(
              icon: Icons.monitor_heart_rounded,
              title: 'Body Recovery Metrics',
              accent: MyApp.clinicalTeal,
              rows: [
                for (final metric in metricSet.additional)
                  _buildMetricRowWithTrend(
                    label: metric.label,
                    metricKey: _bodyMetricStorageKey(metric.label),
                    value: metric.valueFor(skin, rawMetrics: bodyScores),
                    lowerIsBetter: metric.lowerIsBetter,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _framingNote(
              'Body recovery scores use a 0-10 scale with direction shown per metric. '
              'Higher is better for fat retention, firmness, smoothness, and overall healing; '
              'lower is better for swelling, bruising, and hyperpigmentation. Educational only - not a diagnosis.',
            ),
          ],
        ),
      );
    }

    // The four quality metrics are "higher = more concern", so overall
    // skin health is the inverse of their average (higher = healthier).
    final avgConcern = (pigment + redness + texture + wrinkle) / 4;
    final healthScore = (10 - avgConcern).clamp(0, 10).toDouble();

    // Accent palette: calm teal for general quality, attention-grabbing
    // coral/pink for inflammatory conditions.
    const inflammatoryAccent = Color(0xFFD06B6B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall skin-health gauge.
          _overallHealthHeader(healthScore),
          const SizedBox(height: 18),
          // Group 1 — general skin quality (teal accents).
          _metricGroup(
            icon: Icons.spa_rounded,
            title: 'General Skin Quality',
            accent: MyApp.clinicalTeal,
            rows: [
              _buildMetricRowWithTrend(
                label: 'Pigmentation',
                metricKey: 'pigment',
                value: pigment,
              ),
              _buildMetricRowWithTrend(
                label: 'Redness',
                metricKey: 'redness',
                value: redness,
              ),
              _buildMetricRowWithTrend(
                label: 'Texture',
                metricKey: 'texture',
                value: texture,
              ),
              _buildMetricRowWithTrend(
                label: 'Wrinkles',
                metricKey: 'wrinkle',
                value: wrinkle,
              ),
              if (pore != null)
                _buildMetricRowWithTrend(
                  label: 'Pores',
                  metricKey: 'pore',
                  value: pore,
                ),
            ],
          ),
          if (!showCoreOnly) ...[
            const SizedBox(height: 14),
            // Group 2 — inflammatory conditions (red/pink accents).
            _metricGroup(
              icon: Icons.local_fire_department_rounded,
              title: 'Inflammatory Conditions',
              eyebrow: 'NEEDS ATTENTION',
              accent: inflammatoryAccent,
              rows: [
                _buildMetricRowWithTrend(
                  label: 'Acne Severity',
                  metricKey: 'acne_severity',
                  value: acne,
                ),
                _buildMetricRowWithTrend(
                  label: 'Rosacea Intensity',
                  metricKey: 'rosacea_intensity',
                  value: rosacea,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _framingNote(
            showCoreOnly
                ? 'Full-face view is focused on core skin-quality metrics '
                      '(pigmentation, redness, texture, wrinkles, pores) for '
                      'cleaner trend tracking. Educational only — not a diagnosis.'
                : 'Scores use a 0–10 scale where higher = more pronounced. '
                      'Trend arrows compare against your most recent previous scan. '
                      'Overall skin health inverts the average of the four quality '
                      'metrics. Educational only — not a diagnosis.',
          ),
        ],
      ),
    );
  }

  /// Prominent gradient header showing the overall skin-health score
  /// (0–10, higher = healthier) with a circular gauge.
  Widget _overallHealthHeader(
    double score, {
    String title = 'OVERALL SKIN HEALTH',
    String description = 'Averaged from the four general skin-quality metrics.',
  }) {
    final pct = (score / 10).clamp(0.0, 1.0);
    final label = score >= 8
        ? 'Excellent'
        : score >= 6
        ? 'Good'
        : score >= 4
        ? 'Fair'
        : 'Needs care';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.clinicalNavy.withValues(alpha: 0.94),
            MyApp.clinicalTeal.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Circular gauge with the score centered inside.
          SizedBox(
            width: 66,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 66,
                  height: 66,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.20),
                    valueColor: AlwaysStoppedAnimation(MyApp.goldShimmer),
                  ),
                ),
                Text(
                  score.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w900,
                    color: MyApp.goldShimmer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$label · ${score.toStringAsFixed(2)} / 10',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Renders one accented metric group (a tinted, bordered container with
  /// an icon header) and lays out its [rows] with consistent spacing.
  Widget _metricGroup({
    required IconData icon,
    required String title,
    required Color accent,
    required List<Widget> rows,
    String? eyebrow,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow,
                        style: TextStyle(
                          fontSize: 8.5,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 1),
                    ],
                    Text(
                      title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w900,
                        color: MyApp.clinicalNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// A single 0–10 metric row with an optional trend indicator: label +
  /// trend chip, severity band, a 2-decimal value pill, and a
  /// colour-coded progress bar. Severity colours come from the shared
  /// [_valueColor] / [_severityBandForValue] helpers for consistency.
  Widget _buildMetricRowWithTrend({
    required String label,
    required String metricKey,
    required double value,
    bool lowerIsBetter = true,
  }) {
    final color = _directedValueColor(value, lowerIsBetter: lowerIsBetter);
    final band = _directedSeverityBand(value, lowerIsBetter: lowerIsBetter);
    final trend = _trendFor(metricKey, value, lowerIsBetter: lowerIsBetter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MyApp.clinicalNavy,
                      ),
                    ),
                  ),
                  if (trend != null) ...[
                    const SizedBox(width: 7),
                    _trendChip(trend),
                  ],
                ],
              ),
            ),
            Text(
              band.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${value.toStringAsFixed(2)} / 10',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value / 10).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  /// Compact trend pill: arrow icon + word (Improved / Worsened /
  /// Stable) plus the numeric delta for non-stable changes (e.g.
  /// "Improved +12%"). Green for improvement, coral for worsening, grey when
  /// stable.
  Widget _trendChip(
    ({
      IconData icon,
      Color color,
      String label,
      double delta,
      double percentDelta,
    })
    trend,
  ) {
    final isStable = trend.label == 'Stable';
    final deltaText = isStable
        ? ''
        : ' ${trend.percentDelta > 0 ? '+' : ''}${trend.percentDelta.toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: trend.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: trend.color.withValues(alpha: 0.35),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trend.icon, size: 10, color: trend.color),
          const SizedBox(width: 3),
          Text(
            '${trend.label}$deltaText',
            style: TextStyle(
              fontSize: 8.5,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w900,
              color: trend.color,
            ),
          ),
        ],
      ),
    );
  }

  /// Computes the trend for [metricKey] by comparing the current 0–10
  /// [current] value against the same metric from the previous scan.
  /// Returns null when there is no prior value to compare. All six
  /// metrics are "higher = worse", so a DROP is an improvement. The
  /// returned [delta] is the signed change (current - previous).
  ({
    IconData icon,
    Color color,
    String label,
    double delta,
    double percentDelta,
  })?
  _trendFor(String metricKey, double current, {bool lowerIsBetter = true}) {
    String? serverKeyForMetric(String key) {
      switch (key) {
        case 'redness':
          return 'localized_redness';
        case 'texture':
          return 'texture_smoothness';
        case 'pore':
          return 'pore_visibility';
        case 'acne_severity':
          return 'breakout_activity';
        case 'pigment':
          return 'pigment_load';
        case 'wrinkle':
          return 'wrinkle_load';
      }
      return null;
    }

    final serverKey = serverKeyForMetric(metricKey);
    if (serverKey != null) {
      final serverDelta = _serverTrendDeltas[serverKey];
      if (serverDelta != null) {
        if (serverDelta.abs() < 1.0) {
          return (
            icon: Icons.trending_flat_rounded,
            color: MyApp.clinicalSlate,
            label: 'Stable',
            delta: 0,
            percentDelta: serverDelta,
          );
        }
        final improved = lowerIsBetter ? serverDelta < 0 : serverDelta > 0;
        return (
          icon: improved
              ? (lowerIsBetter
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded)
              : (lowerIsBetter
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded),
          color: improved ? AppColors.mutedSage : AppColors.softTerracotta,
          label: improved ? 'Improved' : 'Worsened',
          delta: serverDelta,
          percentDelta: serverDelta,
        );
      }
    }

    final previous = _previousMetrics[metricKey];
    if (previous == null) return null;
    final delta = current - previous;
    final denominator = previous.abs() < 0.1 ? 0.1 : previous.abs();
    final percentDelta = (delta / denominator) * 100.0;
    // Ignore sub-0.25 wobble on the 0–10 scale to avoid noisy flips.
    if (delta.abs() < 0.25) {
      return (
        icon: Icons.trending_flat_rounded,
        color: MyApp.clinicalSlate,
        label: 'Stable',
        delta: delta,
        percentDelta: percentDelta,
      );
    }
    final improved = lowerIsBetter ? delta < 0 : delta > 0;
    if (improved) {
      return (
        icon: lowerIsBetter
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded,
        color: AppColors.mutedSage,
        label: 'Improved',
        delta: delta,
        percentDelta: percentDelta,
      );
    }
    return (
      icon: lowerIsBetter
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded,
      color: AppColors.softTerracotta,
      label: 'Worsened',
      delta: delta,
      percentDelta: percentDelta,
    );
  }

  Color _directedValueColor(double value, {required bool lowerIsBetter}) {
    if (lowerIsBetter) return _valueColor(value.round());
    if (value >= 8) return const Color(0xFF4FAE8B);
    if (value >= 6) return const Color(0xFF7AA874);
    if (value >= 4) return const Color(0xFFB89A6E);
    return const Color(0xFFC76A55);
  }

  String _directedSeverityBand(double value, {required bool lowerIsBetter}) {
    if (lowerIsBetter) return _severityBandForValue(value.round());
    if (value >= 8) return 'Strong';
    if (value >= 6) return 'Good';
    if (value >= 4) return 'Fair';
    return 'Low';
  }

  /// Reads the six metrics from the most recent PREVIOUS scan, normalised
  /// to the 0–10 scale so they can be compared against the current scan.
  /// Returns an empty map when no prior scan exists. Must be called
  /// BEFORE the current scan is persisted.
  /// The focus area persisted with the current scan. Prefers the active
  /// procedure's configured focus area, falling back to the region the user
  /// selected in the analysis screen. Used for both saving and same-region
  /// retrieval so before/after comparisons stay accurate.
  String _resolvedFocusArea() =>
      (_selectedProcedureFocusArea ??
              (_region == null ? '' : PhotoAnalysisUi.regionLabel(_region!)))
          .trim();

  /// Canonical key for comparing focus-area strings. Normalises case and
  /// collapses any internal/edge whitespace so visually-identical values
  /// like "Full Face", "Full face" and "full  face" all match.
  String _normalizeFocus(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<Map<String, double>> _getPreviousMetrics() async {
    try {
      _previousFocusAreaScan = null;
      _baselineFocusAreaScan = null;
      final focus = _normalizeFocus(_resolvedFocusArea());
      final scans = await SkinHistoryRepository.instance.getAllScans();
      final candidates = <ScanHistoryEntry>[];
      // getAllScans() is newest-first. We keep both edges:
      // - first: most recent prior scan (for trend deltas)
      // - last: earliest same-focus baseline (for before/after left frame)
      for (final scan in scans) {
        final scanFocus = _normalizeFocus(scan.focusArea);
        if (focus.isNotEmpty && scanFocus != focus) {
          continue;
        }
        final raw = scan.metrics;
        final hasAny =
            SkinHistoryRepository.allMetricKeys.any(
              (k) => raw.containsKey(k),
            ) ||
            const [
              'fatRetention',
              'swelling',
              'firmness',
              'smoothness',
              'scarringBruising',
              'hyperpigmentation',
              'overallHealingScore',
            ].any((k) => raw.containsKey(k));
        if (!hasAny) {
          continue;
        }
        candidates.add(scan);
      }

      if (candidates.isEmpty) return const {};

      _previousFocusAreaScan = candidates.first;
      _baselineFocusAreaScan = candidates.last;

      // Scans persisted by this service store 0–1 values; legacy /
      // fallback scans may already be 0–10. Normalise either way.
      double norm(double v) => (v <= 1.0 ? v * 10 : v).clamp(0, 10).toDouble();
      final raw = _previousFocusAreaScan!.metrics;
      return {for (final entry in raw.entries) entry.key: norm(entry.value)};
    } catch (_) {
      // Non-fatal — simply show no trend indicators.
    }
    _previousFocusAreaScan = null;
    _baselineFocusAreaScan = null;
    return const {};
  }

  List<
    ({
      String key,
      String label,
      double current,
      double previous,
      bool lowerIsBetter,
      Color color,
    })
  >
  _trendDeltaSeries() {
    final result = _result;
    if (result == null || _previousMetrics.isEmpty) return const [];
    final current = _timelineMetricsFor(result, unifiedMetrics: _fullMetrics);
    final specs = _isBodyProcedure
        ? <({String key, String label, bool lowerIsBetter, Color color})>[
            (
              key: 'overall_healing',
              label: 'Overall Healing',
              lowerIsBetter: false,
              color: MyApp.clinicalTeal,
            ),
            (
              key: 'swelling',
              label: 'Swelling',
              lowerIsBetter: true,
              color: const Color(0xFFC76A55),
            ),
            (
              key: 'smoothness',
              label: 'Texture Smoothness',
              lowerIsBetter: false,
              color: const Color(0xFF4FAE8B),
            ),
            (
              key: 'scarring_bruising',
              label: 'Scarring / Bruising',
              lowerIsBetter: true,
              color: const Color(0xFFB89A6E),
            ),
          ]
        : <({String key, String label, bool lowerIsBetter, Color color})>[
            (
              key: 'texture_smoothness',
              label: 'Texture Smoothness',
              lowerIsBetter: false,
              color: const Color(0xFF4FAE8B),
            ),
            (
              key: 'localized_redness',
              label: 'Localized Redness',
              lowerIsBetter: true,
              color: const Color(0xFFC76A55),
            ),
            (
              key: 'pigment_load',
              label: 'Pigment Load',
              lowerIsBetter: true,
              color: const Color(0xFFB89A6E),
            ),
            (
              key: 'wrinkle_load',
              label: 'Wrinkle Load',
              lowerIsBetter: true,
              color: const Color(0xFFD08A4A),
            ),
          ];

    final rows =
        <
          ({
            String key,
            String label,
            double current,
            double previous,
            bool lowerIsBetter,
            Color color,
          })
        >[];
    for (final spec in specs) {
      final currentValue = _trendMetricValueFromMap(current, spec.key);
      final previousValue = _trendMetricValueFromMap(
        _previousMetrics,
        spec.key,
      );
      if (currentValue == null || previousValue == null) continue;
      rows.add((
        key: spec.key,
        label: spec.label,
        current: currentValue,
        previous: previousValue,
        lowerIsBetter: spec.lowerIsBetter,
        color: spec.color,
      ));
    }
    return rows;
  }

  Widget _trendDeltaSummaryCard() {
    final series = _trendDeltaSeries();
    if (series.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows_rounded,
                size: 16,
                color: MyApp.clinicalTeal,
              ),
              const SizedBox(width: 8),
              Text(
                'Trend Deltas vs Baseline',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'These percentage shifts compare today\'s calibrated scan against your most recent same-area baseline, reducing noise from framing and lighting differences.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < series.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _trendDeltaRow(series[i]),
          ],
        ],
      ),
    );
  }

  Widget _trendDeltaRow(
    ({
      String key,
      String label,
      double current,
      double previous,
      bool lowerIsBetter,
      Color color,
    })
    item,
  ) {
    final deltaPct = _percentDelta(item.current, item.previous) ?? 0.0;
    final stable = deltaPct.abs() < 3.0;
    final improved = item.lowerIsBetter ? deltaPct < 0 : deltaPct > 0;
    final tone = stable
        ? MyApp.clinicalSlate
        : improved
        ? AppColors.mutedSage
        : AppColors.softTerracotta;
    final prefix = deltaPct > 0 ? '+' : '';
    final direction = stable
        ? 'Stable'
        : improved
        ? 'Improved'
        : 'Needs attention';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.22), width: 0.7),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$direction against baseline',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$prefix${deltaPct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultHeroCard(PhotoAnalysisResult r) {
    final confidence = (r.confidence * 100).round();
    final image = _imageProviderForPath(r.input.imagePath);
    final metrics = _singleScanMetricMap();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 0.78,
            child: image == null
                ? Container(
                    color: const Color(0xFF141821),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      size: 34,
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_fullMetrics.isNotEmpty)
                        SkinHeatmapOverlay.laser(
                          photo: image,
                          redness: _fullMetrics['redness'] ?? 0,
                          wrinkles: _fullMetrics['wrinkle'] ?? 0,
                          improvement: _fullMetrics['texture'] ?? 0,
                        )
                      else
                        Image(image: image, fit: BoxFit.cover),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.18),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.58),
                              ],
                              stops: const [0.0, 0.52, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: [
                            _heroBadge('Single Scan'),
                            const SizedBox(width: 8),
                            _heroBadge('$confidence% confidence'),
                            const Spacer(),
                            _heroBadge(r.severityBandLabel),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.headline,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              r.subheadline,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontSize: 12.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            color: const Color(0xFF151922),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Calibrated scan summary',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reset baseline benchmark',
                      onPressed: () => _showResetConfirmationDialog(context),
                      icon: Icon(
                        Icons.restart_alt_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                      splashRadius: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (_awaitingBaselineOnboarding) ...[
                  Text(
                    'Baseline onboarding mode: your next scan will become the benchmark.',
                    style: TextStyle(
                      color: AppColors.champagneGold.withValues(alpha: 0.9),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    _miniStat('Severity', r.severityIndex.toStringAsFixed(1)),
                    const SizedBox(width: 10),
                    _miniStat('Metrics', metrics.length.toString()),
                    const SizedBox(width: 10),
                    _miniStat(
                      'Mode',
                      _showCoreFaceMetricSetOnly ? 'Core face' : 'Full scan',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _singleScanMetricMap() {
    if (_fullMetrics.isNotEmpty) {
      final redness = (_fullMetrics['redness'] ?? 0) * 100;
      final wrinkles = (_fullMetrics['wrinkle'] ?? 0) * 100;
      final darkSpots = (_fullMetrics['pigment'] ?? 0) * 100;

      return <String, double>{
        'redness': redness.clamp(0, 100).toDouble(),
        'wrinkles': wrinkles.clamp(0, 100).toDouble(),
        'darkSpots': darkSpots.clamp(0, 100).toDouble(),
      };
    }

    // Backend / rule-analysis path: use the already-normalized timeline metric
    // projection (0..10) and map to the UI's 0..100 scale.
    final result = _result;
    if (result != null) {
      final timeline = _timelineMetricsFor(result);
      final redness = (timeline['redness'] ?? 0) * 10;
      final wrinkles = (timeline['wrinkle'] ?? 0) * 10;
      final darkSpots = (timeline['pigment'] ?? 0) * 10;

      return <String, double>{
        'redness': redness.clamp(0, 100).toDouble(),
        'wrinkles': wrinkles.clamp(0, 100).toDouble(),
        'darkSpots': darkSpots.clamp(0, 100).toDouble(),
      };
    }

    return <String, double>{'redness': 0, 'wrinkles': 0, 'darkSpots': 0};
  }

  Widget _severityChip(String label, double index) {
    final color = _severityColor(index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.6),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
          color: color,
        ),
      ),
    );
  }

  Widget _clearStateCard(PhotoAnalysisResult r) {
    final lowConf = r.isLowConfidence && !r.isClear;
    final accent = lowConf ? MyApp.clinicalSlate : const Color(0xFF4FAE8B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.10),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.40), width: 0.7),
      ),
      child: Row(
        children: [
          Icon(
            lowConf ? Icons.help_outline_rounded : Icons.verified_rounded,
            color: accent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lowConf
                      ? 'Low-confidence read'
                      : 'No significant issues detected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.detectionSummary,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detectedMetricsCard(PhotoAnalysisResult r) {
    final entries = r.detected.values.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(),
        child: Text(
          'No metrics scored above zero in this photo.',
          style: TextStyle(fontSize: 12, color: MyApp.clinicalSlate),
        ),
      );
    }
    final top = entries.first;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topFindingBanner(top.key, top.value),
          const SizedBox(height: 12),
          for (int i = 0; i < entries.length; i++) ...[
            if (i > 0)
              Divider(
                height: 18,
                color: MyApp.clinicalSlate.withValues(alpha: 0.12),
              ),
            _metricRow(
              entries[i].key,
              entries[i].value,
              r.derivations[entries[i].key],
            ),
          ],
          // Always surface post-acne marks / scarring (virtual metric,
          // not in the registry) when the analyzer detected any pigment
          // or textural residue. Clarifies that the AI IS seeing
          // something — just classifying it as scarring rather than
          // active disease.
          if ((r.derivations['postAcneScarring']?.score ?? 0) > 0) ...[
            Divider(
              height: 18,
              color: MyApp.clinicalSlate.withValues(alpha: 0.12),
            ),
            _metricRow(
              'postAcneScarring',
              r.derivations['postAcneScarring']!.score,
              r.derivations['postAcneScarring'],
            ),
          ],
        ],
      ),
    );
  }

  Widget _topFindingBanner(String key, int value) {
    final spec = SkinMetricRegistry.byKey(key);
    final label = spec?.clinicalName ?? key;
    final color = _valueColor(value);
    final band = _severityBandForValue(value);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.6),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: MyApp.textBrown.withValues(alpha: 0.92),
                ),
                children: [
                  const TextSpan(
                    text: 'MOST PROMINENT · ',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                  TextSpan(
                    text: '$label — $band ($value/10). ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(
                    text:
                        'This is what the photo emphasised most — a helpful '
                        'starting point for a conversation with a licensed '
                        'professional.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Honest-disclosure banner shown above the metrics. When a real AI
  /// model is loaded it surfaces the model name, dataset, and reported
  /// accuracy alongside a "research-grade, not diagnostic" caveat. When
  /// only the rule engine is active it explicitly says so.
  Widget _aiModelBanner() {
    final info = _modelInfo;
    final isAi = !info.isFallback;
    final meshUsed = _meshUsed;
    final yoloUsed = _yoloUsed;
    final effUsed = _efficientNetUsed;
    final anyEngine = isAi || meshUsed;
    final color = anyEngine ? MyApp.clinicalTeal : MyApp.clinicalSlate;
    final icon = anyEngine
        ? Icons.psychology_alt_rounded
        : Icons.calculate_rounded;
    final stack = <String>[
      if (meshUsed) 'ML Kit Face Mesh',
      if (yoloUsed) 'YOLOv8-Nano Lesion Detector',
      if (effUsed) 'EfficientNet-B0 Skin Quality',
      if (isAi && !yoloUsed && !effUsed) 'TensorFlow Lite',
    ];
    final headline = stack.isEmpty
        ? 'Analysis completed successfully'
        : 'Powered by ${stack.join(" + ")}';
    final confLine = (_modelConfidence != null)
        ? '  ·  Model confidence: ${(_modelConfidence! * 100).round()}%'
        : '';
    final meshLine = meshUsed
        ? '\nFace Mesh: '
              '${_faceCoverage != null ? "face covers ${(_faceCoverage! * 100).round()}% of frame" : "face cropped"}'
              '${_symmetryScore != null ? " · L/R symmetry ${(_symmetryScore! * 100).round()}%" : ""}'
        : '';
    final detLine = yoloUsed
        ? '\nYOLO: ${_detections.length} lesion${_detections.length == 1 ? "" : "s"} detected'
              '${_lesionBreakdown()}'
        : '';
    final qLine = (effUsed && _qualityScores != null)
        ? '\nEfficientNet: ${_qualitySummary(_qualityScores!)}'
        : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: color,
                  ),
                ),
              ),
              if (isAi)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isAi
                ? 'Dataset: ${info.dataset}\n'
                      'Accuracy: ${info.reportedAccuracy}\n'
                      'Backend: ${info.backend}$confLine$meshLine$detLine$qLine\n'
                      'Research-grade benchmark — NOT a diagnostic tool. Drives '
                      'only the active-acne score; rosacea, vessels, flushing, '
                      'sensitivity and scarring use evidence-informed heuristics.'
                : 'Your analysis has been generated successfully using the '
                      'configured backend pipeline.$meshLine$detLine$qLine',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.45,
              color: MyApp.textBrown.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI-assisted analysis — not a substitute for professional '
            'medical advice. Consult a board-certified dermatologist for '
            'diagnosis and treatment.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: MyApp.clinicalSlate,
            ),
          ),
        ],
      ),
    );
  }

  String _lesionBreakdown() {
    if (_detections.isEmpty) return '';
    final counts = <String, int>{};
    for (final d in _detections) {
      counts[d.label] = (counts[d.label] ?? 0) + 1;
    }
    final parts = counts.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.value} ${e.key}${e.value == 1 ? "" : "s"}')
        .toList();
    return parts.isEmpty ? '' : ' (${parts.join(", ")})';
  }

  String _qualitySummary(SkinQualityScores q) {
    int pct(double? v) => ((v ?? 0) * 100).round();
    final parts = <String>[
      if (q.overall != null) 'overall ${pct(q.overall)}%',
      if (q.texture != null) 'texture ${pct(q.texture)}%',
      if (q.wrinkles != null) 'wrinkles ${pct(q.wrinkles)}%',
      if (q.pores != null) 'pores ${pct(q.pores)}%',
      if (q.elasticity != null) 'elasticity ${pct(q.elasticity)}%',
    ];
    return parts.join(' \u00b7 ');
  }

  Widget _scoreDirectionLegend() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFC76A55).withValues(alpha: 0.08),
            const Color(0xFF4FAE8B).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.clinicalSlate.withValues(alpha: 0.20),
          width: 0.6,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.straighten_rounded, size: 14, color: MyApp.clinicalNavy),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: MyApp.textBrown.withValues(alpha: 0.92),
                ),
                children: const [
                  TextSpan(
                    text: 'How to read these scores: ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'higher = more prominent in this photo. Lower is '
                        'generally better. Each item below is a 0–10 visual '
                        'estimate, not a diagnosis or medical grade.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String key, int value, MetricDerivation? d) {
    final spec = SkinMetricRegistry.byKey(key);
    final label = key == 'postAcneScarring'
        ? 'Post-Acne Marks / Scarring'
        : (spec?.clinicalName ?? key);
    final color = _valueColor(value);
    final band = _severityBandForValue(value);
    final meaning = _metricMeaning(key);
    final isLowConf = (d?.confidence ?? 1.0) < 0.50;
    final fromModel = _modelOwnedMetrics.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: MyApp.clinicalNavy,
                          ),
                        ),
                      ),
                      if (fromModel) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: MyApp.clinicalTeal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'AI',
                            style: TextStyle(
                              fontSize: 8,
                              letterSpacing: 0.7,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.arrow_upward_rounded,
                        size: 10,
                        color: MyApp.clinicalSlate.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Higher = more severe',
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w700,
                          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$value / 10',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  band.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                if (isLowConf) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.clinicalSlate.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: MyApp.clinicalSlate.withValues(alpha: 0.35),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.help_outline_rounded,
                          size: 8,
                          color: MyApp.clinicalSlate,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'LOW CONFIDENCE',
                          style: TextStyle(
                            fontSize: 7.5,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w900,
                            color: MyApp.clinicalSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value / 10,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          meaning,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.45,
            color: MyApp.textBrown.withValues(alpha: 0.85),
          ),
        ),
        if (d != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.science_outlined,
                size: 11,
                color: MyApp.clinicalSlate,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${d.methodLabel} · ${d.methodDetail}',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Plain-English one-liner explaining what each acne/rosacea metric
  /// measures and reinforcing that higher numbers indicate a worse
  /// finding. Keyed by `SkinMetricRegistry.acneAndRosacea` keys.
  String _metricMeaning(String key) {
    switch (key) {
      case 'acneSeverity':
        return 'Overall density and intensity of active breakouts '
            '(papules + pustules) across the face. Higher = more '
            'active inflammation.';
      case 'cysticAcneSeverity':
        return 'Deep, painful nodules and cysts under the skin. '
            'Higher = larger or more clustered lesions that usually '
            'need prescription care.';
      case 'hormonalAcneSeverity':
        return 'Breakouts concentrated along the jawline, chin and '
            'lower face — the classic androgen-driven pattern. Higher '
            '= more lower-face involvement.';
      case 'rosaceaSeverity':
        return 'Persistent central-face redness and rosacea-pattern '
            'inflammation. Higher = stronger standing erythema.';
      case 'rosaceaFlushing':
        return 'Uneven, transient redness suggesting flushing '
            'episodes. Higher = more variable / reactive blush.';
      case 'visibleBloodVessels':
        return 'Telangiectasia — thin red vessels visible at the '
            'skin surface. Higher = more vessels (structural, '
            'usually treated with vascular laser / IPL).';
      case 'skinSensitivity':
        return 'Reactive-skin proxy from persistent redness + '
            'distribution variance. Higher = more likely to sting '
            'or react to actives. Hard to measure from a photo — '
            'override if you know how your skin actually feels.';
      case 'postAcneScarring':
        return 'Residual marks from PRIOR acne — post-inflammatory '
            'pigmentation (PIH) and surface texture changes. Distinct '
            'from active disease; treated with retinoids, peels, '
            'microneedling, or pigment-targeted laser.';
      default:
        return 'Higher scores indicate a more pronounced finding.';
    }
  }

  /// Severity band label matching the overall band convention used by
  /// the analyzer (Clear / Mild / Moderate / Marked / Severe).
  String _severityBandForValue(int v) {
    if (v <= 1) return 'Clear';
    if (v <= 3) return 'Mild';
    if (v <= 5) return 'Moderate';
    if (v <= 7) return 'Marked';
    return 'Severe';
  }

  Widget _insightsCard(PhotoAnalysisResult r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int i = 0; i < r.insights.length; i++) ...[
            if (i > 0)
              Divider(
                height: 18,
                color: MyApp.clinicalSlate.withValues(alpha: 0.12),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: r.insights[i].accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    r.insights[i].icon,
                    size: 16,
                    color: r.insights[i].accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.insights[i].title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        r.insights[i].detail,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: MyApp.textBrown.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecommendationsSection(PhotoAnalysisResult r) {
    final scores = _recommendationScoresFor(r);
    if (_isBodyProcedure) {
      return _buildBodyRecoveryRecommendationsSection(scores);
    }

    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final treatInflammationFirst = inflammation >= 4.0;

    final recommendations = _productRecommendationsForScores(scores);
    final routine = _routineForScores(scores);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.clinicalTeal.withValues(alpha: 0.13),
                  const Color(0xFFD06B6B).withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.20),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: MyApp.clinicalTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        treatInflammationFirst
                            ? 'Calm first, actives second'
                            : 'Support the strongest visible concerns',
                        style: TextStyle(
                          color: MyApp.clinicalNavy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        treatInflammationFirst
                            ? 'Inflammation-led scores are the priority today: redness ${redness.toStringAsFixed(1)}, rosacea ${rosacea.toStringAsFixed(1)}, acne ${acne.toStringAsFixed(1)}. Keep the routine calming before stronger exfoliating or brightening actives.'
                            : 'Today\'s routine is matched to pigmentation ${pigment.toStringAsFixed(1)}, texture ${texture.toStringAsFixed(1)}, and wrinkle ${wrinkle.toStringAsFixed(1)} scores while keeping the skin barrier steady.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          height: 1.42,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < recommendations.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _recommendationTile(recommendations[i], index: i + 1),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _routineColumn('AM', routine.$1, MyApp.clinicalTeal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _routineColumn(
                  'PM',
                  routine.$2,
                  const Color(0xFFD06B6B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _framingNote(
            'These are popular options that often help with similar concerns. '
            'Patch test new products, introduce one change at a time, and consult '
            'a professional if your skin is painful, worsening, or highly reactive.',
          ),
        ],
      ),
    );
  }

  Widget _buildBodyRecoveryRecommendationsSection(Map<String, double> scores) {
    final bodyScores = _bodyRecoveryScoresFor(scores);
    final swelling = bodyScores['swelling'] ?? 0;
    final bruising = bodyScores['scarringBruising'] ?? 0;
    final firmness = bodyScores['firmness'] ?? 0;
    final healing = bodyScores['overallHealingScore'] ?? 0;
    final subtype = procedure_intel.ProcedureIntelligence.bodyContouringSubtype(
      _selectedProcedureType,
    );
    final recommendations = _bodyProductRecommendationsForScores(
      bodyScores,
      subtype,
    );
    final routine = _bodyRoutineForScores(bodyScores, subtype);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.clinicalTeal.withValues(alpha: 0.13),
                  MyApp.goldShimmer.withValues(alpha: 0.10),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.20),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.monitor_heart_rounded,
                    color: MyApp.clinicalTeal,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        swelling >= 4 || bruising >= 4
                            ? 'Prioritize swelling and bruising control'
                            : 'Protect contour and healing momentum',
                        style: TextStyle(
                          color: MyApp.clinicalNavy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Body recovery readout: swelling ${swelling.toStringAsFixed(1)}, bruising/scarring ${bruising.toStringAsFixed(1)}, firmness ${firmness.toStringAsFixed(1)}, overall healing ${healing.toStringAsFixed(1)}. Follow your surgeon\'s restrictions first, then use supportive care consistently.',
                        style: TextStyle(
                          color: MyApp.textBrown.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          height: 1.42,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < recommendations.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _recommendationTile(recommendations[i], index: i + 1),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _routineColumn('AM', routine.$1, MyApp.clinicalTeal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _routineColumn('PM', routine.$2, MyApp.goldShimmer),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _framingNote(
            'Body recovery suggestions are supportive only. Do not start massage, arnica, scar products, or compression changes unless your surgeon has cleared them, especially after BBL, liposuction, or tummy tuck.',
          ),
        ],
      ),
    );
  }

  Map<String, double> _recommendationScoresFor(PhotoAnalysisResult r) {
    if (_fullMetrics.isNotEmpty) {
      double score(String key) =>
          ((_fullMetrics[key] ?? 0) * 10).clamp(0, 10).toDouble();
      return {
        'pigment': score('pigment'),
        'redness': score('redness'),
        'texture': score('texture'),
        'wrinkle': score('wrinkle'),
        'acne_severity': score('acne_severity'),
        'rosacea_intensity': score('rosacea_intensity'),
      };
    }

    final timeline = _timelineMetricsFor(r);
    double score(String key) => (timeline[key] ?? 0).clamp(0, 10).toDouble();
    return {
      'pigment': score('pigment'),
      'redness': score('redness'),
      'texture': score('texture'),
      'wrinkle': score('wrinkle'),
      'acne_severity': score('acne_severity'),
      'rosacea_intensity': score('rosacea_intensity'),
    };
  }

  List<({String title, String reason, IconData icon, Color accent})>
  _productRecommendationsForScores(Map<String, double> scores) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);

    final recs =
        <({String title, String reason, IconData icon, Color accent})>[];
    void add(String title, String reason, IconData icon, Color accent) {
      if (recs.any((r) => r.title == title)) return;
      if (recs.length < 6) {
        recs.add((title: title, reason: reason, icon: icon, accent: accent));
      }
    }

    if (inflammation >= 4) {
      add(
        'SKIN1004 Madagascar Centella Ampoule',
        'Best first step when redness/rosacea/acne are leading. Centella keeps the routine calming before stronger actives.',
        Icons.local_florist_rounded,
        MyApp.clinicalTeal,
      );
      add(
        'COSRX Advanced Snail 96 Mucin Essence',
        'A light barrier-support layer for reactive days; helpful when redness is ${redness.toStringAsFixed(1)} or texture feels stressed.',
        Icons.water_drop_outlined,
        MyApp.clinicalTeal,
      );
    }

    if (acne >= 3.5) {
      add(
        'COSRX Acne Pimple Master Patch',
        'Spot-focused support for active breakouts without adding an all-over active while inflammation is high.',
        Icons.radio_button_checked_rounded,
        const Color(0xFFD06B6B),
      );
      add(
        'Some By Mi AHA-BHA-PHA 30 Days Miracle Toner',
        'Consider only 1-2 nights weekly after skin feels calm; acne score ${acne.toStringAsFixed(1)} suggests pores may benefit from slow exfoliation.',
        Icons.science_outlined,
        const Color(0xFFD06B6B),
      );
    }

    if (rosacea >= 3.5 || redness >= 3.5) {
      add(
        'SKIN1004 Centella Probio-Cica Intensive Ampoule',
        'A richer cica option for redness/rosacea-prone days; pairs well with a simple moisturizer and SPF.',
        Icons.spa_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (pigment >= 3.5 || redness < 4 && acne < 4) {
      add(
        'COSRX The Niacinamide 15 Serum',
        'Niacinamide is a good bridge active for pigment ${pigment.toStringAsFixed(1)} and visible redness, but start slowly if skin is reactive.',
        Icons.tonality_rounded,
        MyApp.goldShimmer,
      );
    }

    if ((texture >= 3.5 || wrinkle >= 3.5) && inflammation < 6) {
      add(
        'Copper peptide serum / GHK-Cu peptide serum',
        'A barrier-friendly PM option for texture ${texture.toStringAsFixed(1)} and wrinkle ${wrinkle.toStringAsFixed(1)} support without jumping straight to harsh actives.',
        Icons.grain_rounded,
        MyApp.clinicalNavy,
      );
    }

    add(
      'COSRX Balancium Comfort Ceramide Cream',
      'A gentle barrier-repair moisturizer to buffer actives and keep redness, acne, and texture routines easier to tolerate.',
      Icons.shield_outlined,
      MyApp.clinicalTeal,
    );
    add(
      'Daily broad-spectrum SPF 30+',
      'SPF is the quiet workhorse for pigment, redness, and collagen support. Use it every morning, especially with niacinamide or exfoliating acids.',
      Icons.wb_sunny_outlined,
      MyApp.goldShimmer,
    );

    return recs.take(6).toList();
  }

  List<({String title, String reason, IconData icon, Color accent})>
  _bodyProductRecommendationsForScores(
    Map<String, double> scores,
    procedure_intel.ProcedureBodyContouringSubtype subtype,
  ) {
    final swelling = scores['swelling'] ?? 0;
    final bruising = scores['scarringBruising'] ?? 0;
    final pigment = scores['hyperpigmentation'] ?? 0;
    final firmness = scores['firmness'] ?? 0;
    final recs =
        <({String title, String reason, IconData icon, Color accent})>[];

    void add(String title, String reason, IconData icon, Color accent) {
      if (recs.any((r) => r.title == title)) return;
      if (recs.length < 6) {
        recs.add((title: title, reason: reason, icon: icon, accent: accent));
      }
    }

    add(
      'Surgeon-approved compression garment',
      'Compression is the anchor for swelling control and contour support. Keep fit smooth and even; avoid rolling, bunching, or pressure points.',
      Icons.checkroom_outlined,
      MyApp.clinicalTeal,
    );

    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl) {
      add(
        'BBL pillow / no-pressure positioning',
        'For BBL recovery, protect transferred fat by avoiding direct sitting pressure until your surgeon clears it.',
        Icons.airline_seat_recline_extra_rounded,
        MyApp.goldShimmer,
      );
    }

    if (swelling >= 3.5) {
      add(
        'Manual lymphatic drainage when cleared',
        'Swelling ${swelling.toStringAsFixed(1)} suggests lymphatic support may help, but timing matters. Start only after surgical clearance.',
        Icons.waves_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (bruising >= 3.5) {
      add(
        'Arnica gel or oral arnica if approved',
        'Bruising/scarring ${bruising.toStringAsFixed(1)} makes arnica a reasonable supportive option if it is safe with your medications and surgeon protocol.',
        Icons.local_florist_outlined,
        const Color(0xFFD06B6B),
      );
    }

    if (firmness < 6) {
      add(
        'Gentle walking and hydration routine',
        'Firmness ${firmness.toStringAsFixed(1)} can reflect swelling or tissue tightness. Short walks and hydration support circulation without stressing incisions.',
        Icons.directions_walk_rounded,
        MyApp.clinicalTeal,
      );
    }

    if (pigment >= 3.5) {
      add(
        'Silicone scar care plus SPF on exposed areas',
        'Pigment ${pigment.toStringAsFixed(1)} suggests marks need protection. Use silicone only on closed, healed incisions and protect exposed areas from UV.',
        Icons.healing_outlined,
        MyApp.goldShimmer,
      );
    }

    add(
      'Protein-forward meals and electrolyte support',
      'Adequate protein, fluids, and electrolytes support wound healing and reduce the temptation to overcorrect swelling with aggressive massage or activity.',
      Icons.restaurant_menu_rounded,
      MyApp.clinicalNavy,
    );

    return recs.take(6).toList();
  }

  (List<String>, List<String>) _routineForScores(Map<String, double> scores) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final calmFirst = inflammation >= 4;

    final am = <String>[
      'Gentle cleanse or water rinse',
      calmFirst ? 'Centella or cica ampoule' : 'Niacinamide serum if tolerated',
      'Ceramide moisturizer',
      'Broad-spectrum SPF 30+',
    ];
    final pm = <String>[
      'Gentle cleanse',
      calmFirst
          ? 'Snail mucin or centella layer'
          : 'Copper peptide / GHK-Cu serum',
      'Barrier cream',
      calmFirst
          ? 'Pimple patches only where needed; save acids for calmer nights'
          : 'Optional Some By Mi toner 1-2 nights weekly, not with irritation',
    ];
    return (am, pm);
  }

  (List<String>, List<String>) _bodyRoutineForScores(
    Map<String, double> scores,
    procedure_intel.ProcedureBodyContouringSubtype subtype,
  ) {
    final swelling = scores['swelling'] ?? 0;
    final bruising = scores['scarringBruising'] ?? 0;
    final am = <String>[
      'Check garment fit and incision comfort',
      subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl
          ? 'Use BBL pillow / no direct sitting if still restricted'
          : 'Short easy walk if cleared',
      swelling >= 4
          ? 'Elevate/rest between walks'
          : 'Hydrate and keep protein steady',
      'Call clinic for sudden pain, heat, fever, or one-sided swelling',
    ];
    final pm = <String>[
      'Gentle shower and dry garment-safe skin fully',
      bruising >= 4 ? 'Arnica only if approved' : 'Moisturize intact skin only',
      'Scar silicone only on closed healed incisions',
      'Sleep in surgeon-approved position',
    ];
    return (am, pm);
  }

  Widget _recommendationTile(
    ({String title, String reason, IconData icon, Color accent}) rec, {
    required int index,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: rec.accent.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: rec.accent.withValues(alpha: 0.18),
          width: 0.7,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: rec.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(rec.icon, size: 15, color: rec.accent),
                Positioned(
                  right: 3,
                  bottom: 2,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: rec.accent,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rec.title,
                  style: TextStyle(
                    color: MyApp.clinicalNavy,
                    fontSize: 12.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rec.reason,
                  style: TextStyle(
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                    fontSize: 11.5,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routineColumn(String label, List<String> steps, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.20), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                label == 'AM'
                    ? Icons.wb_sunny_outlined
                    : Icons.nights_stay_outlined,
                color: accent,
                size: 15,
              ),
              const SizedBox(width: 6),
              Text(
                '$label ROUTINE',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    steps[i],
                    style: TextStyle(
                      color: MyApp.textBrown.withValues(alpha: 0.82),
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _proceduresCard(PhotoAnalysisResult r) {
    return Column(
      children: [
        for (int i = 0; i < r.procedures.take(4).length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: i == 0
                    ? AppColors.champagneGold.withValues(alpha: 0.45)
                    : MyApp.clinicalSlate.withValues(alpha: 0.15),
                width: i == 0 ? 1.0 : 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: (i == 0 ? AppColors.champagneGold : MyApp.clinicalNavy)
                      .withValues(alpha: i == 0 ? 0.10 : 0.04),
                  blurRadius: i == 0 ? 16 : 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (i == 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.champagneGold.withValues(alpha: 0.18),
                            MyApp.goldShimmer.withValues(alpha: 0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.45,
                          ),
                          width: 0.6,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: AppColors.champagneGold,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'COMMONLY EXPLORED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                              color: AppColors.champagneGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.procedures[i].name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${r.procedures[i].suitabilityPct}% relevance',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: MyApp.clinicalTeal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  r.procedures[i].indication,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: MyApp.textBrown.withValues(alpha: 0.85),
                  ),
                ),
                if (r.procedures[i].pros.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final pro in r.procedures[i].pros.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 11,
                            color: Color(0xFF4FAE8B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              pro,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: MyApp.textBrown.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _miniMeta(
                      Icons.fitness_center_rounded,
                      _intensityLabel(r.procedures[i].intensity),
                    ),
                    _miniMeta(
                      Icons.event_repeat_rounded,
                      r.procedures[i].expectedSessions,
                    ),
                    _miniMeta(
                      Icons.timelapse_rounded,
                      r.procedures[i].timelineWeeks,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _intensityLabel(ProcedureIntensity i) {
    switch (i) {
      case ProcedureIntensity.gentle:
        return 'Gentle';
      case ProcedureIntensity.moderate:
        return 'Moderate';
      case ProcedureIntensity.intensive:
        return 'Intensive';
      case ProcedureIntensity.systemic:
        return 'Systemic / Rx';
    }
  }

  Widget _miniMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: MyApp.clinicalSlate),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: MyApp.clinicalSlate,
          ),
        ),
      ],
    );
  }

  Widget _productCuesCard(PhotoAnalysisResult r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final cue in r.productCues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 13,
                    color: MyApp.clinicalTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cue,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: MyApp.textBrown.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────

  /// Inline validation note shown beneath the focus-area chips when the
  /// user tries to run analysis without selecting a focus area.
  Widget _focusAreaErrorNote(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEDED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD06B6B).withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFC0504D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC0504D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmapImageForPath(
    String path, {
    Map<String, double>? heatmapScores,
  }) {
    final provider = _imageProviderForPath(path);
    if (provider == null) {
      return Container(color: AppColors.champagneGold.withValues(alpha: 0.06));
    }

    if (heatmapScores == null || heatmapScores.isEmpty) {
      return Image(image: provider, fit: BoxFit.cover);
    }

    if (_isBodyProcedure) {
      return SkinHeatmapOverlay.bodyContouring(
        photo: provider,
        region: _analysisBodyHeatmapRegion(),
        inflammation: _scoreOrZero(heatmapScores, 'redness'),
        textureIrregularity: _scoreOrZero(heatmapScores, 'texture'),
        improvement: _estimatedHeatmapImprovement(heatmapScores),
      );
    }

    return SkinHeatmapOverlay.laser(
      photo: provider,
      redness: _scoreOrZero(heatmapScores, 'redness'),
      wrinkles: _scoreOrZero(heatmapScores, 'wrinkle'),
      improvement: _estimatedHeatmapImprovement(heatmapScores),
    );
  }

  ImageProvider<Object>? _imageProviderForPath(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;

    if (kIsWeb ||
        p.startsWith('data:image') ||
        p.startsWith('http://') ||
        p.startsWith('https://')) {
      return NetworkImage(p);
    }
    return FileImage(File(p));
  }

  double _scoreOrZero(Map<String, double> scores, String key) {
    final raw = scores[key] ?? 0;
    return raw.clamp(0, 10).toDouble();
  }

  double _estimatedHeatmapImprovement(Map<String, double> scores) {
    final redness = _scoreOrZero(scores, 'redness');
    final texture = _scoreOrZero(scores, 'texture');
    final wrinkle = _scoreOrZero(scores, 'wrinkle');
    final pigment = _scoreOrZero(scores, 'pigment');
    final concernAvg = (redness + texture + wrinkle + pigment) / 4;
    return (10 - concernAvg).clamp(0, 10).toDouble();
  }

  SkinHeatmapBodyRegion _analysisBodyHeatmapRegion() {
    final subtype = procedure_intel.ProcedureIntelligence.bodyContouringSubtype(
      _selectedProcedureType,
    );
    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.bbl) {
      return SkinHeatmapBodyRegion.flanks;
    }
    if (subtype == procedure_intel.ProcedureBodyContouringSubtype.liposuction) {
      return SkinHeatmapBodyRegion.abdomen;
    }

    final canonical = (_selectedProcedureType ?? '').toLowerCase().trim();
    if (canonical.contains('thigh')) return SkinHeatmapBodyRegion.thighs;
    if (canonical.contains('arm')) return SkinHeatmapBodyRegion.arms;
    if (canonical.contains('breast')) return SkinHeatmapBodyRegion.breasts;
    if (canonical.contains('tummy') || canonical.contains('abdomen')) {
      return SkinHeatmapBodyRegion.abdomen;
    }
    return SkinHeatmapBodyRegion.generic;
  }

  /// Small italic caption used to frame procedure / ingredient sections as
  /// general information rather than a personalised recommendation.
  Widget _framingNote(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 12,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: AppColors.champagneGold.withValues(alpha: 0.22),
      width: 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.refinedSlate.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );

  String _regionLabel(FacialRegion r) {
    switch (r) {
      case FacialRegion.fullFace:
        return 'Full face';
      case FacialRegion.forehead:
        return 'Forehead';
      case FacialRegion.cheeks:
        return 'Cheeks';
      case FacialRegion.jawlineChin:
        return 'Jawline / chin';
      case FacialRegion.nose:
        return 'Nose';
      case FacialRegion.perioral:
        return 'Around mouth';
    }
  }

  Color _severityColor(double index) {
    if (index < 1.5) return const Color(0xFF4FAE8B);
    if (index < 4) return const Color(0xFFB89A6E);
    if (index < 6.5) return const Color(0xFFD08A4A);
    if (index < 8.5) return const Color(0xFFC76A55);
    return const Color(0xFFA64A4A);
  }

  Color _valueColor(int v) {
    if (v <= 2) return const Color(0xFF4FAE8B);
    if (v <= 5) return const Color(0xFFB89A6E);
    if (v <= 7) return const Color(0xFFD08A4A);
    return const Color(0xFFC76A55);
  }
}

class LuxeMetricGrid extends StatelessWidget {
  const LuxeMetricGrid({super.key, required this.metrics});

  final Map<String, double> metrics;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _LuxeMetricTile(
        label: 'Redness',
        value: metrics['redness'] ?? 0,
        accent: const Color(0xFFC76A55),
      ),
      _LuxeMetricTile(
        label: 'Wrinkles',
        value: metrics['wrinkles'] ?? 0,
        accent: const Color(0xFFD08A4A),
      ),
      _LuxeMetricTile(
        label: 'Dark spots',
        value: metrics['darkSpots'] ?? 0,
        accent: const Color(0xFFB89A6E),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) => tiles[index],
    );
  }
}

class _LuxeMetricTile extends StatelessWidget {
  const _LuxeMetricTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final double value;
  final Color accent;

  String get _status {
    if (value < 25) return 'Low';
    if (value < 50) return 'Mild';
    if (value < 75) return 'Moderate';
    return 'High';
  }

  @override
  Widget build(BuildContext context) {
    final score = value.clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151922),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            score.toStringAsFixed(0),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w300,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '0-100 calibrated',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            _status,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: LinearProgressIndicator(
                value: score / 100,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable results screen for the backend-powered Deep Analysis flow in
/// [CameraScreen]. It accepts flexible JSON so future trained-model payloads
/// can be displayed without coupling the camera screen to a specific schema.
class SkinAiAnalysisResultsScreen extends StatelessWidget {
  final Map<String, dynamic> analysisResult;
  final Uint8List? croppedImageBytes;

  const SkinAiAnalysisResultsScreen({
    super.key,
    required this.analysisResult,
    required this.croppedImageBytes,
  });

  Map<String, dynamic> get _body {
    final nested =
        analysisResult['analysis'] ??
        analysisResult['result'] ??
        analysisResult['data'] ??
        analysisResult['results'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return analysisResult;
  }

  @override
  Widget build(BuildContext context) {
    final metricsPayload = _buildLuxeRenderPayload();
    final baselineImage = _baselineImageProvider();
    final currentImage = _currentImageProvider();
    final recommendedProducts = _recommendedProducts();
    final narrative =
        _stringValue([
          'smart_narrative',
          'narrative',
          'summary',
          'overall_summary',
          'interpretation',
          'description',
        ]) ??
        'Single-scan analysis completed successfully.';

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.warmAlabaster,
        foregroundColor: MyApp.clinicalNavy,
        title: const Text(
          'Skin AI Analysis',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topDisclaimer(),
                  const SizedBox(height: 14),
                  LuxeReportLayout(
                    rawPayload: metricsPayload,
                    baselineImageProvider: baselineImage,
                    currentImageProvider: currentImage,
                    baselineLabel: 'Baseline Image',
                    currentLabel: 'Current Scan',
                  ),
                  if (recommendedProducts.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _recommendedProductsCarousel(context, recommendedProducts),
                  ],
                  const SizedBox(height: 16),
                  SmartNarrativeContainer(narrativeText: narrative),
                  const SizedBox(height: 18),
                  _actionsCard(context),
                  const SizedBox(height: 14),
                  _footerDisclaimer(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Map<String, dynamic> _buildLuxeRenderPayload() {
    final metrics = _firstMap(['metrics']) ?? _body;
    final merged = Map<String, dynamic>.from(metrics);

    Map<String, dynamic>? readMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final rootTrend = readMap(
      _body['trend_deltas'] ?? analysisResult['trend_deltas'],
    );
    final nestedTrend = readMap(metrics['trend_deltas']);
    final rootMatrix = readMap(
      _body['metric_matrix'] ?? analysisResult['metric_matrix'],
    );
    final nestedMatrix = readMap(metrics['metric_matrix']);

    final trendDeltas = rootTrend ?? nestedTrend;
    final metricMatrix = rootMatrix ?? nestedMatrix;

    if (trendDeltas != null) {
      merged['trend_deltas'] = trendDeltas;
    }
    if (metricMatrix != null) {
      merged['metric_matrix'] = metricMatrix;
    }

    return merged;
  }

  ImageProvider<Object>? _currentImageProvider() {
    if (croppedImageBytes != null && croppedImageBytes!.isNotEmpty) {
      return MemoryImage(croppedImageBytes!);
    }
    final path = _stringValue([
      'image_path',
      'imagePath',
      'current_image_path',
      'currentImagePath',
    ]);
    return _imageProviderFromDynamic(path);
  }

  ImageProvider<Object>? _baselineImageProvider() {
    final baselineFromMap = _firstMap([
      'baseline',
      'baseline_image',
      'baselineImage',
    ]);

    final baselinePath =
        baselineFromMap?['image_path']?.toString() ??
        baselineFromMap?['imagePath']?.toString() ??
        _stringValue([
          'baseline_image_path',
          'baselineImagePath',
          'baseline_path',
          'baselinePath',
          'baseline_image',
          'baselineImage',
        ]);
    final provider = _imageProviderFromDynamic(baselinePath);
    if (provider != null) return provider;

    final baselineBytesRaw =
        baselineFromMap?['image_bytes'] ??
        baselineFromMap?['imageBytes'] ??
        _body['baseline_image_bytes'] ??
        _body['baselineImageBytes'] ??
        analysisResult['baseline_image_bytes'] ??
        analysisResult['baselineImageBytes'];
    if (baselineBytesRaw is String && baselineBytesRaw.trim().isNotEmpty) {
      try {
        final raw = baselineBytesRaw.trim();
        final comma = raw.indexOf(',');
        final payload = comma >= 0 ? raw.substring(comma + 1) : raw;
        return MemoryImage(base64Decode(payload));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  ImageProvider<Object>? _imageProviderFromDynamic(String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return null;

    if (value.startsWith('data:image')) {
      try {
        final comma = value.indexOf(',');
        if (comma < 0) return null;
        return MemoryImage(base64Decode(value.substring(comma + 1)));
      } catch (_) {
        return null;
      }
    }

    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('blob:')) {
      return NetworkImage(value);
    }

    if (!kIsWeb) {
      final file = File(value);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }

  Widget _topDisclaimer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.10),
            AppColors.mutedSage.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 18,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: MyApp.textBrown.withValues(alpha: 0.9),
                ),
                children: const [
                  TextSpan(
                    text:
                        'These are AI-assisted observations, not medical advice. ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'They are not a diagnosis and are for personal cosmetic tracking only. Consult a dermatologist or qualified healthcare professional for medical concerns.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendedProductsCarousel(
    BuildContext context,
    List<_RecommendedProduct> products,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RECOMMENDED PRODUCTS',
          style: TextStyle(
            color: Color(0xFFB76E79),
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Container(
                width: 280,
                margin: EdgeInsets.only(
                  right: index == products.length - 1 ? 0 : 12,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1F2C),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.85),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB76E79).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(
                            0xFFB76E79,
                          ).withValues(alpha: 0.55),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        product.reasonTag,
                        style: const TextStyle(
                          color: Color(0xFFF0B7C1),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      product.brand.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.price,
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () =>
                            _launchAffiliateUrl(context, product.affiliateUrl),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: const Color(0xFF1A1F2C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'BUY PRODUCT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _launchAffiliateUrl(BuildContext context, String url) async {
    final raw = url.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw');
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open product link.')),
      );
    }
  }

  Widget _modelDisclosure() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: MyApp.clinicalTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.clinicalTeal.withValues(alpha: 0.32),
          width: 0.7,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.psychology_alt_rounded,
            size: 15,
            color: MyApp.clinicalTeal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Model output is displayed as visual estimates from this single cropped photo. Lighting, angle and image quality can affect results.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: MyApp.textBrown.withValues(alpha: 0.88),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallScoreCard(_ReportBundle report) {
    final scoreColor = _scoreAccent(report.overallScore);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFCF7),
            const Color(0xFFFFF4F7),
            AppColors.champagneGold.withValues(alpha: 0.20),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.45),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: scoreColor.withValues(alpha: 0.45),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                report.overallScore.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Skin Score',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${report.overallScore.toStringAsFixed(1)} / 10  •  ${report.overallBand}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Balanced hydration, texture, clarity, and recovery markers from this analysis snapshot.',
                  style: TextStyle(
                    fontSize: 10.7,
                    height: 1.35,
                    color: MyApp.textBrown.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid(List<_ReportMetric> metrics) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.86,
      ),
      itemBuilder: (context, index) => _metricCard(metrics[index]),
    );
  }

  Widget _metricCard(_ReportMetric metric) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white,
            const Color(0xFFFFFAFC),
            metric.accent.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: metric.accent.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: metric.accent.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: metric.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(metric.icon, color: metric.accent, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.7,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            metric.displayValue,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: metric.accent,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.2,
              height: 1.28,
              fontWeight: FontWeight.w600,
              color: MyApp.textBrown.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metric.status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
              color: MyApp.textBrown.withValues(alpha: 0.80),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: metric.score / 10,
              minHeight: 5,
              backgroundColor: metric.accent.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(metric.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recommendationsCard(List<String> recommendations) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  color: AppColors.champagneGold,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Actionable Recommendations',
                style: TextStyle(
                  fontSize: 13.2,
                  fontWeight: FontWeight.w900,
                  color: MyApp.clinicalNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final tip in recommendations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.fiber_manual_record_rounded,
                      size: 8,
                      color: AppColors.champagneGold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 11.6,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: MyApp.textBrown.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _clinicalInsightsCard(String narrative) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFCF8),
            const Color(0xFFFFF5F7),
            AppColors.champagneGold.withValues(alpha: 0.16),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.36),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFC98E97).withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.champagneGold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.champagneGold,
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI CLINICAL INSIGHTS',
                  style: TextStyle(
                    fontSize: 11.1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: MyApp.clinicalNavy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  narrative,
                  style: TextStyle(
                    fontSize: 11.7,
                    height: 1.48,
                    fontWeight: FontWeight.w600,
                    color: MyApp.textBrown.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textItemsCard(List<_TextItem> items, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 18,
                color: MyApp.clinicalSlate.withValues(alpha: 0.12),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: MyApp.clinicalTeal),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                      if (items[i].detail.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          items[i].detail,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: MyApp.textBrown.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getSmartNarrative(_ReportBundle report) {
    double metricValue(String key, {double fallback = 0}) {
      for (final metric in report.metrics) {
        if (metric.key == key) return metric.rawValue;
      }
      return fallback;
    }

    final wrinkle = metricValue('wrinkleScore', fallback: 4.1);
    final pigmentation = metricValue('pigmentationScore', fallback: 3.8);
    final overall = report.overallScore;
    final procedureContext =
        _stringValue([
          'procedure_context',
          'procedureContext',
          'procedure_type',
          'procedureType',
          'procedure',
          'selectedProcedureLabel',
        ]) ??
        'skin optimization';

    final bool wrinkleElevated = wrinkle >= 6.5;
    final bool wrinkleQuiet = wrinkle <= 3.5;
    final bool pigmentElevated = pigmentation >= 6.0;
    final bool pigmentQuiet = pigmentation <= 3.5;

    String leading;
    if (wrinkleElevated && pigmentElevated) {
      leading =
          'This scan shows a combined pattern of visible line formation and uneven tone, suggesting that both collagen support and pigment-calming strategies should stay central.';
    } else if (wrinkleElevated) {
      leading =
          'The strongest signal in this scan is wrinkle activity, with fine-line depth reading more prominently than pigment variation.';
    } else if (pigmentElevated) {
      leading =
          'Pigmentation is the dominant visual concern in this scan, with tone variation standing out more than structural line depth.';
    } else if (wrinkleQuiet && pigmentQuiet) {
      leading =
          'Wrinkle and pigmentation signals both read relatively calm here, which supports a maintenance-focused strategy rather than aggressive correction.';
    } else {
      leading =
          'This scan reads as moderately balanced, with subtle structural and tone concerns that are present but not dominant.';
    }

    String procedureNote;
    final contextLower = procedureContext.toLowerCase();
    if (contextLower.contains('microneed') ||
        contextLower.contains('laser') ||
        contextLower.contains('peel')) {
      procedureNote =
          'In the context of $procedureContext, this pattern usually benefits from disciplined barrier support and pigment-safe recovery while the skin remodels.';
    } else if (contextLower.contains('botox') ||
        contextLower.contains('filler') ||
        contextLower.contains('tox')) {
      procedureNote =
          'Against a $procedureContext backdrop, these readings are most useful for tracking surface quality around the treated result rather than volume change itself.';
    } else {
      procedureNote =
          'For $procedureContext, the most useful next step is consistent follow-up scanning under similar lighting so line depth and tone shift can be separated from day-to-day variability.';
    }

    String closing;
    if (overall >= 8.0) {
      closing =
          'Overall skin quality remains strong, so the emphasis should be on preserving clarity, smoothness, and treatment gains.';
    } else if (overall >= 6.0) {
      closing =
          'Overall skin quality is in a stable middle range, with room for targeted improvement where the highest-scoring concern is concentrated.';
    } else {
      closing =
          'Overall skin quality is still asking for closer support, and the wrinkle/pigment pattern suggests staying consistent with recovery-aware topical care and repeat tracking.';
    }

    return '$leading $procedureNote $closing';
  }

  Widget _actionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text(
              'Run another analysis',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.clinicalNavy,
              minimumSize: const Size(double.infinity, 46),
              side: BorderSide(
                color: MyApp.clinicalNavy.withValues(alpha: 0.35),
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Results are based on one cropped photo and may change with '
            'better lighting, a different crop, or over time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerDisclaimer() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 13,
          color: MyApp.clinicalSlate.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'AI-assisted observations — not a diagnosis and not a substitute '
            'for professional medical advice. Always consult a qualified '
            'healthcare professional for any concern, diagnosis, or '
            'treatment decision.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: MyApp.clinicalSlate,
            ),
          ),
        ),
      ],
    );
  }

  _ReportBundle _buildReportBundle() {
    final source = _firstMap(['metrics', 'scores', 'measurements']) ?? _body;
    final custom = _firstMap([
      'custom_metrics',
      'customMetrics',
      'user_metrics',
      'userTrackedMetrics',
      'tracked_metrics',
    ]);

    final ignored = <String>{
      'status',
      'success',
      'message',
      'headline',
      'summary',
      'overall_summary',
      'description',
      'interpretation',
      'confidence',
      'model_confidence',
      'confidence_score',
      'analysis',
      'result',
      'data',
      'results',
    };

    double normalizeScore(dynamic raw) {
      final parsed = _toNumber(raw);
      if (parsed == null) return double.nan;
      if (parsed >= 0 && parsed <= 1) return (parsed * 10).clamp(0.0, 10.0);
      if (parsed >= 0 && parsed <= 100) {
        return (parsed / 10).clamp(0.0, 10.0);
      }
      return parsed.clamp(0.0, 10.0).toDouble();
    }

    final numeric = <String, double>{};
    source.forEach((key, raw) {
      final k = key.toString();
      if (ignored.contains(k)) return;
      final n = normalizeScore(raw);
      if (n.isNaN) return;
      numeric[k] = n;
    });
    custom?.forEach((key, raw) {
      final n = normalizeScore(raw);
      if (n.isNaN) return;
      numeric[key.toString()] = n;
    });

    final cv = _extractCvSignals(croppedImageBytes);

    double? fromNumeric(List<String> keys) {
      for (final key in keys) {
        if (numeric.containsKey(key)) {
          return numeric[key]!.clamp(0.0, 10.0).toDouble();
        }
      }
      return null;
    }

    double? explicitNumeric(List<String> keys) => fromNumeric(keys);

    double pick(
      List<String> keys, {
      required double fallback,
      double? cvScore,
      bool invert = false,
    }) {
      final model = fromNumeric(keys);
      var resolved = model ?? cvScore ?? fallback;
      if (model != null && cvScore != null) {
        // Blend model output with lightweight CV estimates for stability.
        resolved = model * 0.65 + cvScore * 0.35;
      }
      resolved = resolved.clamp(0.0, 10.0).toDouble();
      return invert ? (10 - resolved).clamp(0.0, 10.0) : resolved;
    }

    final hydration = pick(
      ['hydrationLevel', 'hydration', 'waterRetention'],
      fallback: 6.6,
      cvScore: cv?.hydrationScore,
    );
    final oiliness = pick(
      ['oiliness', 'sebum', 'oilLevel'],
      fallback: 4.0,
      cvScore: cv?.oilinessLevelScore,
    );
    final pores = pick(
      ['poreSize', 'pores', 'poresVisibility'],
      fallback: 5.0,
      cvScore: cv?.poreVisibilityScore,
    );
    final sensitivity = pick(
      ['skinSensitivity', 'sensitivity'],
      fallback: 3.1,
      cvScore: cv?.sensitivityScore,
    );
    final collagen = pick(
      ['collagenScore', 'elasticity', 'firmness', 'skinLaxityFirmness'],
      fallback: 7.3,
      cvScore: cv?.collagenScore,
    );
    final redness = pick(
      ['redness', 'inflammation', 'rosaceaSeverity', 'erythema'],
      fallback: 3.3,
      cvScore: cv?.rednessScore,
    );
    final pigmentationScore = pick([
      'pigmentation_score',
      'pigmentationScore',
      'pigmentation',
      'pigment',
      'darkSpots',
      'postAcneScarring',
    ], fallback: 3.8);
    final darkSpots = pick([
      'darkSpots',
      'pigmentation',
      'pigment',
      'postAcneScarring',
    ], fallback: pigmentationScore);
    final texture = pick(
      ['texture', 'roughness', 'skinTexture'],
      fallback: 4.2,
      cvScore: cv?.textureRoughnessScore,
    );
    final wrinkleScore = pick([
      'wrinkle_score',
      'wrinkleScore',
      'wrinkle',
      'wrinkles',
      'rhytids',
      'fineLines',
    ], fallback: 4.1);
    final acne = pick([
      'acneSeverity',
      'breakoutSeverity',
      'activeBreakouts',
      'acneCount',
    ], fallback: 2.9);
    final scarProgress = pick(
      ['scarHealingProgress', 'overallHealingScore', 'scarringBruising'],
      fallback: 7.1,
      invert: numeric.containsKey('scarringBruising'),
    );

    final oilBalanceScore = (10 - (oiliness - 5).abs() * 2).clamp(0.0, 10.0);
    final explicitOverall = explicitNumeric([
      'overall_skin_score',
      'overallSkinScore',
      'overall_score',
      'skinScore',
      'overallHealingScore',
    ]);
    final computedOverall =
        (hydration * 0.16 +
                oilBalanceScore * 0.09 +
                collagen * 0.14 +
                (10 - redness) * 0.12 +
                (10 - darkSpots) * 0.10 +
                (10 - pigmentationScore) * 0.10 +
                (10 - texture) * 0.10 +
                (10 - wrinkleScore) * 0.09 +
                (10 - acne) * 0.06 +
                scarProgress * 0.04)
            .clamp(0.0, 10.0);
    final overall = explicitOverall != null
        ? explicitOverall.clamp(0.0, 10.0)
        : computedOverall;

    final hydrationPct = cv != null
        ? cv.hydrationPercent.round()
        : (40 + hydration * 5.5).clamp(0, 100).round();
    final oilinessPct = cv != null
        ? cv.oilinessPercent.round()
        : (20 + oiliness * 7).clamp(0, 100).round();
    final poreSizeMm = cv != null ? cv.poreSizeMm : (0.14 + pores * 0.018);

    final cards = <_ReportMetric>[
      _ReportMetric(
        key: 'hydrationLevel',
        label: 'Hydration Level',
        rawValue: hydration,
        score: hydration,
        displayValue: '$hydrationPct%',
        description: 'Surface water balance and bounce',
        status: _hydrationBand(hydration),
        icon: Icons.water_drop_rounded,
        accent: const Color(0xFFB989A3),
      ),
      _ReportMetric(
        key: 'oiliness',
        label: 'Oiliness',
        rawValue: oiliness,
        score: oilBalanceScore,
        displayValue: '$oilinessPct%',
        description: 'Sebum balance across the visible patch',
        status: _oilBand(oiliness),
        icon: Icons.opacity_rounded,
        accent: const Color(0xFFCFA67D),
      ),
      _ReportMetric(
        key: 'poreSize',
        label: 'Pore Size',
        rawValue: pores,
        score: (10 - pores).clamp(0.0, 10.0),
        displayValue: '${poreSizeMm.toStringAsFixed(2)}mm',
        description: 'Estimated pore opening visibility',
        status: '${_poreBand(pores)} (estimated)',
        icon: Icons.blur_on_rounded,
        accent: const Color(0xFFBC8CA5),
      ),
      _ReportMetric(
        key: 'skinSensitivity',
        label: 'Skin Sensitivity',
        rawValue: sensitivity,
        score: (10 - sensitivity).clamp(0.0, 10.0),
        displayValue: sensitivity.toStringAsFixed(1),
        description: 'Reactivity and comfort under visible stress',
        status: _lowMidHigh(sensitivity, reverse: true),
        icon: Icons.favorite_border_rounded,
        accent: const Color(0xFFB77D92),
      ),
      _ReportMetric(
        key: 'collagenScore',
        label: 'Collagen / Elasticity',
        rawValue: collagen,
        score: collagen,
        displayValue: '${collagen.toStringAsFixed(1)} / 10',
        description: 'Firmness and rebound appearance',
        status: _lowMidHigh(collagen),
        icon: Icons.spa_rounded,
        accent: const Color(0xFFC9A06D),
      ),
      _ReportMetric(
        key: 'rednessInflammation',
        label: 'Redness / Inflammation',
        rawValue: redness,
        score: (10 - redness).clamp(0.0, 10.0),
        displayValue: redness.toStringAsFixed(1),
        description: 'Visible flushing and inflammatory tone',
        status: _lowMidHigh(redness, reverse: true),
        icon: Icons.local_fire_department_outlined,
        accent: const Color(0xFFD08A74),
      ),
      _ReportMetric(
        key: 'darkSpotsPigmentation',
        label: 'Dark Spots / Pigmentation',
        rawValue: darkSpots,
        score: (10 - darkSpots).clamp(0.0, 10.0),
        displayValue: darkSpots.toStringAsFixed(1),
        description: 'Spot-specific discoloration and marks',
        status: _lowMidHigh(darkSpots, reverse: true),
        icon: Icons.tonality_rounded,
        accent: const Color(0xFFB48765),
      ),
      _ReportMetric(
        key: 'wrinkleScore',
        label: 'Wrinkle Score',
        rawValue: wrinkleScore,
        score: (10 - wrinkleScore).clamp(0.0, 10.0),
        displayValue: '${wrinkleScore.toStringAsFixed(1)} / 10',
        description: 'Fine lines and texture depth',
        status: _lowMidHigh(wrinkleScore, reverse: true),
        icon: Icons.auto_awesome_rounded,
        accent: const Color(0xFFD4AB6A),
      ),
      _ReportMetric(
        key: 'pigmentationScore',
        label: 'Pigmentation Score',
        rawValue: pigmentationScore,
        score: (10 - pigmentationScore).clamp(0.0, 10.0),
        displayValue: '${pigmentationScore.toStringAsFixed(1)} / 10',
        description: 'Tone variation and dark spot visibility',
        status: _lowMidHigh(pigmentationScore, reverse: true),
        icon: Icons.tonality_rounded,
        accent: const Color(0xFFC89B72),
      ),
      _ReportMetric(
        key: 'textureRoughness',
        label: 'Texture / Roughness',
        rawValue: texture,
        score: (10 - texture).clamp(0.0, 10.0),
        displayValue: texture.toStringAsFixed(1),
        description: 'Surface smoothness and uneven grain',
        status: _lowMidHigh(texture, reverse: true),
        icon: Icons.grain_rounded,
        accent: const Color(0xFFC697A8),
      ),
      _ReportMetric(
        key: 'acneSeverity',
        label: 'Acne / Breakout Severity',
        rawValue: acne,
        score: (10 - acne).clamp(0.0, 10.0),
        displayValue: acne.toStringAsFixed(1),
        description: 'Breakout load and active congestion',
        status: _lowMidHigh(acne, reverse: true),
        icon: Icons.healing_outlined,
        accent: const Color(0xFFCD836D),
      ),
      _ReportMetric(
        key: 'scarHealingProgress',
        label: 'Scar Healing Progress',
        rawValue: scarProgress,
        score: scarProgress,
        displayValue: '${scarProgress.toStringAsFixed(1)} / 10',
        description: 'Recovery trend across visible marks',
        status: _lowMidHigh(scarProgress),
        icon: Icons.timeline_rounded,
        accent: const Color(0xFFC9A975),
      ),
    ];

    const consumed = <String>{
      'hydrationLevel',
      'hydration',
      'waterRetention',
      'oiliness',
      'sebum',
      'oilLevel',
      'poreSize',
      'pores',
      'poresVisibility',
      'skinSensitivity',
      'sensitivity',
      'collagenScore',
      'elasticity',
      'firmness',
      'skinLaxityFirmness',
      'redness',
      'inflammation',
      'rosaceaSeverity',
      'erythema',
      'darkSpots',
      'pigmentation_score',
      'pigmentationScore',
      'pigmentation',
      'pigment',
      'postAcneScarring',
      'texture',
      'roughness',
      'skinTexture',
      'wrinkle_score',
      'wrinkleScore',
      'wrinkle',
      'wrinkles',
      'rhytids',
      'fineLines',
      'acneSeverity',
      'breakoutSeverity',
      'activeBreakouts',
      'acneCount',
      'scarHealingProgress',
      'overall_skin_score',
      'overallHealingScore',
      'scarringBruising',
      'overallSkinScore',
      'overall_score',
      'skinScore',
    };

    final extraEntries =
        numeric.entries.where((e) => !consumed.contains(e.key)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    for (final e in extraEntries.take(6)) {
      final value = e.value.clamp(0.0, 10.0);
      cards.add(
        _ReportMetric(
          key: e.key,
          label: _humanize(e.key),
          rawValue: value,
          score: value,
          displayValue: '${value.toStringAsFixed(1)} / 10',
          description: 'Custom tracked metric from backend output',
          status: 'Custom tracked metric',
          icon: Icons.tune_rounded,
          accent: const Color(0xFFB08A58),
        ),
      );
    }

    return _ReportBundle(
      overallScore: overall,
      overallBand: _overallBand(overall),
      metrics: cards,
    );
  }

  _CvSignals? _extractCvSignals(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    const int targetW = 144;
    final int targetH = math.max(
      96,
      (decoded.height * targetW / decoded.width).round(),
    );
    final sampled = img.copyResize(decoded, width: targetW, height: targetH);

    final w = sampled.width;
    final h = sampled.height;
    final x0 = (w * 0.12).round();
    final x1 = (w * 0.88).round();
    final y0 = (h * 0.10).round();
    final y1 = (h * 0.92).round();
    final cx = (x0 + x1) / 2.0;
    final cy = (y0 + y1) / 2.0;
    final rx = (x1 - x0) * 0.46;
    final ry = (y1 - y0) * 0.47;

    final luma = List<double>.filled(w * h, 0);
    int n = 0;
    double sumL = 0;
    double sumL2 = 0;
    double sumSat = 0;
    double sumRedness = 0;
    int oilySpecularCount = 0;

    bool inFaceMask(int x, int y) {
      final nx = (x - cx) / rx;
      final ny = (y - cy) / ry;
      return nx * nx + ny * ny <= 1.0;
    }

    for (int y = y0; y < y1; y++) {
      for (int x = x0; x < x1; x++) {
        if (!inFaceMask(x, y)) continue;
        final p = sampled.getPixel(x, y);
        final r = p.r.toDouble() / 255.0;
        final g = p.g.toDouble() / 255.0;
        final b = p.b.toDouble() / 255.0;
        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final delta = maxC - minC;
        final sat = maxC <= 0 ? 0.0 : delta / maxC;
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final redness = (r - (g + b) * 0.5 + 0.2).clamp(0.0, 1.0);

        luma[y * w + x] = lum;
        sumL += lum;
        sumL2 += lum * lum;
        sumSat += sat;
        sumRedness += redness;
        if (lum > 0.76 && sat < 0.20) oilySpecularCount++;
        n++;
      }
    }

    if (n < 100) return null;

    final meanL = sumL / n;
    final varL = (sumL2 / n) - (meanL * meanL);
    final stdL = math.sqrt(math.max(0.0, varL));
    final meanSat = sumSat / n;
    final meanRedness = sumRedness / n;
    final specularFrac = oilySpecularCount / n;

    double edgeSum = 0;
    double diffSum = 0;
    int edgeN = 0;
    int highEdgeN = 0;
    for (int y = y0 + 1; y < y1 - 1; y++) {
      for (int x = x0 + 1; x < x1 - 1; x++) {
        if (!inFaceMask(x, y)) continue;
        final c = luma[y * w + x];
        final gx = luma[y * w + (x + 1)] - luma[y * w + (x - 1)];
        final gy = luma[(y + 1) * w + x] - luma[(y - 1) * w + x];
        final grad = math.sqrt(gx * gx + gy * gy);
        edgeSum += grad;
        if (grad > 0.11) highEdgeN++;

        final right = luma[y * w + (x + 1)];
        final down = luma[(y + 1) * w + x];
        diffSum += (c - right).abs() + (c - down).abs();
        edgeN++;
      }
    }

    if (edgeN == 0) return null;
    final edgeMean = edgeSum / edgeN;
    final edgeDensity = highEdgeN / edgeN;
    final roughnessNorm = (diffSum / (edgeN * 2) / 0.18).clamp(0.0, 1.0);
    final contrastNorm = (stdL / 0.24).clamp(0.0, 1.0);
    final edgeNorm = ((edgeMean - 0.04) / 0.24).clamp(0.0, 1.0);

    final hydrationNorm =
        (meanL * 0.54 + (1 - contrastNorm) * 0.24 + (1 - roughnessNorm) * 0.22)
            .clamp(0.0, 1.0);
    final oilinessNorm =
        (specularFrac * 0.55 + meanSat * 0.25 + edgeNorm * 0.20).clamp(
          0.0,
          1.0,
        );
    final poreNorm = (edgeDensity * 0.65 + roughnessNorm * 0.35).clamp(
      0.0,
      1.0,
    );
    final rednessNorm = (meanRedness * 0.72 + meanSat * 0.28).clamp(0.0, 1.0);
    final sensitivityNorm =
        (rednessNorm * 0.62 + contrastNorm * 0.20 + roughnessNorm * 0.18).clamp(
          0.0,
          1.0,
        );
    final collagenNorm =
        ((1 - roughnessNorm) * 0.62 + (1 - poreNorm) * 0.23 + meanL * 0.15)
            .clamp(0.0, 1.0);

    return _CvSignals(
      hydrationPercent: (hydrationNorm * 100).clamp(0.0, 100.0),
      hydrationScore: (hydrationNorm * 10).clamp(0.0, 10.0),
      oilinessPercent: (oilinessNorm * 100).clamp(0.0, 100.0),
      oilinessLevelScore: (oilinessNorm * 10).clamp(0.0, 10.0),
      poreVisibilityScore: (poreNorm * 10).clamp(0.0, 10.0),
      poreSizeMm: (0.14 + poreNorm * 0.20).clamp(0.10, 0.45),
      sensitivityScore: (sensitivityNorm * 10).clamp(0.0, 10.0),
      rednessScore: (rednessNorm * 10).clamp(0.0, 10.0),
      textureRoughnessScore: (roughnessNorm * 10).clamp(0.0, 10.0),
      collagenScore: (collagenNorm * 10).clamp(0.0, 10.0),
    );
  }

  List<String> _buildActionableRecommendations(_ReportBundle report) {
    final byKey = <String, _ReportMetric>{
      for (final m in report.metrics) m.key: m,
    };

    final tips = <String>[];
    final hydration = byKey['hydrationLevel']?.score ?? 6.6;
    if (hydration < 6.0) {
      tips.add(
        'Increase barrier hydration: use a hyaluronic acid serum followed by a ceramide-rich moisturizer morning and evening.',
      );
    }

    final sensitivity = 10 - (byKey['skinSensitivity']?.score ?? 6.9);
    if (sensitivity > 4.5) {
      tips.add(
        'Reduce irritation load for 7-10 days: pause exfoliants, use a fragrance-free routine, and prioritize soothing repair products.',
      );
    }

    final redness = 10 - (byKey['rednessInflammation']?.score ?? 6.7);
    if (redness > 4.5) {
      tips.add(
        'Support anti-redness recovery with daily SPF 50, cool-water cleansing, and anti-inflammatory actives like niacinamide or azelaic acid.',
      );
    }

    final acne = 10 - (byKey['acneSeverity']?.score ?? 7.1);
    if (acne > 4.0) {
      tips.add(
        'For breakout control, keep routine simple: non-comedogenic cleanser, targeted BHA at night, and avoid heavy occlusive layering in active zones.',
      );
    }

    if (tips.isEmpty) {
      tips.add(
        'Maintain your current routine consistency: daily SPF, gentle cleansing, nightly hydration, and weekly photo tracking under similar lighting.',
      );
      tips.add(
        'Continue collagen-supportive care with peptides, antioxidant protection, and sleep-recovery habits to preserve elasticity and tone.',
      );
    }

    tips.add(
      'Re-scan in 10-14 days with identical angle and lighting to confirm trend direction before making major routine changes.',
    );

    return tips.take(5).toList();
  }

  List<AIProductRecommendation> _buildProductRecommendationsFromReport(
    _ReportBundle report,
  ) {
    final byKey = <String, _ReportMetric>{
      for (final m in report.metrics) m.key: m,
    };

    double metric(String key, double fallback) => byKey[key]?.score ?? fallback;

    final skinMetrics = SkinMetrics(
      redness: (10 - metric('rednessInflammation', 6.5)).clamp(0.0, 10.0),
      texture: (10 - metric('textureRoughness', 6.0)).clamp(0.0, 10.0),
      wrinkle: (10 - metric('collagenScore', 7.0)).clamp(0.0, 10.0),
      pore: (10 - metric('poreSize', 6.0)).clamp(0.0, 10.0),
      darkSpots: (10 - metric('darkSpotsPigmentation', 6.0)).clamp(0.0, 10.0),
      elasticity: metric('collagenScore', 6.8).clamp(0.0, 10.0),
    );

    final cvContext = CvSkinMetricsContext(
      hydrationLevel: metric('hydrationLevel', 6.5),
      oilinessLevel:
          ((byKey['oiliness'] != null) ? (byKey['oiliness']!.score / 2.0) : 4.5)
              .clamp(0.0, 10.0),
      poreVisibility: (10 - metric('poreSize', 6.0)).clamp(0.0, 10.0),
      sensitivityLevel: (10 - metric('skinSensitivity', 6.8)).clamp(0.0, 10.0),
      rednessLevel: (10 - metric('rednessInflammation', 6.5)).clamp(0.0, 10.0),
      textureRoughness: (10 - metric('textureRoughness', 6.0)).clamp(0.0, 10.0),
      collagenElasticity: metric('collagenScore', 6.8).clamp(0.0, 10.0),
      poreSizeMm: _parsePoreSizeMm(byKey['poreSize']?.displayValue),
    );

    final concerns = <String>[];
    if ((cvContext.hydrationLevel ?? 10) < 5.8) concerns.add('dryness');
    if ((cvContext.oilinessLevel ?? 0) > 6.0) concerns.add('oiliness');
    if ((cvContext.sensitivityLevel ?? 0) > 5.8) concerns.add('sensitive');
    if ((cvContext.rednessLevel ?? 0) > 5.8) concerns.add('redness');
    if ((cvContext.textureRoughness ?? 0) > 5.8) concerns.add('texture');

    final resolvedProcedureType = (() {
      final candidates = <String?>[
        _stringValue(['procedure', 'procedure_type']),
        _stringValue(['scanProcedure', 'scan_procedure']),
        _stringValue(['selectedProcedureType', 'selected_procedure_type']),
        _stringValue(['analysisContextProcedureType']),
      ];
      for (final candidate in candidates) {
        final normalized = (candidate ?? '').trim();
        if (normalized.isNotEmpty && normalized.toLowerCase() != 'unknown') {
          return normalized;
        }
      }
      return 'General Skincare';
    })();
    AppLogger.verbose(
      '[SkinAiAnalysisScreen] resolvedProcedureType=$resolvedProcedureType',
    );

    return AIProductRecommendationEngine.generateRecommendations(
      skinMetrics,
      procedureType: resolvedProcedureType,
      maxRecommendations: 4,
      cvMetrics: cvContext,
      userSkinConcerns: concerns,
      recentProcedureTypes:
          resolvedProcedureType.toLowerCase() != 'general skincare'
          ? [resolvedProcedureType]
          : null,
    );
  }

  double? _parsePoreSizeMm(String? displayValue) {
    if (displayValue == null || displayValue.trim().isEmpty) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(displayValue);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  List<_TextItem> _extractTextItems(List<String> keys) {
    final items = <_TextItem>[];
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      items.addAll(_parseTextItems(value));
    }
    final seen = <String>{};
    return items
        .where((item) {
          final sig = '${item.title}|${item.detail}';
          if (seen.contains(sig)) return false;
          seen.add(sig);
          return true;
        })
        .take(8)
        .toList();
  }

  List<_TextItem> _parseTextItems(dynamic value) {
    if (value == null) return const [];
    if (value is String && value.trim().isNotEmpty) {
      return [_TextItem('Observation', value.trim())];
    }
    if (value is List) {
      return value.expand(_parseTextItems).toList();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.containsKey('title') ||
          map.containsKey('detail') ||
          map.containsKey('description')) {
        return [
          _TextItem(
            map['title']?.toString() ?? 'Observation',
            (map['detail'] ?? map['description'] ?? map['text'] ?? '')
                .toString(),
          ),
        ];
      }
      return map.entries
          .where((e) => e.value != null && e.value.toString().trim().isNotEmpty)
          .map(
            (e) => _TextItem(_humanize(e.key.toString()), e.value.toString()),
          )
          .toList();
    }
    return [_TextItem('Observation', value.toString())];
  }

  Map<String, dynamic>? _firstMap(List<String> keys) {
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String? _stringValue(List<String> keys) {
    for (final key in keys) {
      final value = _body[key] ?? analysisResult[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  double? _numericValue(List<String> keys) {
    for (final key in keys) {
      final value = _toNumber(_body[key] ?? analysisResult[key]);
      if (value != null) return value;
    }
    return null;
  }

  double? _toNumber(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    if (value is Map && value['score'] != null) {
      return _toNumber(value['score']);
    }
    return null;
  }

  String _humanize(String key) {
    final spaced = key
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .trim();
    if (spaced.isEmpty) return 'Metric';
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  String _overallBand(double score) {
    if (score >= 8.5) return 'Excellent';
    if (score >= 7.2) return 'Healthy';
    if (score >= 5.8) return 'Good';
    return 'Needs Attention';
  }

  List<_RecommendedProduct> _recommendedProducts() {
    final raw =
        _body['recommended_products'] ?? analysisResult['recommended_products'];
    if (raw is! List) return const [];

    final out = <_RecommendedProduct>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final brand = (map['brand'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      final price = (map['price'] ?? '').toString().trim();
      final reasonTag = (map['reason_tag'] ?? '').toString().trim();
      final affiliateUrl = (map['affiliate_url'] ?? '').toString().trim();
      if (brand.isEmpty || name.isEmpty || affiliateUrl.isEmpty) continue;
      out.add(
        _RecommendedProduct(
          brand: brand,
          name: name,
          price: price.isEmpty ? 'See details' : price,
          reasonTag: reasonTag.isEmpty ? 'Recommended' : reasonTag,
          affiliateUrl: affiliateUrl,
        ),
      );
    }
    return out;
  }

  String _hydrationBand(double score) {
    if (score >= 7.6) return 'Well Hydrated';
    if (score >= 5.8) return 'Normal';
    return 'Low Hydration';
  }

  String _oilBand(double rawOilScore) {
    if (rawOilScore >= 3.5 && rawOilScore <= 6.0) return 'Balanced';
    if (rawOilScore < 3.5) return 'Dry-leaning';
    return 'Oil-leaning';
  }

  String _poreBand(double score) {
    if (score <= 3.0) return 'Refined';
    if (score <= 5.5) return 'Average';
    return 'Visible';
  }

  String _lowMidHigh(double score, {bool reverse = false}) {
    final s = score.clamp(0.0, 10.0);
    if (reverse) {
      if (s <= 3.3) return 'Low';
      if (s <= 6.6) return 'Moderate';
      return 'High';
    }
    if (s >= 7.0) return 'Strong';
    if (s >= 4.5) return 'Moderate';
    return 'Low';
  }

  Color _scoreAccent(double score) {
    if (score >= 8.5) return const Color(0xFFB68A4E);
    if (score >= 7.0) return const Color(0xFFC29560);
    if (score >= 5.5) return const Color(0xFFBD7C85);
    return const Color(0xFFC76A55);
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: MyApp.clinicalSlate.withValues(alpha: 0.15),
      width: 0.6,
    ),
    boxShadow: [
      BoxShadow(
        color: MyApp.clinicalNavy.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

class _TextItem {
  final String title;
  final String detail;

  const _TextItem(this.title, this.detail);
}

class _ReportBundle {
  final double overallScore;
  final String overallBand;
  final List<_ReportMetric> metrics;

  const _ReportBundle({
    required this.overallScore,
    required this.overallBand,
    required this.metrics,
  });
}

class _ReportMetric {
  final String key;
  final String label;
  final double rawValue;
  final String displayValue;
  final String description;
  final String status;
  final double score;
  final IconData icon;
  final Color accent;

  const _ReportMetric({
    required this.key,
    required this.label,
    required this.rawValue,
    required this.displayValue,
    required this.description,
    required this.status,
    required this.score,
    required this.icon,
    required this.accent,
  });
}

class _CvSignals {
  final double hydrationPercent;
  final double hydrationScore;
  final double oilinessPercent;
  final double oilinessLevelScore;
  final double poreVisibilityScore;
  final double poreSizeMm;
  final double sensitivityScore;
  final double rednessScore;
  final double textureRoughnessScore;
  final double collagenScore;

  const _CvSignals({
    required this.hydrationPercent,
    required this.hydrationScore,
    required this.oilinessPercent,
    required this.oilinessLevelScore,
    required this.poreVisibilityScore,
    required this.poreSizeMm,
    required this.sensitivityScore,
    required this.rednessScore,
    required this.textureRoughnessScore,
    required this.collagenScore,
  });
}

class _RecommendedProduct {
  const _RecommendedProduct({
    required this.brand,
    required this.name,
    required this.price,
    required this.reasonTag,
    required this.affiliateUrl,
  });

  final String brand;
  final String name;
  final String price;
  final String reasonTag;
  final String affiliateUrl;
}

/// Calm, premium scanning indicator: a gold core with expanding concentric
/// pulse rings, a rotating sweep arc, and orbiting particle glints. Used in
/// the analyzing stage to make AI processing feel expensive and unhurried.
class _LuxeScanningIndicator extends StatefulWidget {
  const _LuxeScanningIndicator();

  @override
  State<_LuxeScanningIndicator> createState() => _LuxeScanningIndicatorState();
}

class _LuxeScanningIndicatorState extends State<_LuxeScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 152,
      height: 152,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScanPulsePainter(
              progress: _controller.value,
              gold: AppColors.champagneGold,
            ),
            child: Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.champagneGold,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.onChampagneGold,
                  size: 26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated concentric pulse + rotating sweep + orbiting particles for the
/// [_LuxeScanningIndicator]. Purely decorative.
class _ScanPulsePainter extends CustomPainter {
  final double progress;
  final Color gold;

  _ScanPulsePainter({required this.progress, required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const twoPi = math.pi * 2;

    // Expanding concentric pulse rings.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 30 + t * (maxRadius - 30);
      final opacity = ((1 - t) * 0.5).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = gold.withValues(alpha: opacity),
      );
    }

    // Faint static guide ring.
    canvas.drawCircle(
      center,
      maxRadius - 6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gold.withValues(alpha: 0.12),
    );

    // Rotating sweep arc.
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius - 6);
    canvas.drawArc(
      sweepRect,
      progress * twoPi,
      1.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [gold.withValues(alpha: 0.0), gold.withValues(alpha: 0.9)],
          transform: GradientRotation(progress * twoPi),
        ).createShader(sweepRect),
    );

    // Orbiting particle glints.
    for (var i = 0; i < 6; i++) {
      final angle = progress * twoPi + i * (twoPi / 6);
      final r = maxRadius - 18;
      final dot = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      final dotOpacity = (0.25 + 0.55 * ((math.sin(angle * 2) + 1) / 2)).clamp(
        0.0,
        1.0,
      );
      canvas.drawCircle(
        dot,
        2.2,
        Paint()..color = gold.withValues(alpha: dotOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPulsePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Static gold "scan target" overlay: corner brackets plus faint concentric
/// guide rings, with an optional animated expanding [pulse] ring. Layered over
/// the selected photo preview and the empty photo placeholder to give the
/// capture flow a calibrated, clinical-luxury feel.
class _ScanFramePainter extends CustomPainter {
  final Color color;
  final Color ringColor;
  final double? pulse;

  _ScanFramePainter({required this.color, required this.ringColor, this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0;
    const len = 22.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;

    final w = size.width;
    final h = size.height;

    // Top-left.
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset + len, inset),
      paint,
    );
    canvas.drawLine(
      const Offset(inset, inset),
      const Offset(inset, inset + len),
      paint,
    );
    // Top-right.
    canvas.drawLine(
      Offset(w - inset, inset),
      Offset(w - inset - len, inset),
      paint,
    );
    canvas.drawLine(
      Offset(w - inset, inset),
      Offset(w - inset, inset + len),
      paint,
    );
    // Bottom-left.
    canvas.drawLine(
      Offset(inset, h - inset),
      Offset(inset + len, h - inset),
      paint,
    );
    canvas.drawLine(
      Offset(inset, h - inset),
      Offset(inset, h - inset - len),
      paint,
    );
    // Bottom-right.
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset - len, h - inset),
      paint,
    );
    canvas.drawLine(
      Offset(w - inset, h - inset),
      Offset(w - inset, h - inset - len),
      paint,
    );

    // Concentric guide rings.
    final center = Offset(w / 2, h / 2);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ringColor;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, 16.0 * i, ringPaint);
    }

    // Animated expanding pulse ring + orbiting glints when a pulse value is
    // supplied (used by the empty-state placeholder).
    final p = pulse;
    if (p != null) {
      const twoPi = math.pi * 2;
      final t = p % 1.0;
      final radius = 16 + t * 54;
      final opacity = ((1 - t) * 0.55).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = ringColor.withValues(alpha: opacity),
      );
      for (var i = 0; i < 6; i++) {
        final angle = p * twoPi + i * (twoPi / 6);
        const orbit = 44.0;
        final dot = Offset(
          center.dx + orbit * math.cos(angle),
          center.dy + orbit * math.sin(angle),
        );
        final glint = (0.25 + 0.5 * ((math.sin(angle * 2) + 1) / 2)).clamp(
          0.0,
          1.0,
        );
        canvas.drawCircle(
          dot,
          1.8,
          Paint()..color = ringColor.withValues(alpha: glint),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.pulse != pulse;
}

/// Empty-state capture target: an animated, softly glowing gold scan frame with
/// a breathing border, pulse ring and orbiting glints. Shown before a photo is
/// selected to make the capture step feel premium and alive.
class _PulsingScanFrame extends StatefulWidget {
  const _PulsingScanFrame();

  @override
  State<_PulsingScanFrame> createState() => _PulsingScanFrameState();
}

class _PulsingScanFrameState extends State<_PulsingScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = 0.5 + 0.5 * math.sin(_controller.value * math.pi * 2);
        return Container(
          height: 178,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.warmAlabaster,
                AppColors.champagneGold.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.champagneGold.withValues(
                alpha: 0.45 + 0.35 * glow,
              ),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.champagneGold.withValues(
                  alpha: 0.12 + 0.18 * glow,
                ),
                blurRadius: 18 + 12 * glow,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScanFramePainter(
                      color: AppColors.champagneGold.withValues(
                        alpha: 0.6 + 0.3 * glow,
                      ),
                      ringColor: AppColors.champagneGold.withValues(alpha: 0.5),
                      pulse: _controller.value,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.champagneGold.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.5 + 0.3 * glow,
                          ),
                          width: 1.2,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_a_photo_outlined,
                        size: 24,
                        color: AppColors.goldHover,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a clear face photo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.refinedSlate,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Good lighting · neutral expression · no makeup if possible',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.refinedSlate.withValues(alpha: 0.74),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
