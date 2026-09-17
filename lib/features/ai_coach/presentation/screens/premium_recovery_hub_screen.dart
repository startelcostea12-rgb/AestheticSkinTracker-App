import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:aesthetic_skin_tracker/models/premium_recovery_models.dart';
import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/app_theme.dart';
import 'package:aesthetic_skin_tracker/widgets/clinical_section_header.dart';
import 'package:aesthetic_skin_tracker/widgets/bridge_card.dart';
import 'package:aesthetic_skin_tracker/utils/app_prefs.dart';
import 'package:aesthetic_skin_tracker/utils/ai_intelligence_engine.dart';

const Color _clinicalSage = Color(0xFF7A8B7B);
const Color _mintHighlight = Color(0xFFA3B899);

// ─────────────────────────────────────────────────────────────────────────────
// Hub Feature Model and Builder
// ─────────────────────────────────────────────────────────────────────────────

class _HubFeature {
  final String title;
  final String accentLabel;
  final String description;
  final IconData icon;
  final String? route;
  final bool opensFutureSimulator;
  final bool highlight;

  const _HubFeature({
    required this.title,
    required this.accentLabel,
    required this.description,
    required this.icon,
    this.route,
    this.opensFutureSimulator = false,
    this.highlight = false,
  });
}

List<_HubFeature> buildHubFeatures(
  String activeProcedure,
  bool hasActiveProcedure,
) {
  return const [
    _HubFeature(
      title: 'AI Recovery Coach',
      accentLabel: 'Chat • Peptide & Scan Insights',
      description:
          'Chat with your personal recovery advisor. Get peptide & scan insights tailored to your stack and metrics.',
      icon: Icons.auto_awesome_motion,
      route: '/ai-recovery-coach',
      highlight: true,
    ),
    _HubFeature(
      title: 'Future Look Simulator',
      accentLabel: 'AI-Powered 3D Recovery',
      description:
          'See a dramatic, procedure-specific visual simulation of your healing journey, with refined overlays and milestone captions.',
      icon: Icons.auto_awesome,
      opensFutureSimulator: true,
      highlight: true,
    ),
    _HubFeature(
      title: 'Scar Healing Tracker',
      accentLabel: 'Voice Journal + AI',
      description:
          'Track scar healing with voice journals, AI transcript, and milestone-based progress.',
      icon: Icons.healing_outlined,
      route: '/scar-tracker',
    ),
    _HubFeature(
      title: 'Recovery Timeline',
      accentLabel: 'Milestones & Insights',
      description:
          'View your personalized recovery timeline, milestones, and AI insights for each stage.',
      icon: Icons.timeline,
      route: '/timeline',
    ),
    _HubFeature(
      title: 'Photo Gallery',
      accentLabel: 'Compare Progress',
      description:
          'Browse and compare your before/after photos, with AI-powered highlights and annotations.',
      icon: Icons.photo_library_outlined,
      route: '/gallery',
    ),
    _HubFeature(
      title: 'Provider Notes',
      accentLabel: 'Surgeon Instructions',
      description:
          'Access your surgeon’s post-op instructions, care tips, and important reminders.',
      icon: Icons.note_alt_outlined,
      route: '/provider-notes',
    ),
    _HubFeature(
      title: 'Peptide Tracker',
      accentLabel: 'Progress Correlation Engine',
      description:
          'Log your peptide stack and see evidence-based correlations with your skin metric improvements over time.',
      icon: Icons.science_outlined,
      route: '/peptide-tracker',
    ),
    _HubFeature(
      title: 'Product Store',
      accentLabel: 'Curated · AI Recommended',
      description:
          'Shop evidence-informed peptides, serums, and recovery essentials. AI picks tailored to your active procedure.',
      icon: Icons.shopping_bag_outlined,
      route: '/store',
    ),
  ];
}

// Main Premium Recovery Hub Screen
class PremiumRecoveryHubScreen extends StatefulWidget {
  const PremiumRecoveryHubScreen({super.key});

  @override
  State<PremiumRecoveryHubScreen> createState() =>
      _PremiumRecoveryHubScreenState();
}

class _PremiumRecoveryHubScreenState extends State<PremiumRecoveryHubScreen> {
  bool _loading = false;
  final bool _isPremium = true;
  List<_HubSignal> _hubSignals = const [
    _HubSignal(
      label: 'Healing Progress',
      value: 'Excellent',
      icon: Icons.healing_outlined,
    ),
    _HubSignal(
      label: 'Active Procedure',
      value: '',
      icon: Icons.face_retouching_natural,
    ),
    _HubSignal(
      label: 'AI Insights',
      value: '3 new',
      icon: Icons.psychology_alt_rounded,
    ),
  ];
  List<_HubFeature> _features = [];
  final List<VoiceJournalEntry> _voiceJournals = [];
  bool _hasActiveProcedure = false;
  Procedure? _activeProcedure;
  ScanHistoryEntry? _latestProcedureScan;
  ScanHistoryEntry? _baselineProcedureScan;

  @override
  void initState() {
    super.initState();
    _loadActiveProcedure();
  }

  Future<void> _loadActiveProcedure() async {
    setState(() => _loading = true);
    final entries = await AppPrefs.getProcedureEntries();
    final scans = await AppPrefs.getScanEntries();
    Procedure? procedure;
    if (entries.isNotEmpty) {
      final selectedId = await AppPrefs.getSelectedProcedureIdOrNull();
      if (selectedId != null && selectedId.trim().isNotEmpty) {
        final match = entries.firstWhere(
          (item) =>
              (item['id'] ?? item['procedureId'] ?? '').toString().trim() ==
              selectedId.trim(),
          orElse: () => <String, dynamic>{},
        );
        procedure = Procedure.fromJson(Map<String, dynamic>.from(match));
      }
      procedure ??= Procedure.fromJson(
        Map<String, dynamic>.from(entries.first),
      );

      final procedureId = selectedId?.trim();
      final resolvedScans = procedureId == null || procedureId.isEmpty
          ? <ScanHistoryEntry>[]
          : scans
              .where((scan) => (scan.procedureId ?? '').trim() == procedureId)
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final fallbackScans = scans
          .where((scan) => (scan.metrics).isNotEmpty)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final baselineScan = resolvedScans.isNotEmpty
          ? resolvedScans.first
          : (fallbackScans.isNotEmpty ? fallbackScans.first : null);
      final latestScan = resolvedScans.isNotEmpty
          ? resolvedScans.last
          : (fallbackScans.isNotEmpty ? fallbackScans.last : null);

      if (mounted) {
        setState(() {
          _latestProcedureScan = latestScan;
          _baselineProcedureScan = baselineScan;
        });
      }
    }
    setState(() {
      _activeProcedure = procedure;
      _hasActiveProcedure = procedure != null;
      _features = buildHubFeatures(
        _activeProcedure?.type ?? '',
        _hasActiveProcedure,
      );
      _hubSignals = [
        const _HubSignal(
          label: 'Healing Progress',
          value: 'Excellent',
          icon: Icons.healing_outlined,
        ),
        _HubSignal(
          label: 'Active Procedure',
          value: _activeProcedure?.type ?? 'None',
          icon: Icons.face_retouching_natural,
        ),
        const _HubSignal(
          label: 'AI Insights',
          value: '3 new',
          icon: Icons.psychology_alt_rounded,
        ),
      ];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 640;
    final horizontalPadding = isCompact ? 14.0 : 24.0;
    final contentMaxWidth = screenWidth >= 1100 ? 1040.0 : 940.0;

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.refinedSlate,
        title: const ClinicalAppBarTitle(
          title: 'Premium Recovery Hub',
          eyebrow: 'Elite recovery suite',
          color: AppColors.refinedSlate,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.warmAlabaster,
                      AppColors.cardBackground,
                      AppColors.warmAlabaster,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -130,
              left: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
              ),
            ),
            Positioned(
              top: 120,
              right: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
              ),
            ),
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMaxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeroHeader(isCompact),
                      const SizedBox(height: 24),
                      const ClinicalSectionHeader(
                        icon: Icons.monitor_heart_outlined,
                        title: 'Recovery Signals',
                        eyebrow: 'Live indicators',
                      ),
                      const SizedBox(height: 12),
                      _buildHubSignals(isCompact),
                      const SizedBox(height: 12),
                      BridgeCard(
                        scans: [
                          if (_baselineProcedureScan != null)
                            _baselineProcedureScan!,
                          if (_latestProcedureScan != null)
                            _latestProcedureScan!,
                        ],
                        title: 'Procedure Milestone Bridge',
                        ctaLabel: 'Open AI Recovery Coach',
                        onTap: () {
                          Navigator.of(context).pushNamed('/ai-recovery-coach');
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 42),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (!_isPremium)
                        _buildPremiumLockCard()
                      else ...[
                        const ClinicalSectionHeader(
                          icon: Icons.auto_awesome_outlined,
                          title: 'Premium Tools',
                          eyebrow: 'Premium suite',
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureLayout(isCompact),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool isCompact) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borders),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.all(isCompact ? 18 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _clinicalSage.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: _clinicalSage.withValues(alpha: 0.24),
                  ),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: _clinicalSage,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.mutedSage.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppColors.mutedSage.withValues(alpha: 0.22),
                        ),
                      ),
                      child: const Text(
                        'PREMIUM SUITE',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.mutedSage,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Recovery Command Center',
                      style: MyApp.sectionTitleStyle().copyWith(
                        fontSize: isCompact ? 20 : 23,
                        letterSpacing: 0,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'A calm, luxury recovery command center to make your healing journey feel trustworthy, personalized, and confidently guided.',
            style: TextStyle(
              color: Color(0xFF1E2225),
              fontSize: isCompact ? 13.0 : 14.0,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniPill(Icons.verified_outlined, 'Premium Suite'),
              _miniPill(Icons.lock_outline, 'Private & Secure'),
              _miniPill(Icons.auto_graph_outlined, 'Outcome Intelligence'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders),
        color: AppColors.warmAlabaster,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.mutedSage),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1E2225),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumLockCard() {
    const perks = [
      ('Recovery Timeline', Icons.timeline_rounded),
      ('Future Simulator', Icons.auto_awesome_rounded),
      ('AI Recovery Coach', Icons.psychology_alt_rounded),
      ('Symmetry Insights', Icons.insights_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.cardBackground,
            AppColors.warmAlabaster,
            _clinicalSage.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _clinicalSage.withValues(alpha: 0.32),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_clinicalSage, _mintHighlight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: _clinicalSage.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              size: 34,
              color: Color(0xFF1E2225),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Unlock Premium Recovery',
            style: MyApp.cardTitleStyle().copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Advanced recovery intelligence to guide every step of your healing journey — beautifully, privately, and powerfully.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF1E2225),
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: perks
                .map(
                  (p) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warmAlabaster.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _clinicalSage.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(p.$2, size: 13, color: _clinicalSage),
                        const SizedBox(width: 6),
                        Text(
                          p.$1,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2225),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 22),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: MyApp.buttonRadius,
              boxShadow: [
                BoxShadow(
                  color: _clinicalSage.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: 1,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/paywall'),
                icon: const Icon(
                  Icons.lock_open_rounded,
                  color: Color(0xFF1E2225),
                  size: 18,
                ),
                label: const Text(
                  'Unlock Premium',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E2225),
                    fontSize: 14.5,
                  ),
                ),
                style: MyApp.primaryGoldButton,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cancel anytime · Your data stays private',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E2225),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubSignals(bool isCompact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final items = _hubSignals
            .map(
              (signal) => Container(
                padding: EdgeInsets.all(isCompact ? 16 : 18),
                decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05)
                    .copyWith(
                      border: Border.all(
                        color: _clinicalSage.withValues(alpha: 0.22),
                      ),
                    ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _clinicalSage.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        signal.icon,
                        color: _clinicalSage,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            signal.label,
                            style: const TextStyle(
                              color: Color(0xFF1E2225),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            signal.value,
                            overflow: TextOverflow.ellipsis,
                            style: MyApp.cardTitleStyle().copyWith(
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList();

        if (wide) {
          return Row(
            children: [
              for (var index = 0; index < items.length; index++) ...[
                Expanded(child: items[index]),
                if (index != items.length - 1) const SizedBox(width: 14),
              ],
            ],
          );
        }

        return Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              items[index],
              if (index != items.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFeatureLayout(bool isCompact) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 1 : 2;
        final spacing = isCompact ? 12.0 : 16.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _features.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: columns == 1 ? 2.02 : 1.55,
          ),
          itemBuilder: (context, index) {
            final feature = _features[index];
            return _LuxuryFeatureCard(
              feature: feature,
              onTap: () {
                if (feature.opensFutureSimulator) {
                  _show3DSimulator();
                  return;
                }
                final route = feature.route;
                if (route == null || route.isEmpty) return;
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                // Route-specific arguments so dedicated screens can
                // pre-scope their content to the active procedure.
                Object? routeArgs;
                if (route == '/provider-notes' ||
                    route == '/gallery' ||
                    route == '/timeline') {
                  routeArgs = {
                    'procedureId': _activeProcedure?.id,
                    'procedureLabel': _activeProcedure?.type,
                  };
                }
                // Pre-flight: confirm the app's router can build a page
                // for this route. If not, surface a SnackBar instead of
                // letting `onUnknownRoute` silently redirect the user
                // back to the home screen.
                final route$ = navigator.widget.onGenerateRoute?.call(
                  RouteSettings(name: route, arguments: routeArgs),
                );
                if (route$ == null) {
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text(
                        'The "${feature.title}" screen is not available yet ($route).',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                navigator.pushNamed(route, arguments: routeArgs);
              },
              trailing: feature.title == 'Scar Healing Tracker'
                  ? OutlinedButton.icon(
                      onPressed: _showVoiceJournalModal,
                      icon: const Icon(Icons.mic_rounded, size: 17),
                      label: Text('Voice Journal (${_voiceJournals.length})'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _clinicalSage,
                        side: BorderSide(
                          color: _clinicalSage.withValues(
                            alpha: 0.42,
                          ),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: AppColors.cardBackground.withValues(
                          alpha: 0.92,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    )
                  : feature.opensFutureSimulator
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _clinicalSage.withValues(
                            alpha: 0.24,
                          ),
                        ),
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hasActiveProcedure
                                ? Icons.verified_outlined
                                : Icons.info_outline,
                            size: 15,
                            color: _clinicalSage,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _hasActiveProcedure
                                  ? 'Active: ${_activeProcedure?.type ?? ''}'
                                  : 'Select active procedure',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1E2225),
                                fontSize: 11.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  // Voice Journal Modal
  void _showVoiceJournalModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.warmAlabaster,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        String transcript = '';
        bool recording = false;

        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 32,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _clinicalSage.withValues(alpha: 0.22),
                        _mintHighlight.withValues(alpha: 0.22),
                      ],
                    ),
                  ),
                  child: Icon(
                    recording ? Icons.mic : Icons.mic_none,
                    size: 48,
                    color: _clinicalSage,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  recording ? 'Recording...' : 'Voice Journal for Scar',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => setSheetState(() => recording = !recording),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: recording
                          ? AppColors.softTerracotta.withValues(alpha: 0.10)
                          : AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: recording
                            ? AppColors.softTerracotta
                            : AppColors.borders,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        recording ? 'Stop Recording' : 'Start Recording',
                        style: TextStyle(
                          color: recording
                              ? AppColors.softTerracotta
                              : AppColors.refinedSlate,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'AI Transcript',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 3,
                  maxLines: 5,
                  onChanged: (val) => transcript = val,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: MyApp.primaryGoldButton,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Journal Entry'),
                  onPressed: () {
                    if (transcript.trim().isNotEmpty) {
                      setState(() {
                        _voiceJournals.add(
                          VoiceJournalEntry(
                            id: DateTime.now().toIso8601String(),
                            transcript: transcript,
                            createdAt: DateTime.now(),
                            procedureType: 'Scar',
                          ),
                        );
                      });
                      Navigator.pop(context);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 3D Simulator Modal
  void _show3DSimulator() {
    if (!_hasActiveProcedure || _activeProcedure == null) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _clinicalSage.withValues(alpha: 0.22),
                        _mintHighlight.withValues(alpha: 0.24),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: _clinicalSage,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Select an Active Procedure First',
                  textAlign: TextAlign.center,
                  style: MyApp.sectionTitleStyle().copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To generate a luxury, clinically relevant 3D prediction, choose your active procedure in your procedure tracker first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF1E2225),
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: MyApp.primaryGoldButton,
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FutureSimulatorScreen(
          procedure: _activeProcedure!,
          latestScan: _latestProcedureScan,
          baselineScan: _baselineProcedureScan,
        ),
      ),
    );
  }
}

class _HubSignal {
  const _HubSignal({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _LuxuryFeatureCard extends StatefulWidget {
  const _LuxuryFeatureCard({
    required this.feature,
    required this.onTap,
    this.trailing,
  });

  final _HubFeature feature;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_LuxuryFeatureCard> createState() => _LuxuryFeatureCardState();
}

class _LuxuryFeatureCardState extends State<_LuxuryFeatureCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final hoverLift = _hovered ? -4.0 : 0.0;
    final scale = _pressed ? 0.988 : 1.0;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          transform: Matrix4.translationValues(0, hoverLift, 0),
          decoration:
              MyApp.surfaceCardDecoration(
                tintOpacity: feature.highlight ? 0.10 : 0.04,
              ).copyWith(
                border: Border.all(
                  color: feature.highlight
                      ? _clinicalSage.withValues(
                          alpha: _hovered ? 0.42 : 0.28,
                        )
                      : AppColors.borders,
                  width: _hovered ? 1.3 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.refinedSlate.withValues(
                      alpha: _hovered ? 0.12 : 0.07,
                    ),
                    blurRadius: _hovered ? 26 : 18,
                    offset: Offset(0, _hovered ? 11 : 8),
                  ),
                ],
              ),
          child: Material(
            color: Colors.transparent,
            borderRadius: MyApp.cardRadius,
            child: InkWell(
              borderRadius: MyApp.cardRadius,
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              splashColor: _clinicalSage.withValues(alpha: 0.10),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [
                                _clinicalSage,
                                _mintHighlight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _clinicalSage.withValues(
                                  alpha: 0.18,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            feature.icon,
                            color: Color(0xFF1E2225),
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                feature.title,
                                style: MyApp.cardTitleStyle().copyWith(
                                  fontSize: 17.2,
                                  height: 1.22,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                feature.accentLabel,
                                style: const TextStyle(
                                  color: Color(0xFF1E2225),
                                  fontSize: 11.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.34,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF1E2225),
                          size: 19,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      feature.description,
                      style: const TextStyle(
                        color: Color(0xFF1E2225),
                        height: 1.45,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    if (widget.trailing != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: widget.trailing!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Future Look Simulator — full-screen premium experience
// ─────────────────────────────────────────────────────────────────────────────

class _FutureSimulatorScreen extends StatefulWidget {
  const _FutureSimulatorScreen({
    required this.procedure,
    this.latestScan,
    this.baselineScan,
  });
  final Procedure procedure;
  final ScanHistoryEntry? latestScan;
  final ScanHistoryEntry? baselineScan;

  @override
  State<_FutureSimulatorScreen> createState() => _FutureSimulatorScreenState();
}

class _FutureSimulatorScreenState extends State<_FutureSimulatorScreen> {
  int _selectedMonth = 1;
  Uint8List? _baselinePhoto;
  bool _loadingPhoto = true;
  String? _aiSummary;

  String get procedureName => widget.procedure.type;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    try {
      final selectedId = await AppPrefs.resolveActiveProcedureId();
      final scanPhotoComparison = selectedId == null || selectedId.isEmpty
          ? null
          : await AppPrefs.getProcedurePhotoComparison(selectedId);
      if (selectedId != null && selectedId.isNotEmpty) {
        final baselinePath = scanPhotoComparison?['baselineImagePath'];
        if (baselinePath != null && baselinePath.isNotEmpty) {
          final bytes = _decodePath(baselinePath);
          if (bytes != null) {
            if (mounted) {
              setState(() {
                _baselinePhoto = bytes;
                _loadingPhoto = false;
              });
            }
            _updateAiSummary();
            return;
          }
        }
      }
      final scans = await AppPrefs.getScanEntries();
      final withImage =
          scans.where((s) => (s.imagePath ?? '').trim().isNotEmpty).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (withImage.isNotEmpty) {
        final bytes = _decodePath(withImage.first.imagePath!);
        if (mounted) {
          setState(() {
            _baselinePhoto = bytes;
            _loadingPhoto = false;
          });
        }
        _updateAiSummary();
      } else {
        if (mounted) setState(() => _loadingPhoto = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPhoto = false);
    }
  }

  SkinMetrics? _metricsFromScan(ScanHistoryEntry? scan) {
    if (scan == null || scan.metrics.isEmpty) return null;
    return SkinMetrics(
      redness: scan.metrics['redness'] ?? 5.0,
      texture: scan.metrics['texture'] ?? 5.0,
      wrinkle: scan.metrics['wrinkles'] ?? scan.metrics['wrinkle'] ?? 5.0,
      pore: scan.metrics['pores'] ?? 5.0,
      darkSpots: scan.metrics['darkSpots'] ?? 5.0,
      elasticity: scan.metrics['elasticity'] ?? 5.0,
      date: scan.timestamp,
      procedure: scan.procedure,
    );
  }

  void _updateAiSummary() {
    final latest = widget.latestScan;
    final metrics = _metricsFromScan(latest);
    if (metrics == null) return;
    final baselineMetrics = _metricsFromScan(widget.baselineScan);
    final report = AiIntelligenceEngine.interpretScanMetrics(
      metrics,
      baseline: baselineMetrics,
      procedureType: widget.procedure.type,
      daysSinceProcedure: latest == null
          ? null
          : DateTime.now().difference(latest.timestamp).inDays,
      rawMetrics: latest?.metrics,
      baselineRawMetrics: widget.baselineScan?.metrics,
    );
    if (!mounted) return;
    setState(() {
      _aiSummary = report.overallNarrative;
    });
  }

  Uint8List? _decodePath(String path) {
    if (path.startsWith('data:image')) {
      final comma = path.indexOf(',');
      if (comma != -1) {
        try {
          return base64Decode(path.substring(comma + 1));
        } catch (_) {}
      }
    }
    return null;
  }

  // ── Per-timepoint simulation parameters (procedure-aware) ──────────────────

  _SimParams _paramsFor(int month) {
    final p = widget.procedure.type.toLowerCase();
    final latest = widget.latestScan;
    final rednessSignal = (latest?.metrics['redness'] ?? 5.0).clamp(0.0, 10.0);
    final textureSignal = (latest?.metrics['texture'] ?? 5.0).clamp(0.0, 10.0);
    final wrinkleSignal = (latest?.metrics['wrinkles'] ?? latest?.metrics['wrinkle'] ?? 5.0).clamp(0.0, 10.0);
    final skinTension = ((rednessSignal + (10.0 - textureSignal) + wrinkleSignal) / 3.0)
        .clamp(0.0, 10.0)
        .toDouble();
    final emphasis = (skinTension / 10.0).clamp(0.0, 1.0);
    final isLaser =
        p.contains('laser') ||
        p.contains('morpheus') ||
        p.contains('microneedling') ||
        p.contains('peel') ||
        p.contains('resurfac');
    final isBody =
        p.contains('liposuction') ||
        p.contains('tummy') ||
        p.contains('contour') ||
        p.contains('bbl');
    final isBreast = p.contains('breast') || p.contains('augmentation');
    final isSurgical =
        p.contains('facelift') ||
        p.contains('blepharoplasty') ||
        p.contains('lift') ||
        p.contains('rhinoplasty') ||
        p.contains('nose');
    final isInjectables =
        p.contains('filler') ||
        p.contains('botox') ||
        p.contains('injection') ||
        p.contains('neurotox') ||
        p.contains('thread');

    // ── Body Contouring (Liposuction / BBL / Tummy / Contour) ──
    // Clinical, realistic progression: early swelling reduction → smoother
    // contour → refined final result. Effects stay subtle and natural.
    if (isBody) {
      return switch (month) {
        // 1 month — body still swollen; photo should look almost identical
        // to the original. Zero warp, zero blur, zero overlay. Only the
        // faintest redness hint so it doesn't look literally unchanged.
        1 => const _SimParams(
          category: 'body',
          rednessScale: 0.98,
          brightness: 1,
          contrast: 1.001,
          saturation: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Color(0xFFFFEFE2),
          glow: 0.0,
          slimming: 0.0,
          vignette: 0.0,
        ),
        // 3 months — swelling clearing; first visible contour improvement.
        // ~7 % narrower waist, ~5 % narrower hips/thighs — subtle but real.
        3 => const _SimParams(
          category: 'body',
          rednessScale: 0.84,
          brightness: 14,
          contrast: 1.028,
          saturation: 1.07,
          blurSigma: 0.5,
          overlayOpacity: 0.09,
          overlayColor: Color(0xFFFFE8D6),
          glow: 0.13,
          slimming: 0.130,
          vignette: 0.11,
        ),
        // 12 months — final sculpted result; clearly visible fat reduction.
        // ~14 % narrower waist, ~11 % narrower hips, ~8 % narrower upper
        // thighs — strong but still believable post-lipo silhouette.
        12 => const _SimParams(
          category: 'body',
          rednessScale: 0.72,
          brightness: 26,
          contrast: 1.046,
          saturation: 1.15,
          blurSigma: 1.1,
          overlayOpacity: 0.14,
          overlayColor: Color(0xFFFFE2CE),
          glow: 0.22,
          slimming: 0.260,
          vignette: 0.17,
        ),
        _ => const _SimParams(
          category: 'body',
          rednessScale: 1.0,
          brightness: 0,
          contrast: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Colors.transparent,
        ),
      };
    }

    // ── Breast Augmentation — gentle settling, no slimming ──
    if (isBreast) {
      return switch (month) {
        1 => const _SimParams(
          category: 'breast',
          rednessScale: 0.92,
          brightness: 5,
          contrast: 1.015,
          saturation: 1.02,
          blurSigma: 0.4,
          overlayOpacity: 0.05,
          overlayColor: Color(0xFFFFEFE2),
          glow: 0.06,
          vignette: 0.06,
        ),
        3 => const _SimParams(
          category: 'breast',
          rednessScale: 0.84,
          brightness: 9,
          contrast: 1.025,
          saturation: 1.05,
          blurSigma: 0.7,
          overlayOpacity: 0.08,
          overlayColor: Color(0xFFFFE8D6),
          glow: 0.10,
          vignette: 0.10,
        ),
        12 => const _SimParams(
          category: 'breast',
          rednessScale: 0.78,
          brightness: 13,
          contrast: 1.035,
          saturation: 1.08,
          blurSigma: 1.0,
          overlayOpacity: 0.10,
          overlayColor: Color(0xFFFFE2CE),
          glow: 0.14,
          vignette: 0.14,
        ),
        _ => const _SimParams(
          category: 'breast',
          rednessScale: 1.0,
          brightness: 0,
          contrast: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Colors.transparent,
        ),
      };
    }

    // ── Laser / Microneedling / Peel — measured tone & texture refinement ──
    if (isLaser) {
      return switch (month) {
        1 => const _SimParams(
          category: 'laser',
          rednessScale: 0.90,
          brightness: 6,
          contrast: 1.015,
          saturation: 1.02,
          blurSigma: 0.3,
          overlayOpacity: 0.05,
          overlayColor: Color(0xFFFFEFE2),
          glow: 0.06,
          vignette: 0.06,
        ),
        3 => const _SimParams(
          category: 'laser',
          rednessScale: 0.80,
          brightness: 10,
          contrast: 1.025,
          saturation: 1.05,
          blurSigma: 0.6,
          overlayOpacity: 0.08,
          overlayColor: Color(0xFFFFE8D6),
          glow: 0.10,
          vignette: 0.10,
        ),
        12 => const _SimParams(
          category: 'laser',
          rednessScale: 0.70,
          brightness: 14,
          contrast: 1.035,
          saturation: 1.08,
          blurSigma: 0.9,
          overlayOpacity: 0.10,
          overlayColor: Color(0xFFFFE2CE),
          glow: 0.14,
          vignette: 0.14,
          contour: true,
        ),
        _ => const _SimParams(
          category: 'laser',
          rednessScale: 1.0,
          brightness: 0,
          contrast: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Colors.transparent,
        ),
      };
    }

    // ── Surgical face (facelift / bleph / rhino) — natural refinement ──
    if (isSurgical) {
      return switch (month) {
        1 => const _SimParams(
          category: 'surgical',
          rednessScale: 0.92,
          brightness: 5,
          contrast: 1.015,
          saturation: 1.02,
          blurSigma: 0.4,
          overlayOpacity: 0.05,
          overlayColor: Color(0xFFFFEFE2),
          glow: 0.06,
          tightening: 0.004,
          vignette: 0.06,
        ),
        3 => const _SimParams(
          category: 'surgical',
          rednessScale: 0.84,
          brightness: 9,
          contrast: 1.025,
          saturation: 1.05,
          blurSigma: 0.7,
          overlayOpacity: 0.08,
          overlayColor: Color(0xFFFFE8D6),
          glow: 0.10,
          tightening: 0.010,
          vignette: 0.10,
        ),
        12 => const _SimParams(
          category: 'surgical',
          rednessScale: 0.78,
          brightness: 13,
          contrast: 1.035,
          saturation: 1.08,
          blurSigma: 1.0,
          overlayOpacity: 0.10,
          overlayColor: Color(0xFFFFE2CE),
          glow: 0.14,
          tightening: 0.018,
          vignette: 0.14,
          contour: true,
        ),
        _ => const _SimParams(
          category: 'surgical',
          rednessScale: 1.0,
          brightness: 0,
          contrast: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Colors.transparent,
        ),
      };
    }

    // ── Injectables — very subtle refinement ──
    if (isInjectables) {
      return switch (month) {
        1 => const _SimParams(
          category: 'injectables',
          rednessScale: 0.94,
          brightness: 4,
          contrast: 1.01,
          saturation: 1.02,
          blurSigma: 0.3,
          overlayOpacity: 0.04,
          overlayColor: Color(0xFFFFF2E6),
          glow: 0.05,
          tightening: 0.003,
          vignette: 0.05,
        ),
        3 => const _SimParams(
          category: 'injectables',
          rednessScale: 0.88,
          brightness: 7,
          contrast: 1.02,
          saturation: 1.04,
          blurSigma: 0.5,
          overlayOpacity: 0.06,
          overlayColor: Color(0xFFFFEDDA),
          glow: 0.08,
          tightening: 0.008,
          vignette: 0.08,
        ),
        12 => const _SimParams(
          category: 'injectables',
          rednessScale: 0.82,
          brightness: 10,
          contrast: 1.03,
          saturation: 1.06,
          blurSigma: 0.7,
          overlayOpacity: 0.08,
          overlayColor: Color(0xFFFFE8D2),
          glow: 0.11,
          tightening: 0.014,
          vignette: 0.11,
        ),
        _ => const _SimParams(
          category: 'injectables',
          rednessScale: 1.0,
          brightness: 0,
          contrast: 1.0,
          blurSigma: 0.0,
          overlayOpacity: 0.0,
          overlayColor: Colors.transparent,
        ),
      };
    }

    // ── Generic ──
    return switch (month) {
      1 => _SimParams(
        category: 'generic',
        rednessScale: 0.92 - (emphasis * 0.06),
        brightness: 5 + (emphasis * 3.0),
        contrast: 1.015 + (emphasis * 0.006),
        saturation: 1.02 + (emphasis * 0.02),
        blurSigma: 0.4 + (emphasis * 0.08),
        overlayOpacity: 0.05 + (emphasis * 0.03),
        overlayColor: Color(0xFFFFEFE2),
        glow: 0.06 + (emphasis * 0.03),
        vignette: 0.06 + (emphasis * 0.02),
      ),
      3 => _SimParams(
        category: 'generic',
        rednessScale: 0.84 - (emphasis * 0.05),
        brightness: 9 + (emphasis * 4.0),
        contrast: 1.025 + (emphasis * 0.01),
        saturation: 1.05 + (emphasis * 0.025),
        blurSigma: 0.7 + (emphasis * 0.08),
        overlayOpacity: 0.08 + (emphasis * 0.02),
        overlayColor: Color(0xFFFFE8D6),
        glow: 0.10 + (emphasis * 0.04),
        vignette: 0.10 + (emphasis * 0.03),
      ),
      12 => _SimParams(
        category: 'generic',
        rednessScale: 0.78 - (emphasis * 0.04),
        brightness: 13 + (emphasis * 5.0),
        contrast: 1.035 + (emphasis * 0.012),
        saturation: 1.08 + (emphasis * 0.03),
        blurSigma: 1.0 + (emphasis * 0.1),
        overlayOpacity: 0.10 + (emphasis * 0.03),
        overlayColor: Color(0xFFFFE2CE),
        glow: 0.14 + (emphasis * 0.05),
        vignette: 0.14 + (emphasis * 0.04),
        contour: true,
      ),
      _ => const _SimParams(
        category: 'generic',
        rednessScale: 1.0,
        brightness: 0,
        contrast: 1.0,
        blurSigma: 0.0,
        overlayOpacity: 0.0,
        overlayColor: Colors.transparent,
      ),
    };
  }

  // ── Milestone data ──────────────────────────────────────────────────────────

  _MilestoneData get _milestone =>
      _milestoneFor(widget.procedure.type, _selectedMonth);

  static _MilestoneData _milestoneFor(String procedure, int month) {
    final p = procedure.toLowerCase();
    if (p.contains('rhinoplasty') || p.contains('nose')) {
      return _rhinoplastyMilestone(month);
    }
    if (p.contains('breast') || p.contains('augmentation')) {
      return _breastMilestone(month);
    }
    if (p.contains('liposuction') ||
        p.contains('tummy') ||
        p.contains('contour') ||
        p.contains('bbl')) {
      return _lipoMilestone(month);
    }
    if (p.contains('facelift') ||
        p.contains('blepharoplasty') ||
        p.contains('lift')) {
      return _faceliftMilestone(month);
    }
    if (p.contains('laser') ||
        p.contains('morpheus') ||
        p.contains('microneedling') ||
        p.contains('peel')) {
      return _resurfacingMilestone(month);
    }
    if (p.contains('filler') ||
        p.contains('botox') ||
        p.contains('injection')) {
      return _fillerMilestone(month);
    }
    return _genericMilestone(month);
  }

  static _MilestoneData _rhinoplastyMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Swelling softening, contour emerging'
        : m == 3
        ? 'Bridge definition visible'
        : 'Final refined silhouette',
    description: m == 1
        ? 'Major swelling has resolved. The nasal bridge and tip are beginning to show their refined shape, though subtle puffiness may remain.'
        : m == 3
        ? 'Tip projection and bridge contour are now clearly visible. Most patients feel comfortable in social settings.'
        : 'The nose has fully settled into its final form. Natural harmony with facial features is at its peak.',
    metrics: [
      _MetricProjection(
        'Swelling resolved',
        m == 1
            ? 0.55
            : m == 3
            ? 0.80
            : 0.97,
      ),
      _MetricProjection(
        'Contour definition',
        m == 1
            ? 0.40
            : m == 3
            ? 0.72
            : 0.95,
      ),
      _MetricProjection(
        'Overall symmetry',
        m == 1
            ? 0.60
            : m == 3
            ? 0.82
            : 0.96,
      ),
    ],
  );

  static _MilestoneData _breastMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Implants settling, shape forming'
        : m == 3
        ? 'Natural contour establishing'
        : 'Full, balanced final result',
    description: m == 1
        ? 'Implants are descending into position. Firmness is normal; the shape will continue to soften over the coming months.'
        : m == 3
        ? 'Soft-tissue adaptation is well underway. Projection and symmetry appear increasingly natural.'
        : 'Pocket adaptation is complete. Volume, symmetry, and softness reflect the intended outcome.',
    metrics: [
      _MetricProjection(
        'Implant settling',
        m == 1
            ? 0.50
            : m == 3
            ? 0.78
            : 0.96,
      ),
      _MetricProjection(
        'Shape symmetry',
        m == 1
            ? 0.55
            : m == 3
            ? 0.80
            : 0.95,
      ),
      _MetricProjection(
        'Tissue softness',
        m == 1
            ? 0.45
            : m == 3
            ? 0.70
            : 0.94,
      ),
    ],
  );

  static _MilestoneData _lipoMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Edema reducing, shape refining'
        : m == 3
        ? 'Contour becoming visible'
        : 'Clean, defined final result',
    description: m == 1
        ? 'Fluid retention is decreasing. Early contour changes are visible though full results are still emerging.'
        : m == 3
        ? 'Treated zones show significantly improved definition. Transitions between areas appear smoother.'
        : 'Residual swelling has resolved completely. The final body contour is established.',
    metrics: [
      _MetricProjection(
        'Swelling resolved',
        m == 1
            ? 0.45
            : m == 3
            ? 0.75
            : 0.97,
      ),
      _MetricProjection(
        'Contour definition',
        m == 1
            ? 0.35
            : m == 3
            ? 0.68
            : 0.94,
      ),
      _MetricProjection(
        'Skin smoothness',
        m == 1
            ? 0.50
            : m == 3
            ? 0.74
            : 0.93,
      ),
    ],
  );

  static _MilestoneData _faceliftMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Tightness settling, fresh appearance'
        : m == 3
        ? 'Natural rejuvenation visible'
        : 'Fully refined, rested result',
    description: m == 1
        ? 'Initial tension is softening. Incisions are healing well and the rested, lifted effect is clearly visible.'
        : m == 3
        ? 'Soft tissue has relaxed into a natural position. Jawline definition and peri-orbital improvements are prominent.'
        : 'The face fully reflects a naturally refreshed, well-rested appearance consistent with the procedure goals.',
    metrics: [
      _MetricProjection(
        'Tightness resolved',
        m == 1
            ? 0.50
            : m == 3
            ? 0.78
            : 0.96,
      ),
      _MetricProjection(
        'Jawline definition',
        m == 1
            ? 0.55
            : m == 3
            ? 0.80
            : 0.95,
      ),
      _MetricProjection(
        'Overall rejuvenation',
        m == 1
            ? 0.48
            : m == 3
            ? 0.76
            : 0.94,
      ),
    ],
  );

  static _MilestoneData _resurfacingMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Collagen building, tone improving'
        : m == 3
        ? 'Texture refinement visible'
        : 'Peak luminosity and clarity',
    description: m == 1
        ? 'New collagen synthesis is actively underway. Skin tone is more even and early texture improvements are apparent.'
        : m == 3
        ? 'Surface irregularities are noticeably smoother. Pore appearance, fine lines, and pigmentation show clear improvement.'
        : 'Full collagen remodelling is complete. Luminosity, texture, and overall skin quality reflect the procedure\'s peak benefit.',
    metrics: [
      _MetricProjection(
        'Texture improvement',
        m == 1
            ? 0.38
            : m == 3
            ? 0.68
            : 0.92,
      ),
      _MetricProjection(
        'Tone evenness',
        m == 1
            ? 0.42
            : m == 3
            ? 0.72
            : 0.94,
      ),
      _MetricProjection(
        'Luminosity',
        m == 1
            ? 0.40
            : m == 3
            ? 0.70
            : 0.93,
      ),
    ],
  );

  static _MilestoneData _fillerMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Product integrating, volume visible'
        : m == 3
        ? 'Natural volume established'
        : 'Settled, refined result',
    description: m == 1
        ? 'Initial swelling has resolved. Filler product is integrating with surrounding tissue and volume looks natural.'
        : m == 3
        ? 'Product is fully integrated. Contour enhancement appears balanced and proportionate.'
        : 'The final settled result reflects natural-looking volume with excellent facial harmony.',
    metrics: [
      _MetricProjection(
        'Volume naturalness',
        m == 1
            ? 0.60
            : m == 3
            ? 0.82
            : 0.95,
      ),
      _MetricProjection(
        'Symmetry',
        m == 1
            ? 0.65
            : m == 3
            ? 0.84
            : 0.96,
      ),
      _MetricProjection(
        'Integration',
        m == 1
            ? 0.55
            : m == 3
            ? 0.80
            : 0.97,
      ),
    ],
  );

  static _MilestoneData _genericMilestone(int m) => _MilestoneData(
    headline: m == 1
        ? 'Early healing progress'
        : m == 3
        ? 'Significant improvement visible'
        : 'Final result established',
    description: m == 1
        ? 'Initial healing is progressing well. Swelling and any temporary changes are beginning to resolve.'
        : m == 3
        ? 'The treated area shows substantial improvement. Tissue remodelling is well underway.'
        : 'Recovery is complete. The final, stable outcome of the procedure is now fully visible.',
    metrics: [
      _MetricProjection(
        'Healing progress',
        m == 1
            ? 0.45
            : m == 3
            ? 0.74
            : 0.95,
      ),
      _MetricProjection(
        'Visual improvement',
        m == 1
            ? 0.40
            : m == 3
            ? 0.70
            : 0.93,
      ),
      _MetricProjection(
        'Stability',
        m == 1
            ? 0.50
            : m == 3
            ? 0.78
            : 0.97,
      ),
    ],
  );

  // ── Procedure-aware captions ────────────────────────────────────────────────

  String _captionFor(int month) {
    final p = widget.procedure.type.toLowerCase();
    if (p.contains('laser') ||
        p.contains('morpheus') ||
        p.contains('microneedling') ||
        p.contains('peel')) {
      return switch (month) {
        1 =>
          'Month 1 — Early collagen response. Mild residual erythema, tone beginning to even.',
        3 =>
          'Month 3 — Texture refinement visible. Tone more uniform, pores subtly tighter.',
        12 =>
          'Month 12 — Stable result. Smoother texture, even tone, healthy clarity.',
        _ => '',
      };
    }
    if (p.contains('liposuction') ||
        p.contains('tummy') ||
        p.contains('contour') ||
        p.contains('bbl')) {
      return switch (month) {
        1 =>
          'Month 1 — Early healing phase. Treated areas still swollen and firm — this is completely normal. Your body is actively recovering; real contouring results are forming beneath the surface.',
        3 =>
          'Month 3 — Real results emerging. Swelling largely resolved; waist and hip definition now clearly visible. Skin actively retracting and reshaping to your new contour.',
        12 =>
          'Month 12 — Your sculpted final result. Dramatic fat reduction, defined waist, refined silhouette, and smoothly tightened skin. This is your long-term outcome.',

        _ => '',
      };
    }
    if (p.contains('rhinoplasty') || p.contains('nose')) {
      return switch (month) {
        1 =>
          'Month 1 — Tip swelling reducing. Bridge contour beginning to emerge.',
        3 =>
          'Month 3 — Most swelling resolved. Natural profile becoming apparent.',
        12 =>
          'Month 12 — Final, settled silhouette. Refined and proportionate.',
        _ => '',
      };
    }
    if (p.contains('facelift') ||
        p.contains('lift') ||
        p.contains('blepharoplasty')) {
      return switch (month) {
        1 =>
          'Month 1 — Initial tightness softening. Subtle lift visible along jawline and peri-orbital region.',
        3 =>
          'Month 3 — Tissues relaxed into natural position. Refreshed, rested appearance.',
        12 =>
          'Month 12 — Stable, natural rejuvenation. Refined jawline and rested expression.',
        _ => '',
      };
    }
    if (p.contains('filler') ||
        p.contains('botox') ||
        p.contains('injection')) {
      return switch (month) {
        1 =>
          'Month 1 — Initial swelling resolved. Product integrating naturally.',
        3 => 'Month 3 — Fully integrated. Balanced, proportionate result.',
        12 =>
          'Month 12 — Settled, refined enhancement. Natural facial harmony.',
        _ => '',
      };
    }
    return switch (month) {
      1 => 'Month 1 — Early healing. Mild residual swelling and redness.',
      3 => 'Month 3 — Steady improvement. Tone and texture more even.',
      12 => 'Month 12 — Stable final result. Refined, healthy appearance.',
      _ => '',
    };
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  String get _monthLabel => _selectedMonth == 1
      ? '1 Month'
      : _selectedMonth == 3
      ? '3 Months'
      : '12 Months';

  String get _stageLabel => _selectedMonth == 1
      ? 'Early healing'
      : _selectedMonth == 3
      ? 'Mid recovery'
      : 'Final result';

  @override
  Widget build(BuildContext context) {
    final milestone = _milestone;
    final params = _paramsFor(_selectedMonth);
    final caption = _captionFor(_selectedMonth);
    final monthLabel = _monthLabel;

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: MyApp.textBrown),
        title: const ClinicalAppBarTitle(
          eyebrow: 'AI Progress Projection',
          title: 'Future Look Simulator',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'About this projection',
            icon: Icon(Icons.info_outline_rounded, color: MyApp.clinicalTeal),
            onPressed: _showMethodologyDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Procedure clinical header card ────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _buildProcedureHeaderCard(),
            ),
            const SizedBox(height: 22),

            // ── Section 1 · Projection Timeline ───────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ClinicalSectionHeader(
                icon: Icons.timeline_rounded,
                eyebrow: 'Step 1',
                title: 'Projection Timeline',
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Text(
                'Select a recovery milestone to visualize how the treated area is expected to progress.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: MyApp.clinicalMuted,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final month in [1, 3, 12]) ...[
                    Expanded(
                      child: _MonthChip(
                        label: month == 12 ? '12 mo' : '$month mo',
                        sublabel: month == 1
                            ? 'Early healing'
                            : month == 3
                            ? 'Mid recovery'
                            : 'Final result',
                        selected: _selectedMonth == month,
                        onTap: () => setState(() => _selectedMonth = month),
                      ),
                    ),
                    if (month != 12) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),

            // ── Section 2 · Visual Projection (side-by-side) ──────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ClinicalSectionHeader(
                icon: Icons.compare_rounded,
                eyebrow: 'Step 2 · Before / After',
                title: 'Visual Projection',
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildComparisonRow(params, monthLabel),
            ),
            if ((_aiSummary ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildAiContextCard(),
              ),
            ],
            const SizedBox(height: 14),

            // ── Caption ───────────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              child: Padding(
                key: ValueKey('cap_$_selectedMonth'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildCaptionCard(caption),
              ),
            ),
            const SizedBox(height: 24),

            // ── Section 3 · Clinical Milestones ───────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ClinicalSectionHeader(
                icon: Icons.medical_information_outlined,
                eyebrow: 'Step 3',
                title: 'Recovery Milestones',
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              child: Padding(
                key: ValueKey('ms_$_selectedMonth'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMilestoneCard(milestone),
              ),
            ),
            const SizedBox(height: 22),

            // ── Section 4 · Clinical Disclaimer ───────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDisclaimerPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiContextCard() {
    final latest = widget.latestScan;
    final metrics = _metricsFromScan(latest);
    if ((_aiSummary ?? '').trim().isEmpty || metrics == null) {
      return const SizedBox.shrink();
    }

    Widget metricChip(String label, double value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: MyApp.clinicalTeal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: MyApp.clinicalTeal.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          '$label ${(value * 10).round() / 10}',
          style: TextStyle(
            color: MyApp.clinicalNavy,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _clinicalSage.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_rounded, color: MyApp.clinicalTeal),
              const SizedBox(width: 8),
              Text(
                'AI Skin Context',
                style: TextStyle(
                  color: MyApp.clinicalNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _aiSummary!,
            style: TextStyle(
              color: MyApp.textBrown,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              metricChip('Redness', metrics.redness),
              metricChip('Texture', metrics.texture),
              metricChip('Wrinkles', metrics.wrinkle),
            ],
          ),
        ],
      ),
    );
  }

  // ── Procedure header card ────────────────────────────────────────────────
  Widget _buildProcedureHeaderCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _clinicalSage.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.mutedSage.withValues(alpha: 0.16),
                  _clinicalSage.withValues(alpha: 0.16),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.30),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: MyApp.clinicalTeal,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TREATMENT PLAN',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: MyApp.clinicalMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  procedureName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.mutedSage.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _stageLabel,
              style: const TextStyle(
                color: AppColors.mutedSage,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Before / After comparison row ────────────────────────────────────────
  Widget _buildComparisonRow(_SimParams params, String monthLabel) {
    if (_loadingPhoto) {
      return const _PhotoPlaceholder(loading: true);
    }
    if (_baselinePhoto == null) {
      return const _PhotoPlaceholder(loading: false);
    }
    final baselineBytes = _baselinePhoto!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ComparisonPanel(
            label: 'Current Appearance',
            sublabel: 'Baseline',
            badgeColor: MyApp.clinicalNavy,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(
                      baselineBytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Before',
                          style: TextStyle(
                            color: Color(0xFF1E2225),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ComparisonPanel(
            label: 'Projected at $monthLabel',
            sublabel: _stageLabel,
            badgeColor: MyApp.clinicalTeal,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final scale = Tween<double>(begin: 0.97, end: 1.0).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                );
                return FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: scale, child: child),
                );
              },
              child: Stack(
                key: ValueKey(_selectedMonth),
                children: [
                  _SimulatedPhoto(
                    baselineBytes: baselineBytes,
                    params: params,
                    monthLabel: monthLabel,
                  ),
                  // Clinical measurement grid overlay (rule of thirds).
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CustomPaint(painter: _ClinicalGridPainter()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Caption card ─────────────────────────────────────────────────────────
  Widget _buildCaptionCard(String caption) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mutedSage.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.mutedSage,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 11),
          const Icon(
            Icons.insights_rounded,
            size: 16,
            color: AppColors.mutedSage,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              caption,
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Milestone card ───────────────────────────────────────────────────────
  Widget _buildMilestoneCard(_MilestoneData milestone) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _clinicalSage.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final m in [1, 3, 12])
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _selectedMonth == m ? 24 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _selectedMonth == m
                          ? MyApp.clinicalTeal
                          : MyApp.clinicalTeal.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Month $_selectedMonth',
                  style: TextStyle(
                    color: MyApp.clinicalTeal,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            milestone.headline,
            style: TextStyle(
              color: MyApp.clinicalNavy,
              fontWeight: FontWeight.w800,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            milestone.description,
            style: TextStyle(color: MyApp.textBrown, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'PROJECTED PROGRESS',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                  color: MyApp.clinicalMuted,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'Each metric reflects the expected percentage of the full expected outcome '
                    'reached at this milestone, based on typical recovery patterns for your procedure.',
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 13,
                  color: MyApp.clinicalMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final metric in milestone.metrics) ...[
            _ProjectionBar(metric: metric, month: _selectedMonth),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  // ── Clinical disclaimer panel ───────────────────────────────────────────
  Widget _buildDisclaimerPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MyApp.clinicalNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.clinicalNavy.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: MyApp.clinicalNavy.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI-GENERATED PROGRESS PROJECTION',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: MyApp.clinicalNavy.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This visualization is an AI-generated simulation for educational purposes only. '
                  'Projections are based on typical recovery patterns for your procedure type and do not '
                  'constitute medical advice or a guarantee of results. Actual outcomes vary by individual '
                  'physiology, technique, and aftercare. Consult your treating provider for medical guidance.',
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Methodology dialog ───────────────────────────────────────────────────
  void _showMethodologyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        Widget bullet(IconData icon, String title, String body) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: MyApp.clinicalTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: MyApp.clinicalNavy,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          color: MyApp.textBrown,
                          fontSize: 12,
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

        return Dialog(
          backgroundColor: AppColors.warmAlabaster,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ClinicalSectionHeader(
                    icon: Icons.science_outlined,
                    eyebrow: 'Methodology',
                    title: 'How this projection works',
                  ),
                  const SizedBox(height: 16),
                  bullet(
                    Icons.timeline_rounded,
                    'Evidence-informed timeline',
                    'Three milestones (1 mo · 3 mo · 12 mo) reflect typical healing curves for the '
                        'selected procedure category — body contouring, surgical lift, resurfacing, '
                        'injectables, and others each follow their own validated trajectory.',
                  ),
                  bullet(
                    Icons.photo_filter_outlined,
                    'Photo-realistic rendering pipeline',
                    'A layered engine that preserves your real skin texture and lighting: subtle '
                        'tone correction, luminance-preserving hue blending, texture-safe smoothing, '
                        'soft-light healthy sheen, and a subject-aware mask so the background, hair '
                        'edges, and frame are never altered.',
                  ),
                  bullet(
                    Icons.bar_chart_rounded,
                    'Projected progress metrics',
                    'Percentages indicate how close each recovery dimension (swelling, contour, tone, etc.) '
                        'is to its expected long-term outcome at the chosen milestone.',
                  ),
                  bullet(
                    Icons.warning_amber_rounded,
                    'Not a medical prediction',
                    'Results vary based on physiology, surgical technique, and aftercare. Use this tool '
                        'for educational visualization — not as a guarantee or substitute for medical advice.',
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: MyApp.clinicalTeal,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w800),
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
  }
}

// ── Comparison panel chrome ──────────────────────────────────────────────────
class _ComparisonPanel extends StatelessWidget {
  const _ComparisonPanel({
    required this.label,
    required this.sublabel,
    required this.badgeColor,
    required this.child,
  });

  final String label;
  final String sublabel;
  final Color badgeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: badgeColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: badgeColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: MyApp.clinicalMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
        ],
      ),
    );
  }
}

// ── Clinical grid overlay (rule of thirds + center axis) ─────────────────────
class _ClinicalGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 0.7;
    final axis = Paint()
      ..color = MyApp.clinicalTeal.withValues(alpha: 0.32)
      ..strokeWidth = 0.9;

    final w = size.width, h = size.height;
    // Rule of thirds
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), line);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), line);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), line);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), line);
    // Symmetry axis (vertical center)
    canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), axis);

    // Corner ticks for a clinical "measurement frame" feel.
    final tick = Paint()
      ..color = MyApp.clinicalTeal.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    const t = 10.0;
    canvas.drawLine(const Offset(0, 0), const Offset(t, 0), tick);
    canvas.drawLine(const Offset(0, 0), const Offset(0, t), tick);
    canvas.drawLine(Offset(w, 0), Offset(w - t, 0), tick);
    canvas.drawLine(Offset(w, 0), Offset(w, t), tick);
    canvas.drawLine(Offset(0, h), Offset(t, h), tick);
    canvas.drawLine(Offset(0, h), Offset(0, h - t), tick);
    canvas.drawLine(Offset(w, h), Offset(w - t, h), tick);
    canvas.drawLine(Offset(w, h), Offset(w, h - t), tick);
  }

  @override
  bool shouldRepaint(covariant _ClinicalGridPainter oldDelegate) => false;
}

// ── Simulation parameters data class ─────────────────────────────────────────

class _SimParams {
  const _SimParams({
    this.category = 'generic',
    required this.rednessScale,
    required this.brightness,
    required this.contrast,
    this.saturation = 1.0,
    required this.blurSigma,
    required this.overlayOpacity,
    required this.overlayColor,
    this.glow = 0.0,
    this.slimming = 0.0,
    this.tightening = 0.0,
    this.vignette = 0.0,
    this.contour = false,
  });

  /// 'body' (lipo/bbl/tummy/contour) · 'breast' · 'laser' · 'surgical' ·
  /// 'injectables' · 'generic'. Drives which overlays/painters are applied.
  final String category;
  final double rednessScale;
  final double brightness;
  final double contrast;

  /// 1.0 = neutral, >1 boosts saturation, <1 desaturates.
  final double saturation;
  final double blurSigma;
  final double overlayOpacity;
  final Color overlayColor;

  /// 0–1 strength of warm radial glow (luminosity enhancement).
  final double glow;

  /// 0–0.15 vertical elongation strength — slimming illusion for body procedures.
  final double slimming;

  /// 0–0.08 vertical lift for facial procedures — sharper jaw / elevated cheeks.
  final double tightening;

  /// 0–1 frame vignette strength.
  final double vignette;
  final bool contour;

  // ── Realism scalars ─────────────────────────────────────────────────────
  // The raw category presets in `_paramsFor` are tuned for visual clarity.
  // The clinical realism pipeline (see `_SimulatedPhoto.build`) applies these
  // multipliers to dial each effect back toward a much more believable,
  // photo-realistic range. Tweak these in ONE place to globally retune the
  // realism / dramatic-effect balance.
  //
  // These values are intentionally CONSERVATIVE — the goal is a subtle,
  // clinically plausible projection, not a dramatic transformation. The
  // texture re-injection layer (L1.5) restores pores/detail lost to blur.
  double get realBlur => blurSigma * 0.14; // tiny smoothing only
  double get realOverlay => overlayOpacity * 0.42; // gentle tone shift
  double get realGlow => glow * 0.38; // very subtle sheen
  double get realSlimming => slimming * 0.55; // natural silhouette
  double get realTightening => tightening * 0.42; // barely perceptible lift
  double get realVignette => vignette * 0.75; // soft focus

  /// How much of the category's color-correction preset to retain
  /// (1.0 = full preset, 0.0 = identity / no correction). Pulling this
  /// down preserves the patient's natural skin tone & undertones, which
  /// is the single biggest realism win.
  static const double _realismToward = 0.55;

  /// 4×5 ColorFilter matrix: gently shifts toward the post-procedure tone
  /// while preserving most of the patient's natural skin color.
  /// Inputs and offset are in [0, 255] range.
  List<double> get colorMatrix {
    // Soften the preset toward identity for realism.
    final r = 1.0 + (rednessScale - 1.0) * _realismToward;
    final c = 1.0 + (contrast - 1.0) * _realismToward;
    final b = brightness * _realismToward;
    final rScale = r * c;
    final gbScale = c;
    const mid = 128.0;
    final rOff = b + (1 - c) * mid * r;
    final gbOff = b + (1 - c) * mid;
    return [
      rScale,
      0,
      0,
      0,
      rOff,
      0,
      gbScale,
      0,
      0,
      gbOff,
      0,
      0,
      gbScale,
      0,
      gbOff,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// Standard luma-weighted saturation matrix, softened toward identity.
  List<double> get saturationMatrix {
    final s = 1.0 + (saturation - 1.0) * _realismToward;
    const lumR = 0.213, lumG = 0.715, lumB = 0.072;
    final sr = (1 - s) * lumR;
    final sg = (1 - s) * lumG;
    final sb = (1 - s) * lumB;
    return [
      sr + s,
      sg,
      sb,
      0,
      0,
      sr,
      sg + s,
      sb,
      0,
      0,
      sr,
      sg,
      sb + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// Effective saturation after realism softening (used to skip the matrix
  /// step when the change would be imperceptible).
  double get effectiveSaturationDelta =>
      ((saturation - 1.0) * _realismToward).abs();
}

// ── Supporting widgets ────────────────────────────────────────────────────────

// Applies geometric body-contouring via pixel-level horizontal strip warping.
// The full source image is mapped to a narrower destination at waist/hip height,
// producing genuine pixel-level silhouette narrowing — not just a shadow overlay.
// Edge gaps are filled with stretched edge pixels so no transparent seams appear.
class _BodyWarpPainter extends CustomPainter {
  final ui.Image image;

  /// Slim factor 0.0 – 0.15  (0.15 ≈ 13 % narrowing at waist peak).
  final double slim;

  _BodyWarpPainter({required this.image, required this.slim});

  /// Multi-zone warp profile covering the full liposuction treatment area —
  /// upper waist/flanks, waist (peak), hips, and upper thighs. Produces a
  /// smooth, balanced hourglass taper rather than only pinching one band.
  ///   t = 0.30 upper waist / flanks         (70 %)
  ///   t = 0.50 waist                        (100 % — peak)
  ///   t = 0.65 hips                         (80 %)
  ///   t = 0.78 upper thighs                 (55 %)
  /// Smoothly fades to 0 above the chest (t < ~0.22) and below the knees
  /// (t > ~0.88).
  double _warpAt(double t) {
    // Each bell: peak height * (1 - ((t - center) / halfWidth)^2), clamped.
    double bell(double center, double half, double height) {
      final d = (t - center) / half;
      final v = height * (1.0 - d * d);
      return v < 0 ? 0 : v;
    }

    final flank = bell(0.38, 0.14, 0.72);
    final waist = bell(0.50, 0.13, 1.00);
    final hip = bell(0.65, 0.13, 0.82);
    final thigh = bell(0.78, 0.11, 0.55);

    // Combine as a smooth maximum so bells blend into one continuous curve.
    double m = flank;
    if (waist > m) m = waist;
    if (hip > m) m = hip;
    if (thigh > m) m = thigh;
    return m.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final canW = size.width;
    final canH = size.height;

    // Compute a BoxFit.cover source rectangle so this painter matches the
    // surrounding `Image.memory(... BoxFit.cover)` baseline exactly. Without
    // this, the painter stretches the entire image to fill the canvas,
    // producing a completely different framing from the Before pane.
    final canAspect = canW / canH;
    final imgAspect = imgW / imgH;
    double sX, sY, sW, sH;
    if (imgAspect > canAspect) {
      // Image is wider — crop sides.
      sH = imgH;
      sW = imgH * canAspect;
      sX = (imgW - sW) / 2;
      sY = 0;
    } else {
      // Image is taller — crop top/bottom.
      sW = imgW;
      sH = imgW / canAspect;
      sX = 0;
      sY = (imgH - sH) / 2;
    }

    if (slim < 0.001) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(sX, sY, sW, sH),
        Rect.fromLTWH(0, 0, canW, canH),
        Paint(),
      );
      return;
    }

    const strips = 96;
    final stripCanH = canH / strips;
    final stripSrcH = sH / strips;
    // Outermost 4.5 % of (cover-cropped) image width used to fill freed
    // edge gaps — wider sample tolerates the stronger inward warp.
    final edgeSampleW = sW * 0.045;

    for (int i = 0; i < strips; i++) {
      final t = (i + 0.5) / strips;
      final warp = _warpAt(t) * slim;
      // 0.55 multiplier: with slim=0.26 (12 mo) and waist warp=1.0, this
      // narrows each side by ~14 % of the canvas width (~28 % total at
      // the waist) — a clear, clinically believable sculpt.
      final inset = canW * warp * 0.55;
      final srcY1 = sY + i * stripSrcH;
      final srcY2 = sY + (i + 1) * stripSrcH;
      final dstY1 = i * stripCanH;
      final dstY2 = (i + 1) * stripCanH;

      if (inset < 0.5) {
        canvas.drawImageRect(
          image,
          Rect.fromLTRB(sX, srcY1, sX + sW, srcY2),
          Rect.fromLTRB(0, dstY1, canW, dstY2),
          Paint(),
        );
      } else {
        // Left gap — stretch left edge pixels to fill.
        canvas.drawImageRect(
          image,
          Rect.fromLTRB(sX, srcY1, sX + edgeSampleW, srcY2),
          Rect.fromLTRB(0, dstY1, inset, dstY2),
          Paint(),
        );
        // Body — cover-cropped source compressed into narrowed destination.
        canvas.drawImageRect(
          image,
          Rect.fromLTRB(sX, srcY1, sX + sW, srcY2),
          Rect.fromLTRB(inset, dstY1, canW - inset, dstY2),
          Paint(),
        );
        // Right gap — stretch right edge pixels to fill.
        canvas.drawImageRect(
          image,
          Rect.fromLTRB(sX + sW - edgeSampleW, srcY1, sX + sW, srcY2),
          Rect.fromLTRB(canW - inset, dstY1, canW, dstY2),
          Paint(),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyWarpPainter old) =>
      old.slim != slim || old.image != image;
}

// Painter for facial contour — very gentle jawline / cheekbone / T-zone
// highlights to suggest natural rejuvenation without looking like makeup.
class _FaceContourPainter extends CustomPainter {
  final double strength;
  _FaceContourPainter({required this.strength});

  @override
  void paint(Canvas canvas, Size size) {
    final s = strength.clamp(0.0, 1.8);

    // Jawline arc — soft warm highlight.
    final jaw = Paint()
      ..color = const Color(
        0xFFFFF6E6,
      ).withValues(alpha: (0.05 * s).clamp(0.0, 0.12))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 + 5 * s
      ..strokeCap = StrokeCap.round;
    final jawPath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.80)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.97,
        size.width * 0.82,
        size.height * 0.80,
      );
    canvas.drawPath(jawPath, jaw);

    // Cheekbone arcs.
    final cheek = Paint()
      ..color = Colors.white.withValues(alpha: (0.035 * s).clamp(0.0, 0.09))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 + 4 * s
      ..strokeCap = StrokeCap.round;
    final left = Path()
      ..moveTo(size.width * 0.26, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.52,
        size.width * 0.49,
        size.height * 0.62,
      );
    final right = Path()
      ..moveTo(size.width * 0.51, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.52,
        size.width * 0.74,
        size.height * 0.62,
      );
    canvas.drawPath(left, cheek);
    canvas.drawPath(right, cheek);

    // Subtle T-zone highlight (forehead).
    final tzone = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.28),
        size.width * 0.32,
        [
          Colors.white.withValues(alpha: (0.04 * s).clamp(0.0, 0.09)),
          Colors.transparent,
        ],
        [0.0, 1.0],
      );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.28),
      size.width * 0.32,
      tzone,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceContourPainter old) =>
      old.strength != strength;
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? MyApp.clinicalTeal : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MyApp.clinicalTeal
                : MyApp.clinicalNavy.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: MyApp.clinicalTeal.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: MyApp.clinicalNavy.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1E2225),
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: const TextStyle(
                color: Color(0xFF1E2225),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimulatedPhoto extends StatefulWidget {
  const _SimulatedPhoto({
    required this.baselineBytes,
    required this.params,
    required this.monthLabel,
  });
  final Uint8List baselineBytes;
  final _SimParams params;
  final String monthLabel;

  @override
  State<_SimulatedPhoto> createState() => _SimulatedPhotoState();
}

class _SimulatedPhotoState extends State<_SimulatedPhoto> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(_SimulatedPhoto old) {
    super.didUpdateWidget(old);
    if (!identical(old.baselineBytes, widget.baselineBytes)) {
      _image?.dispose();
      _image = null;
      _loadImage();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.baselineBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _image = frame.image);
      } else {
        frame.image.dispose();
      }
    } catch (_) {
      // Falls back to Image.memory rendering when ui.Image is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.params;
    final baselineBytes = widget.baselineBytes;
    final monthLabel = widget.monthLabel;

    // ── 1-Month view = pure baseline ──────────────────────────────────────
    // The 1-month projection must be the user's original photo with ZERO
    // processing: no color grading, no blur, no warp, no glow, no overlay,
    // no vignette. Only the framing chrome (rounded corner, "Projected at"
    // badge, "Your photo" label) is layered on top. This guarantees a
    // perfectly clean reference frame against which 3 mo and 12 mo
    // enhancements are compared.
    if (monthLabel == '1 Month') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.memory(
                  baselineBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Color(0xFF1E2225).withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _clinicalSage.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 11,
                        color: _clinicalSage,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Projected at $monthLabel',
                        style: TextStyle(
                          color: _clinicalSage,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Color(0xFF1E2225).withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Your photo',
                    style: TextStyle(
                      color: Color(0xFF1E2225),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final category = params.category;
    final isBody = category == 'body';
    final isBreast = category == 'breast';
    final isSurgical = category == 'surgical';
    final isFaceCategory =
        category == 'laser' ||
        isSurgical ||
        category == 'injectables' ||
        category == 'generic';

    // ────────────────────────────────────────────────────────────────────
    // Clinical-realism rendering pipeline
    // ────────────────────────────────────────────────────────────────────
    // The goal is photo-realistic output that preserves the patient's
    // actual skin texture, lighting, and background — only the *treated*
    // area is refined. The pipeline is:
    //
    //   L0  Clean baseline           (untouched original — background fidelity)
    //   L1  Subject-masked enhancement layer:
    //         • Body warp (when applicable) using `ui.Image` painter
    //         • Tone-correction matrix (gentle redness reduction)
    //         • Saturation matrix
    //         • Light blur for skin softening (≈0.10 σ — texture preserved)
    //         • HUE-PRESERVING warm tone shift via `BlendMode.color`
    //           (keeps original luminance / shadows intact)
    //         • Vertical lift transform (face categories only)
    //         • Face contour painter (jaw / cheek / T-zone highlights)
    //         • Healthy-skin sheen via `BlendMode.softLight` radial mask
    //       The whole layer is masked to a soft ellipse so the frame edges,
    //       hair, and background are not affected.
    //   L2  Multiply-blend vignette  (natural subject focus)
    //   L3  Clinical badges          ("Your photo" / "Projected at X")
    // ────────────────────────────────────────────────────────────────────
    final realBlur = params.realBlur;
    final realOverlay = params.realOverlay;
    final realGlow = params.realGlow;
    final realTightening = params.realTightening;
    final realVignette = params.realVignette;

    // ── L1 base image source ─────────────────────────────────────────────
    Widget img;
    if (isBody && _image != null) {
      img = SizedBox.expand(
        child: CustomPaint(
          painter: _BodyWarpPainter(image: _image!, slim: params.realSlimming),
          isComplex: true,
        ),
      );
    } else {
      img = Image.memory(
        baselineBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    // L1.a — Tone correction matrix (subtle redness reduction + lift).
    img = ColorFiltered(
      colorFilter: ColorFilter.matrix(params.colorMatrix),
      child: img,
    );

    // L1.b — Saturation refinement (skip if softened delta is negligible).
    if (params.effectiveSaturationDelta > 0.005) {
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(params.saturationMatrix),
        child: img,
      );
    }

    // L1.c — Edge-preserving "soft skin". The sigma is intentionally tiny
    //        so pore-level detail survives — this is the most important fix
    //        for the previous "plastic" look.
    if (realBlur > 0.02) {
      img = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: realBlur, sigmaY: realBlur),
        child: img,
      );
    }

    // L1.d — Hue-preserving warm tone shift.
    //        `BlendMode.color` blends the warm hue/saturation while keeping
    //        the underlying luminance (shadows + highlights) intact — far
    //        more realistic than a flat over-painted tint. Kept very gentle
    //        so the patient's natural undertone is preserved.
    if (realOverlay > 0.001) {
      final tintAlpha = (realOverlay * 2.4).clamp(0.0, 0.20);
      img = ColorFiltered(
        colorFilter: ColorFilter.mode(
          params.overlayColor.withValues(alpha: tintAlpha),
          BlendMode.color,
        ),
        child: img,
      );
    }

    // L1.e — Geometric refinement (face categories).
    if (!isBody && !isBreast && realTightening > 0.001) {
      final stretchY = 1.0 + realTightening;
      img = ClipRect(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(1.0, stretchY, 1.0),
          child: img,
        ),
      );
    }

    // L1.f — Face contour highlights (jawline / cheekbone / T-zone).
    if (isFaceCategory && params.contour) {
      img = Stack(
        fit: StackFit.expand,
        children: [
          img,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FaceContourPainter(
                  strength: realBlur * 0.4 + realOverlay * 2.0 + realGlow,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // L1.g — Healthy-skin sheen.
    //        `BlendMode.softLight` lifts highlights without crushing shadows,
    //        the photographic "glow" that flat overlays can never achieve.
    //        Intentionally very subtle to avoid a waxy/plastic appearance.
    if (realGlow > 0.01) {
      img = ShaderMask(
        blendMode: BlendMode.softLight,
        shaderCallback: (rect) => RadialGradient(
          center: Alignment(0, (isBody || isBreast) ? 0.05 : -0.10),
          radius: 0.85,
          colors: [
            Colors.white.withValues(alpha: (0.22 * realGlow).clamp(0.0, 0.22)),
            Colors.white.withValues(alpha: (0.08 * realGlow).clamp(0.0, 0.10)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
        child: img,
      );
    }

    // Subject ellipse — mask all enhancements to the central region so the
    // background, hair edges, and frame border remain pristine.
    final enhanced = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => RadialGradient(
        center: Alignment(0, (isBody || isBreast) ? 0.0 : -0.05),
        radius: 0.98,
        colors: const [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect),
      child: img,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // L0 — Clean baseline. ALWAYS visible underneath; the subject mask
            //      on L1 fades enhancements at the edges so this baseline
            //      provides the natural background, edges and frame.
            Positioned.fill(
              child: Image.memory(
                baselineBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),

            // L1 — Subject-masked clinical enhancements.
            Positioned.fill(child: enhanced),

            // L1.5 — Texture re-injection.
            //        Poor-man's frequency separation: a low-opacity copy of
            //        the ORIGINAL (sharp) photo, masked to the subject ellipse,
            //        is composited on top of the smoothed enhancement layer to
            //        restore pore-level detail. This is the key fix for the
            //        "waxy" look — it puts the patient's real skin texture
            //        back into the simulated result.
            if (realBlur > 0.01)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.45,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => RadialGradient(
                        center: Alignment(
                          0,
                          (isBody || isBreast) ? 0.0 : -0.05,
                        ),
                        radius: 0.95,
                        colors: const [
                          Color(0xFFFFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ).createShader(rect),
                      child: Image.memory(
                        baselineBytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),

            // L2 — Multiply-blend vignette.
            //      Natural subject focus that preserves highlights inside the
            //      subject ellipse and darkens only the outer frame.
            if (realVignette > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      backgroundBlendMode: BlendMode.multiply,
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.95,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Color.lerp(
                            Colors.white,
                            Color(0xFF1E2225),
                            (0.32 * realVignette).clamp(0.0, 0.32),
                          )!,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

            // Projected at X badge (bottom-right).
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Color(0xFF1E2225).withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _clinicalSage.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 11,
                      color: _clinicalSage,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Projected at $monthLabel',
                      style: TextStyle(
                        color: _clinicalSage,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Baseline label (top-left).
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Your photo',
                  style: TextStyle(
                    color: Color(0xFF1E2225),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MyApp.clinicalNavy.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: MyApp.clinicalNavy.withValues(alpha: 0.03),
            child: Center(
              child: loading
                  ? CircularProgressIndicator(color: MyApp.clinicalTeal)
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.face_retouching_natural,
                            size: 48,
                            color: MyApp.clinicalTeal.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No baseline photo yet',
                            style: TextStyle(
                              color: MyApp.clinicalNavy,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add a photo in Track Procedure to generate your simulation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: MyApp.clinicalMuted,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectionBar extends StatelessWidget {
  const _ProjectionBar({required this.metric, required this.month});
  final _MetricProjection metric;
  final int month;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              metric.label,
              style: TextStyle(
                color: MyApp.clinicalNavy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${(metric.value * 100).round()}%',
              style: TextStyle(
                color: MyApp.clinicalTeal,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          key: ValueKey('${metric.label}-$month'),
          tween: Tween<double>(begin: 0, end: metric.value),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: MyApp.clinicalNavy.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color.lerp(
                    AppColors.softTerracotta,
                    AppColors.mutedSage,
                    value,
                  )!,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Data models ────────────────────────────────────────────────────────────────

class _MilestoneData {
  const _MilestoneData({
    required this.headline,
    required this.description,
    required this.metrics,
  });
  final String headline;
  final String description;
  final List<_MetricProjection> metrics;
}

class _MetricProjection {
  const _MetricProjection(this.label, this.value);
  final String label;
  final double value; // 0.0–1.0
}

