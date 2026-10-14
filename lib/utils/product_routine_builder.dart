/// Turns skincare products into a morning / evening routine and the active
/// AI routine payload the Routines screen reads (morningSteps /
/// eveningSteps). No metric is involved.
library;

/// Whether a product belongs in the night routine: retinoids, creams,
/// masks, and non-sunscreen treatments. The same rule the home screen uses
/// for a saved product analysis.
bool isNightRoutineProduct({required String name, String purpose = ''}) {
  final p = purpose.toLowerCase();
  final n = name.toLowerCase();
  return p.contains('night') ||
      p.contains('retinol') ||
      p.contains('cream') ||
      n.contains('retinol') ||
      n.contains('cream') ||
      n.contains('mask') ||
      (p.contains('treatment') && !p.contains('sunscreen'));
}

/// Splits product names into morning and evening steps with
/// [isNightRoutineProduct]. Blank and duplicate names are skipped.
({List<String> morning, List<String> evening}) buildAmPmStepsFromProductNames(
  Iterable<String> names,
) {
  final morning = <String>[];
  final evening = <String>[];
  for (final raw in names) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final target = isNightRoutineProduct(name: name) ? evening : morning;
    if (!target.contains(name)) target.add(name);
  }
  return (morning: morning, evening: evening);
}

/// Morning / evening steps from an AI reply that has "Morning routine" and
/// "Evening routine" (or "Night routine") sections of bulleted or numbered
/// lines. Restored from the AI coach screen removed in 193eee3.
({List<String> morning, List<String> evening}) extractAmPmRoutineSteps(
  String text,
) {
  final morning = <String>[];
  final evening = <String>[];
  var section = '';

  void addStep(String step) {
    final normalized = step.trim();
    if (normalized.length < 3) return;
    if (section == 'morning' && !morning.contains(normalized)) {
      morning.add(normalized);
    } else if (section == 'evening' && !evening.contains(normalized)) {
      evening.add(normalized);
    }
  }

  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();

    if (lower.contains('morning routine')) {
      section = 'morning';
      continue;
    }
    if (lower.contains('evening routine') || lower.contains('night routine')) {
      section = 'evening';
      continue;
    }
    if (lower.startsWith('products') || lower.startsWith('detected products')) {
      section = '';
      continue;
    }
    if (section.isEmpty) continue;

    final looksLikeHeading =
        RegExp(r'^[a-zA-Z\s]{3,}:$').hasMatch(line) ||
        lower.contains('strong recommendation:') ||
        lower.contains('medical disclaimer') ||
        lower.contains('priority focus') ||
        lower.contains('weekly') ||
        lower.contains('as needed');
    if (looksLikeHeading) continue;

    addStep(_stripListMarker(line));
  }

  return (morning: morning, evening: evening);
}

/// Product names listed under a "Products:" (or "Detected products:")
/// heading in an AI reply, up to the next routine section.
List<String> extractDetectedProducts(String text) {
  final products = <String>[];
  var inProducts = false;
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('products') || lower.startsWith('detected products')) {
      inProducts = true;
      continue;
    }
    if (lower.contains('routine')) {
      inProducts = false;
      continue;
    }
    if (!inProducts) continue;
    final name = _stripListMarker(line);
    if (name.length >= 2 && !products.contains(name)) products.add(name);
  }
  return products;
}

/// The active AI routine payload stored by AppPrefs.saveActiveAiRoutine.
Map<String, dynamic> activeAiRoutinePayload({
  required List<String> morningSteps,
  required List<String> eveningSteps,
  List<String> detectedProducts = const <String>[],
  required String source,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return <String, dynamic>{
    'id': 'ai_${at.millisecondsSinceEpoch}',
    'source': source,
    'generatedAt': at.toIso8601String(),
    'morningSteps': morningSteps,
    'eveningSteps': eveningSteps,
    'detectedProducts': detectedProducts,
  };
}

String _stripListMarker(String line) => line
    .replaceFirst(RegExp(r'^[-*•]+\s*'), '')
    .replaceFirst(RegExp(r'^\d+[\).:-]?\s*'), '')
    .trim();
