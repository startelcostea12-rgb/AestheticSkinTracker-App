// lib/screens/peptide_tracker_screen.dart
// Clinical-grade Peptide Tracker — Premium Feature.
// Tabs: My Stack | Insights | Library

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/peptide_model.dart';
import '../models/procedure.dart';
import '../models/scan_history.dart';
import '../theme/app_colors.dart';
import '../utils/app_prefs.dart';
import '../utils/metric_trend.dart';
import '../utils/peptide_service.dart';
import '../utils/report_flow.dart';
import '../widgets/clinical_section_header.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Body-composition detection
// ─────────────────────────────────────────────────────────────────────────────
//
// Used throughout the tracker so Stack Detail metrics, Per-peptide Insights,
// and the Peptide Detail correlation card enforce strict body-only rendering
// for the known weight-loss/body-composition peptides listed below.
const List<String> _kBodyPeptideKeywords = <String>[
  // Direct category tags.
  'body-composition',
  'body composition',
  // Strict body-focused peptide roster.
  'retatrutide',
  'tirzepatide',
  'semaglutide',
  'liraglutide',
  'tesamorelin',
  'aod-9604',
  'aod 9604',
  'aod9604',
  'sermorelin',
  'cjc-1295',
  'cjc 1295',
  'cjc1295',
  'ipamorelin',
  'hexarelin',
  'mots-c',
  'mots c',
  'motsc',
  'igf-1 lr3',
  'igf 1 lr3',
  'igf1 lr3',
];

bool _peptideIsBodyFocused(PeptideEntry e) {
  final hay = '${e.category} ${e.name}'.toLowerCase();
  return _kBodyPeptideKeywords.any(hay.contains);
}

bool _stackIsBodyFocused(Iterable<PeptideEntry> peptides) =>
    peptides.any(_peptideIsBodyFocused);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class PeptideTrackerScreen extends StatefulWidget {
  const PeptideTrackerScreen({super.key, this.initialTab});

  final int? initialTab;

  @override
  State<PeptideTrackerScreen> createState() => _PeptideTrackerScreenState();
}

class _PeptideTrackerScreenState extends State<PeptideTrackerScreen> {
  int _tab = 0;
  bool _loading = true;
  bool _tabInitialized = false;
  static const String _defaultStackName = 'My Stack';

  List<PeptideEntry> _entries = [];
  List<PeptideStack> _stacks = [];
  List<ScanHistoryEntry> _scans = [];
  List<PeptideCorrelationResult> _correlations = [];
  Procedure? _procedure;
  String _stackName = _defaultStackName;
  // Tracks the stackId of the most recently added peptide so that when the
  // user immediately taps "Take New Scan" from a context that doesn't
  // explicitly know the stack (e.g. My Stack tab / Insights tab), the scan
  // still auto-links to the new stack. Cleared once consumed.
  String? _lastSavedStackId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // NOTE: Legacy migration removed — standalone peptides (stackId == null)
    // are intentional and must stay in "My Peptides" tab. The old migration
    // was incorrectly converting standalone entries into stack entries.

    final entries = await PeptideService.loadAll();
    final stacks = await PeptideService.loadStacks();
    final scans = await AppPrefs.getScanEntries();
    final correlations = PeptideService.computeCorrelations(entries, scans);
    final savedStackName = await AppPrefs.getPeptideStackNameOrNull();
    // Resolve the procedure for camera navigation:
    // 1. Try the user's explicitly selected procedure.
    // 2. Fall back to the first active (non-completed) procedure.
    // 3. Fall back to any procedure.
    Procedure? proc;
    final rawProcs = await AppPrefs.getProcedureEntries();
    if (rawProcs.isNotEmpty) {
      final procId = await AppPrefs.getSelectedProcedureIdOrNull();
      if (procId != null) {
        final match = rawProcs.where((p) => p['id'] == procId).firstOrNull;
        if (match != null) {
          proc = Procedure.fromJson(Map<String, dynamic>.from(match));
        }
      }
      if (proc == null) {
        final active = rawProcs
            .where((p) => p['isCompleted'] != true)
            .firstOrNull;
        if (active != null) {
          proc = Procedure.fromJson(Map<String, dynamic>.from(active));
        }
      }
      proc ??= Procedure.fromJson(Map<String, dynamic>.from(rawProcs.first));
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _stacks = stacks;
      _scans = scans;
      _correlations = correlations;
      _procedure = proc;
      _stackName = savedStackName ?? _defaultStackName;
      _loading = false;
      // On first load pick the most relevant starting tab:
      //   → "My Stacks" (tab 1) when the user already has stacks
      //   → "My Peptides" (tab 0) otherwise (standalone peptides / fresh install)
      if (!_tabInitialized) {
        _tab = widget.initialTab?.clamp(0, 3) ?? (stacks.isNotEmpty ? 1 : 0);
        _tabInitialized = true;
      }
    });
  }

  Future<void> _takeScan({String? stackId, String? peptideId}) async {
    // Fallback: if the caller didn't pass a stackId but the user just
    // added a peptide tied to a stack, auto-link the scan to that stack.
    stackId ??= _lastSavedStackId;
    _lastSavedStackId = null; // one-shot

    // Always read the freshest peptide list from disk so a peptide that was
    // saved moments ago (and may not have round-tripped into _entries yet)
    // is still considered when deciding body-vs-skin routing.
    final List<PeptideEntry> freshEntries = await PeptideService.loadAll();

    Procedure? procedureToUse = _procedure;

    // Detect whether this scan is being taken in the context of a
    // body-composition peptide stack (Tirzepatide, Semaglutide, Retatrutide,
    // Tesamorelin, AOD-9604, etc.) so the downstream analysis flow can route
    // to body-focused metrics + recommendations instead of facial skin model.
    // Uses the same keyword list as _peptideIsBodyFocused so all GLP-1 /
    // GHRH / lipolytic peptides are correctly detected, not just those whose
    // category string contains 'body-composition'.
    final bool isBodyFocusedStack =
        (stackId != null &&
            freshEntries.any(
              (e) => e.stackId == stackId && _peptideIsBodyFocused(e),
            )) ||
        (peptideId != null &&
            freshEntries.any(
              (e) => e.id == peptideId && _peptideIsBodyFocused(e),
            ));
    final String defaultPeptideType = isBodyFocusedStack
        ? 'Body Composition Peptides'
        : 'Peptide Tracking';
    final String defaultPeptideCategory = isBodyFocusedStack
        ? 'Body Composition'
        : 'Peptide';

    // If launched from a stack, prefer the procedure already associated with
    // that stack so scans stay consistently tagged across visits.
    if (stackId != null) {
      final stacks = await PeptideService.loadStacks();
      final stack = stacks.where((s) => s.id == stackId).firstOrNull;
      final pinned = stack?.procedureId;
      if (pinned != null) {
        final rawProcs = await AppPrefs.getProcedureEntries();
        final match = rawProcs.where((p) => p['id'] == pinned).firstOrNull;
        if (match != null) {
          procedureToUse = Procedure.fromJson(Map<String, dynamic>.from(match));
        }
      }
    }

    // Resolve again at action time so we never fall back into generic
    // skincare scan mode from the peptide tracker flow.
    if (procedureToUse == null) {
      final rawProcs = await AppPrefs.getProcedureEntries();
      if (rawProcs.isNotEmpty) {
        final selectedId = await AppPrefs.getSelectedProcedureIdOrNull();
        Map<String, dynamic>? procJson;
        if (selectedId != null) {
          final selected = rawProcs
              .where((p) => p['id'] == selectedId)
              .firstOrNull;
          if (selected != null) {
            procJson = Map<String, dynamic>.from(selected);
          }
        }
        procJson ??= rawProcs
            .where((p) => p['isCompleted'] != true)
            .map((p) => Map<String, dynamic>.from(p))
            .firstOrNull;
        procJson ??= Map<String, dynamic>.from(rawProcs.first);
        procedureToUse = Procedure.fromJson(procJson);
      }
    }

    if (procedureToUse == null) {
      // No procedure exists anywhere. Auto-create a lightweight default so the
      // scan flow stays fully automatic and the user is never blocked by the
      // "Please select a procedure" guard inside CameraScreen.
      final newProc = Procedure(
        id: 'pep_${DateTime.now().millisecondsSinceEpoch}',
        type: defaultPeptideType,
        category: defaultPeptideCategory,
        provider: 'Self',
        startDate: DateTime.now(),
        numSessions: 1,
      );
      await AppPrefs.addProcedureToHistory(newProc.toJson());
      procedureToUse = newProc;
    } else if (isBodyFocusedStack &&
        procedureToUse.type.toLowerCase() == 'peptide tracking') {
      // Upgrade a prior generic "Peptide Tracking" procedure to the body-focused
      // type when the originating stack now contains body-composition peptides.
      // This keeps the procedure id stable (no scan history loss) while
      // re-routing analysis to body metrics.
      final upgraded = procedureToUse.copyWith(
        type: 'Body Composition Peptides',
        category: 'Body Composition',
      );
      await AppPrefs.updateProcedureInHistory(upgraded.id, upgraded.toJson());
      procedureToUse = upgraded;
    }

    await AppPrefs.setSelectedProcedureId(procedureToUse.id);
    if (mounted) {
      setState(() => _procedure = procedureToUse);
    }

    // Tag this stack with the procedure (idempotent) so future scans from
    // the stack stay linked even if the user changes the global selection.
    if (stackId != null) {
      await PeptideService.setStackProcedure(stackId, procedureToUse.id);
    }

    // Snapshot scan count for this procedure BEFORE launching the camera so
    // we can detect whether a new scan was actually saved (user may have
    // backed out of the camera without taking a photo).
    final int scansBefore = (await AppPrefs.getScanEntries())
        .where((s) => s.procedureId == procedureToUse!.id)
        .length;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          procedure: procedureToUse,
          capturePurpose: CameraCapturePurpose.trackProcedure,
        ),
      ),
    );

    // Unified post-camera flow — identical for ALL peptide categories.
    // Step 1: detect whether a new scan was saved (single source of truth).
    // Step 2: tag the new scan with peptideId so it shows up in this
    //         peptide's Before/After section immediately.
    // Step 3: ONLY for body-focused peptides, additionally prompt for body
    //         measurements as a follow-up. This prompt is purely additive
    //         and never blocks photo display.
    if (mounted) {
      final allAfter = await AppPrefs.getScanEntries();
      final procedureScans =
          allAfter.where((s) => s.procedureId == procedureToUse!.id).toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final bool scanWasSaved = procedureScans.length > scansBefore;

      if (scanWasSaved) {
        // Always stamp the new scan with the peptide id so the Before/After
        // section can render it instantly (same code path for skin and body).
        if (peptideId != null) {
          await AppPrefs.patchScanPeptideId(procedureScans.last.id, peptideId);
        }

        // Body-focused add-on: prompt for measurements. Skin peptides skip
        // this; the photo is already visible regardless.
        if (isBodyFocusedStack && mounted) {
          final bodyMetrics = await showBodyMetricsEntrySheet(
            context,
            procedureId: procedureToUse.id,
            justAfterScan: true,
          );
          if (bodyMetrics != null && bodyMetrics.isNotEmpty) {
            await AppPrefs.patchScanMetrics(
              procedureScans.last.id,
              bodyMetrics,
            );
          }
        }
      }
    }

    if (mounted) await _load();
  }

  Future<void> _openAddSheet({
    PeptideEntry? editing,
    bool openDetailAfterSave = false,
    String? stackId,
  }) async {
    // When adding into a stack, surface interaction advisories by passing
    // the names of peptides already in the stack down to the form.
    final existingNames = stackId == null
        ? const <String>[]
        : _entries
              .where(
                (e) =>
                    e.stackId == stackId && e.isActive && e.id != editing?.id,
              )
              .map((e) => e.name)
              .toList();
    final existingLower = existingNames.map((n) => n.toLowerCase()).toSet();
    final isAddingNew = editing == null || (editing.id.isEmpty);
    final result = await Navigator.of(context).push<_AddPeptideResult>(
      MaterialPageRoute(
        builder: (_) => _AddEditPeptidePage(
          editing: editing,
          defaultStackId: stackId,
          existingStackPeptideNames: existingNames,
          // Only show Popular Blends when adding a brand-new peptide.
          onAddBlend: !isAddingNew
              ? null
              : (blend) async {
                  int added = 0;
                  final now = DateTime.now();
                  for (final libName in blend.peptideNames) {
                    if (existingLower.contains(libName.toLowerCase())) continue;
                    final lib = kPeptideLibrary
                        .where((e) => e.name == libName)
                        .firstOrNull;
                    if (lib == null) continue;
                    final conc = _kTypicalConcentrations[libName];
                    final benefits = lib.primaryMetrics.isNotEmpty
                        ? 'Benefits: ${lib.primaryMetrics.join(', ')}'
                        : '';
                    final mech = lib.mechanism.isNotEmpty
                        ? 'Mechanism: ${lib.mechanism}'
                        : '';
                    final notes = [
                      benefits,
                      mech,
                    ].where((s) => s.isNotEmpty).join('\n');
                    final entry = PeptideEntry(
                      id: 'pep_${now.millisecondsSinceEpoch}_${added}_${libName.hashCode.toUnsigned(16)}',
                      name: lib.name,
                      concentration: conc,
                      frequency: 'Once daily',
                      startDate: now,
                      notes: notes,
                      category: lib.category.isNotEmpty
                          ? lib.category
                          : blend.defaultCategory,
                      stackId: stackId,
                    );
                    await PeptideService.upsert(entry);
                    added++;
                  }
                  await _load();
                  if (mounted && added > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Added ${blend.name} — $added peptide${added == 1 ? '' : 's'} to your stack.',
                        ),
                        backgroundColor: const Color(0xFFD4AF37),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                  return added;
                },
        ),
        fullscreenDialog: false,
      ),
    );
    if (result != null) {
      // Force-assign stackId from the caller if the form didn't set one.
      final entry = result.entry;
      final toSave = (stackId != null && entry.stackId == null)
          ? entry.copyWith(stackId: stackId)
          : entry;
      await PeptideService.upsert(toSave);
      // Remember the saved stack so a subsequent generic "Take New Scan"
      // tap from My Stack / Insights still routes to this stack.
      _lastSavedStackId = toSave.stackId ?? stackId;
      await _load();
      if (!mounted) return;
      // Auto-switch to the correct tab: individual peptides → My Peptides (0),
      // stack peptides → My Stacks (1).
      setState(() {
        _tab = (toSave.stackId != null) ? 1 : 0;
      });
      // "Save & Take Scan" — go straight into the camera tied to this stack.
      if (result.takeScan) {
        await _takeScan(stackId: toSave.stackId ?? stackId);
        return;
      }
      if (!openDetailAfterSave) return;
      final savedEntry =
          _entries.where((e) => e.id == toSave.id).firstOrNull ?? toSave;
      _openDetailPage(savedEntry);
    }
  }

  /// Prompt the user for a stack name, create the stack, then open its
  /// detail page so they can start adding peptides.
  Future<void> _createStack({
    String? suggestedName,
    String? seedCategory,
  }) async {
    final name = await _promptStackName(
      title: 'Create New Stack',
      initial: suggestedName ?? '',
      hint: 'e.g. Healing Stack, Anti-Aging, Weight Loss Support',
      confirmLabel: 'Create',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final stack = await PeptideService.createStack(name);
    await _load();
    if (!mounted) return;
    _openStackDetail(stack, seedCategory: seedCategory, addImmediately: true);
  }

  Future<String?> _promptStackName({
    required String title,
    required String hint,
    required String confirmLabel,
    String initial = '',
  }) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          title,
          style: const TextStyle(
            color: _textBrown,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(
              confirmLabel,
              style: const TextStyle(color: _rose, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameStackById(PeptideStack stack) async {
    final newName = await _promptStackName(
      title: 'Rename Stack',
      hint: 'e.g. Night Repair Stack',
      confirmLabel: 'Save',
      initial: stack.name,
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    await PeptideService.renameStack(stack.id, newName);
    await _load();
  }

  Future<void> _deleteStack(PeptideStack stack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete Stack?', style: TextStyle(color: _textBrown)),
        content: Text(
          'Delete "${stack.name}"? Peptides in this stack will be kept as individual peptides.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.kMetricWorsenedColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await PeptideService.deleteStack(stack.id);
    await _load();
  }

  Future<void> _openStackDetail(
    PeptideStack stack, {
    String? seedCategory,
    bool addImmediately = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StackDetailPage(
          stackId: stack.id,
          openPeptideDetail: (e) async => _openDetailPage(e),
          openAddPeptide: ({String? seedCategoryArg}) async {
            await _openAddSheet(
              openDetailAfterSave: false,
              stackId: stack.id,
              editing: seedCategoryArg != null
                  ? PeptideEntry(
                      id: _newId(),
                      name: '',
                      frequency: 'Once daily',
                      startDate: DateTime.now(),
                      category: seedCategoryArg,
                    )
                  : null,
            );
          },
          renameStack: (s) => _renameStackById(s),
          deleteStack: (s) async {
            await _deleteStack(s);
            if (mounted) Navigator.of(context).maybePop();
          },
          deletePeptide: _delete,
          editPeptide: (e) => _openAddSheet(editing: e),
          takeScan: () => _takeScan(stackId: stack.id),
          reopenSelf: () async {
            // Close the current (now stale) stack detail page, then push a
            // fresh instance bound to the same stack so Before & After +
            // Stack Metrics rebuild with the latest scans immediately after
            // a scan completes. The stack is re-fetched in case its
            // procedureId was assigned during the scan flow.
            if (!mounted) return;
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            await _load();
            if (!mounted) return;
            final stacks = await PeptideService.loadStacks();
            final fresh = stacks.where((s) => s.id == stack.id).firstOrNull;
            if (fresh == null || !mounted) return;
            _openStackDetail(fresh);
          },
          seedCategoryOnOpen: addImmediately ? seedCategory : null,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _renameStack() async {
    final ctrl = TextEditingController(
      text: _stackName == _defaultStackName ? '' : _stackName,
    );
    final renamed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text(
          'Rename Stack',
          style: TextStyle(
            color: _textBrown,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Night Repair Stack',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(color: _rose, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (renamed == null || !mounted) return;
    final nextName = renamed.isEmpty ? _defaultStackName : renamed;
    await AppPrefs.setPeptideStackName(
      nextName == _defaultStackName ? null : nextName,
    );
    if (!mounted) return;
    setState(() => _stackName = nextName);
  }

  Future<void> _delete(PeptideEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text(
          'Remove Peptide?',
          style: TextStyle(color: Color(0xFF2C3539)),
        ),
        content: Text(
          'Remove "${entry.name}" from your stack?',
          style: const TextStyle(color: Color(0xFF5B6469)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.kMetricWorsenedColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await PeptideService.delete(entry.id);
      await _load();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  void _openDetailPage(PeptideEntry entry) {
    // STRICT per-peptide scan isolation.
    // Only scans explicitly tagged with this peptide's id are shown.
    // No legacy/procedure/null-peptideId fallback — that previously
    // allowed scans from a different procedure (e.g. Halo Laser) to
    // bleed into the Before & After view of an untouched peptide.
    final scopedScans = _scans.where((s) => s.peptideId == entry.id).toList();

    final scopedCorr = scopedScans.isEmpty
        ? null
        : PeptideService.computeCorrelations([
            entry,
          ], scopedScans).where((c) => c.peptide.id == entry.id).firstOrNull;

    // Do NOT fall back to the unscoped _correlations list — that list is
    // computed against every scan in the procedure and would re-introduce
    // the cross-contamination bug. If this peptide has no scans of its
    // own, the detail page must render its empty state.
    final corr = scopedCorr;

    // A peptide is "standalone" when it does not belong to any stack —
    // i.e. its stackId is null/empty. This holds whether it was created as
    // standalone or was removed from a stack. The detail page swaps
    // "My Stack" → "My Peptide" and "View Full Stack" → "View Full Peptide"
    // in this case.
    final bool isStandalone = entry.stackId == null || entry.stackId!.isEmpty;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PeptideDetailSheet(
          entry: entry,
          stackName: _stackName,
          correlation: corr,
          allScans: scopedScans,
          isPage: true,
          isStandalone: isStandalone,
          onEdit: () {
            Navigator.of(context).pop();
            _openAddSheet(editing: entry);
          },
          onDelete: () {
            Navigator.of(context).pop();
            _delete(entry);
          },
          onTakeScan: () async {
            // Take the scan (camera + persistence + body-metrics sheet for
            // body-focused stacks). _takeScan already calls _load() so the
            // outer screen's _scans/_correlations are fresh on return. The
            // detail page then refreshes its own state via [onRefresh] —
            // no pop + repush, the user stays put.
            await _takeScan(stackId: entry.stackId, peptideId: entry.id);
          },
          onRefresh: () async {
            // Strict per-peptide isolation (matches _openDetailPage rule):
            // only scans whose peptideId matches this entry. No fallback
            // to legacy/null-peptideId scans — those belong to a
            // procedure, not this peptide.
            final fresh = _scans.where((s) => s.peptideId == entry.id).toList();
            final refreshedCorr = fresh.isEmpty
                ? null
                : PeptideService.computeCorrelations([
                    entry,
                  ], fresh).where((c) => c.peptide.id == entry.id).firstOrNull;
            return (scans: fresh, correlation: refreshedCorr);
          },
          onAddAnother: () {
            // Pop the current detail page first so the nav stack stays clean,
            // then push the add form. After the user saves a new peptide,
            // _openAddSheet pushes a fresh detail page automatically.
            Navigator.of(context).pop();
            _openAddSheet(openDetailAfterSave: true, stackId: entry.stackId);
          },
          onRenameStack: _renameStack,
        ),
      ),
    );
  }

  static const Color _surface = Color(0xFFF8F6F0);
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _textBrown,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const ClinicalAppBarTitle(
          title: 'Peptide Tracker',
          eyebrow: 'Premium therapy log',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Open Library',
            onPressed: () {
              if (_tab != 3) {
                setState(() => _tab = 3);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Library opened: Reconstitution Cheat Sheet is featured first.',
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              Navigator.of(context).pushNamed('/peptide-reconstitution');
            },
            icon: const Icon(Icons.science_outlined),
            color: _rose,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Premium',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_rose),
              ),
            )
          : Column(
              children: [
                _buildTabRow(),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      // Tab 0 — My Peptides (individual / standalone)
                      _StacksTab(
                        entries: _entries
                            .where((e) => e.stackId == null)
                            .toList(),
                        stacks: const [],
                        onAddIndividual: () =>
                            _openAddSheet(openDetailAfterSave: true),
                        onCreateStack: () => _createStack(),
                        onOpenStack: _openStackDetail,
                        onTapPeptide: _openDetailPage,
                        onEditPeptide: (e) => _openAddSheet(editing: e),
                        onDeletePeptide: _delete,
                      ),
                      // Tab 1 — My Stacks
                      _StacksTab(
                        isStacksTab: true,
                        entries: _entries
                            .where((e) => e.stackId != null)
                            .toList(),
                        stacks: _stacks,
                        onAddIndividual: () =>
                            _openAddSheet(openDetailAfterSave: true),
                        onCreateStack: () => _createStack(),
                        onOpenStack: _openStackDetail,
                        onTapPeptide: _openDetailPage,
                        onEditPeptide: (e) => _openAddSheet(editing: e),
                        onDeletePeptide: _delete,
                      ),
                      // Tab 2 — Insights
                      _InsightsTab(
                        correlations: _correlations,
                        scanCount: _scans.length,
                        entryCount: _entries.length,
                        onTakeScan: _takeScan,
                      ),
                      // Tab 3 — Library
                      _LibraryTab(
                        onOpenReconstitutionSheet: () => Navigator.of(
                          context,
                        ).pushNamed('/peptide-reconstitution'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      // Contextual FAB: one button per tab, matching the primary action.
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              heroTag: 'add_peptide_fab',
              onPressed: () => _openAddSheet(openDetailAfterSave: true),
              backgroundColor: _rose,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Peptide',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : _tab == 1
          ? FloatingActionButton.extended(
              heroTag: 'new_stack_fab',
              onPressed: () => _createStack(),
              backgroundColor: Colors.white,
              foregroundColor: _rose,
              elevation: 2,
              icon: const Icon(Icons.layers_outlined),
              label: const Text(
                'New Stack',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
    );
  }

  Widget _buildTabRow() {
    const tabs = ['My Peptides', 'My Stacks', 'Insights', 'Library'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE8),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? _rose : _muted,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static String _newId() =>
      'peptide_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Stacks list (Stacks + Individual Peptides)
// ─────────────────────────────────────────────────────────────────────────────

class _StacksTab extends StatelessWidget {
  final List<PeptideEntry> entries;
  final List<PeptideStack> stacks;
  final VoidCallback onAddIndividual;
  final VoidCallback onCreateStack;
  final ValueChanged<PeptideStack> onOpenStack;
  final ValueChanged<PeptideEntry> onTapPeptide;
  final ValueChanged<PeptideEntry> onEditPeptide;
  final ValueChanged<PeptideEntry> onDeletePeptide;

  /// True when this widget is rendering the "My Stacks" tab. Used to
  /// customise the empty-state copy. False = "My Peptides" tab.
  final bool isStacksTab;

  const _StacksTab({
    required this.entries,
    required this.stacks,
    required this.onAddIndividual,
    required this.onCreateStack,
    required this.onOpenStack,
    required this.onTapPeptide,
    required this.onEditPeptide,
    required this.onDeletePeptide,
    this.isStacksTab = false,
  });

  static const Color _rose = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final individual = entries
        .where((e) => e.stackId == null)
        .toList(growable: false);
    final activeIndividual = individual
        .where((e) => e.isActive)
        .toList(growable: false);
    final inactiveIndividual = individual
        .where((e) => !e.isActive)
        .toList(growable: false);
    // My Stacks tab is empty only when there are no stack objects.
    // My Peptides tab is empty only when there are no standalone (stackId == null) entries.
    final isEmpty = isStacksTab ? stacks.isEmpty : individual.isEmpty;

    if (isEmpty) {
      return _EmptyState(
        icon: isStacksTab ? Icons.layers_outlined : Icons.science_outlined,
        title: isStacksTab ? 'No Stacks Yet' : 'No Individual Peptides',
        subtitle: isStacksTab
            ? 'Group your peptides into a named stack — e.g. Healing, Anti-Aging, Body Composition — to unlock correlation insights. Tap + New Stack to get started.'
            : 'Your individual peptides appear here. Tap + Add Peptide to log a standalone peptide, or use + New Stack on the Stacks tab to add a peptide to a group.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
      children: [
        // Quick-action row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onAddIndividual,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text('Add Peptide'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCreateStack,
                icon: const Icon(Icons.layers_outlined, size: 16),
                label: const Text('New Stack'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _rose,
                  side: const BorderSide(color: _rose),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (stacks.isNotEmpty) ...[
          _SectionHeader(
            label: 'Stacks (${stacks.length})',
            icon: Icons.layers_outlined,
            eyebrow: 'Combined protocols',
          ),
          ...stacks.map((s) {
            final stackEntries = entries
                .where((e) => e.stackId == s.id)
                .toList(growable: false);
            return _StackCard(
              stack: s,
              entries: stackEntries,
              onTap: () => onOpenStack(s),
            );
          }),
        ],

        if (!isStacksTab && activeIndividual.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionHeader(
            label: 'Individual Peptides (${activeIndividual.length})',
            icon: Icons.science_outlined,
            eyebrow: 'Active regimen',
          ),
          ...activeIndividual.map(
            (e) => _PeptideCard(
              entry: e,
              onEdit: onEditPeptide,
              onDelete: onDeletePeptide,
              onTap: onTapPeptide,
            ),
          ),
        ],
        if (!isStacksTab && inactiveIndividual.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionHeader(
            label: 'Discontinued (${inactiveIndividual.length})',
            icon: Icons.history,
            eyebrow: 'Past protocols',
          ),
          ...inactiveIndividual.map(
            (e) => _PeptideCard(
              entry: e,
              onEdit: onEditPeptide,
              onDelete: onDeletePeptide,
              onTap: onTapPeptide,
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stack card — preview row in the Stacks list
// ─────────────────────────────────────────────────────────────────────────────

class _StackCard extends StatelessWidget {
  final PeptideStack stack;
  final List<PeptideEntry> entries;
  final VoidCallback onTap;

  const _StackCard({
    required this.stack,
    required this.entries,
    required this.onTap,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    final active = entries.where((e) => e.isActive).length;
    final maxDays = entries.isEmpty
        ? 0
        : entries.map((e) => e.daysTracked).fold<int>(0, math.max);
    final tierCounts = <String, int>{};
    for (final e in entries) {
      final lib = kPeptideLibrary
          .where((l) => l.name.toLowerCase() == e.name.toLowerCase())
          .firstOrNull;
      if (lib != null) {
        tierCounts[lib.evidenceLevel] =
            (tierCounts[lib.evidenceLevel] ?? 0) + 1;
      }
    }
    final preview = entries.take(3).map((e) => e.name).join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.layers_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stack.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _textBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entries.isEmpty
                                ? 'No peptides yet — tap to add one'
                                : '${entries.length} peptide${entries.length == 1 ? '' : 's'} · $active active',
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _rose,
                      size: 20,
                    ),
                  ],
                ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (maxDays > 0)
                        _Chip(
                          label: '${maxDays}d tracked',
                          icon: Icons.calendar_today_outlined,
                        ),
                      for (final entry in tierCounts.entries)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1EEE6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5E8E8)),
                          ),
                          child: Text(
                            '${entry.key} ×${entry.value}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _rose,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5B6469),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? eyebrow;

  const _SectionHeader({required this.label, required this.icon, this.eyebrow});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: ClinicalSectionHeader(icon: icon, title: label, eyebrow: eyebrow),
    );
  }
}

class _PeptideCard extends StatelessWidget {
  final PeptideEntry entry;
  final ValueChanged<PeptideEntry> onEdit;
  final ValueChanged<PeptideEntry> onDelete;
  final ValueChanged<PeptideEntry> onTap;

  const _PeptideCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _rose = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final libEntry = kPeptideLibrary
        .where((l) => l.name.toLowerCase() == entry.name.toLowerCase())
        .firstOrNull;
    final evidenceLevel = libEntry?.evidenceLevel;
    final claims = libEntry?.clinicalNote;
    final benefits = libEntry?.primaryMetrics ?? const <String>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => onTap(entry),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _textBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _categoryLabel(entry.category),
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (evidenceLevel != null)
                          _EvidenceBadge(level: evidenceLevel),
                        const SizedBox(width: 6),
                        if (entry.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.kMetricImprovedColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.kMetricImprovedColor.withValues(alpha: 0.4),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.kMetricImprovedColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Chips row
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (entry.concentration != null)
                      _Chip(
                        label: '${entry.concentration!.toStringAsFixed(1)}%',
                        icon: Icons.science_outlined,
                      ),
                    _Chip(
                      label: entry.frequency,
                      icon: Icons.schedule_outlined,
                    ),
                    _Chip(
                      label: '${entry.daysTracked}d tracked',
                      icon: Icons.calendar_today_outlined,
                    ),
                  ],
                ),
                if (benefits.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: benefits
                        .take(3)
                        .map(
                          (b) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDFBF7),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE5E8E8),
                              ),
                            ),
                            child: Text(
                              b,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF5B6469),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (claims != null && claims.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Clinical claim: $claims',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.notes,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
                const Divider(height: 16, color: Color(0xFFEDEBE3)),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 11,
                        color: _rose,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 14, color: _rose),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String c) {
    const map = {
      'anti-aging': 'Anti-Aging',
      'brightening': 'Brightening',
      'healing': 'Healing & Repair',
      'firming': 'Firming',
      'body-composition': 'Body Composition',
      'other': 'Other',
    };
    return map[c] ?? c;
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEE6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xFF7E868B)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF5B6469),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Insights
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsTab extends StatelessWidget {
  final List<PeptideCorrelationResult> correlations;
  final int scanCount;
  final int entryCount;
  final VoidCallback onTakeScan;

  const _InsightsTab({
    required this.correlations,
    required this.scanCount,
    required this.entryCount,
    required this.onTakeScan,
  });

  @override
  Widget build(BuildContext context) {
    if (scanCount < 2) {
      return _EmptyState(
        icon: Icons.camera_alt_outlined,
        title: 'Scan to Unlock Insights',
        subtitle: scanCount == 0
            ? 'Take your first skin scan to start building\npeptide correlation insights.'
            : 'One more scan needed — take a scan now\nto unlock your peptide correlation data.',
        actionLabel: 'Take a Scan Now',
        onAction: onTakeScan,
      );
    }

    if (entryCount == 0) {
      return const _EmptyState(
        icon: Icons.science_outlined,
        title: 'No Peptides Logged',
        subtitle:
            'Add peptides to your stack to see\nhow they affect your skin metrics.',
      );
    }

    if (correlations.isEmpty) {
      return _EmptyState(
        icon: Icons.hourglass_top_rounded,
        title: 'Keep Tracking',
        subtitle:
            'Correlations unlock after 2+ scans.\nTake a second scan to see how your peptides are performing.',
        actionLabel: 'Take a Scan Now',
        onAction: onTakeScan,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _AiPeptideCoachCard(correlations: correlations),
        const SizedBox(height: 12),
        _InsightsBanner(count: correlations.length),
        const SizedBox(height: 12),
        ...correlations.map((r) => _CorrelationCard(result: r)),
        const SizedBox(height: 16),
        const _ShareWithProviderButton(),
      ],
    );
  }
}

class _AiPeptideCoachCard extends StatelessWidget {
  final List<PeptideCorrelationResult> correlations;
  const _AiPeptideCoachCard({required this.correlations});

  static const Color _aiColor = Color(0xFFD4AF37);

  String _generateInsight(List<PeptideCorrelationResult> corrs) {
    if (corrs.isEmpty) {
      return 'Keep tracking to unlock personalized AI insights.';
    }

    // Find highest positive delta
    PeptideCorrelationResult? topPos;
    String? topMetric;
    double topDelta = 0;

    for (final c in corrs) {
      for (final e in c.metricDeltas.entries) {
        if (e.value > topDelta) {
          topDelta = e.value;
          topPos = c;
          topMetric = e.key;
        }
      }
    }

    // Find any concerning regression
    PeptideCorrelationResult? topNeg;
    String? negMetric;
    double negDelta = 0;
    for (final c in corrs) {
      for (final e in c.metricDeltas.entries) {
        if (e.value < negDelta) {
          negDelta = e.value;
          topNeg = c;
          negMetric = e.key;
        }
      }
    }

    if (topPos != null && topDelta > 0.5) {
      final pct = ((topDelta / 10) * 100).round();
      return '${topPos.peptide.name} is showing a strong response — '
          '${topMetric ?? 'key metric'} improved ~$pct% since you started this peptide. '
          'Continue your current protocol for best results.';
    } else if (topNeg != null && negDelta < -0.5) {
      return '${topNeg.peptide.name} shows a slight ${negMetric?.toLowerCase() ?? 'metric'} regression. '
          'Consider reviewing dosage timing or consulting your provider.';
    } else if (corrs.isNotEmpty) {
      return '${corrs.first.peptide.name} is showing early signals. '
          'Continue tracking scans weekly for statistically meaningful correlations.';
    }
    return 'Your peptide protocol is being analyzed. Keep taking scans to unlock deeper AI insights.';
  }

  @override
  Widget build(BuildContext context) {
    final insight = _generateInsight(correlations);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _aiColor.withValues(alpha: 0.10),
            _aiColor.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.90),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _aiColor.withValues(alpha: 0.22), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _aiColor.withValues(alpha: 0.08),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _aiColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: _aiColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Peptide Coach',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _aiColor,
                      ),
                    ),
                    Text(
                      'Personalized insight from your data',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF7E868B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _aiColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _aiColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _aiColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              insight,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF2C3539),
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI insights are informational and do not constitute medical advice.',
            style: TextStyle(
              fontSize: 9.5,
              color: _aiColor.withValues(alpha: 0.45),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareWithProviderButton extends StatelessWidget {
  const _ShareWithProviderButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await runGatedReportFlow(context);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.26),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2C3539).withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(
              Icons.picture_as_pdf_rounded,
              color: Color(0xFFD4AF37),
              size: 22,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share Professional Report',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3539),
                    ),
                  ),
                  Text(
                    'Generate & send a progress PDF to your provider',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xA82C3539),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Color(0xFFD4AF37),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsBanner extends StatelessWidget {
  final int count;
  const _InsightsBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count Peptide Correlation${count > 1 ? 's' : ''} Found',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Based on your scan history before & after each peptide start date.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrelationCard extends StatelessWidget {
  final PeptideCorrelationResult result;
  const _CorrelationCard({required this.result});

  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Set<String> _bodyOnlyMetricLabels = {
    'Weight',
    'Body Fat %',
    'Waist Circumference',
    'Muscle Mass',
    'Appetite Control',
    'Body Composition Score',
  };

  @override
  Widget build(BuildContext context) {
    final allMetrics = result.metricDeltas.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final bodyMetrics = allMetrics
        .where((e) => _bodyOnlyMetricLabels.contains(e.key))
        .toList();

    // Body-focused results show all body metrics (≤6);
    // skin-focused results show the top 5.
    final topMetrics = result.isBodyFocused
        ? bodyMetrics
        : allMetrics.take(5).toList();

    // Strongest positive impact (improvement).
    MapEntry<String, double>? topImpact;
    final pool = result.isBodyFocused ? bodyMetrics : allMetrics;
    for (final m in pool) {
      if (m.value > 0) {
        topImpact = m;
        break;
      }
    }

    // Build "Top impact" label with proper units for body metrics.
    String topImpactLabel(MapEntry<String, double> m) {
      if (result.isBodyFocused) {
        const lowerBetter = {'Weight', 'Body Fat %', 'Waist Circumference'};
        final unit = _BodyCorrelationMetricRow._unitFor(m.key);
        final arrow = lowerBetter.contains(m.key) ? '\u2193' : '\u2191';
        return 'Top impact: ${m.key} $arrow ${m.value.abs().toStringAsFixed(1)}$unit';
      }
      return 'Top impact: ${m.key} +${m.value.toStringAsFixed(1)} pts';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.peptide.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textBrown,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EEE6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${result.daysTracked}d tracked',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.insightText,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            if (topImpact != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFB7DFB8)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 13,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        topImpactLabel(topImpact),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            ...topMetrics.map(
              (e) => result.isBodyFocused
                  ? _BodyCorrelationMetricRow(
                      metric: e.key,
                      storedDelta: e.value,
                      rawBefore: result.rawBeforeMetrics,
                      rawAfter: result.rawAfterMetrics,
                    )
                  : _MetricDeltaRow(metric: e.key, delta: e.value),
            ),
            if (result.scansAfterCount == 1) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 12,
                    color: Colors.orange.shade400,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Based on 1 scan after start — add more scans for stronger signal.',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB07040)),
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

class _MetricDeltaRow extends StatelessWidget {
  final String metric;
  final double delta;

  const _MetricDeltaRow({required this.metric, required this.delta});

  @override
  Widget build(BuildContext context) {
    final isPositive = delta >= 0;
    final color = isPositive ? const Color(0xFF4CAF50) : AppColors.kMetricWorsenedColor;
    final sign = isPositive ? '+' : '';
    final pct = (delta.abs() / 10.0).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                metric,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5B6469),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$sign${delta.toStringAsFixed(1)} pts',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: LayoutBuilder(
                builder: (ctx, constraints) => Stack(
                  children: [
                    Container(
                      width: constraints.maxWidth,
                      color: const Color(0xFFEDEBE3),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * pct,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A metric row for body-composition–focused peptide correlation cards.
/// Shows the metric name, a before → after value pair with real units,
/// and a coloured improvement arrow.
class _BodyCorrelationMetricRow extends StatelessWidget {
  final String metric;

  /// Stored delta where positive always means improvement.
  final double storedDelta;

  /// Raw scan-metric maps for before/after values.
  final Map<String, double> rawBefore;
  final Map<String, double> rawAfter;

  const _BodyCorrelationMetricRow({
    required this.metric,
    required this.storedDelta,
    required this.rawBefore,
    required this.rawAfter,
  });

  // Lower-is-better body metrics (improvement = value went DOWN).
  static const _lowerBetter = {'Weight', 'Body Fat %', 'Waist Circumference'};

  static const Map<String, List<String>> _metricKeys = {
    'Weight': ['weightLbs', 'weight'],
    'Body Fat %': ['bodyFatPct', 'bodyFat'],
    'Waist Circumference': ['waistInches', 'waistCm', 'waist'],
    'Muscle Mass': ['muscleMassLbs', 'muscleMass', 'leanMass'],
    'Appetite Control': ['satietyScore', 'appetiteControl', 'satiety'],
    'Body Composition Score': ['bodyCompositionScore'],
  };

  static String _unitFor(String m) {
    switch (m) {
      case 'Weight':
        return ' lbs';
      case 'Body Fat %':
        return '%';
      case 'Waist Circumference':
        return ' in';
      case 'Muscle Mass':
        return ' lbs';
      case 'Appetite Control':
        return '/10';
      case 'Body Composition Score':
        return '/10';
      default:
        return '';
    }
  }

  static double? _rawOf(Map<String, double> map, List<String>? keys) {
    if (keys == null) return null;
    for (final k in keys) {
      final v = map[k];
      if (v != null) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unitFor(metric);
    final improved = storedDelta > 0.05;
    final declined = storedDelta < -0.05;
    final color = improved
        ? const Color(0xFF4CAF50)
        : (declined ? AppColors.kMetricWorsenedColor : const Color(0xFF9E9E9E));

    final bVal = _rawOf(rawBefore, _metricKeys[metric]);
    final aVal = _rawOf(rawAfter, _metricKeys[metric]);

    // Directional arrow: lower-is-better = ↓ when improved; higher-is-better = ↑ when improved.
    final IconData arrowIcon = improved
        ? (_lowerBetter.contains(metric)
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded)
        : (declined
              ? (_lowerBetter.contains(metric)
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded)
              : Icons.remove_rounded);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              metric,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF5B6469),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: bVal != null && aVal != null
                ? Text(
                    '${bVal.toStringAsFixed(1)}$unit \u2192 ${aVal.toStringAsFixed(1)}$unit',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2C3539),
                    ),
                  )
                : Text(
                    '${storedDelta.abs().toStringAsFixed(1)}$unit change',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2C3539),
                    ),
                  ),
          ),
          Icon(arrowIcon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${storedDelta.abs().toStringAsFixed(1)}$unit',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Library
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryTab extends StatefulWidget {
  final VoidCallback onOpenReconstitutionSheet;

  const _LibraryTab({required this.onOpenReconstitutionSheet});

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> {
  static const Color _rose = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0x1FD4AF37), Color(0x00FFFFFF), Color(0x1AF4E8CC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x33D4AF37)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Library',
                style: TextStyle(
                  color: Color(0xFF2C3539),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Your reference home for peptide tools and protocol guides. Start with Reconstitution, then grow into databases, glossaries, and saved playbooks.',
                style: TextStyle(
                  color: Color(0xFF5B6469),
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _ReferenceFeatureCard(onOpen: widget.onOpenReconstitutionSheet),
        const SizedBox(height: 18),
        const Text(
          'Next in Library',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2C3539),
          ),
        ),
        const SizedBox(height: 8),
        const _ReferencePlaceholderCard(
          title: 'Product Database',
          subtitle:
              'Search products by peptide composition, concentration format, and intended protocol use.',
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 10),
        const _ReferencePlaceholderCard(
          title: 'Ingredient Glossary',
          subtitle:
              'Decode peptide acronyms, mechanisms, and evidence terms in one clinician-friendly index.',
          icon: Icons.menu_book_rounded,
        ),
        const SizedBox(height: 10),
        const _ReferencePlaceholderCard(
          title: 'Saved Guides',
          subtitle:
              'Pin and revisit your own protocol notes, favorite primers, and provider-approved checklists.',
          icon: Icons.bookmark_border_rounded,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8E3D7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: _rose.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tip: the science icon in the top-right opens this Library instantly so reference tools stay discoverable without adding more top-level tabs.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6A7277),
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferenceFeatureCard extends StatelessWidget {
  final VoidCallback onOpen;

  const _ReferenceFeatureCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD4AF37), Color(0xFFE5C96A)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.science_outlined,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reconstitution Cheat Sheet',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2C3539),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Featured tool in Library',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7E868B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Color(0xFFD4AF37),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use a guided calculator, category chips, favorites, and recently viewed references for fast dose prep and protocol checks.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B6469),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open Cheat Sheet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferencePlaceholderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ReferencePlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E3D7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0E3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFFD4AF37)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2C3539),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0EEE8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Soon',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7E868B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF5B6469),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryCard extends StatefulWidget {
  final PeptideLibraryEntry entry;
  final ValueChanged<PeptideLibraryEntry> onAddToStack;

  const _LibraryCard({required this.entry, required this.onAddToStack});

  @override
  State<_LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<_LibraryCard> {
  bool _expanded = false;

  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _rose = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.entry.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textBrown,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.entry.inci,
                        style: const TextStyle(fontSize: 10, color: _muted),
                      ),
                    ],
                  ),
                ),
                _EvidenceBadge(level: widget.entry.evidenceLevel),
              ],
            ),
            const SizedBox(height: 8),
            // Primary metrics chips
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: widget.entry.primaryMetrics.map((m) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1EEE6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    m,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF7E868B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // Mechanism
            Text(
              widget.entry.mechanism,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5B6469)),
            ),
            // Expandable clinical note
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Text(
                      _expanded ? 'Hide evidence note' : 'View evidence note',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _rose,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: _rose,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F6F0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E8E8), width: 1),
                ),
                child: Text(
                  widget.entry.clinicalNote,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B6469),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Add to stack
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => widget.onAddToStack(widget.entry),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                label: const Text('Add to My Stack'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Evidence Badge
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenceBadge extends StatelessWidget {
  final String level;
  const _EvidenceBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (level) {
      case 'Tier 1':
        bg = const Color(0xFF00897B).withValues(alpha: 0.12);
        fg = const Color(0xFF00695C);
        break;
      case 'Tier 2':
        bg = const Color(0xFFD4AF37).withValues(alpha: 0.12);
        fg = const Color(0xFF8D5E53);
        break;
      default: // Tier 3
        bg = const Color(0xFFE3C766).withValues(alpha: 0.15);
        fg = const Color(0xFF9A7840);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        level,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF0EEE8),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: const Color(0xFFD4AF37)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2C3539),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7E868B),
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 240,
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: Text(actionLabel!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

/// Known peptide / actives interactions surfaced as gentle advisory notes.
///
/// Each entry pairs two ingredient names (or simple substrings) with a
/// short, user-facing reminder. Matching is case-insensitive and uses
/// `String.contains` on the lowercased peptide name so both library names
/// and free-typed names will match (e.g. "GHK-Cu" matches "GHK" / "Copper").
class _PeptideInteractionRule {
  final String a;
  final String b;
  final String message;
  const _PeptideInteractionRule(this.a, this.b, this.message);
}

const List<_PeptideInteractionRule> _kPeptideInteractions = [
  _PeptideInteractionRule(
    'ghk-cu',
    'vitamin c',
    'GHK-Cu and Vitamin C (ascorbic acid) can deactivate each other — apply at different times of day.',
  ),
  _PeptideInteractionRule(
    'ghk-cu',
    'retinol',
    'GHK-Cu and retinoids may increase sensitivity — monitor for redness, alternate nights if irritated.',
  ),
  _PeptideInteractionRule(
    'ghk-cu',
    'aha',
    'GHK-Cu and AHAs/BHAs can lower copper-peptide stability and increase sensitivity — separate by ≥30 min.',
  ),
  _PeptideInteractionRule(
    'ahk-cu',
    'vitamin c',
    'Copper peptides (AHK-Cu) and ascorbic acid can neutralize each other — use AM/PM split.',
  ),
  _PeptideInteractionRule(
    'argireline',
    'retinol',
    'Argireline + retinoids may amplify dryness; introduce gradually and pair with a barrier moisturizer.',
  ),
  _PeptideInteractionRule(
    'matrixyl',
    'retinol',
    'Matrixyl + retinoids: watch for irritation if combined; consider alternating evenings.',
  ),
  _PeptideInteractionRule(
    'egf',
    'retinol',
    'EGF and high-strength retinoids can compete — monitor skin reaction and reduce frequency if needed.',
  ),
  _PeptideInteractionRule(
    'snap-8',
    'argireline',
    'SNAP-8 + Argireline target the same SNARE pathway — combining adds limited benefit but can over-relax expression lines.',
  ),
];

/// Returns a deduplicated list of interaction warnings for any pair within
/// the given peptide names. Comparison is case-insensitive and uses
/// substring matching so user-entered variants still match.
List<String> peptideInteractionWarnings(Iterable<String> names) {
  final lowered = names
      .map((n) => n.trim().toLowerCase())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList();
  final warnings = <String>{};
  for (final rule in _kPeptideInteractions) {
    final hasA = lowered.any((n) => n.contains(rule.a));
    final hasB = lowered.any((n) => n.contains(rule.b));
    if (hasA && hasB) warnings.add(rule.message);
  }
  return warnings.toList();
}

/// Amber-styled advisory banner shown when known peptide interactions are
/// detected in a stack (or about to be created by adding a new peptide).
class _PeptideInteractionBanner extends StatelessWidget {
  final List<String> warnings;
  final EdgeInsetsGeometry margin;
  const _PeptideInteractionBanner({
    required this.warnings,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF1D7A1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Color(0xFFA9762E),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heads up — possible interaction',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5D17),
                  ),
                ),
                const SizedBox(height: 3),
                for (int i = 0; i < warnings.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                    child: Text(
                      '• ${warnings[i]}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8A5D17),
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                const Text(
                  'Educational only — monitor your skin and consult your provider if unsure.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFFA9762E),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Typical starting concentrations for auto-fill when a library peptide is selected.
const Map<String, double> _kTypicalConcentrations = {
  'Matrixyl 3000': 5.0,
  "Matrixyl Synthe'6": 10.0,
  'GHK-Cu (Copper Tripeptide-1)': 1.0,
  'Argireline (Acetyl Hexapeptide-3)': 10.0,
  'Leuphasyl': 4.0,
  'SYN-AKE': 4.0,
  'Palmitoyl Tripeptide-5': 5.0,
  'SNAP-8': 4.0,
  'Tripeptide-10 Citrulline': 2.0,
  'Carnosine': 1.5,
  'AHK-Cu (Copper Tripeptide-3)': 1.0,
  'Tetrapeptide-30': 0.1,
  'Oligopeptide-34': 2.0,
  'Dermaxyl': 5.0,
  'Boostatin (Hexapeptide-14)': 2.0,
  'Uplevity (Acetyl Tetrapeptide-2)': 2.0,
  'Tripeptide-29': 3.0,
  'PEPHA-TIGHT': 2.0,
  'EGF (sh-Oligopeptide-1)': 0.005,
  'Palmitoyl Tetrapeptide-7': 5.0,
  'Vitamin C (L-Ascorbic Acid)': 15.0,
  'Niacinamide (Vitamin B3)': 5.0,
  'Pal-GHK (Palmitoyl Tripeptide-1)': 0.0004,
  'Acetyl Tetrapeptide-9': 3.0,
  'Acetyl Tetrapeptide-22': 3.0,
  'Hexapeptide-11': 2.0,
  // BPC-157, TB-500, Epitalon, Thymosin Alpha-1 are typically dosed by
  // mass/volume (mg/mL) rather than a topical percentage; omitted from
  // auto-fill on purpose.
};

/// Curated multi-peptide combinations users can add to a stack in one tap.
///
/// `peptideNames` must match entries in `kPeptideLibrary` exactly so the
/// blend can pull mechanism, category and typical-concentration metadata.
class _PopularBlend {
  final String name;
  final String tagline;
  final List<String> peptideNames;
  final List<String> benefits;
  final IconData icon;
  final List<Color> gradient;
  final String defaultCategory;
  const _PopularBlend({
    required this.name,
    required this.tagline,
    required this.peptideNames,
    required this.benefits,
    required this.icon,
    required this.gradient,
    required this.defaultCategory,
  });
}

const List<_PopularBlend> _kPopularBlends = [
  _PopularBlend(
    name: 'Glow Stack',
    tagline:
        'Copper-driven repair plus regenerative peptides for radiant, smooth skin.',
    peptideNames: ['GHK-Cu (Copper Tripeptide-1)', 'TB-500', 'BPC-157'],
    benefits: ['Radiance', 'Repair', 'Even Tone'],
    icon: Icons.auto_awesome_rounded,
    gradient: [Color(0xFFE9B7A8), Color(0xFFD9A26A)],
    defaultCategory: 'brightening',
  ),
  _PopularBlend(
    name: 'Recovery Stack',
    tagline:
        'Post-procedure repair: angiogenesis, barrier support and collagen remodeling.',
    peptideNames: ['GHK-Cu (Copper Tripeptide-1)', 'BPC-157', 'Matrixyl 3000'],
    benefits: ['Healing', 'Barrier Repair', 'Redness'],
    icon: Icons.healing_rounded,
    gradient: [Color(0xFFD4AF37), Color(0xFFE8D5A8)],
    defaultCategory: 'healing',
  ),
  _PopularBlend(
    name: 'Anti-Aging Stack',
    tagline:
        'Matrikine collagen support plus expression-line relaxation and copper remodeling.',
    peptideNames: [
      'Matrixyl 3000',
      'Argireline (Acetyl Hexapeptide-3)',
      'GHK-Cu (Copper Tripeptide-1)',
    ],
    benefits: ['Wrinkles', 'Firmness', 'Collagen'],
    icon: Icons.shield_moon_rounded,
    gradient: [Color(0xFFE3C766), Color(0xFFE3C766)],
    defaultCategory: 'anti-aging',
  ),
  _PopularBlend(
    name: 'Brightening Stack',
    tagline:
        'Antioxidant Vitamin C with barrier-repairing Niacinamide and copper-driven tone correction.',
    peptideNames: [
      'Vitamin C (L-Ascorbic Acid)',
      'Niacinamide (Vitamin B3)',
      'GHK-Cu (Copper Tripeptide-1)',
    ],
    benefits: ['Dark Spots', 'Even Tone', 'Antioxidant'],
    icon: Icons.wb_sunny_rounded,
    gradient: [Color(0xFFD9A26A), Color(0xFFE9C28A)],
    defaultCategory: 'brightening',
  ),
  _PopularBlend(
    name: 'Healing Stack',
    tagline:
        'Regenerative trio for soft-tissue repair, post-procedure recovery and scar remodeling.',
    peptideNames: ['BPC-157', 'TB-500', 'GHK-Cu (Copper Tripeptide-1)'],
    benefits: ['Healing', 'Tissue Repair', 'Anti-Inflammatory'],
    icon: Icons.health_and_safety_rounded,
    gradient: [Color(0xFFC9A227), Color(0xFFD4AF37)],
    defaultCategory: 'healing',
  ),
  _PopularBlend(
    name: 'Firming Stack',
    tagline:
        'Collagen scaffolding plus anti-inflammatory and expression-line relaxation for sustained lift.',
    peptideNames: ['Matrixyl 3000', 'Palmitoyl Tetrapeptide-7', 'SNAP-8'],
    benefits: ['Firmness', 'Elasticity', 'Lift'],
    icon: Icons.fitness_center_rounded,
    gradient: [Color(0xFFE3C766), Color(0xFFD9A26A)],
    defaultCategory: 'firming',
  ),
];

class _StackDetailPage extends StatefulWidget {
  final String stackId;
  final Future<void> Function(PeptideEntry) openPeptideDetail;
  final Future<void> Function({String? seedCategoryArg}) openAddPeptide;
  final Future<void> Function(PeptideStack) renameStack;
  final Future<void> Function(PeptideStack) deleteStack;
  final Future<void> Function(PeptideEntry) deletePeptide;
  final ValueChanged<PeptideEntry> editPeptide;
  final Future<void> Function() takeScan;

  /// Closes the current stack detail route and re-pushes it with the latest
  /// data. Used right after a scan completes so Before & After + metrics
  /// reflect the new scan without manual back-and-forward navigation.
  final Future<void> Function()? reopenSelf;
  final String? seedCategoryOnOpen;

  const _StackDetailPage({
    required this.stackId,
    required this.openPeptideDetail,
    required this.openAddPeptide,
    required this.renameStack,
    required this.deleteStack,
    required this.deletePeptide,
    required this.editPeptide,
    required this.takeScan,
    this.reopenSelf,
    this.seedCategoryOnOpen,
  });

  @override
  State<_StackDetailPage> createState() => _StackDetailPageState();
}

class _StackDetailPageState extends State<_StackDetailPage>
    with WidgetsBindingObserver {
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  PeptideStack? _stack;
  List<PeptideEntry> _peptides = [];
  List<StackJournalEntry> _journal = [];
  List<ScanHistoryEntry> _stackScans = [];
  List<PeptideCorrelationResult> _correlations = [];
  bool _loading = true;
  bool _seedFired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    if (widget.seedCategoryOnOpen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_seedFired || !mounted) return;
        _seedFired = true;
        await widget.openAddPeptide(seedCategoryArg: widget.seedCategoryOnOpen);
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final stacks = await PeptideService.loadStacks();
    final all = await PeptideService.loadAll();
    final journal = await PeptideService.loadJournalForStack(widget.stackId);
    final allScans = await AppPrefs.getScanEntries();
    if (!mounted) return;
    final stack = stacks.where((s) => s.id == widget.stackId).firstOrNull;
    final stackPeptides = all.where((e) => e.stackId == widget.stackId).toList()
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.startDate.compareTo(a.startDate);
      });
    // Stack-scoped scans: filter by associated procedureId (if any) AND by
    // scans taken on/after the stack was created. This avoids surfacing
    // scans that pre-date the stack itself.
    final scoped = allScans.where((s) {
      if (stack == null) return false;
      final afterCreation = !s.timestamp.isBefore(stack.createdAt);
      final matchesProc =
          stack.procedureId == null || s.procedureId == stack.procedureId;
      return afterCreation && matchesProc;
    }).toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    // Correlate using ALL scans (so baselines from before peptide-start are
    // available), but the result list is naturally filtered to this stack's
    // peptides.
    final correlations = PeptideService.computeCorrelations(
      stackPeptides,
      allScans,
    );
    setState(() {
      _stack = stack;
      _peptides = stackPeptides;
      _journal = journal;
      _stackScans = scoped;
      _correlations = correlations;
      _loading = false;
    });
  }

  Future<void> _onTakeScan() async {
    await widget.takeScan();
    if (!mounted) return;
    // In-place refresh: re-load this page's data and let `setState` rebuild
    // Before & After + Stack Metrics + Per-peptide Insights against the
    // freshly-saved scan. No pop+reopen — the user stays on this page.
    await _load();
  }

  /// Opens the body-measurements entry sheet so the user can log Weight,
  /// Body Fat %, Waist, etc. without taking a new camera scan. When at
  /// least one scan exists for this stack we patch the latest scan in
  /// place; otherwise we create a synthetic baseline scan that carries
  /// only the body metrics (no image), so Stack Metrics can render
  /// immediately for fresh body-focused stacks.
  Future<void> _logBodyMetricsManually() async {
    final stack = _stack;
    if (stack == null) return;

    // Resolve a procedureId — required to persist a scan. Prefer the stack's
    // pinned procedure, falling back to the most recent scan, then to the
    // currently selected procedure.
    String? procedureId = stack.procedureId;
    if (procedureId == null && _stackScans.isNotEmpty) {
      procedureId = _stackScans.last.procedureId;
    }
    procedureId ??= await AppPrefs.getSelectedProcedureIdOrNull();

    if (procedureId == null) {
      // No procedure to anchor against — auto-create a lightweight one so
      // the body-metrics flow never dead-ends.
      final newProc = Procedure(
        id: 'pep_${DateTime.now().millisecondsSinceEpoch}',
        type: 'Body Composition Peptides',
        category: 'Body Composition',
        provider: 'Self',
        startDate: DateTime.now(),
        numSessions: 1,
      );
      await AppPrefs.addProcedureToHistory(newProc.toJson());
      await PeptideService.setStackProcedure(stack.id, newProc.id);
      procedureId = newProc.id;
    }

    if (!mounted) return;
    final entered = await showBodyMetricsEntrySheet(
      context,
      procedureId: procedureId,
    );
    if (entered == null || entered.isEmpty) return;

    if (_stackScans.isNotEmpty) {
      // Patch the most recent scan so metric deltas remain time-aligned.
      await AppPrefs.patchScanMetrics(_stackScans.last.id, entered);
    } else {
      // No scans yet — create a synthetic baseline scan with only the body
      // metrics so Stack Metrics has at least one data point to display.
      final now = DateTime.now();
      final entry = ScanHistoryEntry(
        id: ScanHistoryEntry.generateId(now, null),
        timestamp: now,
        procedureId: procedureId,
        estimatedSkinAge: 0,
        metrics: Map<String, double>.from(entered),
        procedure: 'Body Composition Peptides',
        isBaseline: true,
      );
      await AppPrefs.addScanEntry(entry);
    }
    if (mounted) await _load();
  }

  Future<void> _onAdd() async {
    await widget.openAddPeptide();
    if (mounted) _load();
  }

  Future<void> _onRename() async {
    final s = _stack;
    if (s == null) return;
    await widget.renameStack(s);
    if (mounted) _load();
  }

  Future<void> _onDeleteStack() async {
    final s = _stack;
    if (s == null) return;
    await widget.deleteStack(s);
  }

  Future<void> _onTapPeptide(PeptideEntry e) async {
    await widget.openPeptideDetail(e);
    if (mounted) _load();
  }

  Future<void> _onDeletePeptide(PeptideEntry e) async {
    await widget.deletePeptide(e);
    if (mounted) _load();
  }

  void _onEditPeptide(PeptideEntry e) {
    widget.editPeptide(e);
  }

  Future<void> _onAddJournalEntry() async {
    final result = await showModalBottomSheet<_JournalDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StackJournalComposerSheet(stackName: _stack?.name ?? 'Stack'),
    );
    if (result == null || result.text.trim().isEmpty || !mounted) return;
    await PeptideService.addStackJournalEntry(
      stackId: widget.stackId,
      text: result.text.trim(),
      isVoice: result.isVoice,
    );
    await _load();
  }

  Future<void> _onEditJournalEntry(StackJournalEntry entry) async {
    final result = await showModalBottomSheet<_JournalDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StackJournalComposerSheet(
        stackName: _stack?.name ?? 'Stack',
        initialText: entry.text,
        initialIsVoice: entry.isVoice,
        isEditing: true,
      ),
    );
    if (result == null || result.text.trim().isEmpty || !mounted) return;
    await PeptideService.updateStackJournalEntry(
      id: entry.id,
      text: result.text.trim(),
      isVoice: result.isVoice,
    );
    await _load();
  }

  Future<void> _onOpenJournalEntry(StackJournalEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JournalDetailSheet(entry: entry),
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _onEditJournalEntry(entry);
    } else if (action == 'delete') {
      await _onDeleteJournalEntry(entry);
    }
  }

  Future<void> _onDeleteJournalEntry(StackJournalEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete note?', style: TextStyle(color: _textBrown)),
        content: const Text(
          'This will permanently delete this journal entry.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.kMetricWorsenedColor),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await PeptideService.deleteStackJournalEntry(entry.id);
    await _load();
  }

  /// Builds a chronological event list for the stack:
  /// • Stack created
  /// • Each peptide added (PeptideEntry.startDate)
  /// • Each peptide ended
  /// • Each journal note
  List<_TimelineEvent> _buildTimelineEvents() {
    final events = <_TimelineEvent>[];
    final s = _stack;
    if (s != null) {
      events.add(
        _TimelineEvent(
          when: s.createdAt,
          icon: Icons.layers_rounded,
          title: 'Stack created',
          subtitle: s.name,
          kind: _TimelineKind.stack,
        ),
      );
    }
    for (final p in _peptides) {
      events.add(
        _TimelineEvent(
          when: p.startDate,
          icon: Icons.science_rounded,
          title: 'Started ${p.name}',
          subtitle: p.frequency,
          kind: _TimelineKind.peptide,
        ),
      );
      if (p.endDate != null) {
        events.add(
          _TimelineEvent(
            when: p.endDate!,
            icon: Icons.stop_circle_outlined,
            title: 'Ended ${p.name}',
            subtitle: '${p.daysTracked} days tracked',
            kind: _TimelineKind.peptideEnd,
          ),
        );
      }
    }
    for (final j in _journal) {
      events.add(
        _TimelineEvent(
          when: j.createdAt,
          icon: j.isVoice ? Icons.mic_rounded : Icons.edit_note_rounded,
          title: j.isVoice ? 'Voice note' : 'Journal note',
          subtitle: j.text,
          kind: _TimelineKind.journal,
        ),
      );
    }
    events.sort((a, b) => b.when.compareTo(a.when));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final stack = _stack;
    final activeCount = _peptides.where((e) => e.isActive).length;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _textBrown,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          stack?.name ?? 'Stack',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textBrown,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined, color: _rose, size: 20),
            onPressed: stack == null ? null : _onRename,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: _rose),
            onSelected: (v) {
              if (v == 'delete') _onDeleteStack();
              if (v == 'rename') _onRename();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18, color: _rose),
                    SizedBox(width: 10),
                    Text('Rename Stack'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.kMetricWorsenedColor,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Delete Stack',
                      style: TextStyle(color: AppColors.kMetricWorsenedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _rose))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        // Stack summary header
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF8F6F0), Color(0xFFF8F6F0)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE5E8E8)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [_rose, Color(0xFFE3C766)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.layers_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_peptides.length} peptide${_peptides.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: _textBrown,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$activeCount active · ${_journal.length} note${_journal.length == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Interaction advisory banner ───────────────────
                        Builder(
                          builder: (_) {
                            final warnings = peptideInteractionWarnings(
                              _peptides
                                  .where((p) => p.isActive)
                                  .map((p) => p.name),
                            );
                            if (warnings.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _PeptideInteractionBanner(
                                warnings: warnings,
                              ),
                            );
                          },
                        ),

                        // ── Take New Scan CTA ─────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _onTakeScan,
                            icon: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text(
                              _stackScans.isEmpty
                                  ? 'Take Baseline Scan'
                                  : 'Take New Scan',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _rose,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        // Secondary CTA for body-focused stacks so the user
                        // can update Weight / Body Fat % / Waist without
                        // taking a new photo. Appears below the camera CTA.
                        if (_stackIsBodyFocused(_peptides)) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _logBodyMetricsManually,
                              icon: const Icon(
                                Icons.monitor_weight_outlined,
                                color: _rose,
                                size: 18,
                              ),
                              label: const Text(
                                'Log Body Measurements',
                                style: TextStyle(
                                  color: _rose,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: _rose,
                                  width: 1.4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          // Compare Metrics Over Time CTA — only meaningful
                          // when we have at least 2 scans to compare.
                          if (_stackScans.length >= 2) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          _BodyProgressCompareScreen(
                                            stackName: _stack?.name ?? 'Stack',
                                            scans: List<ScanHistoryEntry>.from(
                                              _stackScans,
                                            ),
                                          ),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.timeline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Compare Metrics Over Time',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _rose,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 14),

                        // ── Before / After ────────────────────────────────
                        const _StackSectionHeader(
                          icon: Icons.compare_rounded,
                          label: 'Before & After',
                        ),
                        const SizedBox(height: 8),
                        _StackBeforeAfterCard(scans: _stackScans),

                        const SizedBox(height: 18),

                        // ── Aggregated Metrics ────────────────────────────
                        const _StackSectionHeader(
                          icon: Icons.insights_rounded,
                          label: 'Stack Metrics',
                        ),
                        const SizedBox(height: 8),
                        _StackMetricsCard(
                          scans: _stackScans,
                          isBodyFocused: _stackIsBodyFocused(_peptides),
                          onLogBodyMetrics: _stackIsBodyFocused(_peptides)
                              ? _logBodyMetricsManually
                              : null,
                        ),

                        const SizedBox(height: 18),

                        // ── Per-peptide Correlations ──────────────────────
                        const _StackSectionHeader(
                          icon: Icons.auto_graph_rounded,
                          label: 'Per-peptide Insights',
                        ),
                        const SizedBox(height: 8),
                        _StackCorrelationList(
                          results: _correlations,
                          isBodyFocused: _stackIsBodyFocused(_peptides),
                        ),

                        const SizedBox(height: 18),

                        // ── Voice Journal ─────────────────────────────────
                        _StackSectionHeader(
                          icon: Icons.mic_rounded,
                          label: 'Voice Journal',
                          actionLabel: 'Add note',
                          onAction: _onAddJournalEntry,
                        ),
                        const SizedBox(height: 8),
                        if (_journal.isEmpty)
                          _StackJournalEmptyCard(onAdd: _onAddJournalEntry)
                        else
                          Column(
                            children: [
                              for (final entry in _journal.take(5))
                                _StackJournalCard(
                                  entry: entry,
                                  onTap: () => _onOpenJournalEntry(entry),
                                  onDelete: () => _onDeleteJournalEntry(entry),
                                ),
                              if (_journal.length > 5)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '+ ${_journal.length - 5} older note${_journal.length - 5 == 1 ? '' : 's'} \u2014 see timeline below',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _muted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),

                        const SizedBox(height: 18),

                        // ── Timeline ──────────────────────────────────────
                        const _StackSectionHeader(
                          icon: Icons.timeline_rounded,
                          label: 'Timeline',
                        ),
                        const SizedBox(height: 8),
                        _StackTimelineList(events: _buildTimelineEvents()),

                        const SizedBox(height: 18),

                        // ── Peptides ──────────────────────────────────────
                        const _StackSectionHeader(
                          icon: Icons.science_outlined,
                          label: 'Peptides in this stack',
                        ),
                        const SizedBox(height: 8),
                        if (_peptides.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    color: _surface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.science_outlined,
                                    size: 26,
                                    color: _rose,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'No peptides in this stack yet',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _textBrown,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap the button below to add your first peptide.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11, color: _muted),
                                ),
                              ],
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (final p in _peptides)
                                _PeptideCard(
                                  entry: p,
                                  onEdit: _onEditPeptide,
                                  onDelete: _onDeletePeptide,
                                  onTap: _onTapPeptide,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Sticky bottom CTA
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _onAdd,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text(
                          'Add Peptide to this Stack',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rose,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
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

// ─────────────────────────────────────────────────────────────────────────────
// Stack Detail supporting widgets — section headers, journal cards, timeline,
// and the voice-journal composer sheet.
// ─────────────────────────────────────────────────────────────────────────────

// ── Before / After for the stack ──
class _StackBeforeAfterCard extends StatelessWidget {
  final List<ScanHistoryEntry> scans;
  const _StackBeforeAfterCard({required this.scans});

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  @override
  Widget build(BuildContext context) {
    if (scans.isEmpty) {
      return const _EmptyScanCard(
        message:
            'No scans yet. Take your first scan to set a baseline for this stack.',
      );
    }
    // Prefer an explicit baseline scan over the chronologically-first one so
    // the BEFORE tile always reflects the user's actual baseline. Falls back
    // to the earliest scan when no scan was flagged isBaseline.
    final sorted = [...scans]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final baseline =
        sorted.where((s) => s.isBaseline).firstOrNull ?? sorted.first;
    final remaining = sorted.where((s) => s.id != baseline.id).toList();
    final latest = remaining.isEmpty ? null : remaining.last;
    final days = latest != null
        ? latest.timestamp.difference(baseline.timestamp).inDays
        : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ScanPhotoTile(
                  label: 'Baseline',
                  date: baseline.timestamp,
                  imagePath: baseline.imagePath,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ScanPhotoTile(
                  label: latest == null ? 'Latest (pending)' : 'Latest',
                  date: latest?.timestamp,
                  imagePath: latest?.imagePath,
                ),
              ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.timelapse_rounded, size: 14, color: _rose),
                const SizedBox(width: 6),
                Text(
                  '$days day${days == 1 ? '' : 's'} between scans · '
                  '${scans.length} scan${scans.length == 1 ? '' : 's'} total',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _textBrown,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Take another scan to compare against your baseline.',
              style: TextStyle(
                fontSize: 11,
                color: _muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanPhotoTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String? imagePath;
  const _ScanPhotoTile({required this.label, this.date, this.imagePath});

  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _ScanImage(imagePath: imagePath),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: _textBrown,
          ),
        ),
        if (date != null)
          Text(
            _fmtDate(date!),
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
      ],
    );
  }
}

class _ScanImage extends StatelessWidget {
  final String? imagePath;
  const _ScanImage({this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return Container(
        color: const Color(0xFFEFE0D2),
        alignment: Alignment.center,
        child: const Icon(
          Icons.camera_alt_rounded,
          color: Color(0xFF7E868B),
          size: 28,
        ),
      );
    }
    // We may be on web (where File access throws) — guard with try/catch via
    // Image.network-like behaviour: Image.asset/Image.file with errorBuilder.
    final path = imagePath!;
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildErr(),
      );
    }
    return Image.network(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildErr(),
    );
  }

  Widget _buildErr() => Container(
    color: const Color(0xFFEFE0D2),
    alignment: Alignment.center,
    child: const Icon(
      Icons.image_not_supported_outlined,
      color: Color(0xFF7E868B),
      size: 24,
    ),
  );
}

class _EmptyScanCard extends StatelessWidget {
  final String message;
  const _EmptyScanCard({required this.message});

  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE5E8E8),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.photo_camera_outlined, color: _muted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Aggregated metrics ──
//
// Shows a clinical-style breakdown of skin metrics aggregated across all
// stack-scoped scans (filtered in `_load` by the stack's linked procedure
// and date range since stack creation).
//
// For each metric we display:
//   • Baseline value (first stack-scoped scan)
//   • Latest value (smoothed mean of the most recent up-to-3 scans)
//   • A directional delta with green ↑ / red ↓ via `resolveMetricTrend`
//   • A small progress bar showing the current value on a 0–10 scale
class _StackMetricsCard extends StatelessWidget {
  final List<ScanHistoryEntry> scans;

  /// When true, body-composition metrics are rendered first (and skin metrics
  /// are demoted to a secondary section, or hidden when no skin data is
  /// present). Used for stacks containing GLP-1 / GHRH / lipolytic peptides.
  final bool isBodyFocused;

  /// Optional callback to open the body-measurements entry sheet. Surfaced
  /// when [isBodyFocused] is true and the card has no body-metric data yet,
  /// so the user has a clear path to populate the card.
  final VoidCallback? onLogBodyMetrics;
  const _StackMetricsCard({
    required this.scans,
    this.isBodyFocused = false,
    this.onLogBodyMetrics,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _gold = Color(0xFFE3C766);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  /// Skin-metric keys (in display order) → human label.
  static const List<MapEntry<String, String>> _skinMetrics = [
    MapEntry('redness', 'Redness'),
    MapEntry('texture', 'Texture'),
    MapEntry('wrinkles', 'Wrinkles'),
    MapEntry('wrinkle', 'Wrinkles'),
    MapEntry('pores', 'Pores'),
    MapEntry('pore', 'Pores'),
    MapEntry('darkSpots', 'Dark Spots'),
    MapEntry('elasticity', 'Elasticity'),
    MapEntry('hydration', 'Hydration'),
    MapEntry('barrierHealth', 'Hydration'),
    MapEntry('firmness', 'Firmness'),
    MapEntry('evenness', 'Evenness'),
    MapEntry('tone', 'Evenness'),
    MapEntry('skinTone', 'Evenness'),
    MapEntry('inflammation', 'Inflammation'),
    MapEntry('swelling', 'Inflammation'),
    MapEntry('skinAge', 'Skin Age'),
    MapEntry('biologicalAge', 'Skin Age'),
  ];

  /// Body-composition keys (in display order) → human label.
  static const List<MapEntry<String, String>> _bodyMetrics = [
    MapEntry('weightLbs', 'Weight'),
    MapEntry('weight', 'Weight'),
    MapEntry('bodyFatPct', 'Body Fat %'),
    MapEntry('bodyFat', 'Body Fat %'),
    MapEntry('waistInches', 'Waist Circumference'),
    MapEntry('waistCm', 'Waist Circumference'),
    MapEntry('waist', 'Waist Circumference'),
    MapEntry('muscleMassLbs', 'Muscle Mass'),
    MapEntry('muscleMass', 'Muscle Mass'),
    MapEntry('leanMass', 'Muscle Mass'),
    MapEntry('satietyScore', 'Appetite Control'),
    MapEntry('appetiteControl', 'Appetite Control'),
    MapEntry('satiety', 'Appetite Control'),
    MapEntry('bodyCompositionScore', 'Body Composition Score'),
  ];

  /// Final ordered display list. For body-focused stacks/peptides we show
  /// ONLY body-composition metrics so the user is never visually anchored
  /// to facial/skin readings that are irrelevant to weight-loss progress.
  /// For skin-focused stacks we show skin first, then any body metrics
  /// the user has logged.
  List<MapEntry<String, String>> get _displayMetrics =>
      isBodyFocused ? [..._bodyMetrics] : [..._skinMetrics, ..._bodyMetrics];

  static String _formatDate(DateTime dt) {
    const months = [
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
    ];
    final local = dt.toLocal();
    return '${months[local.month - 1]} ${local.day}';
  }

  /// Returns the mean of the metric across the given scans, or null if no
  /// scan has the key.
  double? _meanMetric(List<ScanHistoryEntry> scans, String key) {
    double sum = 0;
    int n = 0;
    for (final s in scans) {
      final v = s.metrics[key];
      if (v != null) {
        sum += v;
        n++;
      }
    }
    return n == 0 ? null : sum / n;
  }

  @override
  Widget build(BuildContext context) {
    if (scans.isEmpty) {
      if (isBodyFocused) {
        return _BodyMetricsEmptyCta(
          title: 'Enter body measurements to unlock metrics',
          message:
              'Tracking Weight, Body Fat %, Waist and Muscle Mass shows your weight-loss progress over time. Add today\u2019s numbers — every field is optional.',
          onLogBodyMetrics: onLogBodyMetrics,
        );
      }
      return const _StackMetricsEmptyState();
    }

    // ── BODY-FOCUSED ────────────────────────────────────────────────────────
    // Render the strict body-composition card for any non-empty body-focused
    // stack so skin metrics never appear in this flow.
    if (isBodyFocused) {
      return _buildBodyFocusedCard(context);
    }

    final baseline = scans.first;
    // Smooth the "latest" value by averaging the most recent 1–3 scans so
    // a single noisy scan doesn't dominate the displayed delta. With only
    // one scan this still reduces to that single scan.
    final recent = scans.length <= 1
        ? scans
        : scans.sublist(math.max(0, scans.length - 3));
    final singleScan = scans.length < 2;

    // Earliest non-null value per key (used as baseline when the first
    // scan in the series doesn't carry that metric — e.g. a face scan
    // followed by a body-measurements entry).
    double? earliestNonNull(String key) {
      for (final s in scans) {
        final v = s.metrics[key];
        if (v != null) return v;
      }
      return null;
    }

    // Build rows from the display list, de-duped by label.
    final rows = <_StackMetricRow>[];
    final seenLabels = <String>{};
    for (final entry in _displayMetrics) {
      final key = entry.key;
      final label = entry.value;
      if (seenLabels.contains(label)) continue;
      final baselineVal = baseline.metrics[key] ?? earliestNonNull(key);
      final latestVal = _meanMetric(recent, key) ?? earliestNonNull(key);
      if (baselineVal == null || latestVal == null) continue;
      seenLabels.add(label);
      rows.add(
        _StackMetricRow(label: label, baseline: baselineVal, latest: latestVal),
      );
    }

    if (rows.isEmpty) {
      if (isBodyFocused) {
        return _BodyMetricsEmptyCta(
          title: 'Enter body measurements to unlock metrics',
          message:
              'Your scans don\u2019t have body composition data yet. Log Weight, Body Fat %, Waist or Muscle Mass and we\u2019ll chart the deltas right here.',
          onLogBodyMetrics: onLogBodyMetrics,
        );
      }
      return const _StackMetricsEmptyState(
        message:
            'Your scans don\u2019t contain comparable metric data yet. Take a new scan to unlock stack metrics.',
      );
    }

    final avgSkinAge =
        scans.map((s) => s.estimatedSkinAge).fold<double>(0, (a, b) => a + b) /
        scans.length;
    final rangeLabel = singleScan
        ? 'Baseline · ${_formatDate(baseline.timestamp)}'
        : '${_formatDate(baseline.timestamp)} \u2192 ${_formatDate(scans.last.timestamp)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_rose, _gold]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBodyFocused
                          ? 'Body Composition Metrics'
                          : 'Aggregated Stack Metrics',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textBrown,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${scans.length} scan${scans.length == 1 ? '' : 's'} \u00b7 $rangeLabel',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E8E8)),
                ),
                child: Text(
                  'Skin age ${avgSkinAge.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: _textBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (singleScan) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF1D7B5)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: Color(0xFFA9762E),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Baseline captured. Take another scan to reveal trend deltas.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFFA9762E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!singleScan && _mostImprovedRow(rows) != null) ...[
            const SizedBox(height: 10),
            _buildMostImprovedBanner(_mostImprovedRow(rows)!),
          ],
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: const Color(0xFFE5E8E8).withValues(alpha: 0.7),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            _buildMetricRow(rows[i], singleScan: singleScan),
            if (i != rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: const Color(0xFFE5E8E8).withValues(alpha: 0.45),
              ),
          ],
        ],
      ),
    );
  }

  // ── Body-Composition Trend (always-unlocked path for 2+ scans) ───────────
  /// Builds the body-focused metrics card. Always renders all six body
  /// metrics — when a metric is missing from every scan, an inline "Log
  /// to track" placeholder is shown so the section never appears locked.
  Widget _buildBodyFocusedCard(BuildContext context) {
    final sorted = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final specs = <_BodyTrendSpec>[
      const _BodyTrendSpec(['weightLbs', 'weight'], 'Weight', ' lbs', true),
      const _BodyTrendSpec(['bodyFatPct', 'bodyFat'], 'Body Fat %', '%', true),
      const _BodyTrendSpec(
        ['waistInches', 'waist', 'waistCm'],
        'Waist Circumference',
        ' in',
        true,
      ),
      const _BodyTrendSpec(
        ['muscleMassLbs', 'muscleMass', 'leanMass'],
        'Muscle Mass',
        ' lbs',
        false,
      ),
      const _BodyTrendSpec(
        ['satietyScore', 'appetiteControl', 'satiety'],
        'Appetite Control',
        '/10',
        false,
      ),
      const _BodyTrendSpec(
        ['bodyCompositionScore'],
        'Body Composition Score',
        '/10',
        false,
      ),
    ];

    // Resolve before/after per spec using exact values first, then clinical
    // fallback estimates derived from weight change when a body metric is
    // absent in the scan payload.
    final rows = <_BodyTrendRow>[];
    for (final spec in specs) {
      final pair = _resolveBodyTrendPair(spec, sorted);
      rows.add(
        _BodyTrendRow(
          spec: spec,
          first: pair.first,
          firstAt: pair.firstAt,
          last: pair.last,
          lastAt: pair.lastAt,
          estimated: pair.estimated,
        ),
      );
    }

    // Most improved among rows with two distinct readings & beneficial diff.
    _BodyTrendRow? mostImproved;
    double bestMag = 0;
    for (final r in rows) {
      if (!r.hasBeforeAndAfter) continue;
      if (!r.isImprovement) continue;
      // Normalise magnitudes so e.g. 5 lbs of weight loss isn't dwarfed by
      // 1 point of appetite control.
      final normScale = switch (r.spec.label) {
        'Weight' => 20.0,
        'Body Fat %' => 5.0,
        'Waist Circumference' => 4.0,
        'Muscle Mass' => 5.0,
        'Appetite Control' => 3.0,
        'Body Composition Score' => 3.0,
        _ => 5.0,
      };
      final mag = r.diff.abs() / normScale;
      if (mag > bestMag) {
        bestMag = mag;
        mostImproved = r;
      }
    }

    // Body-focused stacks intentionally suppress skin metrics here — the
    // user shouldn't be anchored to facial readings while tracking weight
    // loss / muscle gain / appetite control progress.

    final rangeLabel =
        '${_formatDate(sorted.first.timestamp)} \u2192 ${_formatDate(sorted.last.timestamp)}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_rose, _gold]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.monitor_weight_outlined,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI-Powered Body Composition Trend',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textBrown,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${sorted.length} scans \u00b7 $rangeLabel',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E8E8)),
                ),
                child: const Text(
                  'AI-powered',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: _textBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Metrics estimated using evidence formulas + AI analysis when exact values are not provided.',
            style: TextStyle(fontSize: 10.5, color: _muted, height: 1.3),
          ),
          if (mostImproved != null) ...[
            const SizedBox(height: 10),
            _buildBodyMostImprovedBanner(mostImproved),
          ],
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: const Color(0xFFE5E8E8).withValues(alpha: 0.7),
          ),
          for (int i = 0; i < rows.length; i++) ...[
            _buildBodyTrendRow(rows[i]),
            if (i != rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: const Color(0xFFE5E8E8).withValues(alpha: 0.45),
              ),
          ],

          // Body-focused stacks intentionally hide all facial/skin metrics
          // so the user is never anchored to irrelevant readings. (Skin
          // metrics still surface on skin-focused stacks.)
        ],
      ),
    );
  }

  Widget _buildBodyMostImprovedBanner(_BodyTrendRow r) {
    final spec = r.spec;
    final unit = spec.unit;
    final absDiff = r.diff.abs();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB7DFB8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 14,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Most improved: ${spec.label} '
              '${r.first!.toStringAsFixed(1)}$unit \u2192 ${r.last!.toStringAsFixed(1)}$unit '
              '(${r.diff < 0 ? '-' : '+'}${absDiff.toStringAsFixed(1)}$unit ${spec.lowerIsBetter ? '↓' : '↑'})',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ({
    double? first,
    DateTime? firstAt,
    double? last,
    DateTime? lastAt,
    bool estimated,
  })
  _resolveBodyTrendPair(_BodyTrendSpec spec, List<ScanHistoryEntry> sorted) {
    final baseline = sorted.first;
    final latest = sorted.last;

    double? pick(Map<String, double> source, List<String> keys) {
      for (final key in keys) {
        final value = source[key];
        if (value != null) return value;
      }
      return null;
    }

    final baselineWeight = pick(baseline.metrics, const [
      'weightLbs',
      'weight',
    ]);
    final latestWeight = pick(latest.metrics, const ['weightLbs', 'weight']);
    final weightLost = (baselineWeight != null && latestWeight != null)
        ? baselineWeight - latestWeight
        : null;

    double? first = pick(baseline.metrics, spec.keys);
    double? last = pick(latest.metrics, spec.keys);
    var estimated = false;

    if (first != null && last != null) {
      return (
        first: first,
        firstAt: baseline.timestamp,
        last: last,
        lastAt: latest.timestamp,
        estimated: false,
      );
    }

    switch (spec.label) {
      case 'Body Fat %':
        if (baselineWeight != null &&
            latestWeight != null &&
            latestWeight > 0) {
          first ??= (baselineWeight * 0.20).clamp(8.0, 45.0);
          if (weightLost != null) {
            final estChangePct = (weightLost * 0.20) / latestWeight * 100.0;
            last ??= (first - estChangePct).clamp(2.0, 60.0);
            estimated = true;
          }
        }
        break;
      case 'Waist Circumference':
        if (baselineWeight != null && latestWeight != null) {
          first ??= (baselineWeight * 0.18).clamp(24.0, 60.0);
          if (weightLost != null) {
            last ??= (first - (weightLost * 0.18)).clamp(18.0, 60.0);
            estimated = true;
          }
        }
        break;
      case 'Muscle Mass':
        if (baselineWeight != null && latestWeight != null) {
          first ??= (baselineWeight * 0.40).clamp(20.0, 120.0);
          if (weightLost != null) {
            final leanDelta = weightLost.abs() * 0.25;
            last ??= weightLost >= 0 ? first - leanDelta : first + leanDelta;
            estimated = true;
          }
        }
        break;
      case 'Appetite Control':
      case 'Body Composition Score':
        // These are user-entered only. Leave missing values unfilled.
        break;
    }

    return (
      first: first,
      firstAt: baseline.timestamp,
      last: last,
      lastAt: latest.timestamp,
      estimated: estimated,
    );
  }

  Widget _buildBodyTrendRow(_BodyTrendRow r) {
    final spec = r.spec;
    final unit = spec.unit;
    Widget valueWidget;
    if (r.first == null) {
      valueWidget = const Text(
        '— Log to track',
        style: TextStyle(
          fontSize: 12,
          color: _muted,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w600,
        ),
      );
    } else if (!r.hasBeforeAndAfter) {
      valueWidget = Text(
        '${r.first!.toStringAsFixed(1)}$unit · single reading',
        style: const TextStyle(fontSize: 12, color: _muted),
      );
    } else {
      final isGood = r.isImprovement;
      final diff = r.diff;
      final color = diff.abs() < 0.05
          ? _muted
          : (isGood ? const Color(0xFF2E7D32) : const Color(0xFFC97C6E));
      valueWidget = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${r.first!.toStringAsFixed(1)}$unit \u2192 ${r.last!.toStringAsFixed(1)}$unit',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(width: 8),
          Icon(
            diff.abs() < 0.05
                ? Icons.remove_rounded
                : (diff < 0
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded),
            color: color,
            size: 14,
          ),
          const SizedBox(width: 2),
          Text(
            '${diff < 0 ? '-' : '+'}${diff.abs().toStringAsFixed(1)}$unit',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 125,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    spec.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _textBrown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (r.estimated) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFF1D7B5)),
                    ),
                    child: const Text(
                      'est.',
                      style: TextStyle(
                        fontSize: 9,
                        color: Color(0xFFA9762E),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  // Identifies the row with the largest positive directional improvement
  // since baseline. Returns null when no row shows a meaningful gain.
  _StackMetricRow? _mostImprovedRow(List<_StackMetricRow> rows) {
    _StackMetricRow? best;
    double bestChange = 0;
    for (final r in rows) {
      final t = resolveMetricTrend(
        r.label,
        baseline: r.baseline,
        current: r.latest,
      );
      if (!t.hasMeaningfulChange || !t.isImproved) continue;
      final magnitude = t.change.abs();
      if (magnitude > bestChange) {
        bestChange = magnitude;
        best = r;
      }
    }
    return best;
  }

  // Highlight banner: "Most improved: Dark Spots 4.5 → 3.1 (1.4 pts)".
  Widget _buildMostImprovedBanner(_StackMetricRow r) {
    final t = resolveMetricTrend(
      r.label,
      baseline: r.baseline,
      current: r.latest,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB7DFB8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 14,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Most improved: ${r.label} '
              '${r.baseline.toStringAsFixed(1)} \u2192 ${r.latest.toStringAsFixed(1)} '
              '(${t.absoluteChangeText} pts)',
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(_StackMetricRow r, {required bool singleScan}) {
    final trend = singleScan
        ? null
        : resolveMetricTrend(r.label, baseline: r.baseline, current: r.latest);
    final hasArrow = trend != null && trend.hasMeaningfulChange;
    // Body-composition rows carry raw values (lbs, %, inches) that don't
    // map onto a 0–10 visual scale, so we suppress the progress bar for
    // them and append a unit suffix to the displayed numbers instead.
    const bodyLabels = {
      'Weight',
      'Body Fat %',
      'Waist Circumference',
      'Muscle Mass',
      'Appetite Control',
      'Body Composition Score',
    };
    final isBodyRow = bodyLabels.contains(r.label);
    String unitFor(String label) {
      switch (label) {
        case 'Weight':
        case 'Muscle Mass':
          return ' lbs';
        case 'Body Fat %':
          return '%';
        case 'Waist Circumference':
          return ' in';
        default:
          return '';
      }
    }

    final unit = isBodyRow ? unitFor(r.label) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              r.label,
              style: const TextStyle(
                fontSize: 12.5,
                color: _textBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  singleScan
                      ? '${r.baseline.toStringAsFixed(1)}$unit'
                      : '${r.baseline.toStringAsFixed(1)}$unit \u2192 ${r.latest.toStringAsFixed(1)}$unit',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                if (hasArrow) ...[
                  const SizedBox(width: 8),
                  Icon(trend.icon, color: trend.color, size: 14),
                  const SizedBox(width: 2),
                  Text(
                    trend.absoluteChangeText,
                    style: TextStyle(
                      color: trend.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (!isBodyRow) ...[
                  const SizedBox(width: 10),
                  // Progress bar of the latest value on a 0–10 scale.
                  Container(
                    width: 60,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (r.latest / 10).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_rose, _gold],
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StackMetricRow {
  final String label;
  final double baseline;
  final double latest;
  const _StackMetricRow({
    required this.label,
    required this.baseline,
    required this.latest,
  });
}

/// Spec for a body-composition trend row in the always-unlocked
/// `_buildBodyFocusedCard()` path.
class _BodyTrendSpec {
  final List<String> keys;
  final String label;
  final String unit;

  /// True for Weight / Body Fat / Waist where a decrease is the goal.
  final bool lowerIsBetter;
  const _BodyTrendSpec(this.keys, this.label, this.unit, this.lowerIsBetter);
}

class _BodyTrendRow {
  final _BodyTrendSpec spec;
  final double? first;
  final DateTime? firstAt;
  final double? last;
  final DateTime? lastAt;
  final bool estimated;
  const _BodyTrendRow({
    required this.spec,
    required this.first,
    required this.firstAt,
    required this.last,
    required this.lastAt,
    this.estimated = false,
  });
  bool get hasBeforeAndAfter =>
      first != null &&
      last != null &&
      firstAt != null &&
      lastAt != null &&
      firstAt != lastAt;
  double get diff => (last ?? 0) - (first ?? 0);
  bool get isImprovement => spec.lowerIsBetter ? diff < 0 : diff > 0;
}

/// Static description for a single body-composition row rendered inside the
/// peptide detail correlation section.
class _BodyRowSpec {
  final String label;
  final List<String> keys;
  final bool lowerIsBetter;
  final String unit;
  const _BodyRowSpec(
    this.label,
    this.keys, {
    required this.lowerIsBetter,
    this.unit = '',
  });
}

class _BodyMetricsEmptyCta extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onLogBodyMetrics;
  const _BodyMetricsEmptyCta({
    required this.title,
    required this.message,
    this.onLogBodyMetrics,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _gold = Color(0xFFE3C766);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _gold.withValues(alpha: 0.10),
            _rose.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _rose.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.monitor_weight_outlined,
              color: _rose,
              size: 24,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: _textBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: _muted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (onLogBodyMetrics != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLogBodyMetrics,
                icon: const Icon(
                  Icons.add_chart_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  'Log Body Measurements',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _rose,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StackMetricsEmptyState extends StatelessWidget {
  final String message;
  const _StackMetricsEmptyState({
    this.message =
        'Take your first scan to unlock stack metrics. We\u2019ll aggregate redness, texture, wrinkles, pores, dark spots and elasticity across your peptide journey.',
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8F6F0), Color(0xFFF8F6F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _rose.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.insights_rounded, color: _rose, size: 22),
          ),
          const SizedBox(height: 10),
          const Text(
            'Stack metrics locked',
            style: TextStyle(
              fontSize: 13.5,
              color: _textBrown,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: _muted,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Per-peptide correlations ──
class _StackCorrelationList extends StatelessWidget {
  final List<PeptideCorrelationResult> results;

  /// When true, the displayed insight for each peptide is re-derived from
  /// the largest body-composition delta (Weight / Body Fat % / Waist /
  /// Muscle Mass / Appetite Control / Body Composition Score) rather than
  /// the absolute strongest skin delta — so weight-loss peptides surface
  /// their body impact instead of incidental skin readings.
  final bool isBodyFocused;
  const _StackCorrelationList({
    required this.results,
    this.isBodyFocused = false,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  static const Set<String> _bodyMetricLabels = {
    'Weight',
    'Body Fat %',
    'Waist Circumference',
    'Muscle Mass',
    'Appetite Control',
    'Body Composition Score',
  };

  /// Re-renders the auto-generated insight to highlight the strongest body
  /// metric for body-focused peptides. Falls back to the original text if
  /// the result carries no body deltas.
  String _bodyFirstInsight(PeptideCorrelationResult r) {
    final bodyEntries =
        r.metricDeltas.entries
            .where((e) => _bodyMetricLabels.contains(e.key))
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    if (bodyEntries.isEmpty) return r.insightText;
    final top = bodyEntries.first;
    final p = r.peptide;
    final conc = p.concentration != null
        ? '${p.concentration!.toStringAsFixed(1)}% '
        : '';
    final dir = top.value >= 0 ? 'improved' : 'declined';
    return 'After ${r.daysTracked}d of $conc${p.name}, '
        '${top.key} $dir by ${top.value.abs().toStringAsFixed(1)} pts.';
  }

  @override
  Widget build(BuildContext context) {
    // For body-focused stacks, hide skin-focused peptide insights entirely
    // — the user explicitly opted into a body-composition workflow.
    final visible = isBodyFocused
        ? results.where((r) => _peptideIsBodyFocused(r.peptide)).toList()
        : results;
    if (visible.isEmpty) {
      return const _EmptyScanCard(
        message:
            'Per-peptide insights appear after 2+ scans. Take a second scan to unlock correlation data.',
      );
    }
    // When the parent stack is body-focused, render body-focused peptides
    // first so the most relevant insight is at the top of the list.
    final ordered = [...visible];
    if (isBodyFocused) {
      ordered.sort((a, b) {
        final ab = _peptideIsBodyFocused(a.peptide) ? 0 : 1;
        final bb = _peptideIsBodyFocused(b.peptide) ? 0 : 1;
        return ab.compareTo(bb);
      });
    }
    return Column(
      children: [
        for (final r in ordered)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E8E8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _rose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.science_outlined,
                        size: 14,
                        color: _rose,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.peptide.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _textBrown,
                        ),
                      ),
                    ),
                    Text(
                      '${r.daysTracked}d · ${r.scansAfterCount} scan${r.scansAfterCount == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isBodyFocused && _peptideIsBodyFocused(r.peptide)
                      ? _bodyFirstInsight(r)
                      : r.insightText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _textBrown,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StackSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StackSectionHeader({
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _rose, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _textBrown,
              letterSpacing: 0.1,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 16, color: _rose),
            label: Text(
              actionLabel!,
              style: const TextStyle(
                color: _rose,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}

class _StackJournalEmptyCard extends StatelessWidget {
  final VoidCallback onAdd;
  const _StackJournalEmptyCard({required this.onAdd});

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _rose.withValues(alpha: 0.35),
            style: BorderStyle.solid,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _rose.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: _rose,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No notes yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3539),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Capture how this stack feels over time — side effects, results, '
              'energy, sleep, anything you notice. You can dictate by voice or '
              'type directly.',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _emptyStateChip(Icons.mic_rounded, 'Dictate'),
                const SizedBox(width: 8),
                _emptyStateChip(Icons.edit_note_rounded, 'Type'),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: _rose, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStateChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _rose.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _rose),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: _rose,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail sheet for peptide-scoped journal entries (PeptideJournalEntry)
// ─────────────────────────────────────────────────────────────────────────────
class _PeptideJournalDetailSheet extends StatelessWidget {
  final PeptideJournalEntry entry;
  const _PeptideJournalDetailSheet({required this.entry});

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  String _formatFull(DateTime d) {
    const months = [
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
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} \u00b7 $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _rose.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: _rose,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Journal note',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _textBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatFull(entry.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: _muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEFE0D2)),
                    ),
                    child: SelectableText(
                      entry.text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: _textBrown,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('delete'),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.kMetricWorsenedColor,
                          size: 18,
                        ),
                        label: const Text(
                          'Delete',
                          style: TextStyle(
                            color: AppColors.kMetricWorsenedColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFEFC9BC)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop('edit'),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text(
                          'Edit',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rose,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JournalDetailSheet extends StatelessWidget {
  final StackJournalEntry entry;
  const _JournalDetailSheet({required this.entry});

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  String _formatFull(DateTime d) {
    const months = [
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
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} \u00b7 $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _rose.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        entry.isVoice
                            ? Icons.mic_rounded
                            : Icons.edit_note_rounded,
                        color: _rose,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.isVoice ? 'Voice note' : 'Journal note',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _textBrown,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatFull(entry.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: _muted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (entry.isVoice) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEFE0D2)),
                    ),
                    child: Row(
                      children: [
                        Opacity(
                          opacity: 0.4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _rose.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: _rose,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Audio replay unavailable — transcript saved.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Body (scrollable transcript)
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEFE0D2)),
                    ),
                    child: SelectableText(
                      entry.text,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: _textBrown,
                      ),
                    ),
                  ),
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('delete'),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.kMetricWorsenedColor,
                          size: 18,
                        ),
                        label: const Text(
                          'Delete',
                          style: TextStyle(
                            color: AppColors.kMetricWorsenedColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFEFC9BC)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop('edit'),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text(
                          'Edit',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _rose,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StackJournalCard extends StatelessWidget {
  final StackJournalEntry entry;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const _StackJournalCard({
    required this.entry,
    required this.onDelete,
    this.onTap,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) {
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return 'Today · $h:$m';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _rose.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    entry.isVoice ? Icons.mic_rounded : Icons.edit_note_rounded,
                    color: _rose,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            entry.isVoice ? 'Voice note' : 'Journal note',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _rose,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${_formatDate(entry.createdAt)}',
                            style: const TextStyle(fontSize: 10, color: _muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: _textBrown,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _muted,
                    size: 16,
                  ),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StackTimelineList extends StatelessWidget {
  final List<_TimelineEvent> events;
  const _StackTimelineList({required this.events});

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);

  String _shortDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.month}/${d.day}/${d.year.toString().substring(2)}';
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No timeline events yet.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEFE0D2)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < events.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Indicator dot + vertical connector line
                  Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _rose.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _rose.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(events[i].icon, color: _rose, size: 12),
                      ),
                      if (i != events.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: const Color(0xFFEFE0D2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i == events.length - 1 ? 0 : 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  events[i].title,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _textBrown,
                                  ),
                                ),
                              ),
                              Text(
                                _shortDate(events[i].when),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (events[i].subtitle.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              events[i].subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: _muted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
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
}

enum _TimelineKind { stack, peptide, peptideEnd, journal }

class _TimelineEvent {
  final DateTime when;
  final IconData icon;
  final String title;
  final String subtitle;
  final _TimelineKind kind;
  const _TimelineEvent({
    required this.when,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.kind,
  });
}

class _JournalDraft {
  final String text;
  final bool isVoice;
  const _JournalDraft({required this.text, required this.isVoice});
}

class _StackJournalComposerSheet extends StatefulWidget {
  final String stackName;
  final String? initialText;
  final bool initialIsVoice;
  final bool isEditing;
  const _StackJournalComposerSheet({
    required this.stackName,
    this.initialText,
    this.initialIsVoice = false,
    this.isEditing = false,
  });

  @override
  State<_StackJournalComposerSheet> createState() =>
      _StackJournalComposerSheetState();
}

class _StackJournalComposerSheetState
    extends State<_StackJournalComposerSheet> {
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  final _ctrl = TextEditingController();
  final _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _dictating = false;
  bool _didVoice = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _ctrl.text = widget.initialText!;
      _didVoice = widget.initialIsVoice;
    }
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _dictating = false;
            _error = 'Voice error: ${e.errorMsg}';
          });
        },
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _dictating = false);
          }
        },
      );
      if (mounted) setState(() => _speechAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _toggleDictation() async {
    if (_dictating) {
      await _speech.stop();
      if (mounted) setState(() => _dictating = false);
      return;
    }
    if (!_speechAvailable) {
      setState(() => _error = 'Voice input is not available on this device.');
      return;
    }
    setState(() {
      _dictating = true;
      _didVoice = true;
      _error = null;
    });
    final existing = _ctrl.text;
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final combined = existing.isEmpty
            ? result.recognizedWords
            : '$existing ${result.recognizedWords}';
        setState(() {
          _ctrl.text = combined;
          _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
        });
      },
      listenFor: const Duration(minutes: 2),
      pauseFor: const Duration(seconds: 4),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(_JournalDraft(text: text, isVoice: _didVoice));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F6F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: bottomInset + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _rose.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_rounded, color: _rose, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isEditing ? 'Edit note' : 'Add a note',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textBrown,
                      ),
                    ),
                    Text(
                      'For ${widget.stackName}',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: _muted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
                  'How are your skin and stack feeling today? Side effects, results, observations…',
              hintStyle: const TextStyle(fontSize: 12.5, color: _muted),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEFE0D2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEFE0D2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _rose.withValues(alpha: 0.6)),
              ),
            ),
            style: const TextStyle(
              fontSize: 13,
              color: _textBrown,
              height: 1.4,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: const TextStyle(fontSize: 11, color: AppColors.kMetricWorsenedColor),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleDictation,
                  icon: Icon(
                    _dictating ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    size: 18,
                    color: _dictating ? AppColors.kMetricWorsenedColor : _rose,
                  ),
                  label: Text(
                    _dictating
                        ? 'Stop dictation'
                        : (_speechAvailable ? 'Dictate' : 'Voice unavailable'),
                    style: TextStyle(
                      color: _dictating ? AppColors.kMetricWorsenedColor : _rose,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(
                      color: (_dictating ? AppColors.kMetricWorsenedColor : _rose).withValues(
                        alpha: 0.55,
                      ),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text(
                    'Save note',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rose,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddEditPeptidePage extends StatefulWidget {
  final PeptideEntry? editing;
  final String? defaultStackId;

  /// Names of peptides already in the target stack (used to detect known
  /// interactions and show advisory banners).
  final List<String> existingStackPeptideNames;

  /// Optional callback invoked when the user picks a blend in the Popular
  /// Blends tab. Implementation should bulk-insert the blend's peptides and
  /// reload the parent screen. After it completes, the page closes itself.
  final Future<int> Function(_PopularBlend)? onAddBlend;

  const _AddEditPeptidePage({
    this.editing,
    this.defaultStackId,
    this.existingStackPeptideNames = const <String>[],
    this.onAddBlend,
  });

  @override
  State<_AddEditPeptidePage> createState() => _AddEditPeptidePageState();
}

class _AddEditPeptidePageState extends State<_AddEditPeptidePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final GlobalKey<_AddEditSheetState> _formKey =
      GlobalKey<_AddEditSheetState>();
  late final int _tabCount;

  @override
  void initState() {
    super.initState();
    final isEdit = widget.editing != null;
    // Tabs: Manual + Library (+ Popular Blends when adding new and a bulk
    // handler is provided).
    _tabCount = isEdit ? 1 : (widget.onAddBlend != null ? 3 : 2);
    _tabs = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onLibraryPick(PeptideLibraryEntry lib) {
    _formKey.currentState?.applyLibraryEntry(lib);
    _tabs.animateTo(0);
  }

  Future<void> _onBlendPick(_PopularBlend blend) async {
    if (widget.onAddBlend == null) return;
    final added = await widget.onAddBlend!(blend);
    if (!mounted) return;
    Navigator.of(context).pop();
    // Provide a quick confirmation via the calling screen — handled there.
    // We pop synchronously so the user sees the stack update immediately.
    // Defensive no-op if 0 added (callback didn't insert anything).
    if (added <= 0) return;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    final showTabs = _tabCount > 1;
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: const Color(0xFF2C3539),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
            isEdit ? 'Edit Peptide' : 'Add Peptide',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C3539),
          ),
        ),
        centerTitle: true,
        bottom: showTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(46),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F6F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E8E8)),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    isScrollable: false,
                    indicator: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorPadding: const EdgeInsets.all(3),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: const Color(0xFF7E868B),
                    labelPadding: EdgeInsets.zero,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: [
                      const Tab(text: 'Manual Entry'),
                      const Tab(text: 'Library'),
                      if (_tabCount == 3) const Tab(text: 'Popular Blends'),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: showTabs
          ? TabBarView(
              controller: _tabs,
              children: [
                _AddEditSheet(
                  key: _formKey,
                  editing: widget.editing,
                  isNew: false,
                  recoveryMode: false,
                  defaultStackId: widget.defaultStackId,
                  existingStackPeptideNames: widget.existingStackPeptideNames,
                ),
                _LibraryPickerTab(
                  onPick: _onLibraryPick,
                  existingStackPeptideNames: widget.existingStackPeptideNames,
                ),
                if (_tabCount == 3)
                  _PopularBlendsTab(
                    onPick: _onBlendPick,
                    existingStackPeptideNames: widget.existingStackPeptideNames,
                  ),
              ],
            )
          : _AddEditSheet(
              key: _formKey,
              editing: widget.editing,
              isNew: false,
              recoveryMode: false,
              defaultStackId: widget.defaultStackId,
              existingStackPeptideNames: widget.existingStackPeptideNames,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Library picker tab — searchable, popularity-sorted list of all peptides
// ─────────────────────────────────────────────────────────────────────────────

class _LibraryPickerTab extends StatefulWidget {
  final ValueChanged<PeptideLibraryEntry> onPick;
  final List<String> existingStackPeptideNames;
  const _LibraryPickerTab({
    required this.onPick,
    this.existingStackPeptideNames = const <String>[],
  });

  @override
  State<_LibraryPickerTab> createState() => _LibraryPickerTabState();
}

class _LibraryPickerTabState extends State<_LibraryPickerTab> {
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Popularity ranking: lower = more popular. We blend the curated order in
  /// `kPeptideLibrary` with the evidence tier so well-studied peptides come
  /// first within the same popularity bucket.
  int _popularity(PeptideLibraryEntry e, int index) {
    final tierWeight = switch (e.evidenceLevel) {
      'Tier 1' => 0,
      'Tier 2' => 100,
      'Tier 3' => 200,
      _ => 300,
    };
    return tierWeight + index;
  }

  List<PeptideLibraryEntry> get _sortedLibrary {
    final indexed = <MapEntry<int, PeptideLibraryEntry>>[];
    for (int i = 0; i < kPeptideLibrary.length; i++) {
      indexed.add(MapEntry(i, kPeptideLibrary[i]));
    }
    indexed.sort(
      (a, b) =>
          _popularity(a.value, a.key).compareTo(_popularity(b.value, b.key)),
    );
    return indexed.map((e) => e.value).toList();
  }

  List<PeptideLibraryEntry> _filtered() {
    final q = _query.trim().toLowerCase();
    final base = _sortedLibrary;
    if (q.isEmpty) return base;
    return base.where((e) {
      if (e.name.toLowerCase().contains(q)) return true;
      if (e.inci.toLowerCase().contains(q)) return true;
      if (e.category.toLowerCase().contains(q)) return true;
      if (e.primaryMetrics.any((m) => m.toLowerCase().contains(q))) return true;
      if (e.mechanism.toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    final inStack = widget.existingStackPeptideNames
        .map((n) => n.toLowerCase())
        .toSet();
    return SafeArea(
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: _textBrown, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search peptides, benefits, INCI...',
                hintStyle: const TextStyle(
                  color: Color(0xFF9AA0A4),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: _muted,
                  size: 20,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: _muted,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: const Color(0xFFF8F6F0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E8E8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE5E8E8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _rose, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: _rose,
                ),
                const SizedBox(width: 6),
                Text(
                  '${items.length} peptide${items.length == 1 ? '' : 's'} \u00b7 sorted by popularity',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.science_outlined, size: 36, color: _muted),
                          SizedBox(height: 10),
                          Text(
                            'No peptides match your search',
                            style: TextStyle(
                              fontSize: 13,
                              color: _textBrown,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Try a benefit (e.g. "wrinkles") or an INCI name.',
                            style: TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final lib = items[i];
                      final conc = _kTypicalConcentrations[lib.name];
                      final alreadyInStack = inStack.contains(
                        lib.name.toLowerCase(),
                      );
                      return _LibraryItemCard(
                        lib: lib,
                        typicalConcentration: conc,
                        alreadyInStack: alreadyInStack,
                        onTap: () => widget.onPick(lib),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LibraryItemCard extends StatelessWidget {
  final PeptideLibraryEntry lib;
  final double? typicalConcentration;
  final bool alreadyInStack;
  final VoidCallback onTap;

  const _LibraryItemCard({
    required this.lib,
    required this.typicalConcentration,
    required this.alreadyInStack,
    required this.onTap,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _gold = Color(0xFFE3C766);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  String _formatConc(double v) {
    if (v < 0.1) return '${v.toStringAsFixed(3)}%';
    if (v < 1) return '${v.toStringAsFixed(2)}%';
    return '${v.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final benefits = lib.primaryMetrics;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E8E8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_rose, _gold]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                lib.name,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: _textBrown,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _EvidenceBadge(level: lib.evidenceLevel),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lib.inci,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: _muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (typicalConcentration != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1EEE6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _formatConc(typicalConcentration!),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _rose,
                        ),
                      ),
                    ),
                ],
              ),
              if (lib.mechanism.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  lib.mechanism,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _textBrown,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (benefits.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in benefits)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _rose.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          b,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: _rose,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (alreadyInStack) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 13,
                      color: Color(0xFF2E7D32),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Already in this stack',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Popular Blends tab — curated multi-peptide stacks added in a single tap
// ─────────────────────────────────────────────────────────────────────────────

class _PopularBlendsTab extends StatelessWidget {
  final Future<void> Function(_PopularBlend) onPick;
  final List<String> existingStackPeptideNames;
  const _PopularBlendsTab({
    required this.onPick,
    this.existingStackPeptideNames = const <String>[],
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    final existing = existingStackPeptideNames
        .map((n) => n.toLowerCase())
        .toSet();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F6F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E8E8)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: _rose,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Curated combinations real users swear by. One tap adds the entire blend to your stack.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _textBrown,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final blend in _kPopularBlends) ...[
            _BlendCard(
              blend: blend,
              alreadyInStack: blend.peptideNames.every(
                (n) => existing.contains(n.toLowerCase()),
              ),
              overlapCount: blend.peptideNames
                  .where((n) => existing.contains(n.toLowerCase()))
                  .length,
              onTap: () => onPick(blend),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          const Center(
            child: Text(
              'Always introduce new peptides gradually and monitor your skin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: _muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlendCard extends StatelessWidget {
  final _PopularBlend blend;
  final bool alreadyInStack;
  final int overlapCount;
  final VoidCallback onTap;
  const _BlendCard({
    required this.blend,
    required this.alreadyInStack,
    required this.overlapCount,
    required this.onTap,
  });

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E8E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header band
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: blend.gradient),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(blend.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          blend.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          blend.tagline,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Benefits chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final b in blend.benefits)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _rose.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            b,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: _rose,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Peptide list
                  const Text(
                    'CONTAINS',
                    style: TextStyle(
                      fontSize: 10,
                      color: _muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final p in blend.peptideNames)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(
                              Icons.fiber_manual_record,
                              size: 7,
                              color: _rose,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (_) {
                                final lib = kPeptideLibrary
                                    .where((e) => e.name == p)
                                    .firstOrNull;
                                final description = lib?.mechanism ?? '';
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: _textBrown,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        description,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _muted,
                                          fontStyle: FontStyle.italic,
                                          height: 1.35,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Interaction advisory for the blend itself
                  Builder(
                    builder: (_) {
                      final warnings = peptideInteractionWarnings(
                        blend.peptideNames,
                      );
                      if (warnings.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _PeptideInteractionBanner(warnings: warnings),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: alreadyInStack ? null : onTap,
                      icon: Icon(
                        alreadyInStack
                            ? Icons.check_circle_rounded
                            : Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        alreadyInStack
                            ? 'Already in your stack'
                            : overlapCount > 0
                            ? 'Add ${blend.peptideNames.length - overlapCount} new peptide${blend.peptideNames.length - overlapCount == 1 ? '' : 's'}'
                            : 'Add Entire Blend to Stack',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _rose,
                        disabledBackgroundColor: const Color(0xFFC9B7AA),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
}

// ── Body Metrics Entry Sheet ──────────────────────────────────────────────────
/// Top-level helper that presents the [_BodyMetricsEntrySheet] as a
/// non-dismissible modal bottom sheet. Returns the entered map (only the
/// fields that were filled in) or null if the user chose Skip.
Future<Map<String, double>?> showBodyMetricsEntrySheet(
  BuildContext context, {
  required String procedureId,
  bool justAfterScan = false,
}) {
  return showModalBottomSheet<Map<String, double>?>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _BodyMetricsEntrySheet(
      procedureId: procedureId,
      justAfterScan: justAfterScan,
    ),
  );
}

/// Modal bottom-sheet that lets the user enter their current body composition
/// measurements immediately after a camera scan for a body-focused stack.
/// Returns a [Map<String,double>] of only the fields that were filled in, or
/// null if the user dismisses without saving.
class _BodyMetricsEntrySheet extends StatefulWidget {
  final String procedureId;

  /// When true the header indicates the sheet was opened right after a scan
  /// completed. When false it reads as a manual update.
  final bool justAfterScan;
  const _BodyMetricsEntrySheet({
    required this.procedureId,
    this.justAfterScan = false,
  });

  @override
  State<_BodyMetricsEntrySheet> createState() => _BodyMetricsEntrySheetState();
}

class _BodyMetricsEntrySheetState extends State<_BodyMetricsEntrySheet> {
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);
  static const Color _gold = Color(0xFFE3C766);

  // controllers
  final _weightCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _muscleCtrl = TextEditingController();
  final _appetiteCtrl = TextEditingController();
  final _bodyCompCtrl = TextEditingController();
  final _weightFocus = FocusNode();

  bool _showMore = false;

  // Last-known reference values from prior scans (for auto-estimates).
  double? _lastWeight;
  double? _lastWaist;
  double? _lastBodyFat;

  @override
  void initState() {
    super.initState();
    _loadReferenceMetrics();
    // Autofocus the primary Weight field after the sheet animates in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _weightFocus.requestFocus();
    });
  }

  Future<void> _loadReferenceMetrics() async {
    try {
      final all = await AppPrefs.getScanHistory();
      final scoped =
          all.where((s) => s.procedureId == widget.procedureId).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      for (final s in scoped) {
        _lastWeight ??= s.metrics['weightLbs'];
        _lastWaist ??= s.metrics['waistInches'];
        _lastBodyFat ??= s.metrics['bodyFatPct'];
        if (_lastWeight != null && _lastWaist != null && _lastBodyFat != null) {
          break;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Best-effort — auto-estimates simply won't show.
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    _waistCtrl.dispose();
    _muscleCtrl.dispose();
    _appetiteCtrl.dispose();
    _bodyCompCtrl.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  double? get _weightInput => double.tryParse(_weightCtrl.text.trim());

  /// Estimate waist (inches) from current vs prior weight.
  /// Heuristic: ~0.15 inch of waist change per pound of weight change.
  double? get _estimatedWaist {
    final w = _weightInput;
    if (w == null || _lastWeight == null || _lastWaist == null) return null;
    final dW = w - _lastWeight!;
    if (dW.abs() < 0.5) return _lastWaist; // negligible change
    return (_lastWaist! + dW * 0.15).clamp(20.0, 80.0);
  }

  /// Estimate body fat % from current vs prior weight.
  /// Heuristic: ~0.20 % body-fat change per pound of weight change.
  double? get _estimatedBodyFat {
    final w = _weightInput;
    if (w == null || _lastWeight == null || _lastBodyFat == null) return null;
    final dW = w - _lastWeight!;
    if (dW.abs() < 0.5) return _lastBodyFat;
    return (_lastBodyFat! + dW * 0.20).clamp(2.0, 60.0);
  }

  bool get _hasAnyInput {
    return [
      _weightCtrl,
      _bodyFatCtrl,
      _waistCtrl,
      _muscleCtrl,
      _appetiteCtrl,
      _bodyCompCtrl,
    ].any((c) => c.text.trim().isNotEmpty);
  }

  Map<String, double>? _buildResult() {
    final result = <String, double>{};
    void tryAdd(String key, TextEditingController ctrl) {
      final v = double.tryParse(ctrl.text.trim());
      if (v != null) result[key] = v;
    }

    tryAdd('weightLbs', _weightCtrl);
    tryAdd('bodyFatPct', _bodyFatCtrl);
    tryAdd('waistInches', _waistCtrl);
    tryAdd('muscleMassLbs', _muscleCtrl);
    tryAdd('satietyScore', _appetiteCtrl);
    tryAdd('bodyCompositionScore', _bodyCompCtrl);

    // Auto-fill estimated Waist / Body Fat % when the user only entered
    // Weight. Only apply when the user hasn't typed in those fields and
    // we have a previous reading to anchor against.
    if (result.containsKey('weightLbs')) {
      if (!result.containsKey('waistInches')) {
        final est = _estimatedWaist;
        if (est != null) {
          result['waistInches'] = double.parse(est.toStringAsFixed(1));
        }
      }
      if (!result.containsKey('bodyFatPct')) {
        final est = _estimatedBodyFat;
        if (est != null) {
          result['bodyFatPct'] = double.parse(est.toStringAsFixed(1));
        }
      }
    }
    return result.isEmpty ? null : result;
  }

  Future<void> _confirmSkip() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text(
          'Skip measurements?',
          style: TextStyle(color: _textBrown, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Body metrics won\u2019t appear in Stack Metrics until you log at least one number. You can always come back and add them later.',
          style: TextStyle(color: _muted, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep logging'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Skip',
              style: TextStyle(color: _rose, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (proceed == true && mounted) {
      Navigator.of(context).pop<Map<String, double>?>(null);
    }
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController ctrl, {
    FocusNode? focusNode,
    bool primary = false,
  }) {
    final accent = primary ? _rose : _muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        focusNode: focusNode,
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        style: TextStyle(
          color: _textBrown,
          fontSize: primary ? 18 : 14,
          fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(
            color: accent,
            fontSize: primary ? 14 : 13,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
          ),
          hintStyle: TextStyle(
            color: _muted.withValues(alpha: 0.6),
            fontSize: 13,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: primary ? 14 : 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: primary
                  ? _rose.withValues(alpha: 0.6)
                  : _muted.withValues(alpha: 0.3),
              width: primary ? 1.5 : 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: primary
                  ? _rose.withValues(alpha: 0.6)
                  : _muted.withValues(alpha: 0.3),
              width: primary ? 1.5 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _rose, width: 2),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * 0.92;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + mq.viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // drag handle (decorative — sheet is non-dismissible)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title row with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _rose.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.monitor_weight_outlined,
                      color: _rose,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Log Body Measurements',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _textBrown,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Explanation banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _gold.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.justAfterScan
                          ? 'Photo saved \u2728 Just enter your Weight to track progress.'
                          : 'Quick log — just your Weight is enough.',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _textBrown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'You only need to enter Weight for basic tracking. Optional fields give deeper insights.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // ── Primary field: Weight ─────────────────────────────────
              _field(
                'Weight (lbs) — required',
                'e.g. 172.5',
                _weightCtrl,
                focusNode: _weightFocus,
                primary: true,
              ),
              // Auto-estimate preview (shows once weight is entered AND we
              // have prior reference measurements to anchor against).
              if (_weightInput != null &&
                  (_estimatedWaist != null || _estimatedBodyFat != null)) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: _rose.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _rose.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, size: 14, color: _rose),
                          SizedBox(width: 6),
                          Text(
                            'Auto-estimated from weight change',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _rose,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (_estimatedWaist != null)
                            'Waist ≈ ${_estimatedWaist!.toStringAsFixed(1)}"',
                          if (_estimatedBodyFat != null)
                            'Body Fat ≈ ${_estimatedBodyFat!.toStringAsFixed(1)}%',
                        ].join('   •   '),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _textBrown,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'These fill in automatically. Add exact numbers below for more accuracy.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: _muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // ── Appetite Control (always visible — key metric for GLP-1 / body peptides) ──
              _field(
                'Appetite Control (0–10)',
                '0 = poor control  ·  10 = excellent control',
                _appetiteCtrl,
              ),
              // ── Expandable: optional detailed fields ──────────────────
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _showMore = !_showMore),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _showMore
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: _rose,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showMore
                            ? 'Hide optional fields'
                            : 'Add more measurements (optional)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _rose,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showMore) ...[
                _field('Body Fat %', 'e.g. 22.0', _bodyFatCtrl),
                _field('Waist (inches)', 'e.g. 34.0', _waistCtrl),
                _field('Muscle Mass (lbs)', 'e.g. 130.0', _muscleCtrl),
                _field(
                  'Body Composition Score (0–10)',
                  'e.g. 6',
                  _bodyCompCtrl,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _confirmSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: _muted,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Skip for now'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _hasAnyInput
                          ? () {
                              final result = _buildResult();
                              Navigator.of(
                                context,
                              ).pop<Map<String, double>?>(result);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _rose,
                        disabledBackgroundColor: _rose.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Measurements',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result returned by `_AddEditPeptidePage` / `_AddEditSheet` when the user
/// completes the form. When `takeScan` is true the parent launches the camera
/// immediately after persisting `entry`, so the new peptide flows straight
/// into a baseline scan without a manual second tap.
class _AddPeptideResult {
  final PeptideEntry entry;
  final bool takeScan;
  const _AddPeptideResult({required this.entry, this.takeScan = false});
}

class _AddEditSheet extends StatefulWidget {
  final PeptideEntry? editing;
  final bool isNew;
  final bool recoveryMode;
  final String? defaultStackId;
  final List<String> existingStackPeptideNames;
  const _AddEditSheet({
    super.key,
    this.editing,
    this.isNew = false,
    this.recoveryMode = false,
    this.defaultStackId,
    this.existingStackPeptideNames = const <String>[],
  });

  @override
  State<_AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<_AddEditSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _concCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _frequency = 'Once daily';
  String _category = 'anti-aging';
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _hasEndDate = false;

  List<PeptideLibraryEntry> _suggestions = [];
  final _frequencyOptions = [
    'Once daily',
    'Twice daily',
    'Every other day',
    'Weekly',
    'As directed',
  ];
  final _categoryOptions = [
    'anti-aging',
    'brightening',
    'healing',
    'firming',
    'body-composition',
    'other',
  ];

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null && !widget.isNew) {
      _nameCtrl.text = e.name;
      _concCtrl.text = e.concentration?.toStringAsFixed(1) ?? '';
      _notesCtrl.text = e.notes;
      _frequency = e.frequency;
      _category = e.category;
      _startDate = e.startDate;
      _endDate = e.endDate;
      _hasEndDate = e.endDate != null;
    } else if (e != null && widget.isNew) {
      // Seeded values from a recovery-stack flow
      _frequency = e.frequency;
      _category = e.category;
      _startDate = e.startDate;
    }
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _concCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final q = _nameCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Hide dropdown once user has typed the exact full name of a picked entry
    // (prevents the list lingering after auto-fill).
    final exact = kPeptideLibrary.any((e) => e.name.toLowerCase() == q);
    if (exact) {
      setState(() => _suggestions = []);
      return;
    }
    // Rank: exact prefix matches first, then contains (name / inci / benefit)
    final startsWith = kPeptideLibrary
        .where((e) => e.name.toLowerCase().startsWith(q))
        .toList();
    final contains = kPeptideLibrary.where((e) {
      final n = e.name.toLowerCase();
      if (n.startsWith(q)) return false;
      return n.contains(q) ||
          e.inci.toLowerCase().contains(q) ||
          e.primaryMetrics.any((m) => m.toLowerCase().contains(q));
    }).toList();
    final matches = [...startsWith, ...contains].take(6).toList();
    setState(() => _suggestions = matches);
  }

  /// Populates the form with values from a curated library entry. Called by
  /// the parent `_AddEditPeptidePage` when the user picks an entry from the
  /// Library tab.
  void applyLibraryEntry(PeptideLibraryEntry lib) {
    _nameCtrl.text = lib.name;
    _nameCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: lib.name.length),
    );
    final conc = _kTypicalConcentrations[lib.name];
    if (conc != null) {
      _concCtrl.text = conc.toStringAsFixed(conc < 1 ? 3 : 1);
    }
    if (_notesCtrl.text.trim().isEmpty) {
      final benefits = lib.primaryMetrics.isNotEmpty
          ? 'Benefits: ${lib.primaryMetrics.join(', ')}'
          : '';
      final mech = lib.mechanism.isNotEmpty
          ? 'Mechanism: ${lib.mechanism}'
          : '';
      _notesCtrl.text = [benefits, mech].where((s) => s.isNotEmpty).join('\n');
    }
    setState(() {
      _category = lib.category;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  /// Computes interaction warnings between the candidate name in the form
  /// and the existing peptides in the target stack.
  List<String> _currentInteractionWarnings() {
    final candidate = _nameCtrl.text.trim();
    final names = <String>[
      ...widget.existingStackPeptideNames,
      if (candidate.isNotEmpty) candidate,
    ];
    return peptideInteractionWarnings(names);
  }

  void _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : (_endDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFD4AF37),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _submit({bool takeScan = false}) {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final id = (widget.editing != null && !widget.isNew)
        ? widget.editing!.id
        : 'peptide_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';

    final entry = PeptideEntry(
      id: id,
      name: _nameCtrl.text.trim(),
      concentration: double.tryParse(_concCtrl.text.trim()),
      frequency: _frequency,
      startDate: _startDate,
      endDate: _hasEndDate ? _endDate : null,
      notes: _notesCtrl.text.trim(),
      category: _category,
      stackId: widget.defaultStackId ?? widget.editing?.stackId,
    );

    Navigator.of(
      context,
    ).pop(_AddPeptideResult(entry: entry, takeScan: takeScan));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.editing != null && !widget.isNew;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPad),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),

              if (widget.recoveryMode)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.healing_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recovery Stack',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pre-seeded for healing & repair. Try GHK-Cu, EGF, AHK-Cu, or Palmitoyl Tetrapeptide-7.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Name field
              const _Label('Peptide Name *'),
              TextFormField(
                controller: _nameCtrl,
                decoration: _inputDecoration('e.g. Matrixyl 3000'),
                style: const TextStyle(color: _textBrown),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                textCapitalization: TextCapitalization.words,
              ),
              // Clinical description for the matched library entry
              Builder(
                builder: (_) {
                  final typed = _nameCtrl.text.trim().toLowerCase();
                  if (typed.isEmpty) return const SizedBox.shrink();
                  final match = kPeptideLibrary
                      .where((e) => e.name.toLowerCase() == typed)
                      .firstOrNull;
                  if (match == null || match.mechanism.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F6F0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E8E8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.science_outlined,
                            size: 14,
                            color: _rose,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Suggested action',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _rose,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _EvidenceBadge(level: match.evidenceLevel),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                match.mechanism,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: _textBrown,
                                  fontStyle: FontStyle.italic,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              // Interaction advisory (existing stack peptides ± candidate)
              Builder(
                builder: (_) {
                  final warnings = _currentInteractionWarnings();
                  if (warnings.isEmpty) return const SizedBox.shrink();
                  return _PeptideInteractionBanner(
                    warnings: warnings,
                    margin: const EdgeInsets.only(top: 10),
                  );
                },
              ),
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E8E8)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          color: const Color(0xFFFBF4ED),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 12,
                                color: Color(0xFF7E868B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_suggestions.length} match${_suggestions.length == 1 ? '' : 'es'} from peptide library',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: Color(0xFF7E868B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...List.generate(_suggestions.length, (i) {
                          final lib = _suggestions[i];
                          final conc = _kTypicalConcentrations[lib.name];
                          return InkWell(
                            onTap: () => applyLibraryEntry(lib),
                            child: Container(
                              decoration: BoxDecoration(
                                border: i < _suggestions.length - 1
                                    ? const Border(
                                        bottom: BorderSide(
                                          color: Color(0xFFEDEBE3),
                                          width: 0.8,
                                        ),
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFFD4AF37,
                                      ).withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.science_outlined,
                                      size: 14,
                                      color: Color(0xFFD4AF37),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                lib.name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: _textBrown,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            _EvidenceBadge(
                                              level: lib.evidenceLevel,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          lib.mechanism.isNotEmpty
                                              ? lib.mechanism
                                              : (lib.primaryMetrics.isNotEmpty
                                                    ? lib.primaryMetrics
                                                          .take(2)
                                                          .join(' • ')
                                                    : lib.category),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                            height: 1.3,
                                            color: Color(0xFF7E868B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (conc != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1EEE6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${conc < 1 ? conc.toStringAsFixed(conc < 0.1 ? 3 : 2) : conc.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF7E868B),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.north_west_rounded,
                                    size: 12,
                                    color: Color(0xFFD4AF37),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 14),

              // Concentration
              const _Label('Concentration % (optional)'),
              TextFormField(
                controller: _concCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,3}\.?\d{0,2}'),
                  ),
                ],
                decoration: _inputDecoration('e.g. 5.0'),
                style: const TextStyle(color: _textBrown),
              ),

              const SizedBox(height: 14),

              // Frequency
              const _Label('Frequency *'),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: _inputDecoration(null),
                style: const TextStyle(color: _textBrown, fontSize: 14),
                items: _frequencyOptions
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() => _frequency = v!),
              ),

              const SizedBox(height: 14),

              // Category
              const _Label('Category *'),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: _inputDecoration(null),
                style: const TextStyle(color: _textBrown, fontSize: 14),
                items: _categoryOptions
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c, child: Text(_catLabel(c))),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),

              const SizedBox(height: 14),

              // Start date
              const _Label('Start Date *'),
              _DatePickerRow(
                date: _startDate,
                onTap: () => _pickDate(isStart: true),
              ),

              const SizedBox(height: 14),

              // End date toggle
              Row(
                children: [
                  const Expanded(child: _Label('Discontinued?')),
                  Switch(
                    value: _hasEndDate,
                    activeThumbColor: _rose,
                    onChanged: (v) => setState(() {
                      _hasEndDate = v;
                      if (v && _endDate == null) {
                        _endDate = DateTime.now();
                      }
                    }),
                  ),
                ],
              ),
              if (_hasEndDate) ...[
                const SizedBox(height: 6),
                _DatePickerRow(
                  date: _endDate ?? DateTime.now(),
                  onTap: () => _pickDate(isStart: false),
                ),
              ],

              const SizedBox(height: 14),

              // Notes
              const _Label('Notes (optional)'),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration: _inputDecoration(
                  'e.g. Applied after serum step, tolerate well...',
                ),
                style: const TextStyle(color: _textBrown),
              ),

              const SizedBox(height: 24),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rose,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    isEdit
                        ? 'Save Changes'
                        : (widget.defaultStackId != null
                              ? 'Add to Stack'
                              : 'Add Peptide'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _submit(takeScan: true),
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: const Text(
                      'Save & Take Baseline Scan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _rose,
                      side: BorderSide(color: _rose.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA0A4), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8F6F0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E8E8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E8E8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  String _catLabel(String c) {
    const map = {
      'anti-aging': 'Anti-Aging',
      'brightening': 'Brightening',
      'healing': 'Healing & Repair',
      'firming': 'Firming',
      'body-composition': 'Body Composition',
      'other': 'Other',
    };
    return map[c] ?? c;
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF7E868B),
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  const _DatePickerRow({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E8E8)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: Color(0xFFD4AF37),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF2C3539),
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD4AF37)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Peptide Detail Sheet — tapped from My Stack
// ─────────────────────────────────────────────────────────────────────────────

class _PeptideDetailSheet extends StatefulWidget {
  final PeptideEntry entry;
  final String stackName;
  final PeptideCorrelationResult? correlation;
  final List<ScanHistoryEntry> allScans;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Triggered when the user taps the in-page "Take Scan" CTA. Should
  /// open the camera, persist the scan, and complete only when the scan
  /// flow has finished. The detail page will then reload its own data via
  /// [onRefresh] without popping or re-pushing the route.
  final Future<void> Function() onTakeScan;
  final VoidCallback onAddAnother;
  final VoidCallback onRenameStack;

  /// Returns the freshest scoped scans + correlation for this peptide after
  /// a scan has been saved. The detail page calls this after [onTakeScan]
  /// completes and rebuilds Before & After / Correlation in place.
  final Future<
    ({List<ScanHistoryEntry> scans, PeptideCorrelationResult? correlation})
  >
  Function()?
  onRefresh;

  /// When true the widget fills the full screen (pushed as a Navigator page).
  /// When false (default) it renders as a bottom-sheet container.
  final bool isPage;

  /// True when this peptide is the only active peptide in its stack — i.e.
  /// it's being tracked as a single/standalone peptide rather than as part
  /// of a multi-peptide stack. Used to swap labels from "My Stack" to
  /// "My Peptide" so the UI matches the user's mental model.
  final bool isStandalone;

  const _PeptideDetailSheet({
    required this.entry,
    required this.stackName,
    this.correlation,
    required this.allScans,
    required this.onEdit,
    required this.onDelete,
    required this.onTakeScan,
    required this.onAddAnother,
    required this.onRenameStack,
    this.onRefresh,
    this.isPage = false,
    this.isStandalone = false,
  });

  @override
  State<_PeptideDetailSheet> createState() => _PeptideDetailSheetState();
}

class _PeptideDetailSheetState extends State<_PeptideDetailSheet> {
  List<PeptideJournalEntry> _journalEntries = [];
  bool _loadingJournal = true;
  bool _showCompareScans = true;

  // Local mirror of the scans + correlation so we can refresh in place
  // after the user takes a new scan, without popping/re-pushing this page.
  late List<ScanHistoryEntry> _scans = widget.allScans;
  late PeptideCorrelationResult? _correlation = widget.correlation;

  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _bg = Color(0xFFFDFBF7);
  static const Color _surface = Color(0xFFF8F6F0);
  static const Color _divider = Color(0xFFF0EEE8);

  @override
  void initState() {
    super.initState();
    _loadJournal();
  }

  /// Awaits the parent's [onTakeScan], then re-fetches scoped scans and
  /// correlation via [onRefresh] (when provided) so Before & After, the
  /// Body Composition Trend, skin metrics and the correlation section
  /// update in place \u2014 the user never has to leave & re-open the page.
  Future<void> _handleTakeScan() async {
    await widget.onTakeScan();
    if (!mounted) return;
    final refresh = widget.onRefresh;
    if (refresh != null) {
      final next = await refresh();
      if (!mounted) return;
      setState(() {
        // Always rebuild from a fresh list reference so child widgets that
        // compare by identity also pick up the new data.
        _scans = List<ScanHistoryEntry>.from(next.scans);
        _correlation = next.correlation;
      });
    } else {
      // No refresh hook provided \u2014 still trigger a rebuild so any state
      // that depends on the current scan list re-evaluates.
      setState(() {});
    }
  }

  /// Opens the body-measurements entry sheet and patches the most recent scan
  /// with the entered values, then refreshes the detail page in place.
  Future<void> _logBodyMetrics() async {
    final procedureId = _scans.isNotEmpty ? _scans.last.procedureId : null;
    if (procedureId == null || !mounted) return;
    final entered = await showBodyMetricsEntrySheet(
      context,
      procedureId: procedureId,
    );
    if (entered == null || entered.isEmpty || !mounted) return;
    await AppPrefs.patchScanMetrics(_scans.last.id, entered);
    final refresh = widget.onRefresh;
    if (refresh != null && mounted) {
      final next = await refresh();
      if (mounted) {
        setState(() {
          _scans = List<ScanHistoryEntry>.from(next.scans);
          _correlation = next.correlation;
        });
      }
    }
  }

  Future<void> _loadJournal() async {
    final entries = await PeptideService.loadJournal(widget.entry.id);
    if (mounted) {
      setState(() {
        _journalEntries = entries;
        _loadingJournal = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildHandle(),
        _buildScanButton(),
        _buildQuickActions(),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildTimeline()),
              SliverToBoxAdapter(child: _buildCorrelationSection()),
              SliverToBoxAdapter(child: _buildJournalSection()),
              SliverToBoxAdapter(child: _buildFooterActions()),
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ),
        ),
      ],
    );

    if (widget.isPage) {
      return Scaffold(
        backgroundColor: _bg,
        body: SafeArea(child: content),
      );
    }

    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.92,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: content,
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 4),
      child: Row(
        children: [
          // Back to My Stack (or "My Peptide" when this is a standalone
          // single-peptide stack so the label matches the user's flow).
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0EEE8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: Color(0xFF7E868B),
                  ),
                  Text(
                    widget.isStandalone ? 'My Peptide' : 'My Stack',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7E868B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Centered drag pill
          Expanded(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4B9AE),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Balance spacer so pill stays centered
          const SizedBox(width: 76),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: GestureDetector(
        onTap: _handleTakeScan,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD4AF37), Color(0xFFE3C766)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Take New Scan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 6),
              Text(
                '· updates your insights',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onAddAnother,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: const Text('Add Another Peptide to Stack'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3539),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addJournalNote,
                  icon: const Icon(Icons.mic_none_rounded, size: 16),
                  label: const Text('Voice Journal'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _rose,
                    side: const BorderSide(color: _rose),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.format_list_bulleted_rounded,
                    size: 16,
                  ),
                  label: Text(
                    widget.isStandalone
                        ? 'View Full Peptide'
                        : 'View Full Stack',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _rose,
                    side: const BorderSide(color: _rose),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final libEntry = kPeptideLibrary
        .where((l) => l.name.toLowerCase() == widget.entry.name.toLowerCase())
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.entry.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _textBrown,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: widget.entry.isActive
                      ? AppColors.kMetricImprovedColor.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: widget.entry.isActive
                        ? AppColors.kMetricImprovedColor.withValues(alpha: 0.4)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  widget.entry.isActive ? 'Active' : 'Discontinued',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.entry.isActive
                        ? AppColors.kMetricImprovedColor
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _categoryChip(widget.entry.category),
              if (libEntry != null)
                _EvidenceBadge(level: libEntry.evidenceLevel),
              if (widget.entry.concentration != null)
                _infoChip(
                  '${widget.entry.concentration!.toStringAsFixed(1)}%',
                  Icons.science_outlined,
                ),
              _infoChip(widget.entry.frequency, Icons.schedule_outlined),
            ],
          ),
          const SizedBox(height: 10),
          _buildClinicalSection(libEntry),
          if (libEntry != null && libEntry.inci.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'INCI: ${libEntry.inci}',
              style: const TextStyle(
                fontSize: 10,
                color: _muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const Divider(height: 20, color: _divider),
        ],
      ),
    );
  }

  Widget _buildClinicalSection(PeptideLibraryEntry? libEntry) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0CEBC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 14, color: _rose),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Evidence Benefits and Claims',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Stack: ${widget.stackName}',
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (libEntry != null) ...[
            Text(
              'Evidence tier: ${libEntry.evidenceLevel}',
              style: const TextStyle(
                fontSize: 11,
                color: _textBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: libEntry.primaryMetrics
                  .map(
                    (metric) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E8E8)),
                      ),
                      child: Text(
                        metric,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF5B6469),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Claim: ${libEntry.clinicalNote}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF5B6469),
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            const Text(
              'Evidence tier: Not available',
              style: TextStyle(
                fontSize: 11,
                color: _textBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Evidence benefits and claims are not yet available for this peptide. You can still track scans and journal outcomes.',
              style: TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final e = widget.entry;
    final days = e.daysTracked;
    final progress = (days / 90.0).clamp(0.0, 1.0);
    final months = [
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
    ];
    String fmtDate(DateTime dt) =>
        '${months[dt.month - 1]} ${dt.day}, ${dt.year}';

    return _DetailSection(
      title: 'Timeline',
      icon: Icons.timeline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Started',
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                  Text(
                    fmtDate(e.startDate),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textBrown,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                children: [
                  Text(
                    '$days',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: _rose,
                    ),
                  ),
                  const Text(
                    'days tracked',
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    e.endDate != null ? 'Discontinued' : 'Ongoing',
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                  Text(
                    e.endDate != null ? fmtDate(e.endDate!) : 'Today',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textBrown,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF0EEE8),
              valueColor: const AlwaysStoppedAnimation(_rose),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Day 0',
                style: TextStyle(fontSize: 10, color: _muted),
              ),
              Text(
                days >= 90
                    ? '✓ 90-day milestone reached'
                    : '${90 - days} days to 90-day milestone',
                style: TextStyle(
                  fontSize: 10,
                  color: days >= 90 ? AppColors.kMetricImprovedColor : _muted,
                  fontWeight: days >= 90 ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const Text('90d', style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCorrelationSection() {
    final corr = _correlation;
    final isBody = _peptideIsBodyFocused(widget.entry);
    final canCompareBody = isBody && _scans.length >= 2;
    final scansWithImages = _scans
        .where((s) => (s.imagePath?.isNotEmpty ?? false))
        .length;

    // Hard gate: until the user has logged at least 2 scans, NEVER render
    // any correlation/metrics/trend content. Show a compact card that
    // mirrors the 2+ scan Before/After layout so the section stays the
    // same size for every peptide (skin or body) and never takes over
    // the whole screen.
    if (_scans.length < 2) {
      final bool hasOneScan = _scans.length == 1;
      final ScanHistoryEntry? latestScan = hasOneScan ? _scans.first : null;
      final Uint8List? latestBytes = hasOneScan
          ? _decodeImagePath(latestScan?.imagePath)
          : null;
      const months = [
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
      ];
      String fmtDate(DateTime d) => '${months[d.month - 1]} ${d.day}';
      final String title = isBody
          ? 'Body Composition Trend'
          : 'Before / After Correlation';
      return _DetailSection(
        title: title,
        icon: Icons.bar_chart_rounded,
        trailing: Text(
          hasOneScan ? '1 scan' : '0 scans',
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact side-by-side layout matching the 2+ scan card so the
            // section keeps the same height for every peptide category.
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: hasOneScan
                        ? _onePhotoLatestCard(
                            latestBytes,
                            fmtDate(latestScan!.timestamp),
                          )
                        : _emptyPhotoSlot('BEFORE'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _emptyPhotoSlot(hasOneScan ? 'NEXT SCAN' : 'AFTER'),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6EDE4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE9DCCE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    hasOneScan
                        ? 'Take one more scan to unlock full Before & After comparison.'
                        : 'Take at least 2 scans to unlock Before & After correlation and insights.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _handleTakeScan,
                      icon: const Icon(Icons.camera_alt_rounded, size: 15),
                      label: const Text('Take New Scan'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _rose,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
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

    if (corr == null ||
        corr.baselineMetrics == null ||
        corr.latestMetrics == null) {
      // For body-focused peptides, attempt to show body metric deltas even
      // without a formal correlation, by reading raw metrics from the
      // scoped scans straddling the start date.
      Map<String, double>? bodyBaselineRawEarly;
      Map<String, double>? bodyLatestRawEarly;
      if (isBody) {
        final pair = _resolveBaselineLatestPair();
        bodyBaselineRawEarly = pair.baseline?.metrics;
        bodyLatestRawEarly = pair.latest?.metrics;
      }

      return _DetailSection(
        title: isBody ? 'Body Composition Trend' : 'Before & After',
        icon: Icons.bar_chart_rounded,
        trailing: scansWithImages > 0
            ? Text(
                '$scansWithImages scan${scansWithImages == 1 ? "" : "s"}',
                style: const TextStyle(fontSize: 10, color: _muted),
              )
            : null,
        child: Column(
          children: [
            // Show photos for both skin and body-focused peptides so users
            // can immediately compare visual changes after each scan.
            _buildBeforeAfterPhotos(),
            if (isBody) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canCompareBody
                      ? _openBodyBeforeAfterComparison
                      : null,
                  icon: const Icon(Icons.compare_rounded, size: 16),
                  label: const Text('Compare Before & After'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _rose,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD5C6BD),
                    disabledForegroundColor: const Color(0xFF9E8A7F),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              if (!canCompareBody)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Take at least 2 scans to compare before and after.',
                    style: TextStyle(fontSize: 11, color: _muted),
                  ),
                ),
            ],
            if (isBody) ...[
              const SizedBox(height: 4),
              ..._buildBodyMetricRows(bodyBaselineRawEarly, bodyLatestRawEarly),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEBE3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.grey.shade400,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isBody
                              ? (_scans.length < 2
                                    ? 'Take at least 2 scans to track your body composition progress.'
                                    : 'Log measurements after each scan for the most accurate tracking.')
                              : (_scans.length < 2
                                    ? 'Take a second scan to unlock correlation insights.'
                                    : 'Add skin scans before and after your start date to unlock correlation data.'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isBody) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleTakeScan,
                        icon: const Icon(Icons.camera_alt_outlined, size: 15),
                        label: const Text('Take a Scan to Unlock'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _rose,
                          side: BorderSide(color: _rose.withValues(alpha: 0.6)),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    final baseline = corr.baselineMetrics!;
    final latest = corr.latestMetrics!;

    // Body-focused peptides: pull raw before/after values from the linked
    // scan history so we can render Weight / Body Fat % / Waist / Muscle
    // Mass / Appetite Control rows. The `SkinMetrics` snapshot doesn't
    // carry these, so we walk the raw scan map. Scans are taken from
    // `_scans` (already filtered by procedure upstream + kept fresh by
    // _handleTakeScan).
    Map<String, double>? bodyBaselineRaw;
    Map<String, double>? bodyLatestRaw;
    if (isBody) {
      final pair = _resolveBaselineLatestPair();
      bodyBaselineRaw = pair.baseline?.metrics;
      bodyLatestRaw = pair.latest?.metrics;
    }

    return _DetailSection(
      title: isBody ? 'Body Composition Trend' : 'Before / After Correlation',
      icon: Icons.bar_chart_rounded,
      trailing: Text(
        '${corr.scansAfterCount} scan${corr.scansAfterCount != 1 ? "s" : ""} since start',
        style: const TextStyle(fontSize: 10, color: _muted),
      ),
      child: Column(
        children: [
          _buildBeforeAfterPhotos(),
          const SizedBox(height: 6),
          if (isBody) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canCompareBody
                    ? _openBodyBeforeAfterComparison
                    : null,
                icon: const Icon(Icons.compare_rounded, size: 16),
                label: const Text('Compare Before & After'),
                style: FilledButton.styleFrom(
                  backgroundColor: _rose,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD5C6BD),
                  disabledForegroundColor: const Color(0xFF9E8A7F),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            if (!canCompareBody)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Take at least 2 scans to compare before and after.',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (isBody) ...[
            ..._buildBodyMetricRows(bodyBaselineRaw, bodyLatestRaw),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logBodyMetrics,
                icon: const Icon(Icons.monitor_weight_outlined, size: 15),
                label: const Text('Log Body Metrics'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _rose,
                  side: BorderSide(color: _rose.withValues(alpha: 0.6)),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ] else ...[
            _metricRow(
              'Redness / Swelling',
              baseline.redness,
              latest.redness,
              lowerIsBetter: true,
            ),
            _metricRow(
              'Texture',
              baseline.texture,
              latest.texture,
              lowerIsBetter: true,
            ),
            _metricRow(
              'Fine Lines / Wrinkles',
              baseline.wrinkle,
              latest.wrinkle,
              lowerIsBetter: true,
            ),
            _metricRow(
              'Pore Visibility',
              baseline.pore,
              latest.pore,
              lowerIsBetter: true,
            ),
            _metricRow(
              'Dark Spots',
              baseline.darkSpots,
              latest.darkSpots,
              lowerIsBetter: true,
            ),
            _metricRow(
              'Skin Elasticity',
              baseline.elasticity,
              latest.elasticity,
              lowerIsBetter: false,
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showCompareScans = !_showCompareScans),
            icon: Icon(
              _showCompareScans
                  ? Icons.expand_less
                  : Icons.compare_arrows_rounded,
              size: 16,
            ),
            label: Text(
              _showCompareScans
                  ? (isBody ? 'Hide Body Timeline' : 'Hide Scan Timeline')
                  : (isBody ? 'Show Body Timeline' : 'Compare Scans'),
            ),
            style: TextButton.styleFrom(
              foregroundColor: _rose,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_showCompareScans) _buildScanTimeline(isBody: isBody),
        ],
      ),
    );
  }

  /// Body-composition metric rows for the per-peptide detail correlation
  /// section. Pulls raw before/after values out of the linked scan history
  /// for keys the user actually captured (Weight, Body Fat %, Waist,
  /// Muscle Mass, Appetite Control, Body Composition Score). Returns a
  /// friendly empty-state row when no body data is present.
  List<Widget> _buildBodyMetricRows(
    Map<String, double>? before,
    Map<String, double>? after,
  ) {
    // (label, [possible keys], lowerIsBetter, unit suffix)
    const specs = [
      _BodyRowSpec(
        'Weight',
        ['weightLbs', 'weight'],
        lowerIsBetter: true,
        unit: ' lbs',
      ),
      _BodyRowSpec(
        'Body Fat %',
        ['bodyFatPct', 'bodyFat'],
        lowerIsBetter: true,
        unit: '%',
      ),
      _BodyRowSpec(
        'Waist Circumference',
        ['waistInches', 'waistCm', 'waist'],
        lowerIsBetter: true,
        unit: ' in',
      ),
      _BodyRowSpec(
        'Muscle Mass',
        ['muscleMassLbs', 'muscleMass', 'leanMass'],
        lowerIsBetter: false,
        unit: ' lbs',
      ),
      _BodyRowSpec(
        'Appetite Control',
        ['satietyScore', 'appetiteControl', 'satiety'],
        lowerIsBetter: false,
        unit: '/10',
      ),
      _BodyRowSpec(
        'Body Composition Score',
        ['bodyCompositionScore'],
        lowerIsBetter: false,
        unit: '/10',
      ),
    ];

    const tooltipMap = <String, String>{
      'Weight': 'Your current body weight in pounds.',
      'Body Fat %':
          'Estimated percentage of body weight that is fat. Lower is generally better for health.',
      'Waist Circumference':
          'Measurement around your waist in inches. Lower is generally better.',
      'Muscle Mass': 'Estimated pounds of lean muscle tissue.',
      'Appetite Control':
          'How well you can control hunger and cravings (0\u202f=\u202fpoor control, 10\u202f=\u202fexcellent control). Important for weight-loss peptides.',
      'Body Composition Score':
          'Overall score (0\u20138) combining weight, body fat, muscle mass, and waist. Higher is better.',
    };

    final widgets = <Widget>[];
    for (final s in specs) {
      final pair = _resolveBodyMetricPair(s, before, after);
      final b = pair.before;
      final l = pair.after;
      widgets.add(
        _bodyMetricRow(
          s.label,
          b,
          l,
          lowerIsBetter: s.lowerIsBetter,
          unit: s.unit,
          estimated: pair.estimated,
          tooltip: tooltipMap[s.label],
        ),
      );
    }
    return widgets;
  }

  /// Renders a single body-composition row showing raw before → after
  /// values with their natural unit (no 0–10 progress bar — the scale
  /// would be meaningless for raw weight / circumference values).
  // Helper: name label with optional est. badge and ? tooltip icon.
  Widget _metricLabel(String name, {bool estimated = false, String? tooltip}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _textBrown,
          ),
        ),
        if (estimated) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF1D7B5)),
            ),
            child: const Text(
              'est.',
              style: TextStyle(
                fontSize: 9.5,
                color: Color(0xFFA9762E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (tooltip != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: tooltip,
            triggerMode: TooltipTriggerMode.tap,
            child: const Icon(
              Icons.help_outline_rounded,
              size: 13,
              color: _muted,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bodyMetricRow(
    String name,
    double? before,
    double? after, {
    required bool lowerIsBetter,
    String unit = '',
    bool estimated = false,
    String? tooltip,
  }) {
    if (before == null || after == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: _metricLabel(name, estimated: estimated, tooltip: tooltip),
            ),
            const Text(
              'No data yet',
              style: TextStyle(
                fontSize: 11.5,
                color: _muted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    final rawDelta = after - before;
    final directional = lowerIsBetter ? -rawDelta : rawDelta;
    final improved = directional > 0.1;
    final declined = directional < -0.1;
    final Color deltaColor = improved
        ? AppColors.kMetricImprovedColor
        : declined
        ? AppColors.kMetricWorsenedColor
        : Colors.grey.shade500;
    final deltaSign = rawDelta >= 0 ? '+' : '';
    final deltaArrow = improved
        ? (lowerIsBetter ? '↓' : '↑')
        : declined
        ? (lowerIsBetter ? '↑' : '↓')
        : '→';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: _metricLabel(name, estimated: estimated, tooltip: tooltip),
          ),
          Text(
            '${before.toStringAsFixed(1)}$unit \u2192 ${after.toStringAsFixed(1)}$unit',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: improved
                  ? AppColors.kMetricImprovedColor.withValues(alpha: 0.12)
                  : declined
                  ? AppColors.kMetricWorsenedColor.withValues(alpha: 0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: deltaColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$deltaSign${rawDelta.toStringAsFixed(1)}$unit $deltaArrow',
              style: TextStyle(
                fontSize: 11,
                color: deltaColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(
    String name,
    double before,
    double after, {
    required bool lowerIsBetter,
  }) {
    final rawDelta = lowerIsBetter ? (before - after) : (after - before);
    final improved = rawDelta > 0.1;
    final declined = rawDelta < -0.1;
    final Color deltaColor = improved
        ? AppColors.kMetricImprovedColor
        : declined
        ? AppColors.kMetricWorsenedColor
        : Colors.grey.shade500;
    final clinical = _clinicalNote(name, rawDelta);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textBrown,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: improved
                      ? AppColors.kMetricImprovedColor.withValues(alpha: 0.12)
                      : declined
                      ? AppColors.kMetricWorsenedColor.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: deltaColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${rawDelta >= 0 ? "+" : ""}${rawDelta.toStringAsFixed(1)} pts',
                  style: TextStyle(
                    fontSize: 11,
                    color: deltaColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 52,
                child: Text(
                  'Before',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (before / 10.0).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: const Color(0xFFF0EEE8),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFD4A8A0)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 28,
                child: Text(
                  before.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(
                width: 52,
                child: Text(
                  'After',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (after / 10.0).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: const Color(0xFFF0EEE8),
                    valueColor: AlwaysStoppedAnimation(deltaColor),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 28,
                child: Text(
                  after.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 10,
                    color: deltaColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (clinical.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              clinical,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const Divider(height: 14, color: Color(0xFFEDEBE3)),
        ],
      ),
    );
  }

  static const List<_BodyRowSpec> _kBodyCompareSpecs = [
    _BodyRowSpec(
      'Weight',
      ['weightLbs', 'weight'],
      lowerIsBetter: true,
      unit: ' lbs',
    ),
    _BodyRowSpec(
      'Body Fat %',
      ['bodyFatPct', 'bodyFat'],
      lowerIsBetter: true,
      unit: '%',
    ),
    _BodyRowSpec(
      'Waist Circumference',
      ['waistInches', 'waistCm', 'waist'],
      lowerIsBetter: true,
      unit: ' in',
    ),
    _BodyRowSpec(
      'Muscle Mass',
      ['muscleMassLbs', 'muscleMass', 'leanMass'],
      lowerIsBetter: false,
      unit: ' lbs',
    ),
    _BodyRowSpec(
      'Appetite Control',
      ['satietyScore', 'appetiteControl', 'satiety'],
      lowerIsBetter: false,
      unit: '/10',
    ),
    _BodyRowSpec(
      'Body Composition Score',
      ['bodyCompositionScore'],
      lowerIsBetter: false,
      unit: '/10',
    ),
  ];

  double? _pickRawMetric(Map<String, double>? source, List<String> keys) {
    if (source == null) return null;
    for (final k in keys) {
      final v = source[k];
      if (v != null) return v;
    }
    return null;
  }

  ({ScanHistoryEntry? baseline, ScanHistoryEntry? latest})
  _resolveBaselineLatestPair() {
    final sorted = [..._scans]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (sorted.isEmpty) return (baseline: null, latest: null);
    final baseline = sorted.first;
    final latest = sorted.length >= 2 ? sorted.last : null;
    return (baseline: baseline, latest: latest);
  }

  ({ScanHistoryEntry? before, ScanHistoryEntry? after}) _resolvePhotoPair() {
    final pair = _resolveBaselineLatestPair();
    return (before: pair.baseline, after: pair.latest);
  }

  ({double? before, double? after, bool estimated}) _resolveBodyMetricPair(
    _BodyRowSpec spec,
    Map<String, double>? beforeRaw,
    Map<String, double>? afterRaw,
  ) {
    double? before = _pickRawMetric(beforeRaw, spec.keys);
    double? after = _pickRawMetric(afterRaw, spec.keys);
    bool estimated = false;

    if (before != null && after != null) {
      return (before: before, after: after, estimated: false);
    }

    // Clinical fallback estimates for missing values.
    final weightBefore = _pickRawMetric(beforeRaw, const [
      'weightLbs',
      'weight',
    ]);
    final weightAfter = _pickRawMetric(afterRaw, const ['weightLbs', 'weight']);
    final weightLost = (weightBefore != null && weightAfter != null)
        ? (weightBefore - weightAfter)
        : null;

    // When BOTH values are missing, synthesize baseline from weight and
    // derive the after value from weight-change formulas.
    switch (spec.label) {
      case 'Body Fat %':
        if (weightBefore != null && weightAfter != null && weightAfter > 0) {
          final estChangePct = (weightLost! * 0.20) / weightAfter * 100.0;
          before ??= (weightBefore * 0.20).clamp(8.0, 45.0);
          after ??= (before - estChangePct).clamp(2.0, 60.0);
          estimated = true;
        }
        break;
      case 'Waist Circumference':
        if (weightBefore != null && weightLost != null) {
          before ??= (weightBefore * 0.18).clamp(24.0, 60.0);
          after ??= (before - weightLost * 0.18).clamp(18.0, 60.0);
          estimated = true;
        }
        break;
      case 'Muscle Mass':
        if (weightBefore != null && weightLost != null) {
          before ??= (weightBefore * 0.40).clamp(20.0, 120.0);
          final leanDelta = weightLost.abs() * 0.25;
          after ??= weightLost >= 0 ? before - leanDelta : before + leanDelta;
          estimated = true;
        }
        break;
      default:
        break;
    }

    return (before: before, after: after, estimated: estimated);
  }

  Future<void> _openBodyBeforeAfterComparison() async {
    final pair = _resolvePhotoPair();
    final beforeScan = pair.before;
    final afterScan = pair.after;
    if (beforeScan == null && afterScan == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Take a scan first to compare before and after photos.',
          ),
        ),
      );
      return;
    }

    final beforeRaw = beforeScan?.metrics;
    final afterRaw = afterScan?.metrics;
    final rows = _kBodyCompareSpecs.map((spec) {
      final pair = _resolveBodyMetricPair(spec, beforeRaw, afterRaw);
      final b = pair.before;
      final a = pair.after;
      return (spec: spec, before: b, after: a, estimated: pair.estimated);
    }).toList();

    ({_BodyRowSpec spec, double before, double after})? mostImproved;
    double bestMagnitude = 0;
    for (final r in rows) {
      if (r.before == null || r.after == null) continue;
      final rawDiff = r.after! - r.before!;
      final directional = r.spec.lowerIsBetter ? -rawDiff : rawDiff;
      if (directional <= 0.05) continue;
      final normScale = switch (r.spec.label) {
        'Weight' => 20.0,
        'Body Fat %' => 5.0,
        'Waist Circumference' => 4.0,
        'Muscle Mass' => 5.0,
        'Appetite Control' => 3.0,
        'Body Composition Score' => 3.0,
        _ => 5.0,
      };
      final mag = directional.abs() / normScale;
      if (mag > bestMagnitude) {
        bestMagnitude = mag;
        mostImproved = (spec: r.spec, before: r.before!, after: r.after!);
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        const months = [
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
        ];
        String fmtDate(DateTime dt) =>
            '${months[dt.month - 1]} ${dt.day}, ${dt.year}';

        Widget photoPanel(ScanHistoryEntry? scan, String label, Color color) {
          final bytes = _decodeImagePath(scan?.imagePath);
          return Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEDEBE3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0D0C8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(13),
                    ),
                    child: SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: bytes != null
                          ? Image.memory(bytes, fit: BoxFit.cover)
                          : _noPhotoPlaceholder(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            scan == null
                                ? 'No photo yet'
                                : fmtDate(scan.timestamp),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
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

        return Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(
              backgroundColor: _surface,
              foregroundColor: _textBrown,
              elevation: 0,
              title: const Text(
                'Compare Before & After',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 22),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photoPanel(beforeScan, 'BEFORE', const Color(0xFFD4A8A0)),
                      const SizedBox(width: 10),
                      photoPanel(afterScan, 'AFTER', const Color(0xFF4CAF50)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (mostImproved != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFB7DFB8)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emoji_events_rounded,
                            size: 15,
                            color: Color(0xFF2E7D32),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Most improved: ${mostImproved.spec.label} '
                              '${mostImproved.before.toStringAsFixed(1)}${mostImproved.spec.unit} → '
                              '${mostImproved.after.toStringAsFixed(1)}${mostImproved.spec.unit}',
                              style: const TextStyle(
                                fontSize: 11.8,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E8E8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Body Metrics Comparison',
                          style: TextStyle(
                            fontSize: 13,
                            color: _textBrown,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final r in rows) ...[
                          _buildBodyCompareMetricRow(
                            label: r.spec.label,
                            before: r.before,
                            after: r.after,
                            unit: r.spec.unit,
                            lowerIsBetter: r.spec.lowerIsBetter,
                            estimated: r.estimated,
                          ),
                          if (r != rows.last)
                            const Divider(height: 14, color: Color(0xFFEDEBE3)),
                        ],
                      ],
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

  Widget _buildBodyCompareMetricRow({
    required String label,
    required double? before,
    required double? after,
    required String unit,
    required bool lowerIsBetter,
    bool estimated = false,
  }) {
    if (before == null || after == null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _textBrown,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(
            'No data yet',
            style: TextStyle(
              fontSize: 11.5,
              color: _muted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }

    final rawDelta = after - before;
    final directional = lowerIsBetter ? -rawDelta : rawDelta;
    final improved = directional > 0.05;
    final declined = directional < -0.05;
    final color = improved
        ? AppColors.kMetricImprovedColor
        : (declined ? AppColors.kMetricWorsenedColor : Colors.grey.shade500);
    final arrow = improved
        ? (lowerIsBetter ? '↓' : '↑')
        : (declined ? (lowerIsBetter ? '↑' : '↓') : '→');
    final sign = rawDelta >= 0 ? '+' : '-';
    final abs = rawDelta.abs().toStringAsFixed(1);

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: _textBrown,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (estimated) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF1D7B5)),
                  ),
                  child: const Text(
                    'est.',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: Color(0xFFA9762E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          '${before.toStringAsFixed(1)}$unit → ${after.toStringAsFixed(1)}$unit',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(width: 8),
        Text(
          '($sign$abs$unit $arrow)',
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildScanTimeline({required bool isBody}) {
    final afterScans =
        _scans
            .where((s) => s.timestamp.isAfter(widget.entry.startDate))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (afterScans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'No scans recorded after start date.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }

    final months = [
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
    ];

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBody ? 'Body Metrics Timeline' : 'Scan Timeline',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _textBrown,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(afterScans.length, (i) {
            final scan = afterScans[i];
            final m = scan.toSkinMetrics();
            final dt = scan.timestamp;
            final dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
            return Padding(
              padding: EdgeInsets.only(
                bottom: i < afterScans.length - 1 ? 10 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: _rose,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _textBrown,
                        ),
                      ),
                      if (scan.procedure != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${scan.procedure}',
                          style: const TextStyle(fontSize: 10, color: _muted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: isBody
                        ? [
                            _bodyScanBadge(
                              'Weight',
                              _pickRawMetric(scan.metrics, const [
                                'weightLbs',
                                'weight',
                              ]),
                              lowerBetter: true,
                              unit: ' lbs',
                            ),
                            _bodyScanBadge(
                              'Body Fat %',
                              _pickRawMetric(scan.metrics, const [
                                'bodyFatPct',
                                'bodyFat',
                              ]),
                              lowerBetter: true,
                              unit: '%',
                            ),
                            _bodyScanBadge(
                              'Waist Circumference',
                              _pickRawMetric(scan.metrics, const [
                                'waistInches',
                                'waistCm',
                                'waist',
                              ]),
                              lowerBetter: true,
                              unit: ' in',
                            ),
                            _bodyScanBadge(
                              'Muscle Mass',
                              _pickRawMetric(scan.metrics, const [
                                'muscleMassLbs',
                                'muscleMass',
                                'leanMass',
                              ]),
                              lowerBetter: false,
                              unit: ' lbs',
                            ),
                            _bodyScanBadge(
                              'Appetite Control',
                              _pickRawMetric(scan.metrics, const [
                                'satietyScore',
                                'appetiteControl',
                                'satiety',
                              ]),
                              lowerBetter: false,
                              unit: '/10',
                            ),
                            _bodyScanBadge(
                              'Body Composition Score',
                              _pickRawMetric(scan.metrics, const [
                                'bodyCompositionScore',
                              ]),
                              lowerBetter: false,
                              unit: '/10',
                            ),
                          ]
                        : [
                            _scanBadge('Redness', m.redness, lowerBetter: true),
                            _scanBadge('Texture', m.texture, lowerBetter: true),
                            _scanBadge(
                              'Wrinkles',
                              m.wrinkle,
                              lowerBetter: true,
                            ),
                            _scanBadge('Pores', m.pore, lowerBetter: true),
                            _scanBadge(
                              'Dark Spots',
                              m.darkSpots,
                              lowerBetter: true,
                            ),
                            _scanBadge(
                              'Elasticity',
                              m.elasticity,
                              lowerBetter: false,
                            ),
                          ],
                  ),
                  if (i < afterScans.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Divider(height: 1, color: Color(0xFFE5E8E8)),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _scanBadge(String name, double value, {required bool lowerBetter}) {
    final good = lowerBetter ? value <= 4.0 : value >= 6.0;
    final bad = lowerBetter ? value >= 7.0 : value <= 3.0;
    final Color c = good
        ? AppColors.kMetricImprovedColor
        : bad
        ? AppColors.kMetricWorsenedColor
        : Colors.orange.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: const TextStyle(fontSize: 9, color: _muted)),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyScanBadge(
    String name,
    double? value, {
    required bool lowerBetter,
    required String unit,
  }) {
    if (value == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: const TextStyle(fontSize: 9, color: _muted)),
            const SizedBox(width: 3),
            const Text(
              '—',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: _muted,
              ),
            ),
          ],
        ),
      );
    }

    final good = lowerBetter ? value <= 4.0 : value >= 6.0;
    final bad = lowerBetter ? value >= 7.0 : value <= 3.0;
    final Color c = good
        ? AppColors.kMetricImprovedColor
        : bad
        ? AppColors.kMetricWorsenedColor
        : Colors.orange.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: const TextStyle(fontSize: 9, color: _muted)),
          const SizedBox(width: 3),
          Text(
            '${value.toStringAsFixed(1)}$unit',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  // ── Before / After Photo Helpers ──────────────────────────────────────────

  /// Decodes a scan imagePath (base64 data-URL or raw base64) to bytes.
  static Uint8List? _decodeImagePath(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final raw = path.startsWith('data:')
          ? path.substring(path.indexOf(',') + 1)
          : path;
      final normalized = raw.replaceAll(RegExp(r'\s+'), '');
      final needsPadding = normalized.length % 4;
      final padded = needsPadding == 0
          ? normalized
          : '$normalized${'=' * (4 - needsPadding)}';
      return base64Decode(padded);
    } catch (_) {
      return null;
    }
  }

  Widget _buildBeforeAfterPhotos() {
    final pair = _resolvePhotoPair();
    final baselineScan = pair.before;
    final latestScan = pair.after;
    if (baselineScan == null && latestScan == null) {
      return const SizedBox.shrink();
    }

    const months = [
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
    ];
    String fmtDate(DateTime dt) => '${months[dt.month - 1]} ${dt.day}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _photoCard(
              baselineScan,
              'BEFORE',
              fmtDate,
              const Color(0xFFD4A8A0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _photoCard(
              latestScan,
              'AFTER',
              fmtDate,
              const Color(0xFF4CAF50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoCard(
    ScanHistoryEntry? scan,
    String label,
    String Function(DateTime) fmtDate,
    Color labelColor,
  ) {
    final imageBytes = _decodeImagePath(scan?.imagePath);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D0C8)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: imageBytes != null
                  ? Image.memory(
                      imageBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _noPhotoPlaceholder(),
                    )
                  : _noPhotoPlaceholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  scan != null ? fmtDate(scan.timestamp) : 'No scan yet',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noPhotoPlaceholder() {
    return Container(
      color: const Color(0xFFF0EEE8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_outlined, size: 26, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text(
              'No photo',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact card matching `_photoCard` dimensions used when the user has
  /// exactly one scan. Renders the photo with a "LATEST" label so the
  /// section keeps the same height for every peptide category.
  Widget _onePhotoLatestCard(Uint8List? bytes, String dateLabel) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D0C8)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: bytes != null
                  ? Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _noPhotoPlaceholder(),
                    )
                  : _noPhotoPlaceholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                const Text(
                  'LATEST',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _rose,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  dateLabel,
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Placeholder slot used in the <2-scans empty state to keep the
  /// Before/After section at a fixed compact height for all peptides.
  Widget _emptyPhotoSlot(String label) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D0C8)),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: Container(
                color: const Color(0xFFF0EEE8),
                child: Center(
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: 26,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  'Pending',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJournalSection() {
    return _DetailSection(
      title: 'Journal',
      icon: Icons.mic_none_rounded,
      trailing: GestureDetector(
        onTap: _addJournalNote,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _rose.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _rose.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 12, color: _rose),
              SizedBox(width: 3),
              Text(
                'Add Note',
                style: TextStyle(
                  fontSize: 11,
                  color: _rose,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      child: _loadingJournal
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_rose),
                ),
              ),
            )
          : _journalEntries.isEmpty
          ? Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEBE3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No journal notes yet.\nTap "Add Note" to record observations, reactions, or daily progress for this peptide.',
                style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
              ),
            )
          : Column(
              children: _journalEntries
                  .map(
                    (e) => _JournalNoteTile(
                      entry: e,
                      onTap: () => _openJournalNote(e),
                      onEdit: () => _editJournalNote(e),
                      onDelete: () => _deleteJournalNote(e.id),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Future<void> _addJournalNote() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.mic_none_rounded, color: _rose, size: 20),
            SizedBox(width: 8),
            Text(
              'Add Journal Note',
              style: TextStyle(
                color: _textBrown,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText:
                'Describe your skin observation, reaction, or daily progress...',
            hintStyle: const TextStyle(color: _muted, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFFEDEBE3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _rose),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text(
              'Save',
              style: TextStyle(color: _rose, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (text != null && text.isNotEmpty && mounted) {
      final newEntry = PeptideJournalEntry(
        id: 'pj_${DateTime.now().millisecondsSinceEpoch}',
        peptideId: widget.entry.id,
        createdAt: DateTime.now(),
        text: text,
      );
      await PeptideService.addJournalEntry(newEntry);
      final updated = await PeptideService.loadJournal(widget.entry.id);
      if (mounted) setState(() => _journalEntries = updated);
    }
  }

  Future<void> _deleteJournalNote(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text(
          'Delete Note?',
          style: TextStyle(color: _textBrown, fontSize: 15),
        ),
        content: const Text(
          'This note will be permanently removed.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.kMetricWorsenedColor),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PeptideService.deleteJournalEntry(id);
      final updated = await PeptideService.loadJournal(widget.entry.id);
      if (mounted) setState(() => _journalEntries = updated);
    }
  }

  Future<void> _openJournalNote(PeptideJournalEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeptideJournalDetailSheet(entry: entry),
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _editJournalNote(entry);
    } else if (action == 'delete') {
      await _deleteJournalNote(entry.id);
    }
  }

  Future<void> _editJournalNote(PeptideJournalEntry entry) async {
    final ctrl = TextEditingController(text: entry.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: _rose, size: 20),
            SizedBox(width: 8),
            Text(
              'Edit Note',
              style: TextStyle(
                color: _textBrown,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Describe your observation or progress...',
            hintStyle: const TextStyle(color: _muted, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFFEDEBE3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _rose),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text(
              'Save',
              style: TextStyle(color: _rose, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (text != null && text.isNotEmpty && mounted) {
      await PeptideService.updateJournalEntry(entry.id, text);
      final updated = await PeptideService.loadJournal(widget.entry.id);
      if (mounted) setState(() => _journalEntries = updated);
    }
  }

  Widget _buildFooterActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Peptide'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _rose,
                side: const BorderSide(color: _rose),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Remove'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.kMetricWorsenedColor,
                side: BorderSide(color: AppColors.kMetricWorsenedColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _categoryChip(String cat) {
    Color color;
    String label;
    switch (cat) {
      case 'anti-aging':
        color = const Color(0xFFD4AF37);
        label = 'Anti-Aging';
        break;
      case 'brightening':
        color = const Color(0xFFE3C766);
        label = 'Brightening';
        break;
      case 'healing':
        color = const Color(0xFF7A9E6E);
        label = 'Healing & Repair';
        break;
      case 'firming':
        color = const Color(0xFF6E7A9E);
        label = 'Firming';
        break;
      case 'body-composition':
        color = const Color(0xFF9E6E7A);
        label = 'Body Composition';
        break;
      default:
        color = const Color(0xFF7E868B);
        label = 'Other';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EEE6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _muted),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5B6469)),
          ),
        ],
      ),
    );
  }

  String _clinicalNote(String metric, double delta) {
    final improved = delta > 0.1;
    switch (metric) {
      case 'Redness / Swelling':
        return improved
            ? 'Erythema reduction detected — reflects resolving inflammation.'
            : 'Redness persisting — monitor for skin barrier disruption.';
      case 'Texture':
        return improved
            ? 'Surface smoothness improved — consistent with epidermal barrier normalization.'
            : 'Texture roughening noted — may reflect delayed barrier repair.';
      case 'Fine Lines / Wrinkles':
        return improved
            ? 'Wrinkle reduction — consistent with stimulated collagen synthesis.'
            : 'No visible wrinkle change yet — allow additional cycle time.';
      case 'Pore Visibility':
        return improved
            ? 'Pore refinement detected — reflects sebum regulation and collagen support.'
            : 'Pores unchanged — consider pairing with niacinamide for synergy.';
      case 'Dark Spots':
        return improved
            ? 'Pigment suppression confirmed — consistent with tyrosinase pathway inhibition.'
            : 'Pigmentation stable — may require extended treatment duration.';
      case 'Skin Elasticity':
        return improved
            ? 'Elasticity gain confirmed — dermal collagen and elastin strengthening.'
            : 'Elasticity unchanged — review concentration and application frequency.';
      default:
        return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailSection — card-style section for detail sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.icon,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFFD4AF37)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2C3539),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const Divider(height: 14, color: Color(0xFFEDEBE3)),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _JournalNoteTile — individual journal entry in detail sheet
// ─────────────────────────────────────────────────────────────────────────────

class _JournalNoteTile extends StatelessWidget {
  final PeptideJournalEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _JournalNoteTile({
    required this.entry,
    required this.onDelete,
    this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    const months = [
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
    ];
    final dt = entry.createdAt;
    final dateStr =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year}  '
        '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFDFBF7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF0EEE8)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF7E868B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2C3539),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
                padding: EdgeInsets.zero,
                iconSize: 18,
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 16),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: AppColors.kMetricWorsenedColor,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: AppColors.kMetricWorsenedColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Compare Metrics Over Time (full-screen body progress view) ───────────────

/// Describes a body metric for the compare view.
/// `goodWhenDecreasing` is true for weight / body fat / waist where a
/// lower number is better; false for muscle mass, satiety, body comp score.
class _BodyMetricSpec {
  final String key;
  final String label;
  final String unit;
  final IconData icon;
  final bool goodWhenDecreasing;
  const _BodyMetricSpec(
    this.key,
    this.label,
    this.unit,
    this.icon,
    this.goodWhenDecreasing,
  );
}

const List<_BodyMetricSpec> _bodyMetricSpecs = [
  _BodyMetricSpec(
    'weightLbs',
    'Weight',
    'lbs',
    Icons.monitor_weight_outlined,
    true,
  ),
  _BodyMetricSpec('bodyFatPct', 'Body Fat', '%', Icons.percent_rounded, true),
  _BodyMetricSpec('waistInches', 'Waist', '"', Icons.straighten_rounded, true),
  _BodyMetricSpec(
    'muscleMassLbs',
    'Muscle Mass',
    'lbs',
    Icons.fitness_center_rounded,
    false,
  ),
  _BodyMetricSpec(
    'satietyScore',
    'Appetite Control',
    '/10',
    Icons.restaurant_menu_rounded,
    false,
  ),
  _BodyMetricSpec(
    'bodyCompositionScore',
    'Body Comp Score',
    '/10',
    Icons.auto_graph_rounded,
    false,
  ),
];

class _BodyProgressCompareScreen extends StatelessWidget {
  static const Color _rose = Color(0xFFD4AF37);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _surface = Color(0xFFF8F6F0);
  static const Color _gold = Color(0xFFE3C766);
  static const Color _good = Color(0xFF6FA28A);
  static const Color _bad = Color(0xFFC97C6E);

  final String stackName;
  final List<ScanHistoryEntry> scans;

  const _BodyProgressCompareScreen({
    required this.stackName,
    required this.scans,
  });

  /// Sorted chronologically (oldest first).
  List<ScanHistoryEntry> get _sorted {
    final l = List<ScanHistoryEntry>.from(scans)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return l;
  }

  ScanHistoryEntry? _baseline(List<ScanHistoryEntry> sorted) {
    if (sorted.isEmpty) return null;
    return sorted.firstWhere((s) => s.isBaseline, orElse: () => sorted.first);
  }

  /// Earliest non-null value for a metric.
  double? _firstValue(List<ScanHistoryEntry> sorted, String key) {
    for (final s in sorted) {
      final v = s.metrics[key];
      if (v != null) return v;
    }
    return null;
  }

  /// Latest non-null value for a metric.
  double? _lastValue(List<ScanHistoryEntry> sorted, String key) {
    for (final s in sorted.reversed) {
      final v = s.metrics[key];
      if (v != null) return v;
    }
    return null;
  }

  String _fmtDate(DateTime dt) {
    const months = [
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
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _fmtVal(double v, String unit) {
    final s = v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s$unit';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final baseline = _baseline(sorted);

    // Compute per-metric deltas (latest - earliest) for present metrics.
    final List<_MetricDelta> deltas = [];
    for (final spec in _bodyMetricSpecs) {
      final first = _firstValue(sorted, spec.key);
      final last = _lastValue(sorted, spec.key);
      if (first == null || last == null) continue;
      deltas.add(_MetricDelta(spec: spec, first: first, last: last));
    }

    // Most-improved: largest beneficial change.
    _MetricDelta? mostImproved;
    for (final d in deltas) {
      if (!d.isImprovement) continue;
      if (mostImproved == null ||
          d.improvementMagnitude > mostImproved.improvementMagnitude) {
        mostImproved = d;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: _textBrown,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Compare Metrics Over Time',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _textBrown,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // Stack name + scan count summary
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stackName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _textBrown,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sorted.length} scan${sorted.length == 1 ? '' : 's'} • '
                    '${baseline != null ? _fmtDate(baseline.timestamp) : '—'} → '
                    '${sorted.isNotEmpty ? _fmtDate(sorted.last.timestamp) : '—'}',
                    style: const TextStyle(fontSize: 12.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Most improved
            if (mostImproved != null) ...[
              const _CompareSectionHeader(
                icon: Icons.emoji_events_rounded,
                label: 'Most Improved',
              ),
              const SizedBox(height: 8),
              _MostImprovedCard(delta: mostImproved),
              const SizedBox(height: 18),
            ],

            // Before/After deltas grid
            if (deltas.isNotEmpty) ...[
              const _CompareSectionHeader(
                icon: Icons.compare_arrows_rounded,
                label: 'Before vs Latest',
              ),
              const SizedBox(height: 8),
              ...deltas.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DeltaCard(delta: d, fmtVal: _fmtVal),
                ),
              ),
              const SizedBox(height: 12),
            ] else
              _emptyDeltasCard(),

            const SizedBox(height: 12),

            // Scan-by-scan timeline
            const _CompareSectionHeader(
              icon: Icons.timeline_rounded,
              label: 'Scan-by-Scan Progress',
            ),
            const SizedBox(height: 8),
            ..._buildTimelineRows(sorted),
          ],
        ),
      ),
    );
  }

  Widget _emptyDeltasCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _muted.withValues(alpha: 0.3)),
      ),
      child: const Text(
        'Log at least 2 measurements with the same metric (e.g. Weight) to '
        'see before / after deltas here.',
        style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
      ),
    );
  }

  List<Widget> _buildTimelineRows(List<ScanHistoryEntry> sorted) {
    if (sorted.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _muted.withValues(alpha: 0.3)),
          ),
          child: const Text('No scans yet.', style: TextStyle(color: _muted)),
        ),
      ];
    }
    final rows = <Widget>[];
    // Track previous values to render scan-vs-prev arrows.
    final Map<String, double> prev = {};
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final entries = <Widget>[];
      for (final spec in _bodyMetricSpecs) {
        final v = s.metrics[spec.key];
        if (v == null) continue;
        final p = prev[spec.key];
        entries.add(_timelineMetricChip(spec, v, p));
      }
      // update prev with this scan's values
      for (final spec in _bodyMetricSpecs) {
        final v = s.metrics[spec.key];
        if (v != null) prev[spec.key] = v;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _muted.withValues(alpha: 0.2)),
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
                        color: s.isBaseline
                            ? _gold.withValues(alpha: 0.18)
                            : _rose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.isBaseline ? 'B' : '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: s.isBaseline ? _gold : _rose,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.isBaseline
                            ? 'Baseline • ${_fmtDate(s.timestamp)}'
                            : 'Scan ${i + 1} • ${_fmtDate(s.timestamp)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _textBrown,
                        ),
                      ),
                    ),
                  ],
                ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: entries),
                ] else ...[
                  const SizedBox(height: 6),
                  const Text(
                    'No body metrics on this scan.',
                    style: TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return rows;
  }

  Widget _timelineMetricChip(_BodyMetricSpec spec, double v, double? prev) {
    Widget arrow = const SizedBox.shrink();
    if (prev != null) {
      final diff = v - prev;
      if (diff.abs() >= 0.05) {
        final goingDown = diff < 0;
        final isGood = spec.goodWhenDecreasing ? goingDown : !goingDown;
        arrow = Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                goingDown
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 11,
                color: isGood ? _good : _bad,
              ),
              Text(
                _fmtVal(diff.abs(), spec.unit),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: isGood ? _good : _bad,
                ),
              ),
            ],
          ),
        );
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _muted.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 13, color: _rose),
          const SizedBox(width: 5),
          Text(
            '${spec.label}: ',
            style: const TextStyle(fontSize: 11.5, color: _muted),
          ),
          Text(
            _fmtVal(v, spec.unit),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _textBrown,
            ),
          ),
          arrow,
        ],
      ),
    );
  }
}

class _MetricDelta {
  final _BodyMetricSpec spec;
  final double first;
  final double last;
  const _MetricDelta({
    required this.spec,
    required this.first,
    required this.last,
  });
  double get diff => last - first;
  bool get isImprovement => spec.goodWhenDecreasing ? diff < 0 : diff > 0;

  /// Magnitude scaled by sensible ranges so different metrics are comparable.
  double get improvementMagnitude {
    // Normalise by typical range so e.g. 5 lbs of weight loss isn't dwarfed
    // by 1.0 of muscle mass.
    final scales = {
      'weightLbs': 20.0,
      'bodyFatPct': 5.0,
      'waistInches': 4.0,
      'muscleMassLbs': 5.0,
      'satietyScore': 3.0,
      'bodyCompositionScore': 3.0,
    };
    final scale = scales[spec.key] ?? 5.0;
    return (diff.abs() / scale);
  }
}

class _CompareSectionHeader extends StatelessWidget {
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _rose = Color(0xFFD4AF37);
  final IconData icon;
  final String label;
  const _CompareSectionHeader({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _rose),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _textBrown,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _MostImprovedCard extends StatelessWidget {
  static const Color _gold = Color(0xFFE3C766);
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _good = Color(0xFF6FA28A);
  final _MetricDelta delta;
  const _MostImprovedCard({required this.delta});
  @override
  Widget build(BuildContext context) {
    final spec = delta.spec;
    final absDiff = delta.diff.abs();
    final unit = spec.unit;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _gold.withValues(alpha: 0.18),
            _good.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(spec.icon, color: _good, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textBrown,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${delta.first.toStringAsFixed(1)}$unit  →  ${delta.last.toStringAsFixed(1)}$unit',
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      delta.diff < 0
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: _good,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${absDiff.toStringAsFixed(1)}$unit ${spec.goodWhenDecreasing ? 'lost' : 'gained'} 🎉',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _good,
                      ),
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
}

class _DeltaCard extends StatelessWidget {
  static const Color _textBrown = Color(0xFF2C3539);
  static const Color _muted = Color(0xFF7E868B);
  static const Color _good = Color(0xFF6FA28A);
  static const Color _bad = Color(0xFFC97C6E);
  static const Color _rose = Color(0xFFD4AF37);

  final _MetricDelta delta;
  final String Function(double, String) fmtVal;
  const _DeltaCard({required this.delta, required this.fmtVal});

  @override
  Widget build(BuildContext context) {
    final spec = delta.spec;
    final isImp = delta.isImprovement;
    final diff = delta.diff;
    final pct = spec.goodWhenDecreasing && delta.first != 0
        ? (diff / delta.first) * 100
        : null;
    final accent = isImp ? _good : (diff.abs() < 0.05 ? _muted : _bad);
    final maxRange = math.max(delta.first.abs(), delta.last.abs());
    final progress = maxRange == 0
        ? 0.0
        : (delta.last / maxRange).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _muted.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _rose.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(spec.icon, color: _rose, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  spec.label,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _textBrown,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      diff.abs() < 0.05
                          ? Icons.remove_rounded
                          : (diff < 0
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded),
                      size: 12,
                      color: accent,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      diff.abs() < 0.05
                          ? 'No change'
                          : '${diff < 0 ? '-' : '+'}${fmtVal(diff.abs(), spec.unit)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    if (pct != null && pct.abs() >= 0.5) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${pct < 0 ? '' : '+'}${pct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Before',
                      style: TextStyle(fontSize: 10.5, color: _muted),
                    ),
                    Text(
                      fmtVal(delta.first, spec.unit),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _textBrown,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: _muted, size: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Latest',
                      style: TextStyle(fontSize: 10.5, color: _muted),
                    ),
                    Text(
                      fmtVal(delta.last, spec.unit),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: _muted.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}
