import 'package:flutter/material.dart';
import '../models/procedure.dart';
import '../utils/peptide_display.dart';
import '../models/peptide_model.dart';
import '../utils/procedure_intelligence.dart';

/// Universal display block for any tracked item (peptide, stack, procedure, skincare, etc.)
class _TrackedItemDisplay {
  final String title;
  final String description;
  final String categoryLabel;
  final Color categoryColor;
  const _TrackedItemDisplay({
    required this.title,
    required this.description,
    required this.categoryLabel,
    required this.categoryColor,
  });
}

Future<_TrackedItemDisplay> resolveTrackedItemDisplay(Procedure p) async {
  // 1. Peptide protocol (single or stack)
  final pep = await resolvePeptideDisplay(p);
  if (pep != null) {
    // Try to get evidence tier and clinical note from the peptide library
    final libEntry = kPeptideLibrary.cast<PeptideLibraryEntry?>().firstWhere(
      (e) =>
          e != null &&
          (e.name.toLowerCase() == pep.title.toLowerCase() ||
              pep.title.toLowerCase().contains(e.name.toLowerCase())),
      orElse: () => null,
    );
    String desc = pep.subtitle;
    if (libEntry != null) {
      desc = libEntry.mechanism;
      if (libEntry.evidenceLevel.isNotEmpty) {
        desc += '  (Evidence: ${libEntry.evidenceLevel})';
      }
      if (libEntry.clinicalNote.isNotEmpty) {
        desc += '\n${libEntry.clinicalNote}';
      }
    }
    return _TrackedItemDisplay(
      title: pep.title,
      description: desc,
      categoryLabel: pep.categoryLabel,
      categoryColor: pep.categoryColor,
    );
  }

  // 2. Procedure (laser, microneedling, etc.)
  final customLabel = procedureContextLabel(
    procedureType: p.type,
    customDescription: p.customDescription,
    focusArea: p.focusArea,
  );
  if (isCustomProcedureType(p.type) || p.customDescription != null) {
    final isBody = usesBodyContouringContext(
      procedureType: p.type,
      customDescription: p.customDescription,
      focusArea: p.focusArea,
    );
    return _TrackedItemDisplay(
      title: customLabel,
      description: isBody
          ? 'Custom body-contouring recovery context. Insights use general body-contour metrics and avoid procedure-specific assumptions unless the description clearly supports them.'
          : 'Custom procedure context. Insights use the closest matching recovery metrics while keeping language general and provider-guided.',
      categoryLabel: isBody ? 'Custom Body Contouring' : 'Custom Procedure',
      categoryColor: Colors.blueGrey.shade700,
    );
  }

  final canonical = canonicalProcedureType(p.type);
  final profile = ProcedureIntelligence.forType(canonical);
  String desc = profile.primaryFocusLabel;
  if (profile.aiCoachContext.isNotEmpty) {
    desc = '${profile.aiCoachContext.split('. ').first.trim()}.';
  }
  return _TrackedItemDisplay(
    title: canonical,
    description: desc,
    categoryLabel: profile.primaryFocusLabel,
    categoryColor: Colors.blueGrey.shade700,
  );
}
