import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/procedure_log.dart';
import '../providers/procedure_logs_provider.dart';
import '../services/ai_llm_service.dart';
import '../widgets/local_image_preview.dart';
import 'at_home_procedure_log_screen.dart';

/// Premium procedure history timeline screen.
///
/// Displays all logged aesthetic procedures in a beautiful timeline format
/// with category badges, photos, reminders, and AI insights.
class ProcedureHistoryScreen extends ConsumerStatefulWidget {
  const ProcedureHistoryScreen({super.key});

  @override
  ConsumerState<ProcedureHistoryScreen> createState() =>
      _ProcedureHistoryScreenState();
}

class _ProcedureHistoryScreenState
    extends ConsumerState<ProcedureHistoryScreen> {
  String? _aiInsights;
  bool _loadingInsights = false;
  DateTime? _insightsCachedAt;

  // Filter & sort state
  String _filterCategory = 'All';
  String _sortOrder = 'Newest';

  static const _categories = ['All', 'At-Home', 'Cosmetic', 'Medical'];
  static const _sortOptions = ['Newest', 'Oldest', 'By Procedure'];

  // Cache insights for 5 minutes to avoid excessive API calls
  static const _cacheValidDuration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    // Ensure the freshest logs (incl. photos just saved in Track Procedure)
    // are loaded whenever this screen opens. The microtask forces a second
    // invalidation after the first build so late Hive writes are picked up.
    ref.invalidate(procedureLogsProvider);
    Future.microtask(() {
      if (mounted) ref.invalidate(procedureLogsProvider);
    });
    // Generate insights after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateAiInsights();
    });
  }

  Future<void> _generateAiInsights() async {
    // Check if cache is still valid
    if (_insightsCachedAt != null &&
        DateTime.now().difference(_insightsCachedAt!) < _cacheValidDuration) {
      return;
    }

    final logs = ref.read(procedureLogsProvider).valueOrNull;
    if (logs == null || logs.isEmpty || logs.length < 2) {
      return; // Need at least 2 procedures for meaningful trends
    }

    setState(() => _loadingInsights = true);

    try {
      final insights = await _generateTrendAnalysis(logs);
      if (mounted) {
        setState(() {
          _aiInsights = insights;
          _loadingInsights = false;
          _insightsCachedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingInsights = false;
          _aiInsights = null;
        });
      }
    }
  }

  Future<String> _generateTrendAnalysis(List<ProcedureLog> logs) async {
    const service = AiService();
    if (!service.isConfigured) {
      throw Exception('AI service not configured');
    }

    // Build summary statistics
    final totalProcedures = logs.length;
    final procedureTypes = <String, int>{};
    final reactionScores = <int>[];
    final categories = <String, int>{};

    for (final log in logs) {
      procedureTypes[log.procedureType] =
          (procedureTypes[log.procedureType] ?? 0) + 1;

      if (log.reactionScore != null) {
        reactionScores.add(log.reactionScore!);
      }

      if (log.category != null) {
        categories[log.category!] = (categories[log.category!] ?? 0) + 1;
      }
    }

    final mostCommon = procedureTypes.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    final avgReaction = reactionScores.isEmpty
        ? null
        : (reactionScores.reduce((a, b) => a + b) / reactionScores.length)
              .toStringAsFixed(1);

    // Chronological reaction sequence so the model can read the direction of
    // the trend (calmer skin over time vs. more reactive).
    final chronological = [...logs]
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final reactionTrend = chronological
        .where((l) => l.reactionScore != null)
        .map((l) => l.reactionScore)
        .join(' → ');
    const systemPrompt = '''
You are an elite aesthetic procedure trend analyst and personal progress coach. Analyze the user's procedure history and write a warm, specific, encouraging reflection that makes them feel genuinely seen and proud of their consistency.

CRITICAL RULES:
- Keep response under 100 words (2-3 flowing sentences)
- Warm, refined, luxurious, and personal — like a private aesthetician celebrating their journey
- Name the user's actual procedures and cadence specifically (e.g. "your consistency with SkinPen sessions") rather than generic praise
- Recognize a concrete pattern or milestone: frequency, variety, a steady/improving reaction trend, or a well-paced routine
- If reaction scores are trending calmer/lower over time, affirm that their skin is tolerating treatments beautifully; if higher, gently encourage recovery-first spacing without alarming them
- For injectables (Botox, Dysport, fillers), reference typical maintenance windows so they can plan their next visit
- Close with one forward-looking, motivating line
- DO NOT diagnose medical conditions or recommend specific new treatments

OUTPUT FORMAT:
A single polished paragraph of 2-3 sentences that is specific to this exact history and ends on an inspiring note.
''';

    final userPrompt =
        '''
Procedure History Summary:
- Total procedures logged: $totalProcedures
- Most common procedure: $mostCommon (${procedureTypes[mostCommon]} times)
${avgReaction != null ? '- Average reaction score: $avgReaction/10' : ''}
${reactionTrend.isNotEmpty ? '- Reaction scores over time (oldest → newest): $reactionTrend' : ''}
- Categories: ${categories.entries.map((e) => '${e.key} (${e.value})').join(', ')}
- Recent procedures: ${logs.take(3).map((l) => '${l.procedureType} on ${DateFormat('MMM dd').format(l.dateTime)}').join(', ')}

Provide a brief, encouraging, specific trend analysis.
''';

    return await service.completeCoachResponse(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
    );
  }

  /// Returns a filtered + sorted copy of [logs] based on current state.
  List<ProcedureLog> _applyFilterSort(List<ProcedureLog> logs) {
    var result = logs.where((l) {
      if (_filterCategory == 'All') return true;
      return (l.category ?? 'At-Home') == _filterCategory;
    }).toList();

    switch (_sortOrder) {
      case 'Newest':
        result.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      case 'Oldest':
        result.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      case 'By Procedure':
        result.sort((a, b) => a.procedureType.compareTo(b.procedureType));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(procedureLogsProvider);

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: MyApp.surface,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timeline_rounded,
              color: AppColors.champagneGold,
              size: 26,
            ),
            const SizedBox(width: 10),
            Text(
              'Procedure History',
              style: MyApp.pageTitleStyle(color: MyApp.textBrown),
            ),
          ],
        ),
        centerTitle: true,
        shape: Border(
          bottom: BorderSide(
            color: AppColors.borders.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) return _buildEmptyState(context);
          final displayed = _applyFilterSort(logs);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(procedureLogsProvider);
              await _generateAiInsights();
            },
            child: CustomScrollView(
              slivers: [
                // ── Filter & Sort bar ──────────────────────────────────
                SliverToBoxAdapter(child: _buildFilterSortBar()),
                // ── AI Insights card ───────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: _buildAiInsightsCard(logs),
                  ),
                ),
                // ── Procedure cards ────────────────────────────────────
                if (displayed.isEmpty)
                  SliverToBoxAdapter(child: _buildNoResultsState())
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _ProcedureCard(log: displayed[i]),
                        ),
                        childCount: displayed.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppColors.champagneGold),
          ),
        ),
        error: (error, stack) => _buildErrorState(context, error),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AtHomeProcedureLogScreen()),
          );
          if (!mounted) return;
          // Refresh so a newly saved procedure (and its photos) appears
          // immediately after returning from Track Procedure.
          ref.invalidate(procedureLogsProvider);
          Future.microtask(() {
            if (mounted) ref.invalidate(procedureLogsProvider);
          });
        },
        backgroundColor: AppColors.champagneGold,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'New Procedure',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        elevation: 8,
      ),
    );
  }

  // ─── Filter & Sort bar ────────────────────────────────────────────────────
  Widget _buildFilterSortBar() {
    return Container(
      color: MyApp.surface,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final selected = _filterCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() => _filterCategory = cat),
                    selectedColor: AppColors.champagneGold.withValues(
                      alpha: 0.25,
                    ),
                    backgroundColor: Colors.transparent,
                    side: BorderSide(
                      color: selected
                          ? AppColors.champagneGold
                          : AppColors.borders.withValues(alpha: 0.5),
                      width: selected ? 1.5 : 0.8,
                    ),
                    checkmarkColor: AppColors.goldHover,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AppColors.goldHover
                          : MyApp.clinicalSlate,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          // Sort options
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Sort: ',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.clinicalMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ..._sortOptions.map((opt) {
                  final selected = _sortOrder == opt;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(opt),
                      selected: selected,
                      onSelected: (_) => setState(() => _sortOrder = opt),
                      selectedColor: AppColors.champagneGold.withValues(
                        alpha: 0.2,
                      ),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(
                        color: selected
                            ? AppColors.champagneGold
                            : AppColors.borders.withValues(alpha: 0.4),
                        width: selected ? 1.4 : 0.7,
                      ),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? AppColors.goldHover
                            : MyApp.clinicalMuted,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(
            Icons.filter_list_off_rounded,
            size: 48,
            color: MyApp.clinicalMuted,
          ),
          const SizedBox(height: 14),
          Text(
            'No $_filterCategory procedures yet.',
            style: TextStyle(color: MyApp.clinicalMuted, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different category or log a new one.',
            style: TextStyle(color: MyApp.clinicalMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: () => setState(() => _filterCategory = 'All'),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Show all procedures'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.goldHover,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.champagneGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.spa_outlined,
                size: 60,
                color: AppColors.champagneGold,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Your Journey Begins Here',
              style: MyApp.sectionTitleStyle(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Start tracking your aesthetic procedures and watch your transformation unfold.',
              style: TextStyle(
                color: MyApp.clinicalSlate,
                fontSize: 15,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AtHomeProcedureLogScreen(),
                  ),
                );
                if (!mounted) return;
                ref.invalidate(procedureLogsProvider);
                Future.microtask(() {
                  if (mounted) ref.invalidate(procedureLogsProvider);
                });
              },
              style: MyApp.primaryGoldButton,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text(
                  'Log First Procedure',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: MyApp.clinicalMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load procedures',
              style: MyApp.cardTitleStyle(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: TextStyle(color: MyApp.clinicalMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiInsightsCard(List<ProcedureLog> logs) {
    // Don't show insights card if less than 2 procedures
    if (logs.length < 2) {
      return const SizedBox.shrink();
    }

    // Calculate quick metrics
    final totalProcedures = logs.length;
    final procedureTypes = <String, int>{};
    final reactionScores = <int>[];

    for (final log in logs) {
      procedureTypes[log.procedureType] =
          (procedureTypes[log.procedureType] ?? 0) + 1;
      if (log.reactionScore != null) {
        reactionScores.add(log.reactionScore!);
      }
    }

    final mostCommon = procedureTypes.entries.isNotEmpty
        ? procedureTypes.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : 'N/A';

    final avgReaction = reactionScores.isEmpty
        ? null
        : (reactionScores.reduce((a, b) => a + b) / reactionScores.length)
              .toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.08),
            AppColors.mutedSage.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.champagneGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.psychology_outlined,
                    color: AppColors.champagneGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI Trend Analysis',
                    style: MyApp.cardTitleStyle(color: AppColors.champagneGold),
                  ),
                ),
                if (_loadingInsights)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        AppColors.champagneGold,
                      ),
                    ),
                  ),
              ],
            ),

            // AI Insights or Metrics
            const SizedBox(height: 14),
            if (_aiInsights != null && _aiInsights!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: AppColors.champagneGold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _aiInsights!,
                            style: TextStyle(
                              color: MyApp.textBrown,
                              fontSize: 13.5,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '⚠️ AI-generated insights are for personal tracking only — not medical advice. Consult a licensed provider for treatment decisions.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: MyApp.clinicalMuted,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else if (!_loadingInsights && logs.length >= 2) ...[
              TextButton.icon(
                onPressed: _generateAiInsights,
                icon: const Icon(Icons.psychology_outlined, size: 16),
                label: const Text('Generate AI Trend Analysis'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldHover,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Quick Metrics Row
            Row(
              children: [
                Expanded(
                  child: _MetricPill(
                    icon: Icons.format_list_numbered_rounded,
                    label: 'Total',
                    value: totalProcedures.toString(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _MetricPill(
                    icon: Icons.trending_up_rounded,
                    label: 'Most Common',
                    value: mostCommon,
                  ),
                ),
                if (avgReaction != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricPill(
                      icon: Icons.favorite_border_rounded,
                      label: 'Avg Score',
                      value: avgReaction,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borders.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: MyApp.clinicalMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: MyApp.clinicalMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: MyApp.textBrown,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ProcedureCard extends StatelessWidget {
  final ProcedureLog log;

  const _ProcedureCard({required this.log});

  /// This log's labeled photos with duplicate paths removed, so a single
  /// uploaded photo never renders more than once.
  List<({String label, String path})> get _dedupedPhotos {
    final seen = <String>{};
    final result = <({String label, String path})>[];
    for (final photo in log.labeledPhotos) {
      final path = photo.path.trim();
      if (path.isEmpty) continue;
      if (!seen.add(path)) continue;
      result.add(photo);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final photos = _dedupedPhotos;
    return Container(
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Procedure Type + Category Badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    log.procedureType,
                    style: MyApp.cardTitleStyle(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (log.category != null) ...[
                  const SizedBox(width: 8),
                  _CategoryBadge(category: log.category!),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Date
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: MyApp.clinicalMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('MMMM dd, yyyy').format(log.dateTime),
                  style: TextStyle(
                    color: MyApp.clinicalSlate,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            // Photo thumbnails with Before/After/Progress labels
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: buildLocalImagePreview(
                            photo.path,
                            width: 72,
                            height: 72,
                            borderRadius: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          photo.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MyApp.clinicalSlate,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],

            // Expected duration & reminder
            if (log.expectedDuration != null ||
                log.nextReminderDate != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (log.expectedDuration != null) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: AppColors.champagneGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Duration: ${log.expectedDuration}',
                            style: TextStyle(
                              color: MyApp.textBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (log.nextReminderDate != null &&
                        log.reminderEnabled) ...[
                      if (log.expectedDuration != null)
                        const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: AppColors.champagneGold,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Next: ${DateFormat('MMM dd, yyyy').format(log.nextReminderDate!)}',
                            style: TextStyle(
                              color: MyApp.textBrown,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Reaction score
            if (log.reactionScore != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.favorite_border_rounded,
                    size: 16,
                    color: MyApp.clinicalMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Reaction: ',
                    style: TextStyle(color: MyApp.clinicalSlate, fontSize: 13),
                  ),
                  Text(
                    '${log.reactionScore}/10',
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],

            // AI Feedback summary
            if (log.aiFeedback != null && log.aiFeedback!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.mutedSage.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: AppColors.mutedSage,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        log.aiFeedback!,
                        style: TextStyle(
                          color: MyApp.clinicalSlate,
                          fontSize: 12,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Settings/Notes preview
            if (log.settings != null && log.settings!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.tune_outlined,
                    size: 14,
                    color: MyApp.clinicalMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      log.settings!,
                      style: TextStyle(
                        color: MyApp.clinicalMuted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData badgeIcon;

    switch (category) {
      case 'Medical':
        badgeColor = AppColors.softTerracotta;
        badgeIcon = Icons.medical_services_rounded;
        break;
      case 'Cosmetic':
        badgeColor = AppColors.champagneGold;
        badgeIcon = Icons.auto_awesome_rounded;
        break;
      case 'At-Home':
      default:
        badgeColor = AppColors.mutedSage;
        badgeIcon = Icons.home_repair_service_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 13, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            category,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
