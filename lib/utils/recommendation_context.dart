/// Context notes shown beside the scan-based recommendations, on product
/// detail and on the routine screen, built only from what the user already
/// logged in the app: journal entries, acne & rosacea log notes, tracked
/// products, product feedback, and the existing interaction rules. It never
/// changes which recommendations are selected, and returns nothing when
/// nothing relevant is stored.
library;

import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/acne_rosacea_log.dart';
import '../models/journal_entry.dart';
import '../models/product_feedback.dart';
import '../models/product_tracker.dart';
import 'app_prefs.dart';
import 'peptide_interactions.dart';
import 'peptide_service.dart';

/// One note, plus the product / ingredient / peptide names it is about, so
/// a screen can keep only the notes relevant to what it shows.
class ContextNote {
  const ContextNote(this.text, {this.subjects = const <String>[]});

  final String text;
  final List<String> subjects;
}

/// Everything the notes are built from, as stored.
class RecommendationContextInputs {
  const RecommendationContextInputs({
    this.journalEntries = const <JournalEntry>[],
    this.productJournals = const <String, List<JournalEntry>>{},
    this.acneRosaceaLogs = const <AcneRosaceaLog>[],
    this.trackedProducts = const <TrackedProduct>[],
    this.productFeedback = const <ProductFeedbackEntry>[],
    this.activePeptideNames = const <String>[],
  });

  final List<JournalEntry> journalEntries;
  final Map<String, List<JournalEntry>> productJournals;
  final List<AcneRosaceaLog> acneRosaceaLogs;
  final List<TrackedProduct> trackedProducts;
  final List<ProductFeedbackEntry> productFeedback;
  final List<String> activePeptideNames;

  /// Reads the stored inputs through the existing AppPrefs / PeptideService
  /// getters. Nothing is written.
  static Future<RecommendationContextInputs> load() async {
    final productJournals = <String, List<JournalEntry>>{};
    final raw = await AppPrefs.getString('skincare_journal_entries');
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((product, entries) {
            if (entries is List) {
              productJournals[product.toString()] = entries
                  .whereType<Map>()
                  .map((e) => JournalEntry.fromJson(Map.from(e).cast()))
                  .toList();
            }
          });
        }
      } catch (_) {}
    }
    final acne = await AppPrefs.getAcneRosaceaLogs();
    final peptides = await PeptideService.loadAll();
    return RecommendationContextInputs(
      journalEntries: await AppPrefs.getGeneralJournalEntries(),
      productJournals: productJournals,
      acneRosaceaLogs: acne.values.expand((logs) => logs).toList(),
      trackedProducts: await AppPrefs.getTrackedProducts(),
      productFeedback: await AppPrefs.getProductFeedback(),
      activePeptideNames: [
        for (final p in peptides)
          if (p.isActive) p.name,
      ],
    );
  }
}

class RecommendationContext {
  const RecommendationContext._();

  /// Word stems that mark a note as an irritation / reaction note.
  static const List<String> irritationWords = <String>[
    'irritat',
    'reaction',
    'reacted',
    'sting',
    'stung',
    'burning',
    'rash',
    'itch',
  ];

  /// Words that cancel an irritation word when they appear within the
  /// three words before it in the same clause ("no irritation", "didn't
  /// sting", "not irritated", "without any burning").
  static const Set<String> negationWords = <String>{
    'no',
    'not',
    'never',
    'without',
    'zero',
    'none',
    'nor',
    "didn't",
    'didnt',
    "don't",
    'dont',
    "doesn't",
    'doesnt',
    "isn't",
    'isnt',
    "wasn't",
    'wasnt',
    "hasn't",
    'hasnt',
    "haven't",
    'havent',
    "hadn't",
    "won't",
  };

  /// Same cut-off the product feedback screen uses for "sensitive" (0–10).
  static const int feedbackIrritationFlag = 5;

  static const int maxNotes = 5;

  /// Whether [text] has an irritation word that is not negated. Text is
  /// split into clauses at punctuation and "but"; inside a clause an
  /// irritation word counts unless one of the three words before it is a
  /// [negationWords] entry, or it is followed by "free" ("irritation-free").
  static bool mentionsIrritation(String text) {
    final normalized = text.toLowerCase().replaceAll('’', "'");
    for (final clause in normalized.split(RegExp(r'[.!?;,:\n]|\bbut\b'))) {
      final words = RegExp(
        r"[a-z']+",
      ).allMatches(clause).map((m) => m.group(0)!).toList();
      for (var i = 0; i < words.length; i++) {
        if (!irritationWords.any(words[i].startsWith)) continue;
        final before = words.sublist(i < 3 ? 0 : i - 3, i);
        final negated =
            before.any(negationWords.contains) ||
            (i + 1 < words.length && words[i + 1] == 'free');
        if (!negated) return true;
      }
    }
    return false;
  }

  static bool isIrritationNote(JournalEntry entry) {
    if (entry.title.trim().toLowerCase() == 'reaction') return true;
    return mentionsIrritation('${entry.title}. ${entry.content}');
  }

  static List<String> notes({
    List<JournalEntry> journalEntries = const <JournalEntry>[],
    Map<String, List<JournalEntry>> productJournals =
        const <String, List<JournalEntry>>{},
    List<AcneRosaceaLog> acneRosaceaLogs = const <AcneRosaceaLog>[],
    List<TrackedProduct> trackedProducts = const <TrackedProduct>[],
    List<ProductFeedbackEntry> productFeedback = const <ProductFeedbackEntry>[],
    List<String> activePeptideNames = const <String>[],
    List<String> recommendedPeptideNames = const <String>[],
  }) => [
    for (final n in contextNotes(
      RecommendationContextInputs(
        journalEntries: journalEntries,
        productJournals: productJournals,
        acneRosaceaLogs: acneRosaceaLogs,
        trackedProducts: trackedProducts,
        productFeedback: productFeedback,
        activePeptideNames: activePeptideNames,
      ),
      recommendedPeptideNames: recommendedPeptideNames,
    ).take(maxNotes))
      n.text,
  ];

  /// The notes in [notes] that are about one of [names] (a product, its
  /// ingredients, or routine steps), capped at [maxNotes]. Notes with no
  /// subject (a reaction note naming nothing) are left out.
  static List<String> relevantTo(
    List<ContextNote> notes,
    Iterable<String> names,
  ) {
    final wanted = [
      for (final n in names)
        if (n.trim().length >= 3) n.trim().toLowerCase(),
    ];
    if (wanted.isEmpty) return const <String>[];
    bool matches(String subject) {
      final s = subject.trim().toLowerCase();
      if (s.length < 3) return false;
      return wanted.any((w) => _hasWords(w, s) || _hasWords(s, w));
    }

    return [
      for (final n in notes)
        if (n.subjects.any(matches)) n.text,
    ].take(maxNotes).toList();
  }

  /// Whether [text] contains [words] as whole words ("glow serum" has
  /// "serum", but "serums" does not have "serum").
  static bool _hasWords(String text, String words) => RegExp(
    '(^|[^a-z0-9])${RegExp.escape(words)}(\$|[^a-z0-9])',
  ).hasMatch(text);

  /// All notes for [inputs], uncapped, each with its subjects.
  static List<ContextNote> contextNotes(
    RecommendationContextInputs inputs, {
    List<String> recommendedPeptideNames = const <String>[],
  }) {
    final notes = <ContextNote>[];
    void add(String text, List<String> subjects) {
      if (notes.any((n) => n.text == text)) return;
      notes.add(ContextNote(text, subjects: subjects));
    }

    String day(DateTime date) => DateFormat('MMM d').format(date);
    final irritationTexts = <String>[];
    final trackedProducts = inputs.trackedProducts;

    // 1. Product feedback logged with an irritation score at the flag.
    final flaggedFeedback = <String, ProductFeedbackEntry>{};
    for (final f in inputs.productFeedback) {
      if (f.irritation < feedbackIrritationFlag) continue;
      final name = f.productName.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final prior = flaggedFeedback[key];
      if (prior == null || f.date.isAfter(prior.date)) flaggedFeedback[key] = f;
    }
    for (final f in flaggedFeedback.values) {
      add(
        'You previously logged irritation (${f.irritation}/10) with '
        '${f.productName.trim()} on ${day(f.date)}.',
        [f.productName.trim()],
      );
      irritationTexts.add('${f.productName} ${f.notes}'.toLowerCase());
    }

    // 2. Journal and acne & rosacea log irritation notes, tied to a
    // product when one is named.
    final productNames = <String>{
      for (final p in trackedProducts)
        if (p.name.trim().length >= 3) p.name.trim(),
    };
    String? namedProduct(String text) {
      final lower = text.toLowerCase();
      for (final name in productNames) {
        if (lower.contains(name.toLowerCase())) return name;
      }
      return null;
    }

    final flagged =
        <({DateTime date, String? product, String text, String source})>[];
    inputs.productJournals.forEach((product, entries) {
      for (final e in entries.where(isIrritationNote)) {
        flagged.add((
          date: e.date,
          product: product.trim().isEmpty ? null : product.trim(),
          text: '$product ${e.title} ${e.content}',
          source: 'journal',
        ));
      }
    });
    for (final e in inputs.journalEntries.where(isIrritationNote)) {
      final text = '${e.title} ${e.content}';
      flagged.add((
        date: e.date,
        product: namedProduct(text),
        text: text,
        source: 'journal',
      ));
    }
    for (final log in inputs.acneRosaceaLogs) {
      if (!mentionsIrritation(log.note)) continue;
      flagged.add((
        date: log.timestamp,
        product: namedProduct(log.note),
        text: log.note,
        source: 'acne & rosacea log',
      ));
    }
    flagged.sort((a, b) => b.date.compareTo(a.date));
    final unnamedShown = <String>{};
    for (final j in flagged) {
      irritationTexts.add(j.text.toLowerCase());
      if (j.product != null) {
        add(
          'You previously noted irritation with ${j.product} in your '
          '${j.source} (${day(j.date)}).',
          [j.product!],
        );
      } else if (unnamedShown.add(j.source)) {
        add('You noted a reaction in your ${j.source} on ${day(j.date)}.', []);
      }
    }

    // 3. Ingredients (or recommended peptides) that appeared in an earlier
    // irritation note.
    if (irritationTexts.isNotEmpty) {
      for (final p in trackedProducts.where((p) => p.endDate == null)) {
        final name = p.name.trim().toLowerCase();
        for (final raw in p.keyIngredients.split(RegExp(r'[,;/\n]'))) {
          final ingredient = raw.trim();
          if (ingredient.length < 4) continue;
          final lower = ingredient.toLowerCase();
          final seen = irritationTexts.any(
            (t) => t.contains(lower) && (name.isEmpty || !t.contains(name)),
          );
          if (seen) {
            add(
              '${p.name.trim()} contains $ingredient, which appeared in an '
              'earlier irritation note.',
              [p.name.trim(), ingredient],
            );
          }
        }
      }
      for (final peptide in recommendedPeptideNames) {
        final base = peptide.split('(').first.trim().toLowerCase();
        final token = base.split(' ').first;
        final seen = irritationTexts.any(
          (t) =>
              (base.isNotEmpty && t.contains(base)) ||
              (token.length >= 5 && t.contains(token)),
        );
        if (seen) {
          add('${peptide.trim()} appeared in an earlier irritation note.', [
            peptide.trim(),
          ]);
        }
      }
    }

    // 4. Compatibility warnings already saved with the latest feedback for
    // each product.
    final latestFeedback = <String, ProductFeedbackEntry>{};
    for (final f in inputs.productFeedback) {
      final key = f.productName.trim().toLowerCase();
      if (key.isEmpty || f.compatibilityWarnings.isEmpty) continue;
      final prior = latestFeedback[key];
      if (prior == null || f.date.isAfter(prior.date)) latestFeedback[key] = f;
    }
    for (final f in latestFeedback.values) {
      add(
        'When you logged ${f.productName.trim()}, the app noted: '
        '${f.compatibilityWarnings.first}',
        [f.productName.trim()],
      );
    }

    // 5. Existing interaction rules across what is in use and what is shown.
    final items = <InteractionItem>[
      for (final name in recommendedPeptideNames)
        (label: name.trim(), text: name),
      for (final name in inputs.activePeptideNames)
        (label: name.trim(), text: name),
      for (final p in trackedProducts.where((p) => p.endDate == null))
        (label: p.name.trim(), text: '${p.name} ${p.keyIngredients}'),
    ];
    final ingredientsOf = {
      for (final p in trackedProducts)
        p.name.trim(): p.keyIngredients
            .split(RegExp(r'[,;/\n]'))
            .map((s) => s.trim())
            .where((s) => s.length >= 4),
    };
    for (final m in interactionMatches(items)) {
      add(
        '${m.a} and ${m.b} are often discussed as a potential interaction. '
        '${m.message}',
        [m.a, m.b, ...?ingredientsOf[m.a], ...?ingredientsOf[m.b]],
      );
    }

    return notes;
  }
}
