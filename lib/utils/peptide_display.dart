// lib/utils/peptide_display.dart
//
// Resolves a user-facing display block for any procedure that represents a
// peptide protocol (single peptide or stack). Both the Home screen and the
// Procedure Profiles screen use this to show the **actual peptide name** +
// short mechanism blurb + category badge, instead of the generic
// "Peptide Tracking" / "Self" combo that previously rendered.

import 'package:flutter/material.dart';

import '../models/peptide_model.dart';
import '../models/procedure.dart';
import 'peptide_service.dart';

/// Lightweight, pre-rendered display block for a peptide procedure row.
class PeptideDisplay {
  final String title; // headline shown in place of procedure.type
  final String subtitle; // single-line mechanism / benefit blurb
  final String
  categoryLabel; // e.g. "Anti-Aging", "Body Composition", "Healing"
  final Color categoryColor; // pill / accent color for the badge
  final IconData icon; // small leading icon for the card
  final String provider; // replacement for raw "Self" (e.g. "Self-managed")

  const PeptideDisplay({
    required this.title,
    required this.subtitle,
    required this.categoryLabel,
    required this.categoryColor,
    required this.icon,
    required this.provider,
  });
}

/// Returns true when the procedure represents a peptide protocol (either
/// individual peptide or stack-based). Robust against legacy data: matches
/// on either the category field or substrings in the procedure type.
bool isPeptideProcedure(Procedure p) {
  final cat = p.category.toLowerCase();
  if (cat.contains('peptide') || cat.contains('body composition')) return true;
  final t = p.type.toLowerCase();
  return t.contains('peptide');
}

// ─────────────────────────────────────────────────────────────────────────────
// Category → label / color / icon mapping
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, String> _categoryLabels = {
  'anti-aging': 'Anti-Aging',
  'antiaging': 'Anti-Aging',
  'brightening': 'Brightening',
  'healing': 'Healing',
  'firming': 'Firming',
  'body-composition': 'Body Composition',
  'body composition': 'Body Composition',
  'glp-1': 'Body Composition',
  'glp1': 'Body Composition',
  'longevity': 'Longevity',
  'nootropic': 'Cognitive',
  'cognitive': 'Cognitive',
  'sleep': 'Sleep & Recovery',
  'peptide': 'Peptide',
  'other': 'Peptide',
};

Color _colorForCategory(String key) {
  switch (key) {
    case 'anti-aging':
    case 'antiaging':
    case 'firming':
      return const Color(0xFFB0717A); // rose
    case 'healing':
      return const Color(0xFF3E7C7E); // teal
    case 'brightening':
      return const Color(0xFFC8A96A); // gold
    case 'body-composition':
    case 'body composition':
    case 'glp-1':
    case 'glp1':
      return const Color(0xFF1E2A3A); // navy
    case 'longevity':
      return const Color(0xFF7B6A8E); // soft violet
    case 'nootropic':
    case 'cognitive':
      return const Color(0xFF4A6B8A); // slate blue
    case 'sleep':
      return const Color(0xFF5C4E78); // dusk
    default:
      return const Color(0xFFB0717A);
  }
}

IconData _iconForCategory(String key) {
  switch (key) {
    case 'body-composition':
    case 'body composition':
    case 'glp-1':
    case 'glp1':
      return Icons.monitor_weight_outlined;
    case 'healing':
      return Icons.healing_outlined;
    case 'brightening':
      return Icons.wb_sunny_outlined;
    case 'anti-aging':
    case 'firming':
      return Icons.spa_outlined;
    case 'longevity':
      return Icons.timer_outlined;
    case 'nootropic':
    case 'cognitive':
      return Icons.psychology_outlined;
    case 'sleep':
      return Icons.bedtime_outlined;
    default:
      return Icons.biotech_outlined;
  }
}

String _labelForCategory(String raw) {
  final key = raw.toLowerCase().trim();
  return _categoryLabels[key] ?? 'Peptide';
}

// ─────────────────────────────────────────────────────────────────────────────
// Library lookup — finds the curated entry whose name fuzzy-matches the
// peptide. Handles "Matrixyl 3000" vs "Matrixyl", "GHK-Cu" vs "GHK", etc.
// ─────────────────────────────────────────────────────────────────────────────

PeptideLibraryEntry? _libraryEntryFor(String name) {
  final lower = name.toLowerCase().trim();
  if (lower.isEmpty) return null;
  for (final entry in kPeptideLibrary) {
    if (entry.name.toLowerCase() == lower) return entry;
  }
  for (final entry in kPeptideLibrary) {
    final entryLower = entry.name.toLowerCase();
    if (lower.contains(entryLower) || entryLower.contains(lower)) {
      return entry;
    }
  }
  // Try the INCI / alternate name as a last resort.
  for (final entry in kPeptideLibrary) {
    if (entry.inci.toLowerCase().contains(lower)) return entry;
  }
  return null;
}

/// Short mechanism blurb suitable for a single-line card subtitle.
String _shortMechanism(PeptideLibraryEntry? entry, PeptideEntry peptide) {
  if (entry != null && entry.mechanism.isNotEmpty) {
    // First sentence only — keeps the subtitle to a single line.
    final firstStop = entry.mechanism.indexOf('.');
    if (firstStop > 0 && firstStop < entry.mechanism.length - 1) {
      return entry.mechanism.substring(0, firstStop).trim();
    }
    return entry.mechanism.trim();
  }
  // Fallback: derive a phrase from the peptide's own category.
  switch (peptide.category.toLowerCase()) {
    case 'anti-aging':
    case 'antiaging':
    case 'firming':
      return 'Supports collagen, elasticity, and dermal remodeling';
    case 'healing':
      return 'Supports tissue repair and barrier recovery';
    case 'brightening':
      return 'Targets pigmentation and tone evenness';
    case 'body-composition':
    case 'body composition':
    case 'glp-1':
      return 'Body composition + metabolic protocol';
    case 'longevity':
      return 'Cellular longevity and recovery support';
    case 'nootropic':
    case 'cognitive':
      return 'Cognitive performance support';
    case 'sleep':
      return 'Sleep quality and overnight recovery';
    default:
      return 'Active peptide protocol';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public resolver
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves a [PeptideDisplay] for the given procedure, or returns null if
/// the procedure is not peptide-related (or has no associated peptides).
///
/// Strategy:
/// 1. Find the [PeptideStack] whose `procedureId` matches `p.id`. Collect
///    its peptides → derive title / subtitle / category from the stack.
/// 2. If no stack matches, fall back to listing **all** active peptides and
///    using them collectively (covers "individual peptide" mode where the
///    user has not created a named stack).
/// 3. If still nothing, returns a generic peptide display so the card at
///    least shows a peptide badge instead of "Self".
Future<PeptideDisplay?> resolvePeptideDisplay(Procedure p) async {
  if (!isPeptideProcedure(p)) return null;

  final stacks = await PeptideService.loadStacks();
  final allPeptides = await PeptideService.loadAll();

  // Step 1 — stack pinned to this procedure.
  final stack = stacks.where((s) => s.procedureId == p.id).firstOrNull;
  List<PeptideEntry> peptides = const [];
  String? stackName;
  if (stack != null) {
    stackName = stack.name;
    peptides = allPeptides
        .where((e) => e.stackId == stack.id && e.isActive)
        .toList();
  }

  // Step 2 — no stack pinned: use individual active peptides as fallback.
  if (peptides.isEmpty) {
    peptides = allPeptides.where((e) => e.isActive).toList();
  }

  // Step 3 — still no peptides: minimal generic display.
  if (peptides.isEmpty) {
    final catKey = p.category.toLowerCase();
    return PeptideDisplay(
      title: p.type.isNotEmpty ? p.type : 'Peptide Protocol',
      subtitle: 'Active peptide tracking — add a peptide to personalise',
      categoryLabel: _labelForCategory(catKey),
      categoryColor: _colorForCategory(catKey),
      icon: _iconForCategory(catKey),
      provider: 'Self-managed',
    );
  }

  // Build display from peptide data.
  final first = peptides.first;
  final libEntry = _libraryEntryFor(first.name);

  final String title;
  final String subtitle;
  if (peptides.length == 1) {
    title = first.name;
    subtitle = _shortMechanism(libEntry, first);
  } else {
    // Multi-peptide stack: lead with the stack name when meaningful,
    // otherwise lead with the first peptide. List the remaining peptides
    // by name (capped) so the user immediately sees what's in the protocol.
    final restNames = peptides.skip(1).map((e) => e.name).toList();
    final namesPreview = restNames.length <= 2
        ? restNames.join(', ')
        : '${restNames.take(2).join(', ')} +${restNames.length - 2} more';
    if (stackName != null &&
        stackName.isNotEmpty &&
        stackName.toLowerCase() != 'my stack' &&
        stackName.toLowerCase() != 'new stack') {
      title = stackName;
      subtitle = '${first.name}, $namesPreview';
    } else {
      title = '${first.name} stack';
      subtitle = 'With $namesPreview';
    }
  }

  // Category resolution: prefer the curated library entry's category, then
  // the peptide entry's own category, then the procedure category.
  final catKey =
      (libEntry?.category ??
              (first.category.isNotEmpty ? first.category : p.category))
          .toLowerCase()
          .trim();

  return PeptideDisplay(
    title: title,
    subtitle: subtitle,
    categoryLabel: _labelForCategory(catKey),
    categoryColor: _colorForCategory(catKey),
    icon: _iconForCategory(catKey),
    provider: 'Self-managed',
  );
}

/// Convenience: resolves displays for a list of procedures in one call.
Future<Map<String, PeptideDisplay>> resolvePeptideDisplaysFor(
  Iterable<Procedure> procedures,
) async {
  final out = <String, PeptideDisplay>{};
  for (final p in procedures) {
    final d = await resolvePeptideDisplay(p);
    if (d != null) out[p.id] = d;
  }
  return out;
}
