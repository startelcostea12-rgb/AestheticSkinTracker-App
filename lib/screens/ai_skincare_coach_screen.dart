import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../models/procedure_log.dart';
import '../models/skincare/skincare_models.dart' as core;
import '../repositories/skincare_repository_impl.dart';
import '../services/ai_llm_service.dart';
import '../utils/ai_skin_advisor_prompt.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/local_image_preview.dart';
import '../widgets/luxe_loading_view.dart';

/// Flagship premium AI skincare coaching surface.
///
/// Prompt construction uses [aiSkinAdvisorSystemPrompt] and
/// [buildAiSkinAdvisorUserPrompt], then sends the request through
/// [AiService]. Local guidance is reserved only for the missing-key
/// configuration fallback.
class AISkincareCoachScreen extends StatefulWidget {
  const AISkincareCoachScreen({super.key, this.initialLog});

  /// When provided, the coach is seeded with this specific procedure's
  /// context and its own attached photo (Before/After/Progress) instead of
  /// falling back to the most recent global scan photo. This keeps every
  /// procedure's photos and details isolated from one another.
  final ProcedureLog? initialLog;

  @override
  State<AISkincareCoachScreen> createState() => _AISkincareCoachScreenState();
}

class _AISkincareCoachScreenState extends State<AISkincareCoachScreen> {
  static const List<String> _coachFocusAreas = [
    'Full Face',
    'Forehead',
    'Cheeks',
    'Chin & Jawline',
    'Under Eyes',
  ];

  final TextEditingController _coachInput = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AiService _coachService = const AiService();
  final SkincareRepositoryImpl _skincareRepository = SkincareRepositoryImpl();

  /// Maximum number of automatic "continue where you left off" calls made when
  /// a coach reply is detected as truncated, so long routines finish fully.
  static const int _maxContinuationAttempts = 5;

  bool _loading = true;
  bool _sending = false;
  bool _analyzingPhoto = false;
  String? _error;
  File? _chatImage; // Image to send with next message
  bool _showDisclaimerBanner = true;

  String _name = '';
  String _age = '';
  List<String> _concerns = const [];
  String _procedure = '';
  core.UserSkinProfile? _userSkinProfile;
  List<core.LoggedProduct> _products = const [];
  List<core.ScanRecord> _scans = const [];
  core.ScanRecord? _latestPhotoScan;
  String? _latestPhotoPath;
  String _latestPhotoSummary = 'No recent photo analysis available yet.';
  String _lastCoachReply =
      'Upload a progress photo or ask a question to receive personalized guidance.';

  /// The routines prompt from the most recent generation, reused by the manual
  /// "Continue Routine" button to stitch a truncated routine back together.
  String? _lastRoutinesPrompt;

  /// The specific procedure log this coach session is scoped to (if any).
  /// All context and photos come from THIS log only — never another one.
  ProcedureLog? _seededLog;
  bool _autoAnalysisTriggered = false;

  @override
  void initState() {
    super.initState();
    _loadDisclaimerBannerState();
    _loadContext();
  }

  Future<void> _loadDisclaimerBannerState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('coach_disclaimer_dismissed') ?? false;
    if (mounted) {
      setState(() => _showDisclaimerBanner = !dismissed);
    }
  }

  Future<void> _dismissDisclaimerBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('coach_disclaimer_dismissed', true);
    if (mounted) {
      setState(() => _showDisclaimerBanner = false);
    }
  }

  @override
  void dispose() {
    _coachInput.dispose();
    _scrollController.dispose();
    unawaited(_skincareRepository.dispose());
    super.dispose();
  }

  Future<void> _loadContext() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userSkinProfile = await _skincareRepository.getAiCoachContext(
        SkincareRepositoryImpl.defaultUserId,
      );
      final profile =
          userSkinProfile ??
          core.UserSkinProfile.empty(id: SkincareRepositoryImpl.defaultUserId);
      final name = profile.displayName.trim().isEmpty
          ? 'Guest'
          : profile.displayName.trim();
      final age = profile.onboarding.ageRange;
      final concerns = profile.concerns;
      final procedure = _latestProcedureForPrompt(profile.procedureHistory);
      final products = profile.currentProducts;
      final scans = profile.scanHistory;
      final latestScan = _latestPhotoScanFrom(scans);

      // If launched for a specific procedure log, prefer that log's own
      // context and photo so the coach never analyzes another procedure's
      // last-used photo.
      final seedLog = widget.initialLog;
      final seedProcedure = seedLog != null && seedLog.procedureType.isNotEmpty
          ? seedLog.procedureType
          : procedure;
      final seedPhotoPath = _photoPathForLog(seedLog);

      if (seedLog != null) {
        debugPrint(
          'Seeded Coach with ProcedureLog ID: ${seedLog.id} - '
          '${seedLog.procedureType} '
          '(photos: ${seedLog.photoPaths.length})',
        );
      }

      if (!mounted) return;
      setState(() {
        _name = name;
        _age = age;
        _concerns = concerns;
        _procedure = seedProcedure;
        _userSkinProfile = profile;
        _products = products;
        _scans = scans;
        _seededLog = seedLog;
        if (seedLog != null) {
          // Isolate this session: discard any global "last used" scan/photo
          // so nothing can override the seeded log's own data.
          _latestPhotoScan = null;
          _latestPhotoPath = seedPhotoPath;
          _chatImage = null;
          _lastCoachReply =
              'Reviewing your ${seedLog.procedureType} log — preparing '
              'guidance for this specific session...';
          _latestPhotoSummary = seedPhotoPath != null
              ? 'Reviewing your ${seedLog.procedureType} log with its '
                    'attached photo.'
              : 'Reviewing your ${seedLog.procedureType} log.';
        } else {
          _latestPhotoScan = latestScan;
          _latestPhotoPath = latestScan?.imagePath;
          _latestPhotoSummary = _summaryForScan(latestScan);
        }
        _loading = false;
      });

      // Seed the pending chat image with this log's own photo (native only —
      // web picker paths are transient blob URLs that cannot be re-read here).
      if (seedLog != null && !kIsWeb && seedPhotoPath != null) {
        final seedFile = File(seedPhotoPath);
        if (seedFile.existsSync() && mounted) {
          setState(() => _chatImage = seedFile);
        }
      }

      // Auto-send an isolated first message about THIS specific log so its
      // photos + details drive the very first coach response.
      if (seedLog != null && !_autoAnalysisTriggered) {
        _autoAnalysisTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestInitialProcedureAdvice(seedLog);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load your skincare profile. Pull down or try again.';
      });
    }
  }

  Future<void> _pickProgressPhoto(ImageSource source) async {
    setState(() {
      _analyzingPhoto = true;
      _error = null;
    });
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (picked == null) {
        if (mounted) setState(() => _analyzingPhoto = false);
        return;
      }

      final focusArea = await _showFocusAreaSheet();
      if (focusArea == null) {
        if (mounted) setState(() => _analyzingPhoto = false);
        return;
      }

      final savedImagePath = await _persistProgressPhoto(picked);
      final now = DateTime.now();
      final sourceLabel = source == ImageSource.camera ? 'taken' : 'selected';
      final entry = core.ScanRecord(
        id: 'ai_coach_${now.millisecondsSinceEpoch}',
        capturedAt: now,
        imagePath: savedImagePath,
        source: core.ScanSource.aiAnalysis,
        procedureId: _userSkinProfile?.procedureHistory.isNotEmpty == true
            ? _userSkinProfile!.procedureHistory.first.id
            : null,
        focusArea: focusArea,
        notes:
            'Progress photo $sourceLabel from AI Skincare Coach for $focusArea',
        aiSummary:
            'Progress photo $sourceLabel from AI Skincare Coach for $focusArea.',
        metrics: const core.SkinMetricSet(
          redness: 5,
          texture: 5,
          fineLines: 5,
          pores: 5,
          pigmentation: 5,
          firmness: 5,
        ),
        visibleFindings: ['progress photo saved', 'focus area: $focusArea'],
        createdAt: now,
      );
      await _skincareRepository.addScanRecord(
        SkincareRepositoryImpl.defaultUserId,
        entry,
      );
      final userSkinProfile = await _skincareRepository.getAiCoachContext(
        SkincareRepositoryImpl.defaultUserId,
      );
      final updatedScans = userSkinProfile?.scanHistory ?? [entry];
      final latestScan = _latestPhotoScanFrom(updatedScans) ?? entry;

      if (!mounted) return;
      setState(() {
        _scans = updatedScans;
        _userSkinProfile = userSkinProfile;
        _latestPhotoScan = latestScan;
        _latestPhotoPath = latestScan.imagePath;
        _latestPhotoSummary = _summaryForScan(latestScan);
        _lastCoachReply =
            'Your $focusArea progress photo is saved and previewed here. I can now use it as part of your coaching context for routines, recovery guidance, and next-scan trend planning.';
        _analyzingPhoto = false;
      });
      _showMessage('Progress photo saved to your scan history.');
      await _requestPhotoAnalysisAdvice(focusArea, scanId: entry.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyzingPhoto = false;
        _error = 'Could not load that photo. Please try another image.';
      });
    }
  }

  /// Persists the selected progress photo to a stable reference before it is
  /// written into scan history. On web this is an inline data URI; on native it
  /// is copied into the app documents directory instead of leaving it in the
  /// image picker's temporary cache.
  Future<String> _persistProgressPhoto(XFile picked) async {
    final bytes = await picked.readAsBytes();
    if (kIsWeb) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = _extensionForPickedImage(picked.path);
    final fileName = 'ai_coach_progress_$timestamp$extension';
    final destinationPath = '${dir.path}/$fileName';
    await picked.saveTo(destinationPath);
    return destinationPath;
  }

  Future<String?> _showFocusAreaSheet() {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.refinedSlate.withValues(alpha: 0.38),
      builder: (sheetContext) {
        var selected = _coachFocusAreas.first;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  decoration: BoxDecoration(
                    color: AppColors.warmAlabaster,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.champagneGold.withValues(alpha: 0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.refinedSlate.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.42,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.champagneGold.withValues(
                                alpha: 0.16,
                              ),
                              border: Border.all(
                                color: AppColors.champagneGold.withValues(
                                  alpha: 0.42,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.face_retouching_natural_rounded,
                              color: AppColors.goldHover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Which area is this photo focusing on?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    height: 1.15,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.refinedSlate,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'This helps your coach compare the right area over time.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.refinedSlate.withValues(
                                      alpha: 0.66,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in _coachFocusAreas)
                            _FocusAreaChip(
                              label: option,
                              selected: selected == option,
                              onTap: () {
                                setSheetState(() => selected = option);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(selected),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Save Photo'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.champagneGold,
                          foregroundColor: AppColors.onChampagneGold,
                          minimumSize: const Size(double.infinity, 52),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.refinedSlate.withValues(
                              alpha: 0.68,
                            ),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _extensionForPickedImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.heic')) return '.heic';
    return '.jpg';
  }

  core.ScanRecord? _latestPhotoScanFrom(List<core.ScanRecord> scans) {
    final withPhoto =
        scans.where((scan) => (scan.imagePath ?? '').trim().isNotEmpty).toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return withPhoto.isEmpty ? null : withPhoto.first;
  }

  /// Picks the most relevant photo for a specific procedure log, preferring
  /// an "After" photo, then "Progress", then "Before", then the first photo.
  String? _photoPathForLog(ProcedureLog? log) {
    if (log == null || log.photoPaths.isEmpty) return null;
    for (final label in const ['After', 'Progress', 'Before']) {
      final path = log.photoForLabel(label);
      if (path != null && path.trim().isNotEmpty) return path;
    }
    for (final path in log.photoPaths) {
      if (path.trim().isNotEmpty) return path;
    }
    return null;
  }

  /// Builds a compact, human-readable context block for a specific procedure
  /// log. Used to anchor the coach to THIS log's data (isolated per id).
  String _procedureContextBlock(ProcedureLog log) {
    final buffer = StringBuffer()
      ..writeln('SPECIFIC PROCEDURE LOG UNDER REVIEW (prioritize this data):')
      ..writeln('- Log ID: ${log.id}')
      ..writeln('- Procedure: ${log.procedureType}');
    if ((log.category ?? '').trim().isNotEmpty) {
      buffer.writeln('- Category: ${log.category}');
    }
    buffer.writeln(
      '- Date: ${DateFormat('MMM dd, yyyy').format(log.dateTime)}',
    );
    if (log.intensity != null) {
      buffer.writeln('- Intensity: ${log.intensity}/10');
    }
    if ((log.settings ?? '').trim().isNotEmpty) {
      buffer.writeln('- Settings: ${log.settings}');
    }
    if (log.productsUsed.isNotEmpty) {
      buffer.writeln('- Products used: ${log.productsUsed.join(', ')}');
    }
    if (log.reactionScore != null) {
      buffer.writeln('- Reaction score: ${log.reactionScore}/10');
    }
    if ((log.notes ?? '').trim().isNotEmpty) {
      buffer.writeln('- Notes: ${log.notes}');
    }
    if (log.labeledPhotos.isNotEmpty) {
      final labels = log.labeledPhotos.map((p) => p.label).join(', ');
      buffer.writeln('- Attached photos (${log.photoPaths.length}): $labels');
    }
    return buffer.toString().trim();
  }

  /// Auto-triggers the first coach response scoped to a specific log, sending
  /// its own photo (native) so the reply is about THIS procedure only.
  Future<void> _requestInitialProcedureAdvice(ProcedureLog log) async {
    if (_sending) return;

    debugPrint(
      'Coach initial analysis for ProcedureLog ID: ${log.id} - '
      '${log.procedureType} using ${log.photoPaths.length} photo(s): '
      '${log.photoPaths.join(", ")}',
    );

    // Build a goal that embeds THIS log's own details + photo paths so the
    // model treats them as the single source of truth for this session.
    final goal =
        'I just logged this specific ${log.procedureType} procedure. '
        'Review ONLY this session using its attached photo(s) and the details '
        'below — ignore any other procedure or previously used photo.\n\n'
        '${_procedureContextBlock(log)}';

    await _requestCoachAdvice(goal, chatImage: _chatImage);
  }

  Future<void> _sendCoachMessage() async {
    final question = _coachInput.text.trim();
    final imageToSend = _chatImage;

    if (question.isEmpty && imageToSend == null) return;
    if (_sending) return;

    _coachInput.clear();
    setState(() => _chatImage = null);

    await _requestCoachAdvice(
      question.isEmpty ? 'Analyze this skin photo' : question,
      chatImage: imageToSend,
    );
  }

  Future<void> _pickChatImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked == null) return;

      if (kIsWeb) {
        // Web: use XFile directly
        setState(() => _chatImage = File(picked.path));
      } else {
        // Native: persist to app directory
        final bytes = await picked.readAsBytes();
        final dir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final localFile = File('${dir.path}/chat_image_$timestamp.jpg');
        await localFile.writeAsBytes(bytes);
        setState(() => _chatImage = localFile);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image: $error')));
    }
  }

  void _removeChatImage() {
    setState(() => _chatImage = null);
  }

  Future<void> _getTodaysAdvice() async {
    await _requestCoachAdvice(
      'Create today\'s personalized morning and evening skincare plan, with recovery cautions, one progress insight, and one 7-day action step.',
    );
  }

  Future<void> _requestPhotoAnalysisAdvice(
    String focusArea, {
    required String scanId,
  }) async {
    await _requestCoachAdvice(
      'Analyze the latest saved photo analysis for $focusArea. Describe visible skin characteristics such as redness, texture, fine lines, wrinkles, uneven tone, dullness, pores, or dryness, then give gentle recommendations based on those observations and the saved UserSkinProfile. Do not infer or mention any procedure unless it is explicitly logged in UserSkinProfile.procedureHistory.',
      scanIdForMetricUpdate: scanId,
    );
  }

  Future<void> _requestCoachAdvice(
    String userGoal, {
    String? scanIdForMetricUpdate,
    File? chatImage,
  }) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
      _lastCoachReply = chatImage != null
          ? 'Coach is analyzing your photo...'
          : 'Coach is preparing your personalized guidance...';
    });

    // If image is provided, use vision analysis
    if (chatImage != null && !kIsWeb) {
      try {
        final seededLog = _seededLog;
        final procedureBlock = seededLog != null
            ? '${_procedureContextBlock(seededLog)}\n\n'
            : '';
        final visionPrompt =
            '''User Context for Personalization:

Current Goal: $userGoal

$procedureBlock${procedureBlock.isNotEmpty ? '''When the goal references a specific logged procedure, prioritize the '''
                      '''SPECIFIC PROCEDURE LOG details above and treat the uploaded photo '''
                      '''as belonging to that exact log.\n\n''' : ''}User Skin Profile:
${jsonEncode(_userSkinProfile?.toJson() ?? {})}

---

Analyze the uploaded skin photo following the structured format. Reference the user's profile, goals, and procedure history when relevant for personalized recommendations.''';

        final visionReply = await _coachService.analyzeSkinWithImage(
          imageFile: chatImage,
          systemPrompt: geminiVisionSinglePhotoPrompt,
          userPrompt: visionPrompt,
        );

        if (!mounted) return;
        setState(() {
          _lastCoachReply = visionReply.isEmpty
              ? 'The photo analysis returned an empty response. Please try again.'
              : visionReply;
          _sending = false;
          if (visionReply.isEmpty) {
            _error = 'Vision analysis returned empty response.';
          }
        });
        _scrollToBottom();
        return;
      } on AiLlmConfigurationException catch (e) {
        if (!mounted) return;
        setState(() {
          _lastCoachReply =
              'GEMINI_API_KEY not configured. '
              'To enable photo analysis, rebuild with:\n\n'
              'flutter run --dart-define=GEMINI_API_KEY=your_key';
          _error = e.message;
          _sending = false;
        });
        _scrollToBottom();
        return;
      } on AiLlmException catch (e) {
        if (!mounted) return;
        setState(() {
          _lastCoachReply = 'Photo analysis failed: ${e.message}';
          _error = e.message;
          _sending = false;
        });
        _scrollToBottom();
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _lastCoachReply = 'Unexpected error during photo analysis: $error';
          _error = error.toString();
          _sending = false;
        });
        _scrollToBottom();
        return;
      }
    }

    final seededLog = _seededLog;
    final effectiveGoal = seededLog != null
        ? '${_procedureContextBlock(seededLog)}\n\n'
              'Prioritize the SPECIFIC PROCEDURE LOG details above over any '
              'other logged procedure.\n\n$userGoal'
        : userGoal;

    final userPrompt = buildAiSkinAdvisorUserPrompt(
      userSkinProfile: _userSkinProfile,
      skinType: _skinTypeForPrompt,
      sensitivityLevel: _sensitivityLevelForPrompt,
      age: _age,
      concerns: _concernsText,
      procedures: _procedure,
      currentRoutine: _routineForPrompt,
      productPreference: _productPreferenceForPrompt,
      favoriteIngredients: _favoriteIngredientsForPrompt,
      ingredientsToAvoid: _ingredientsToAvoidForPrompt,
      pastProcedures: _pastProceduresForPrompt,
      location: _profileLocationForPrompt,
      climate: _profileClimateForPrompt,
      humidity: _profileHumidityForPrompt,
      goals: _profileGoalsForPrompt,
      notes: _profileNotesForPrompt,
      photoAnalysis: _latestPhotoSummary,
      userGoal: effectiveGoal,
    );

    if (!_coachService.isConfigured) {
      if (!mounted) return;
      setState(() {
        _lastCoachReply = _configurationFallbackReply(userGoal);
        _error = 'Live AI is not configured. Showing built-in guidance.';
        _sending = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final expectsMetricJson = scanIdForMetricUpdate != null;
      final analysisReply = await generateCoachAnalysis(
        userPrompt: userPrompt,
        expectsMetricJson: expectsMetricJson,
      );

      if (!mounted) return;
      final visibleAnalysisReply = _displayableAnalysisReply(analysisReply);
      setState(() {
        _lastCoachReply = visibleAnalysisReply.trim().isEmpty
            ? 'Coach has completed your analysis. Building your personalized routines now...'
            : '${visibleAnalysisReply.trimRight()}\n\nCoach is building your personalized morning and evening routines...';
      });
      _scrollToBottom();

      final routinesReply = await generateCoachRoutines(
        coachContextPrompt: userPrompt,
        analysisSummary: visibleAnalysisReply.isEmpty
            ? analysisReply
            : visibleAnalysisReply,
      );

      if (!mounted) return;
      final visibleRoutinesReply = _displayableAnalysisReply(routinesReply);
      final finalReply = [
        visibleAnalysisReply,
        visibleRoutinesReply,
      ].where((part) => part.trim().isNotEmpty).join('\n\n').trim();
      if (scanIdForMetricUpdate != null && analysisReply.isNotEmpty) {
        await _updateScanMetricsFromAiReply(
          scanIdForMetricUpdate,
          analysisReply,
        );
        if (!mounted) return;
      }
      setState(() {
        _lastCoachReply = finalReply.isEmpty
            ? 'The live AI returned an empty response. Please try again in a moment.'
            : _cleanCoachReply(finalReply);
        _sending = false;
        if (finalReply.isEmpty) {
          _error = 'Live AI returned an empty response. Please try again.';
        } else if (_looksTruncated(finalReply)) {
          _error =
              'Live AI may have stopped early. Please tap Get Today\'s Advice again if you want a fuller answer.';
        }
      });
      _scrollToBottom();
    } on AiLlmConfigurationException catch (_) {
      if (!mounted) return;
      setState(() {
        _lastCoachReply = _configurationFallbackReply(userGoal);
        _error = 'Live AI is not configured. Showing built-in guidance.';
        _sending = false;
      });
      _scrollToBottom();
    } on AiLlmException catch (error) {
      if (!mounted) return;
      setState(() {
        _lastCoachReply = _liveAiErrorMessage(error.message);
        _sending = false;
        _error = 'Live AI could not respond: ${_shortAiError(error.message)}';
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastCoachReply = _liveAiErrorMessage(error.toString());
        _sending = false;
        _error =
            'Live AI could not respond: ${_shortAiError(error.toString())}';
      });
      _scrollToBottom();
    }
  }

  Future<String> generateCoachAnalysis({
    required String userPrompt,
    bool expectsMetricJson = false,
  }) async {
    final buffer = StringBuffer();
    var reply = await _streamCoachReply(
      systemPrompt: coachAnalysisSystemPrompt,
      userPrompt: userPrompt,
      buffer: buffer,
    );

    if (!mounted) return reply.trim();
    var attempts = 0;
    while (mounted &&
        attempts < _maxContinuationAttempts &&
        _looksTruncated(reply, expectsMetricJson: expectsMetricJson)) {
      attempts++;
      setState(() {
        _lastCoachReply = '${reply.trimRight()}\n\nFinishing the analysis...';
      });
      _scrollToBottom();

      reply = await _streamCoachReply(
        systemPrompt: coachAnalysisSystemPrompt,
        userPrompt: _buildContinuationPrompt(
          originalPrompt: userPrompt,
          partialReply: reply,
        ),
        buffer: buffer,
      );
    }

    return reply.trim();
  }

  Future<String> generateCoachRoutines({
    required String coachContextPrompt,
    required String analysisSummary,
  }) async {
    final routinesPrompt = buildAiSkinAdvisorRoutinesUserPrompt(
      coachContextPrompt: coachContextPrompt,
      analysisSummary: analysisSummary,
    );
    _lastRoutinesPrompt = routinesPrompt;
    final buffer = StringBuffer();
    var reply = await _streamCoachReply(
      systemPrompt: coachRoutinesSystemPrompt,
      userPrompt: routinesPrompt,
      buffer: buffer,
      displayPrefix: analysisSummary,
    );

    if (!mounted) return reply.trim();
    var attempts = 0;
    while (mounted &&
        attempts < _maxContinuationAttempts &&
        _looksTruncated(reply)) {
      attempts++;
      setState(() {
        _lastCoachReply = [
          analysisSummary,
          '${reply.trimRight()}\n\nFinishing the routines...',
        ].where((part) => part.trim().isNotEmpty).join('\n\n');
      });
      _scrollToBottom();

      reply = await _streamCoachReply(
        systemPrompt: coachRoutinesSystemPrompt,
        userPrompt: _buildContinuationPrompt(
          originalPrompt: routinesPrompt,
          partialReply: reply,
        ),
        buffer: buffer,
        displayPrefix: analysisSummary,
      );
    }

    return reply.trim();
  }

  Future<String> _streamCoachReply({
    required String systemPrompt,
    required String userPrompt,
    required StringBuffer buffer,
    String? displayPrefix,
  }) async {
    final chunks = await _coachService.streamCoachResponse(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      onRetry: (info) {
        if (!mounted) return;
        final currentReply = buffer.toString().trimRight();
        final visibleReply = _joinCoachParts(displayPrefix, currentReply);
        setState(() {
          _error = null;
          _lastCoachReply = visibleReply.isEmpty
              ? 'AI is temporarily busy. Retrying...'
              : '$visibleReply\n\nAI is temporarily busy. Retrying...';
        });
        _scrollToBottom();
      },
    );

    await for (final chunk in chunks) {
      buffer.write(chunk);
      if (!mounted) return buffer.toString().trim();
      setState(
        () => _lastCoachReply = _joinCoachParts(
          displayPrefix,
          buffer.toString().trimLeft(),
        ),
      );
      _scrollToBottom();
    }

    return buffer.toString().trim();
  }

  String _joinCoachParts(String? first, String second) {
    return [
      first?.trim(),
      second.trim(),
    ].where((part) => part != null && part.isNotEmpty).join('\n\n');
  }

  String _buildContinuationPrompt({
    required String originalPrompt,
    required String partialReply,
  }) {
    return '''
The previous answer was cut off. Continue and complete the response from exactly where it stopped.

Original request:
$originalPrompt

Partial response so far:
$partialReply

Requirements:
- Continue the routine exactly where you left off. Do not repeat previous sections. Complete the evening routine.
- Do not restart from the beginning.
- Continue naturally from the last unfinished sentence or section.
- Finish all remaining required sections, especially the morning routine, evening routine, and final metrics JSON block when requested.
- Stop only after a complete final sentence.
''';
  }

  /// Whether to surface the manual "Continue Routine" button. Shown when the
  /// current reply looks incomplete — it ends with an ellipsis or without
  /// proper sentence-terminating punctuation.
  bool get _shouldShowContinueRoutineButton {
    if (_sending) return false;
    if (_lastRoutinesPrompt == null) return false;
    final reply = _lastCoachReply.trim();
    if (reply.length < 80) return false;
    if (reply.endsWith('...') || reply.endsWith('\u2026')) return true;
    return _looksTruncated(reply);
  }

  /// Manually continue a truncated routine from where it stopped, stitching the
  /// continuation onto the existing reply. Reuses the same bounded-retry logic
  /// as automatic continuation.
  Future<void> _continueRoutine() async {
    final prompt = _lastRoutinesPrompt;
    if (_sending || prompt == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final buffer = StringBuffer()..write(_lastCoachReply.trim());
      var reply = buffer.toString().trim();
      var attempts = 0;
      while (mounted &&
          attempts < _maxContinuationAttempts &&
          _looksTruncated(reply)) {
        attempts++;
        setState(() {
          _lastCoachReply = '${reply.trimRight()}\n\nFinishing the routines...';
        });
        _scrollToBottom();

        reply = await _streamCoachReply(
          systemPrompt: coachRoutinesSystemPrompt,
          userPrompt: _buildContinuationPrompt(
            originalPrompt: prompt,
            partialReply: reply,
          ),
          buffer: buffer,
        );
      }

      if (!mounted) return;
      setState(() {
        _lastCoachReply = _cleanCoachReply(
          _displayableAnalysisReply(reply.trim()),
        );
        _sending = false;
      });
      _scrollToBottom();
    } on AiLlmException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not continue routine: ${_shortAiError(error.message)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'Could not continue routine: ${_shortAiError(error.toString())}';
      });
    }
  }

  bool _looksTruncated(String text, {bool expectsMetricJson = false}) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length < 80) return false;

    final lower = normalized.toLowerCase();
    if (expectsMetricJson && !lower.contains('skinmetricscores')) {
      return true;
    }
    // The model is instructed to close with an "--- End of Routines/Analysis ---"
    // sentinel. If it's present, the reply is complete — do NOT treat the marker's
    // trailing dash as a mid-sentence cutoff (that caused runaway continuations
    // and duplicated paragraphs).
    if (lower.contains('end of routines') ||
        lower.contains('end of analysis')) {
      return false;
    }
    final startedStructuredReply =
        lower.contains('morning routine') ||
        lower.contains('evening routine') ||
        lower.contains('priority focus');
    final hasRequiredEnding = expectsMetricJson
        ? lower.contains('skinmetricscores')
        : lower.contains('evening routine') ||
              lower.contains('skinmetricscores');
    if (startedStructuredReply && !hasRequiredEnding) {
      return true;
    }

    final cleaned = normalized.replaceAll(RegExp(r'[\*_`]+$'), '').trimRight();
    if (cleaned.isEmpty) return false;

    final lastCharacter = cleaned[cleaned.length - 1];
    if (',:;-/'.contains(lastCharacter)) return true;

    // A complete reply should end with sentence-terminating punctuation, a
    // closed JSON/code block, or a closing quote/paren. If it does, treat it as
    // finished.
    const completeEndings = {
      '.',
      '!',
      '?',
      '}',
      ')',
      ']',
      '"',
      '\u2019', // ’
      '\u201d', // ”
      '%',
    };
    if (completeEndings.contains(lastCharacter)) return false;

    final words = cleaned.toLowerCase().split(RegExp(r'\s+'));
    final lastWord = words.last.replaceAll(RegExp(r'[^a-z]'), '');
    const hangingWords = {
      'a',
      'an',
      'and',
      'as',
      'because',
      'for',
      'from',
      'in',
      'of',
      'or',
      'the',
      'to',
      'with',
      'without',
      'your',
    };
    if (hangingWords.contains(lastWord)) return true;

    // Ends on a letter or digit with no terminal punctuation → the model almost
    // certainly stopped mid-sentence (e.g. "...elevated redness and is").
    return RegExp(r'[A-Za-z0-9]$').hasMatch(cleaned);
  }

  /// Cleans a coach reply for display: removes the internal
  /// "--- End of Routines/Analysis ---" sentinel markers, collapses excess blank
  /// lines, and drops consecutive duplicate paragraphs that can slip in from
  /// continuation calls.
  String _cleanCoachReply(String reply) {
    var cleaned = reply.replaceAll(
      RegExp(
        r'-{2,}\s*End of (?:Routines|Analysis)\s*-{2,}',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final paragraphs = cleaned.split(RegExp(r'\n\s*\n'));
    final deduped = <String>[];
    for (final paragraph in paragraphs) {
      final trimmed = paragraph.trim();
      if (trimmed.isEmpty) continue;
      if (deduped.isNotEmpty && deduped.last == trimmed) continue;
      deduped.add(trimmed);
    }
    return deduped.join('\n\n').trim();
  }

  String _liveAiErrorMessage(String details) {
    final shortDetails = _shortAiError(details);
    return 'I reached the live AI service, but it could not complete this request. $shortDetails';
  }

  String _shortAiError(String details) {
    final normalized = details.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.toLowerCase().contains('after retries') ||
        normalized.toLowerCase().contains('temporarily busy')) {
      return 'AI is temporarily busy after several retries. Please try again shortly.';
    }
    if (normalized.contains('gemini-1.5-flash') ||
        normalized.contains('NOT_FOUND')) {
      return 'The selected Gemini model is not available for this API key. Try GEMINI_MODEL=gemini-2.5-flash.';
    }
    if (normalized.contains('API key not valid') ||
        normalized.contains('API_KEY_INVALID')) {
      return 'The Gemini API key was rejected by Google.';
    }
    if (normalized.contains('quota') ||
        normalized.contains('RESOURCE_EXHAUSTED') ||
        normalized.contains('503') ||
        normalized.toLowerCase().contains('unavailable') ||
        normalized.toLowerCase().contains('overloaded') ||
        normalized.toLowerCase().contains('temporarily busy')) {
      return 'AI is temporarily busy after several retries. Please try again shortly.';
    }
    if (normalized.isEmpty) {
      return 'Please try again in a moment.';
    }
    return normalized.length > 180
        ? '${normalized.substring(0, 180)}...'
        : normalized;
  }

  String get _concernsText =>
      _concerns.isEmpty ? 'Not provided' : _concerns.join(', ');

  String get _skinTypeForPrompt {
    final skinType = _userSkinProfile?.onboarding.skinType;
    if (skinType == null) return 'Not provided';
    return switch (skinType) {
      core.SkinType.dry => 'Dry',
      core.SkinType.oily => 'Oily',
      core.SkinType.combination => 'Combination',
      core.SkinType.normal => 'Normal',
      core.SkinType.sensitive => 'Sensitive',
    };
  }

  String get _sensitivityLevelForPrompt {
    final sensitivity = _userSkinProfile?.sensitivityLevel;
    if (sensitivity == null) return 'Not provided';
    return switch (sensitivity) {
      core.SkinSensitivityLevel.low => 'Low',
      core.SkinSensitivityLevel.moderate => 'Moderate',
      core.SkinSensitivityLevel.high => 'High',
      core.SkinSensitivityLevel.veryHigh => 'Very high',
    };
  }

  String get _routineForPrompt {
    final routine = _userSkinProfile?.activeRoutine;
    if (routine != null && routine.allSteps.isNotEmpty) {
      return routine.allSteps
          .map((step) => '${_routineTimeLabel(step.timeOfDay)}: ${step.title}')
          .join('; ');
    }
    if (_products.isEmpty) return 'No logged products yet.';
    return _products.take(6).map((p) => p.name).join(', ');
  }

  String get _productPreferenceForPrompt {
    final preferences = _userSkinProfile?.preferences ?? const <String>[];
    return preferences.isEmpty ? 'Not provided' : preferences.join(', ');
  }

  String get _favoriteIngredientsForPrompt {
    final ingredients =
        _userSkinProfile?.favoriteIngredients ?? const <String>[];
    return ingredients.isEmpty ? 'Not provided' : ingredients.join(', ');
  }

  String get _ingredientsToAvoidForPrompt {
    final ingredients =
        _userSkinProfile?.ingredientsToAvoid ?? const <String>[];
    return ingredients.isEmpty ? 'Not provided' : ingredients.join(', ');
  }

  String get _pastProceduresForPrompt {
    final procedures =
        _userSkinProfile?.procedureHistory ?? const <core.ProcedureRecord>[];
    if (procedures.isEmpty) return 'Not provided';
    return procedures
        .map((procedure) {
          final details = <String>[
            _procedureTypeLabel(procedure.type),
            _formatPromptDate(procedure.date),
            if (procedure.treatmentArea.trim().isNotEmpty)
              procedure.treatmentArea.trim(),
            if (procedure.notes.trim().isNotEmpty) procedure.notes.trim(),
          ].where((value) => value.isNotEmpty).join(' - ');
          return details.isEmpty ? 'Unnamed procedure' : details;
        })
        .join('; ');
  }

  String get _profileLocationForPrompt =>
      _promptTextOrFallback(_userSkinProfile?.onboarding.location);

  String get _profileClimateForPrompt =>
      _promptTextOrFallback(_userSkinProfile?.onboarding.climate);

  String get _profileHumidityForPrompt =>
      _promptTextOrFallback(_userSkinProfile?.onboarding.humidity);

  String get _profileGoalsForPrompt {
    final goals = _userSkinProfile?.goals ?? const <String>[];
    return goals.isEmpty ? 'Not provided' : goals.join(', ');
  }

  String get _profileNotesForPrompt =>
      _promptTextOrFallback(_userSkinProfile?.aiCoachNotes);

  String _promptTextOrFallback(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? 'Not provided' : trimmed;
  }

  String _formatPromptDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  bool get _hasProcedure => _procedure.trim().isNotEmpty;

  String _latestProcedureForPrompt(List<core.ProcedureRecord> procedures) {
    if (procedures.isEmpty) return '';
    final sorted = [...procedures]..sort((a, b) => b.date.compareTo(a.date));
    return _procedureTypeLabel(sorted.first.type);
  }

  String _procedureTypeLabel(core.ProcedureType type) {
    return switch (type) {
      core.ProcedureType.skinPen => 'SkinPen',
      core.ProcedureType.rfMicroneedling => 'RF Microneedling/Morpheus8',
      core.ProcedureType.atHomeMicroneedling => 'At-Home Microneedling',
      core.ProcedureType.halo => 'Halo',
      core.ProcedureType.bbl => 'BBL',
      core.ProcedureType.ipl => 'IPL',
      core.ProcedureType.laserResurfacing => 'Laser Resurfacing',
      core.ProcedureType.chemicalPeel => 'Chemical Peel',
      core.ProcedureType.hydraFacial => 'HydraFacial',
      core.ProcedureType.ledLightTherapy => 'LED Light Therapy',
      core.ProcedureType.guaSha => 'Gua Sha',
      core.ProcedureType.facial => 'Facial',
      core.ProcedureType.injectable => 'Injectable',
      core.ProcedureType.other => 'Other',
    };
  }

  String _routineTimeLabel(core.RoutineTimeOfDay timeOfDay) {
    return switch (timeOfDay) {
      core.RoutineTimeOfDay.morning => 'Morning',
      core.RoutineTimeOfDay.evening => 'Evening',
      core.RoutineTimeOfDay.weekly => 'Weekly',
      core.RoutineTimeOfDay.asNeeded => 'As needed',
    };
  }

  String _scanCountLabel() {
    final count = _scans.length;
    if (count == 0) return 'Start a scan streak to unlock trend predictions.';
    if (count == 1) {
      return 'One scan is saved so far; your next scan unlocks clearer trend guidance.';
    }
    return '$count scans are saved, giving your coach stronger progress context.';
  }

  Future<void> _updateScanMetricsFromAiReply(
    String scanId,
    String reply,
  ) async {
    final parsed = _parseAiPhotoMetrics(reply);
    if (parsed == null) return;

    final currentScans = await _skincareRepository.getScanHistory(
      SkincareRepositoryImpl.defaultUserId,
    );
    final scanIndex = currentScans.indexWhere((scan) => scan.id == scanId);
    if (scanIndex == -1) return;

    final existing = currentScans[scanIndex];
    final updatedScan = existing.copyWith(
      metrics: parsed.metrics,
      visibleFindings: parsed.visibleFindings.isEmpty
          ? existing.visibleFindings
          : parsed.visibleFindings,
      aiSummary: parsed.summary.isEmpty ? existing.aiSummary : parsed.summary,
      notes: [
        existing.notes,
        'AI metric scores saved from latest photo analysis.',
      ].where((value) => value.trim().isNotEmpty).join(' | '),
    );

    await _skincareRepository.updateScanRecord(
      SkincareRepositoryImpl.defaultUserId,
      updatedScan,
    );
    final profile = await _skincareRepository.getAiCoachContext(
      SkincareRepositoryImpl.defaultUserId,
    );
    final scans = profile?.scanHistory ?? currentScans;
    final latestScan = _latestPhotoScanFrom(scans) ?? updatedScan;

    if (!mounted) return;
    setState(() {
      _userSkinProfile = profile;
      _scans = scans;
      _latestPhotoScan = latestScan;
      _latestPhotoPath = latestScan.imagePath;
      _latestPhotoSummary = _summaryForScan(latestScan);
    });
  }

  _ParsedPhotoMetrics? _parseAiPhotoMetrics(String reply) {
    for (final map in _candidateJsonMaps(reply).reversed) {
      final parsed = _parsedMetricsFromMap(map);
      if (parsed != null) return parsed;
    }
    return _parseMetricLines(reply);
  }

  String _displayableAnalysisReply(String reply) {
    var display = reply.trim();

    // The metrics JSON block is only for the dashboard parser and must never
    // be shown in the coach reply. It is always emitted at the very end of the
    // response, so locate where it begins (fenced or raw, complete or
    // truncated) and cut everything from there onward.
    var cut = -1;

    final fencedJson = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in fencedJson.allMatches(display)) {
      final body = match.group(1) ?? '';
      final decoded = _decodeJsonMap(body);
      final isMetrics =
          (decoded != null && _parsedMetricsFromMap(decoded) != null) ||
          _looksLikeMetricBlock(body);
      if (isMetrics && (cut < 0 || match.start < cut)) cut = match.start;
    }

    for (final block in _braceBlocks(display)) {
      final decoded = _decodeJsonMap(block);
      final isMetrics =
          (decoded != null && _parsedMetricsFromMap(decoded) != null) ||
          _looksLikeMetricBlock(block);
      if (isMetrics) {
        final idx = display.indexOf(block);
        if (idx >= 0 && (cut < 0 || idx < cut)) cut = idx;
      }
    }

    // Fallback for truncated/unbalanced JSON that never closes but still names
    // the metrics schema.
    if (cut < 0) {
      final signal = display.toLowerCase().indexOf('skinmetricscores');
      if (signal >= 0) {
        final brace = display.lastIndexOf('{', signal);
        cut = brace >= 0 ? brace : signal;
      }
    }

    if (cut >= 0) {
      final head = display.substring(0, cut);
      // Drop a dangling ```json fence marker that preceded the block.
      final fenceStart = RegExp(
        r'```(?:json)?\s*$',
        caseSensitive: false,
      ).firstMatch(head);
      display = fenceStart != null ? head.substring(0, fenceStart.start) : head;
    }

    return display.trim();
  }

  bool _looksLikeMetricBlock(String text) {
    final lower = text.toLowerCase();
    return lower.contains('skinmetricscores') ||
        lower.contains('visiblefindings');
  }

  List<Map<String, dynamic>> _candidateJsonMaps(String text) {
    final candidates = <Map<String, dynamic>>[];
    final fencedJson = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in fencedJson.allMatches(text)) {
      final decoded = _decodeJsonMap(match.group(1) ?? '');
      if (decoded != null) candidates.add(decoded);
    }

    for (final block in _braceBlocks(text)) {
      final decoded = _decodeJsonMap(block);
      if (decoded != null) candidates.add(decoded);
    }
    return candidates;
  }

  List<String> _braceBlocks(String text) {
    final blocks = <String>[];
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;

    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        if (depth == 0) start = index;
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          blocks.add(text.substring(start, index + 1));
          start = -1;
        }
      }
    }
    return blocks;
  }

  Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  _ParsedPhotoMetrics? _parsedMetricsFromMap(Map<String, dynamic> map) {
    final container = _metricContainer(map);
    if (container == null) return null;

    final scale = _readMetricScale(container) ?? _readMetricScale(map) ?? 10;
    final redness = _readMetricValue(container, const ['redness']);
    final texture = _readMetricValue(container, const ['texture']);
    final wrinkles = _readMetricValue(container, const [
      'wrinkles',
      'fineLines',
      'fine_lines',
    ]);
    final pores = _readMetricValue(container, const ['pores']);
    final darkSpots = _readMetricValue(container, const [
      'darkSpots',
      'dark_spots',
      'pigmentation',
    ]);
    final elasticity = _readMetricValue(container, const [
      'elasticity',
      'firmness',
    ]);

    if ([
      redness,
      texture,
      wrinkles,
      pores,
      darkSpots,
      elasticity,
    ].any((value) => value == null)) {
      return null;
    }

    return _ParsedPhotoMetrics(
      metrics: core.SkinMetricSet(
        redness: _normalizeMetricScore(redness!, scale),
        texture: _normalizeMetricScore(texture!, scale),
        fineLines: _normalizeMetricScore(wrinkles!, scale),
        pores: _normalizeMetricScore(pores!, scale),
        pigmentation: _normalizeMetricScore(darkSpots!, scale),
        firmness: _normalizeMetricScore(elasticity!, scale),
      ),
      visibleFindings: _readVisibleFindings(map),
      summary: _readMetricSummary(map),
    );
  }

  Map<String, dynamic>? _metricContainer(Map<String, dynamic> map) {
    const keys = [
      'skinMetricScores',
      'skin_metric_scores',
      'metrics',
      'scores',
    ];
    for (final key in keys) {
      final value = map[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    if (_readMetricValue(map, const ['redness']) != null) return map;
    return null;
  }

  double? _readMetricScale(Map<String, dynamic> map) {
    final raw = map['scale'] ?? map['scoreScale'] ?? map['score_scale'];
    if (raw is num) return raw.toDouble();
    final text = raw?.toString() ?? '';
    if (text.contains('0-5') || text.contains('/5')) return 5;
    if (text.contains('0-10') || text.contains('/10')) return 10;
    return double.tryParse(text);
  }

  double? _readMetricValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) return _toDouble(map[key]);
      final normalizedKey = _normalizeMetricKey(key);
      for (final entry in map.entries) {
        if (_normalizeMetricKey(entry.key) == normalizedKey) {
          return _toDouble(entry.value);
        }
      }
    }
    return null;
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    final text = value?.toString() ?? '';
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  double _normalizeMetricScore(double value, double scale) {
    final normalized = scale <= 5 ? value * 2 : value;
    return normalized.clamp(0, 10).toDouble();
  }

  String _normalizeMetricKey(Object? key) => (key?.toString() ?? '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();

  List<String> _readVisibleFindings(Map<String, dynamic> map) {
    final value = map['visibleFindings'] ?? map['visible_findings'];
    if (value is Iterable) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  String _readMetricSummary(Map<String, dynamic> map) {
    final value = map['summary'] ?? map['aiSummary'] ?? map['ai_summary'];
    return value?.toString().trim() ?? '';
  }

  _ParsedPhotoMetrics? _parseMetricLines(String reply) {
    final values = <String, double>{};
    for (final line in reply.split(RegExp(r'\r?\n'))) {
      final match = RegExp(
        r'(redness|texture|wrinkles?|fine\s*lines?|pores?|dark\s*spots?|pigmentation|elasticity|firmness)\s*[:=\-]\s*(\d+(?:\.\d+)?)(?:\s*/\s*(5|10))?',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final key = _normalizeMetricKey(match.group(1));
      final value = double.tryParse(match.group(2) ?? '');
      if (value == null) continue;
      final scale = double.tryParse(match.group(3) ?? '10') ?? 10;
      values[key] = _normalizeMetricScore(value, scale);
    }

    double? valueFor(List<String> keys) {
      for (final key in keys) {
        final value = values[_normalizeMetricKey(key)];
        if (value != null) return value;
      }
      return null;
    }

    final redness = valueFor(const ['redness']);
    final texture = valueFor(const ['texture']);
    final wrinkles = valueFor(const ['wrinkles', 'fineLines']);
    final pores = valueFor(const ['pores']);
    final darkSpots = valueFor(const ['darkSpots', 'pigmentation']);
    final elasticity = valueFor(const ['elasticity', 'firmness']);
    if ([
      redness,
      texture,
      wrinkles,
      pores,
      darkSpots,
      elasticity,
    ].any((value) => value == null)) {
      return null;
    }

    return _ParsedPhotoMetrics(
      metrics: core.SkinMetricSet(
        redness: redness!,
        texture: texture!,
        fineLines: wrinkles!,
        pores: pores!,
        pigmentation: darkSpots!,
        firmness: elasticity!,
      ),
    );
  }

  String _summaryForScan(core.ScanRecord? scan) {
    if (scan == null) return 'No recent photo analysis available yet.';
    if (scan.visibleFindings.contains('progress photo saved')) {
      return 'Progress photo saved ${_relativeDate(scan.capturedAt)}. It is now stored in your scan history and available for AI coaching context.';
    }
    if (scan.aiSummary.trim().isNotEmpty) {
      return scan.aiSummary.trim();
    }
    return 'Latest scan ${_relativeDate(scan.capturedAt)}: redness ${_scoreText(scan.metrics.redness)}, texture ${_scoreText(scan.metrics.texture)}, pigment ${_scoreText(scan.metrics.pigmentation)}.';
  }

  String _scoreText(double? value) {
    if (value == null) return 'not tracked';
    return '${value.clamp(0, 10).toStringAsFixed(1)}/10';
  }

  String _relativeDate(DateTime date) {
    final days = DateTime.now().difference(date).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }

  String _configurationFallbackReply(String question) {
    final concerns = _concernsText == 'Not provided'
        ? 'barrier support, hydration, and prevention'
        : _concernsText;
    final products = _products.take(3).map((p) => p.name).toList();
    final productLine = products.isEmpty
        ? 'your current gentle cleanser, moisturizer, and SPF'
        : products.join(', ');
    final procedureLine = _hasProcedure
        ? 'Because you are tracking $_procedure, avoid aggressive actives until your provider clears them.'
        : 'No active procedure context is logged, so this focuses on steady skin maintenance.';

    return 'Guidance available now\n\n'
        'Morning: cleanse gently, apply a calming serum if tolerated, moisturize, then finish with broad-spectrum SPF. Work with $productLine where appropriate.\n\n'
        'Evening: cleanse, hydrate, and prioritize barrier repair. If your skin is calm and not post-procedure restricted, introduce actives slowly on alternate nights.\n\n'
        'Insight: Your current focus is $concerns. $_latestPhotoSummary\n\n'
        'Next 7 days: keep photos consistent, avoid adding multiple new products, and note any redness, peeling, warmth, or sensitivity. $procedureLine\n\n'
        'Please consult a licensed dermatologist or qualified clinician for diagnosis, worsening symptoms, or medical concerns.\n\n'
        'You asked: "$question"';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        foregroundColor: AppColors.refinedSlate,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'AI Skincare Coach',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
        ),
      ),
      body: _loading
          ? const LuxeLoadingView(label: 'Preparing your skincare coach...')
          : SafeArea(
              child: Column(
                children: [
                  if (_showDisclaimerBanner) _disclaimerBanner(),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.champagneGold,
                      onRefresh: _loadContext,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          _heroHeader(),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            _errorCard(_error!),
                          ],
                          const SizedBox(height: 18),
                          const ClinicalSectionHeader(
                            icon: Icons.wb_sunny_outlined,
                            eyebrow: 'TODAY',
                            title: "Today's Recommendation",
                          ),
                          const SizedBox(height: 12),
                          _routineCards(),
                          const SizedBox(height: 12),
                          _todaysAdviceButton(),
                          const SizedBox(height: 18),
                          _uploadPhotoButton(),
                          const SizedBox(height: 18),
                          const ClinicalSectionHeader(
                            icon: Icons.auto_awesome_rounded,
                            eyebrow: 'PHOTO & PROGRESS',
                            title: 'Quick Insights',
                          ),
                          const SizedBox(height: 12),
                          _insightsCard(),
                          const SizedBox(height: 18),
                          const ClinicalSectionHeader(
                            icon: Icons.healing_outlined,
                            eyebrow: 'RECOVERY',
                            title: 'Procedure Recovery Status',
                          ),
                          const SizedBox(height: 12),
                          _recoveryStatusCard(),
                          const SizedBox(height: 18),
                          const ClinicalSectionHeader(
                            icon: Icons.chat_bubble_outline_rounded,
                            eyebrow: 'COACH',
                            title: 'Latest Advice',
                          ),
                          const SizedBox(height: 12),
                          _coachReplyCard(),
                        ],
                      ),
                    ),
                  ),
                  _chatInputBar(),
                ],
              ),
            ),
    );
  }

  Widget _heroHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _coachCardDecoration(glow: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.champagneGold.withValues(alpha: 0.28),
                  AppColors.champagneGold.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.42),
              ),
            ),
            child: const Icon(
              Icons.spa_rounded,
              color: AppColors.goldHover,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good skin data, beautiful guidance',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _name.trim().isEmpty
                      ? 'Your coach combines profile details, logged products, procedure context, and photo progress into one calm daily plan.'
                      : 'Hi $_name. Your coach combines profile details, logged products, procedure context, and photo progress into one calm daily plan.',
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _routineCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 680;
        const morning = _RoutineCard(
          icon: Icons.light_mode_outlined,
          title: 'Morning',
          steps: [
            'Gentle cleanse or rinse if skin feels dry',
            'Hydrating serum or barrier support',
            'Moisturizer suited to your skin tolerance',
            'Broad-spectrum SPF as the final step',
          ],
        );
        final evening = _RoutineCard(
          icon: Icons.nightlight_round,
          title: 'Evening',
          steps: [
            'Cleanse thoroughly without stripping',
            'Use calming hydration before actives',
            _hasProcedure
                ? 'Pause strong actives until cleared after $_procedure'
                : 'Introduce active ingredients slowly as tolerated',
            'Seal with a replenishing moisturizer',
          ],
        );
        if (!wide) {
          return Column(
            children: [morning, const SizedBox(height: 12), evening],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: morning),
            const SizedBox(width: 12),
            Expanded(child: evening),
          ],
        );
      },
    );
  }

  Widget _todaysAdviceButton() {
    return OutlinedButton.icon(
      onPressed: _sending ? null : _getTodaysAdvice,
      icon: _sending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_rounded),
      label: Text(_sending ? 'Getting Advice...' : 'Get Today\'s Advice'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.refinedSlate,
        backgroundColor: AppColors.cardBackground,
        minimumSize: const Size(double.infinity, 50),
        side: BorderSide(
          color: AppColors.champagneGold.withValues(alpha: 0.42),
          width: 1.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _uploadPhotoButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _photoSourceButton(
              label: 'Take Photo',
              icon: Icons.photo_camera_rounded,
              source: ImageSource.camera,
              prominent: false,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _photoSourceButton(
              label: 'Choose from Gallery',
              icon: Icons.photo_library_rounded,
              source: ImageSource.gallery,
              prominent: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoSourceButton({
    required String label,
    required IconData icon,
    required ImageSource source,
    required bool prominent,
  }) {
    final childIcon = _analyzingPhoto
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
    final childLabel = Text(_analyzingPhoto ? 'Analyzing...' : label);
    final onPressed = _analyzingPhoto ? null : () => _pickProgressPhoto(source);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );

    if (prominent) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: childIcon,
        label: childLabel,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.champagneGold,
          foregroundColor: AppColors.onChampagneGold,
          minimumSize: const Size(double.infinity, 58),
          elevation: 0,
          shape: shape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: childIcon,
      label: childLabel,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.refinedSlate,
        backgroundColor: AppColors.cardBackground,
        minimumSize: const Size(double.infinity, 58),
        side: BorderSide(
          color: AppColors.champagneGold.withValues(alpha: 0.46),
          width: 1.2,
        ),
        shape: shape,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _insightsCard() {
    final latestPath = _latestPhotoPath?.trim();
    final hasPhoto = latestPath != null && latestPath.isNotEmpty;
    final focusArea = _latestPhotoScan?.focusArea.trim();
    final latestTitle = focusArea?.isNotEmpty == true
        ? 'Latest photo • $focusArea'
        : 'Latest photo';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _coachCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhoto) ...[
            _latestPhotoPreview(latestPath),
            const SizedBox(height: 14),
          ],
          _InsightRow(
            icon: Icons.camera_alt_outlined,
            title: latestTitle,
            text: hasPhoto
                ? 'Saved ${_latestPhotoScan == null ? 'recently' : _relativeDate(_latestPhotoScan!.capturedAt)} and available after refresh or navigation.'
                : 'No uploaded progress photo yet.',
          ),
          const SizedBox(height: 12),
          _InsightRow(
            icon: Icons.insights_rounded,
            title: 'Analysis note',
            text: '$_latestPhotoSummary ${_scanCountLabel()}',
          ),
          const SizedBox(height: 12),
          const _InsightRow(
            icon: Icons.trending_up_rounded,
            title: 'Prediction',
            text:
                'With consistent SPF, hydration, and minimal product changes, your next scan should be easier to compare and interpret.',
          ),
        ],
      ),
    );
  }

  Widget _latestPhotoPreview(String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _imagePreviewFor(path),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.refinedSlate.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.45),
                  ),
                ),
                child: Text(
                  _analyzingPhoto
                      ? 'Selected photo preview'
                      : 'Saved progress photo',
                  style: const TextStyle(
                    color: AppColors.champagneGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePreviewFor(String path) {
    final clean = path.trimLeft();
    if (clean.startsWith('data:image') ||
        clean.startsWith('http://') ||
        clean.startsWith('https://')) {
      return Image.network(
        clean,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _missingPhotoPreview(),
      );
    }
    final preview = buildLocalImagePreview(
      path,
      width: double.infinity,
      height: double.infinity,
      borderRadius: 0,
    );
    return ColoredBox(color: AppColors.warmAlabaster, child: preview);
  }

  Widget _missingPhotoPreview() {
    return Container(
      color: AppColors.warmAlabaster,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.refinedSlate.withValues(alpha: 0.45),
      ),
    );
  }

  Widget _recoveryStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _coachCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _hasProcedure ? Icons.verified_outlined : Icons.info_outline,
            color: AppColors.goldHover,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _hasProcedure
                  ? 'Procedure context detected: $_procedure. Keep your routine conservative, avoid exfoliating acids or retinoids unless cleared, and contact your provider for warmth, spreading redness, drainage, fever, or worsening pain.'
                  : 'No active procedure is logged. Add a procedure profile to unlock more specific recovery timing and restriction guidance.',
              style: TextStyle(
                fontSize: 12.8,
                height: 1.48,
                fontWeight: FontWeight.w600,
                color: AppColors.refinedSlate.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _disclaimerBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 16,
            color: AppColors.champagneGold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Disclaimer: This is AI-generated general skincare guidance. It is not medical advice or a diagnosis. Always consult a licensed dermatologist or aesthetician for professional recommendations.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.refinedSlate.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _dismissDisclaimerBanner,
            borderRadius: BorderRadius.circular(12),
            child: Icon(
              Icons.close,
              size: 16,
              color: AppColors.refinedSlate.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachReplyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _coachCardDecoration(glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _lastCoachReply,
            style: TextStyle(
              fontSize: 12.8,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: AppColors.refinedSlate.withValues(alpha: 0.82),
            ),
          ),
          if (_shouldShowContinueRoutineButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _continueRoutine,
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text('Continue Routine'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.champagneGold,
                  side: BorderSide(
                    color: AppColors.champagneGold.withValues(alpha: 0.55),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEDED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD06B6B).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFC0504D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC0504D),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            top: BorderSide(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.07),
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image preview if selected
            if (_chatImage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _chatImage!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Photo selected',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.refinedSlate,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Will be analyzed with your message',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.refinedSlate,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _removeChatImage,
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.refinedSlate,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Camera/Gallery button
                PopupMenuButton<ImageSource>(
                  icon: const Icon(
                    Icons.add_photo_alternate_rounded,
                    color: AppColors.champagneGold,
                  ),
                  tooltip: 'Add photo',
                  onSelected: _pickChatImage,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: ImageSource.camera,
                      child: Row(
                        children: [
                          Icon(Icons.camera_alt),
                          SizedBox(width: 12),
                          Text('Take Photo'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ImageSource.gallery,
                      child: Row(
                        children: [
                          Icon(Icons.photo_library),
                          SizedBox(width: 12),
                          Text('Choose from Gallery'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _coachInput,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendCoachMessage(),
                    decoration: InputDecoration(
                      hintText: _chatImage != null
                          ? 'Ask about this photo...'
                          : 'Ask Coach Anything',
                      hintStyle: TextStyle(
                        color: AppColors.refinedSlate.withValues(alpha: 0.48),
                      ),
                      filled: true,
                      fillColor: AppColors.warmAlabaster,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.24,
                          ),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.24,
                          ),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.62,
                          ),
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: IconButton.filled(
                    tooltip: 'Send to coach',
                    onPressed: _sending ? null : _sendCoachMessage,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.champagneGold,
                      foregroundColor: AppColors.onChampagneGold,
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
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

class _ParsedPhotoMetrics {
  final core.SkinMetricSet metrics;
  final List<String> visibleFindings;
  final String summary;

  const _ParsedPhotoMetrics({
    required this.metrics,
    this.visibleFindings = const [],
    this.summary = '',
  });
}

class _FocusAreaChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FocusAreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.champagneGold
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.goldHover
                  : AppColors.champagneGold.withValues(alpha: 0.24),
              width: selected ? 1.2 : 0.9,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.24),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: AppColors.onChampagneGold,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: selected
                      ? AppColors.onChampagneGold
                      : AppColors.refinedSlate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> steps;

  const _RoutineCard({
    required this.icon,
    required this.title,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _coachCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.goldHover, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.refinedSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final step in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: AppColors.goldHover,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.38,
                      fontWeight: FontWeight.w600,
                      color: AppColors.refinedSlate.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _InsightRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.goldHover, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.refinedSlate,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppColors.refinedSlate.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

BoxDecoration _coachCardDecoration({bool glow = false}) {
  return BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: glow
          ? AppColors.champagneGold.withValues(alpha: 0.38)
          : AppColors.borders.withValues(alpha: 0.92),
      width: glow ? 1.0 : 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.refinedSlate.withValues(alpha: 0.06),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
      if (glow)
        BoxShadow(
          color: AppColors.champagneGold.withValues(alpha: 0.13),
          blurRadius: 28,
          spreadRadius: 1,
          offset: const Offset(0, 10),
        ),
    ],
  );
}
