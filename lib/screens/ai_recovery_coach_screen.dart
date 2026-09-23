import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../widgets/luxe_loading_view.dart';
import '../models/premium_recovery_models.dart';
import '../models/procedure.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/app_logger.dart';
import '../utils/premium_access.dart';
import '../utils/premium_recovery_service.dart';
import '../utils/peptide_service.dart';
import '../widgets/local_image_preview.dart' as local_preview;

class AIRecoveryCoachScreen extends StatefulWidget {
  const AIRecoveryCoachScreen({super.key, this.procedure});

  final Procedure? procedure;

  @override
  State<AIRecoveryCoachScreen> createState() => _AIRecoveryCoachScreenState();
}

class _AIRecoveryCoachScreenState extends State<AIRecoveryCoachScreen> {
  // This screen is now fully polished with luxury gradients, accent stripes, premium card/button styles, improved spacing, and inviting empty states for both premium and regular users. All chat bubbles, context chips, and empty states match the luxury/clinical design language of the Home and Premium Recovery Hub screens.
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _isPremium = false;
  bool _sending = false;

  /// null = not yet asked; true = user accepted sending data to Gemini; false = declined.
  bool? _aiCoachConsent;

  Procedure? _activeProcedure;
  List<ScanHistoryEntry> _scopedScans = const [];
  List<RecoveryCoachMessage> _messages = const [];
  String? _attachmentRef;
  Timer? _typingPulseTimer;
  int _typingBeat = 0;

  int get _recoveryDay {
    final start = _activeProcedure?.startDate;
    if (start == null) return 0;
    final now = DateTime.now();
    final day =
        now.difference(DateTime(start.year, start.month, start.day)).inDays + 1;
    return day.clamp(1, 999);
  }

  List<String> get _suggestedPrompts {
    final procedureType = (_activeProcedure?.type ?? '').toLowerCase();
    final day = _recoveryDay;

    final prompts = <({String text, int score})>[
      (
        text:
            'Is this swelling normal for week ${((day - 1) ~/ 7 + 1).clamp(1, 12)}?',
        score: 90,
      ),
      (text: 'Why is one side more swollen than the other?', score: 84),
      (text: 'What helps with scar itching?', score: 78),
      (text: 'Tips to reduce swelling faster', score: 82),
      (text: 'When will I see final results?', score: 76),
    ];

    if (procedureType.contains('rhinoplasty') ||
        procedureType.contains('bleph') ||
        procedureType.contains('facelift') ||
        procedureType.contains('brow') ||
        procedureType.contains('lip')) {
      prompts.add((text: 'When can I start wearing makeup?', score: 88));
    }
    if (procedureType.contains('rhinoplasty')) {
      prompts.add((
        text: 'Is this nasal asymmetry expected right now?',
        score: 87,
      ));
    }
    if (procedureType.contains('bbl') ||
        procedureType.contains('lipo') ||
        procedureType.contains('tummy') ||
        procedureType.contains('thigh') ||
        procedureType.contains('arm')) {
      prompts.add((
        text: 'How should swelling look in this body area this week?',
        score: 86,
      ));
    }

    if (day <= 14) {
      prompts.add((
        text: 'What should I prioritize this first 2 weeks?',
        score: 94,
      ));
      prompts.add((
        text: 'Are these early healing changes expected?',
        score: 92,
      ));
    } else if (day <= 60) {
      prompts.add((
        text: 'Is my recovery pace on track for this stage?',
        score: 93,
      ));
      prompts.add((
        text: 'What signs show swelling is resolving well?',
        score: 90,
      ));
    } else {
      prompts.add((
        text: 'Is this normal residual swelling at this stage?',
        score: 92,
      ));
      prompts.add((
        text: 'When should final contour usually settle?',
        score: 91,
      ));
    }

    final merged = <({String text, int score})>[];
    for (final prompt in prompts) {
      final existingIndex = merged.indexWhere(
        (item) => item.text == prompt.text,
      );
      if (existingIndex == -1) {
        merged.add(prompt);
      } else {
        final old = merged[existingIndex];
        if (prompt.score > old.score) {
          merged[existingIndex] = prompt;
        }
      }
    }

    merged.sort((a, b) => b.score.compareTo(a.score));

    if (merged.length <= 4) {
      return merged.map((item) => item.text).toList();
    }

    final topBand = merged.take(7).toList();
    final offset = _messages.length % topBand.length;
    final rotated = [...topBand.sublist(offset), ...topBand.sublist(0, offset)];
    return rotated.take(4).map((item) => item.text).toList();
  }

  void _applyPrompt(String prompt) {
    _inputController.text = prompt;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void dispose() {
    _typingPulseTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startTypingPulse() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final pulseMs = screenWidth < 430
        ? 360
        : screenWidth >= 768
        ? 500
        : 420;
    _typingPulseTimer?.cancel();
    _typingPulseTimer = Timer.periodic(Duration(milliseconds: pulseMs), (_) {
      if (!mounted || !_sending) return;
      setState(() => _typingBeat = (_typingBeat + 1) % 3);
    });
  }

  void _stopTypingPulse() {
    _typingPulseTimer?.cancel();
    _typingPulseTimer = null;
    if (mounted) {
      setState(() => _typingBeat = 0);
    }
  }

  Future<void> _loadContext() async {
    try {
      final resolvedProcedureForKey =
          widget.procedure ?? await _resolveActiveProcedure();
      final result = await Future.wait([
        PremiumAccess.isPremiumUser(),
        PremiumRecoveryService.loadCoachMessages(
          procedureId: resolvedProcedureForKey?.id,
        ),
        Future.value(widget.procedure),
        AppPrefs.getScanEntries(),
        AppPrefs.getAiCoachConsent(),
      ]).timeout(const Duration(seconds: 10));

      final premium = result[0] as bool;
      final messages = (result[1] as List).cast<RecoveryCoachMessage>();
      final procedure =
          result[2] as Procedure? ?? await _resolveActiveProcedure();
      final scans = result[3] as List<ScanHistoryEntry>;
      final consent = result[4] as bool?;
      final scopedScans = _scopeScans(scans, procedure);

      if (!mounted) return;
      setState(() {
        _isPremium = premium;
        _activeProcedure = procedure;
        _messages = messages;
        _scopedScans = scopedScans;
        _aiCoachConsent = consent;
        _loading = false;
      });

      if (premium && procedure != null && messages.isEmpty) {
        _injectWelcomeMessage(procedure);
      }

      if (premium && consent == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _promptForConsent());
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading timed out. Please try again.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load coach: $e')));
      // Optionally log stack trace for debugging
      // debugPrint(stack.toString());
    }
  }

  Future<Procedure?> _resolveActiveProcedure() async {
    final entries = await AppPrefs.getProcedureEntries();
    if (entries.isEmpty) return null;

    final selected = await AppPrefs.getSelectedProcedureIdOrNull();
    if (selected != null && selected.trim().isNotEmpty) {
      for (final item in entries) {
        final id = (item['id'] ?? item['procedureId'] ?? '').toString().trim();
        if (id == selected.trim()) {
          return Procedure.fromJson(Map<String, dynamic>.from(item));
        }
      }
    }

    final latest = entries.first;
    return Procedure.fromJson(Map<String, dynamic>.from(latest));
  }

  List<ScanHistoryEntry> _scopeScans(
    List<ScanHistoryEntry> scans,
    Procedure? procedure,
  ) {
    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (procedure == null) return sorted;
    final scoped = sorted
        .where((s) => (s.procedureId ?? '').trim() == procedure.id)
        .toList();
    return scoped.isNotEmpty ? scoped : sorted;
  }

  Future<void> _injectWelcomeMessage(Procedure procedure) async {
    final procType = procedure.type.trim().isEmpty
        ? 'your procedure'
        : procedure.type.trim();
    final day = _recoveryDay;
    final weekNum = ((day - 1) ~/ 7 + 1).clamp(1, 52);
    final swellingLine = _swellingSnapshot;
    final scanLine = _scanSnapshot;

    final welcomeText = StringBuffer();
    welcomeText.writeln(
      "Welcome back. I'm your AI Recovery Coach, and I'm fully up to date with your **$procType** recovery.",
    );
    welcomeText.writeln();
    welcomeText.writeln("Here's what I have on file:");
    welcomeText.writeln("• **Recovery day:** Day $day (Week $weekNum)");
    welcomeText.writeln("• **Swelling:** $swellingLine");
    welcomeText.writeln("• **Scans:** $scanLine");
    if (procedure.notes.trim().isNotEmpty) {
      final notes = procedure.notes.trim();
      final shortNote = notes.length > 80
          ? '${notes.substring(0, 80)}...'
          : notes;
      welcomeText.writeln("• **Provider notes:** $shortNote");
    }
    welcomeText.writeln();
    welcomeText.writeln(
      "Every answer I give you is shaped around your specific recovery stage and history — not generic advice. What would you like to check in on today?",
    );
    welcomeText.writeln();
    welcomeText.writeln(
      "*This is general guidance, not a diagnosis. Please follow your surgeon's instructions first.*",
    );

    final welcome = RecoveryCoachMessage(
      id: premiumEntityId('coach_welcome'),
      role: 'assistant',
      text: welcomeText.toString().trim(),
      createdAt: DateTime.now(),
    );

    final updated = [welcome];
    try {
      await PremiumRecoveryService.saveCoachMessages(
        updated,
        procedureId: procedure.id,
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() => _messages = updated);
    _scrollToBottomSoon();
  }

  Future<void> _pickAttachment() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 86,
      );
      if (picked == null) return;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (!mounted) return;
        setState(
          () =>
              _attachmentRef = 'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
      } else {
        if (!mounted) return;
        setState(() => _attachmentRef = picked.path);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to attach image right now.')),
      );
    }
  }

  /// Shows the one-time data-sharing disclosure. The dialog is not
  /// dismissible by tapping outside — the user must explicitly accept or
  /// decline so the choice is unambiguous and can be safely persisted.
  Future<void> _promptForConsent() async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Before you chat with AI Coach'),
        content: const Text(
          'AI Recovery Coach sends your recovery/scan metrics (procedure type, '
          'recovery day, and metric trends) to Google\'s Gemini API to generate '
          'personalized responses. No photos are sent unless you attach one to '
          'a message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept & Continue'),
          ),
        ],
      ),
    );
    final decision = accepted ?? false;
    await AppPrefs.setAiCoachConsent(decision);
    if (!mounted) return;
    setState(() => _aiCoachConsent = decision);
  }

  Future<void> _send() async {
    final question = _inputController.text.trim();
    final attached = _attachmentRef;
    if (_sending) return;
    if (_aiCoachConsent != true) return;
    if (question.isEmpty && (attached == null || attached.trim().isEmpty)) {
      return;
    }

    AppLogger.verbose(
      '[AiRecoveryCoachScreen] resolvedProcedureType=${_activeProcedure?.type.trim().isNotEmpty == true ? _activeProcedure!.type.trim() : 'Unknown'}',
    );

    final normalizedQuestion = question.isEmpty
        ? 'Please review this recovery photo and explain what looks expected, what to monitor, and the safest next step.'
        : question;

    // Prepend active peptide stack context so the AI can reference it.
    final peptideContext = await PeptideService.buildAICoachContext();
    final enrichedQuestion = peptideContext.isNotEmpty
        ? '$peptideContext\nUser question: $normalizedQuestion'
        : normalizedQuestion;

    final userMessage = RecoveryCoachMessage(
      id: premiumEntityId('coach_user'),
      role: 'user',
      text: normalizedQuestion,
      createdAt: DateTime.now(),
      imageRef: attached,
    );

    setState(() {
      _sending = true;
      _messages = [..._messages, userMessage];
      _inputController.clear();
      _attachmentRef = null;
    });
    _startTypingPulse();

    _scrollToBottomSoon();

    try {
      final reply = await PremiumRecoveryService.generateRecoveryCoachReply(
        question: enrichedQuestion,
        hasImageAttachment: attached != null && attached.trim().isNotEmpty,
        activeProcedure: _activeProcedure,
        scopedScans: _scopedScans,
      );

      final assistant = RecoveryCoachMessage(
        id: premiumEntityId('coach_ai'),
        role: 'assistant',
        text: reply,
        createdAt: DateTime.now(),
      );

      final updated = [..._messages, assistant];
      try {
        await PremiumRecoveryService.saveCoachMessages(
          updated,
          procedureId: _activeProcedure?.id,
        );
      } catch (_) {
        // Do not block visible coach replies if local persistence fails.
      }

      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = updated;
      });
      _stopTypingPulse();
      _scrollToBottomSoon();
    } catch (e) {
      final raw = e.toString().trim();
      final cleaned = raw.startsWith('Exception:')
          ? raw.replaceFirst('Exception:', '').trim()
          : raw;
      final errorAssistant = RecoveryCoachMessage(
        id: premiumEntityId('coach_ai_error'),
        role: 'assistant',
        text:
            'I could not reach the AI Recovery Coach backend right now. ${cleaned.isEmpty ? 'Please try again in a moment.' : cleaned}',
        createdAt: DateTime.now(),
      );

      final updated = [..._messages, errorAssistant];
      try {
        await PremiumRecoveryService.saveCoachMessages(
          updated,
          procedureId: _activeProcedure?.id,
        );
      } catch (_) {
        // Ignore persistence issues; still show backend error in UI.
      }

      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = updated;
      });
      _stopTypingPulse();
      _scrollToBottomSoon();
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildImagePreview(
    String? ref, {
    double width = 80,
    double height = 80,
  }) {
    if (ref == null || ref.trim().isEmpty) return const SizedBox.shrink();

    if (ref.startsWith('data:image') && ref.contains(',')) {
      final parts = ref.split(',');
      if (parts.length == 2) {
        try {
          final bytes = base64Decode(parts[1]);
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
      }
    }

    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          ref,
          width: width,
          height: height,
          fit: BoxFit.cover,
        ),
      );
    }

    return local_preview.buildLocalImagePreview(
      ref,
      width: width,
      height: height,
      borderRadius: 12,
    );
  }

  String get _swellingSnapshot {
    final procedure = _activeProcedure;
    if (procedure == null) return 'No swelling history logged yet.';
    final entries =
        procedure.journalEntries.where((e) => e.swellingLevel != null).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    if (entries.isEmpty) return 'No swelling history logged yet.';
    final latest = entries.first.swellingLevel!;
    return 'Latest swelling $latest/10 (${entries.length} entries tracked).';
  }

  String get _scanSnapshot {
    if (_scopedScans.isEmpty) return 'No recovery scans yet.';
    final latest = _scopedScans.first;
    final poseSimilarity = latest.metrics['capture_pose_similarity'];
    final lightingConfidence = latest.lightingConfidence;
    final detail = <String>[];
    if (poseSimilarity != null) {
      detail.add('pose ${poseSimilarity.round()}%');
    }
    if (lightingConfidence != null) {
      detail.add('lighting ${(lightingConfidence * 100).round()}%');
    }
    final suffix = detail.isEmpty ? '' : ' (${detail.join(' · ')})';
    return '${_scopedScans.length} scans analyzed$suffix.';
  }

  Widget _buildConsentDeclinedGate() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
        decoration: BoxDecoration(
          color: MyApp.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MyApp.goldShimmer.withValues(alpha: 0.14),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: MyApp.clinicalNavy.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    MyApp.goldShimmer.withValues(alpha: 0.20),
                    MyApp.goldShimmer.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.32),
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.privacy_tip_outlined,
                size: 40,
                color: MyApp.goldShimmer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'AI Coach unavailable',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: MyApp.clinicalNavy,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You declined sharing recovery/scan metrics with Google\'s Gemini API, '
              'so AI Coach responses can\'t be generated. You can change this anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: MyApp.clinicalSlate,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _promptForConsent,
              child: const Text('Review & Enable AI Coach'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumGate() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(22),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
        decoration: BoxDecoration(
          color: MyApp.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MyApp.goldShimmer.withValues(alpha: 0.14),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: MyApp.clinicalNavy.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    MyApp.goldShimmer.withValues(alpha: 0.20),
                    MyApp.goldShimmer.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: MyApp.goldShimmer.withValues(alpha: 0.32),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: MyApp.goldShimmer.withValues(alpha: 0.26),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                size: 40,
                color: MyApp.goldShimmer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Premium Recovery Coach',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: MyApp.clinicalNavy,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock a calmer, more personalized recovery consultation experience with context-aware AI guidance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: MyApp.clinicalSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isVeryNarrow = screenWidth < 340;
    final isCompact = screenWidth < 400;
    final isTablet = screenWidth >= 768;
    final contentMaxWidth = isTablet ? 900.0 : double.infinity;
    final outerPadding = isCompact ? 8.0 : 18.0;
    final headerPadding = isCompact
        ? EdgeInsets.fromLTRB(
            isVeryNarrow ? 6 : 10,
            2,
            isVeryNarrow ? 6 : 10,
            7,
          )
        : const EdgeInsets.fromLTRB(20, 6, 20, 14);
    final composerPadding = isCompact
        ? EdgeInsets.fromLTRB(isVeryNarrow ? 4 : 7, 7, isVeryNarrow ? 4 : 7, 6)
        : const EdgeInsets.fromLTRB(14, 12, 14, 10);
    final sendButtonWidth = isVeryNarrow
      ? 56.0
        : isCompact
      ? 72.0
        : 92.0;
    final visiblePrompts = isVeryNarrow
      ? _suggestedPrompts.take(2).toList()
      : isCompact
      ? _suggestedPrompts.take(3).toList()
      : _suggestedPrompts;

    final procedureName = (_activeProcedure?.type ?? '').trim();
    final subtitle = procedureName.isEmpty
        ? 'Personalized Recovery Intelligence'
        : '$procedureName Recovery Intelligence';

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        centerTitle: true,
        title: ClinicalAppBarTitle(
          title: 'AI Recovery Coach',
          eyebrow: 'Recovery intelligence',
          color: MyApp.textBrown,
        ),
      ),
      body: _loading
          ? const LuxeLoadingView(label: 'Preparing your recovery coach…')
          : !_isPremium
          ? _buildPremiumGate()
          : _aiCoachConsent == false
          ? _buildConsentDeclinedGate()
          : _aiCoachConsent == null
          ? const LuxeLoadingView(label: 'Reviewing AI Coach permissions…')
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    MyApp.champagne,
                    MyApp.goldShimmer.withValues(alpha: 0.06),
                    MyApp.goldShimmer.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isCompact ? (isVeryNarrow ? 10 : 16) : 20,
                        isCompact ? 6 : 10,
                        isCompact ? (isVeryNarrow ? 10 : 16) : 20,
                        isCompact ? 6 : 10,
                      ),
                      child: const ClinicalSectionHeader(
                        icon: Icons.psychology_outlined,
                        title: 'Coach Intelligence',
                        eyebrow: 'Personalized context',
                      ),
                    ),
                    Padding(
                      padding: headerPadding,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(isCompact ? 10 : 18),
                            decoration:
                                MyApp.surfaceCardDecoration(
                                  tintOpacity: 0.07,
                                ).copyWith(
                                  boxShadow: [
                                    BoxShadow(
                                      color: MyApp.goldShimmer.withValues(
                                        alpha: 0.07,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_activeProcedure != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          MyApp.goldShimmer.withValues(
                                            alpha: 0.18,
                                          ),
                                          MyApp.goldShimmer.withValues(
                                            alpha: 0.14,
                                          ),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: MyApp.goldShimmer.withValues(
                                          alpha: 0.30,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.link_rounded,
                                          size: 14,
                                          color: MyApp.goldShimmer,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Attached: ${_activeProcedure!.type.trim().isEmpty ? 'Your Procedure' : _activeProcedure!.type.trim()}  ·  Day $_recoveryDay',
                                            style: TextStyle(
                                              color: MyApp.goldShimmer,
                                              fontWeight: FontWeight.w700,
                                              fontSize: isCompact ? 11.0 : 12.0,
                                              letterSpacing: 0.2,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Wrap(
                                  spacing: isCompact ? 4 : 8,
                                  runSpacing: isCompact ? 4 : 8,
                                  children: [
                                    _contextChip(
                                      Icons.lock_outline,
                                      'Private AI',
                                    ),
                                    _contextChip(
                                      Icons.favorite_border,
                                      'Calm guidance',
                                    ),
                                    _contextChip(
                                      Icons.health_and_safety_outlined,
                                      'Expertly framed',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  subtitle,
                                  style: MyApp.cardTitleStyle().copyWith(
                                    fontSize: isCompact ? 15.5 : 17.5,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _activeProcedure != null
                                      ? 'Your coach is fully calibrated to your ${_activeProcedure!.type.trim().isEmpty ? 'procedure' : _activeProcedure!.type.trim()} recovery — including your swelling logs, journals, scans, and timeline.'
                                      : 'Your coach references procedure context, swelling logs, journals, scan consistency, and timeline checkpoints.',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w600,
                                    fontSize: isCompact ? 12.0 : 13.0,
                                    letterSpacing: 0.13,
                                    height: 1.38,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: isCompact ? 4 : 8,
                                  runSpacing: isCompact ? 4 : 8,
                                  children: [
                                    _contextChip(
                                      Icons.water_drop_outlined,
                                      _swellingSnapshot,
                                    ),
                                    _contextChip(
                                      Icons.photo_library_outlined,
                                      _scanSnapshot,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: Container(
                            margin: EdgeInsets.symmetric(
                              horizontal: outerPadding,
                            ),
                            padding: EdgeInsets.all(isCompact ? 7 : 14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.97),
                                  MyApp.champagne.withValues(alpha: 0.97),
                                  MyApp.goldShimmer.withValues(alpha: 0.04),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: MyApp.goldShimmer.withValues(
                                    alpha: 0.06,
                                  ),
                                  blurRadius: 22,
                                  offset: const Offset(0, 7),
                                ),
                              ],
                              border: Border.all(
                                color: MyApp.goldShimmer.withValues(
                                  alpha: 0.10,
                                ),
                                width: 1,
                              ),
                            ),
                            child: _messages.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.chat_bubble_outline,
                                          size: 44,
                                          color: MyApp.goldShimmer.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Ask anything about your healing.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: Colors.black,
                                            fontWeight: FontWeight.bold,
                                            fontSize: isCompact ? 13.2 : 15.0,
                                            letterSpacing: 0.16,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.84,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: MyApp.goldShimmer
                                                  .withValues(alpha: 0.18),
                                            ),
                                          ),
                                          child: Text(
                                            'Professional, conservative guidance for each stage of recovery',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: isCompact ? 10.8 : 11.8,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.15,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          'Your coach uses your recovery data to guide each next step with care context and calm reassurance.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: isCompact ? 11.5 : 13.0,
                                            letterSpacing: 0.13,
                                            height: 1.56,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      bottom: 2,
                                    ),
                                    itemCount:
                                        _messages.length + (_sending ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index >= _messages.length) {
                                        return _typingIndicatorBubble();
                                      }
                                      return _messageBubble(
                                        _messages[index],
                                        index: index,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        outerPadding,
                        8,
                        outerPadding,
                        isCompact ? 8 : 18,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: Container(
                            padding: composerPadding,
                            decoration:
                                MyApp.surfaceCardDecoration(
                                  tintOpacity: 0.07,
                                ).copyWith(
                                  boxShadow: [
                                    BoxShadow(
                                      color: MyApp.goldShimmer.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                            child: Column(
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Private message composer',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10.8,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.34,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_attachmentRef != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 7),
                                    child: Row(
                                      children: [
                                        _buildImagePreview(_attachmentRef),
                                        const SizedBox(width: 7),
                                        const Expanded(
                                          child: Text(
                                            'Photo attached for contextual review',
                                            style: TextStyle(
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () => setState(
                                            () => _attachmentRef = null,
                                          ),
                                          icon: const Icon(Icons.close),
                                        ),
                                      ],
                                    ),
                                  ),
                                Row(
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 34,
                                        minHeight: 34,
                                      ),
                                      onPressed: _sending
                                          ? null
                                          : _pickAttachment,
                                      icon: const Icon(
                                        Icons.add_photo_alternate_outlined,
                                      ),
                                      tooltip: 'Attach photo',
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _inputController,
                                        minLines: 1,
                                        maxLines: 3,
                                        onSubmitted: (_) => _send(),
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: isCompact ? 12.2 : 13.6,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.11,
                                          height: 1.42,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Ask your AI Recovery Coach...${isVeryNarrow ? '' : ''}',
                                          hintStyle: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.13,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                            borderSide: BorderSide(
                                              color: MyApp.goldShimmer
                                                  .withValues(alpha: 0.13),
                                              width: 1.1,
                                            ),
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: isCompact ? 10 : 14,
                                            vertical: isCompact ? 8 : 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: isVeryNarrow ? 4 : 8),
                                    SizedBox(
                                      width: sendButtonWidth,
                                      height:
                                          MyApp.primaryButtonHeight *
                                          (isCompact ? 0.82 : 1.0),
                                      child: ElevatedButton(
                                        onPressed: _sending ? null : _send,
                                        style: MyApp.primaryGoldButton.copyWith(
                                          padding: WidgetStateProperty.all(
                                            EdgeInsets.symmetric(
                                              horizontal: isCompact ? 10 : 18,
                                              vertical: isCompact ? 8 : 18,
                                            ),
                                          ),
                                          shape: WidgetStateProperty.all(
                                            RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    isCompact ? 13 : 18,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        child: _sending
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Text(
                                                'Send',
                                                style: TextStyle(
                                                  fontSize: isVeryNarrow
                                                      ? 11.0
                                                      : null,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_suggestedPrompts.isNotEmpty) ...[
                                  const SizedBox(height: 7),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Suggested prompts',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10.5,
                                        letterSpacing: 0.38,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final wrapSpacing = isCompact
                                            ? 4.0
                                            : 8.0;
                                        final wrapRunSpacing = isCompact
                                            ? 4.0
                                            : 8.0;
                                        return Wrap(
                                          spacing: wrapSpacing,
                                          runSpacing: wrapRunSpacing,
                                          children: [
                                            for (final prompt in visiblePrompts)
                                              InkWell(
                                                onTap: () =>
                                                    _applyPrompt(prompt),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: isCompact
                                                        ? 11
                                                        : 16,
                                                    vertical: isCompact ? 6 : 9,
                                                  ),
                                                  margin: const EdgeInsets.only(
                                                    bottom: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        MyApp.champagne
                                                            .withValues(
                                                              alpha: 0.97,
                                                            ),
                                                        MyApp.goldShimmer
                                                            .withValues(
                                                              alpha: 0.13,
                                                            ),
                                                        MyApp.goldShimmer
                                                            .withValues(
                                                              alpha: 0.10,
                                                            ),
                                                      ],
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                    border: Border.all(
                                                      color: MyApp.goldShimmer
                                                          .withValues(
                                                            alpha: 0.22,
                                                          ),
                                                      width: 1.1,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: MyApp.goldShimmer
                                                            .withValues(
                                                              alpha: 0.08,
                                                            ),
                                                        blurRadius: 7,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .tips_and_updates_outlined,
                                                        size: 14,
                                                        color: MyApp.goldShimmer
                                                            .withValues(
                                                              alpha: 0.7,
                                                            ),
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        prompt,
                                                        style: TextStyle(
                                                          color: Colors.black,
                                                          fontSize: isCompact
                                                              ? 10.2
                                                              : 12.0,
                                                          letterSpacing: 0.12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _contextChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: MyApp.goldShimmer),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 11.2,
              letterSpacing: 0.08,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Persistent AI-generated content disclosure shown on every assistant
  /// bubble (Apple App Review Guideline requires this on each display, not
  /// as a one-time acknowledgement).
  Widget _aiGeneratedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: MyApp.goldShimmer.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 9,
            color: MyApp.goldShimmer.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 3),
          Text(
            'AI-generated',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: MyApp.textBrown.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(RecoveryCoachMessage message, {required int index}) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isVeryNarrow = screenWidth < 340;
    final isCompact = screenWidth < 400;
    final isTablet = screenWidth >= 768;
    final isUser = message.role == 'user';
    final bubbleGradient = isUser
        ? LinearGradient(
            colors: [
              MyApp.goldShimmer.withValues(alpha: 0.16),
              MyApp.goldShimmer.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0.92),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.99),
              MyApp.champagne.withValues(alpha: 0.97),
              MyApp.goldShimmer.withValues(alpha: 0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    final borderColor = isUser
        ? MyApp.goldShimmer.withValues(alpha: 0.28)
        : MyApp.goldShimmer.withValues(alpha: 0.18);

    final baseMs = isCompact
        ? 170
        : isTablet
        ? 230
        : 200;
    final staggerMs = isCompact
        ? 32
        : isTablet
        ? 45
        : 40;
    final animationMs = baseMs + ((index % 4) * staggerMs);

    return TweenAnimationBuilder<double>(
      key: ValueKey(message.id),
      duration: Duration(milliseconds: animationMs),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(bottom: isCompact ? 7 : 10, top: 1),
          constraints: BoxConstraints(
            maxWidth: isVeryNarrow
                ? screenWidth * 0.97
                : isCompact
                ? screenWidth * 0.93
                : isTablet
                ? 740
                : 660,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 14,
            vertical: isCompact ? 8 : 13,
          ),
          decoration: BoxDecoration(
            gradient: bubbleGradient,
            borderRadius: BorderRadius.circular(isCompact ? 13 : 18),
            border: Border.all(color: borderColor, width: 1.1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUser
                            ? Icons.person_outline
                            : Icons.medical_information_outlined,
                        size: 15,
                        color: isUser
                            ? MyApp.goldShimmer.withValues(alpha: 0.7)
                            : MyApp.goldShimmer.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isUser ? 'You' : 'Expert Recovery Coach',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11.2,
                          letterSpacing: 0.32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (!isUser) _aiGeneratedBadge(),
                ],
              ),
              const SizedBox(height: 6),
              if (message.imageRef != null) ...[
                _buildImagePreview(message.imageRef, width: 220, height: 170),
                const SizedBox(height: 10),
              ],
              Text(
                message.text,
                style: TextStyle(
                  color: MyApp.textBrown,
                  fontSize: isCompact ? 12.2 : 13.7,
                  letterSpacing: 0.10,
                  height: 1.52,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typingIndicatorBubble() {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 400;
    Color dotColor(int index) {
      final isActive = _typingBeat == index;
      return isActive
          ? MyApp.goldShimmer.withValues(alpha: 0.96)
          : MyApp.goldShimmer.withValues(alpha: 0.22);
    }

    double dotSize(int index) {
      return _typingBeat == index ? 8.5 : 5.2;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: isCompact ? 8 : 13, top: 2),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 18,
          vertical: isCompact ? 9 : 14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.99),
              MyApp.champagne.withValues(alpha: 0.97),
              MyApp.goldShimmer.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(isCompact ? 13 : 18),
          border: Border.all(
            color: MyApp.goldShimmer.withValues(alpha: 0.16),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: MyApp.goldShimmer.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                    width: dotSize(i),
                    height: dotSize(i),
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          dotColor(i),
                          MyApp.goldShimmer.withValues(alpha: 0.13),
                        ],
                        center: Alignment.center,
                        radius: 0.85,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (_typingBeat == i)
                          BoxShadow(
                            color: MyApp.goldShimmer.withValues(alpha: 0.13),
                            blurRadius: 7,
                            spreadRadius: 1,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Text(
              'Recovery Coach is thinking',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: isCompact ? 10.8 : 12.0,
                letterSpacing: 0.13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
