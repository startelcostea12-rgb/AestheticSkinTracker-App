/// Context notes shown beside the scan-based recommendations, built only
/// from what the user already logged in the app: journal entries, tracked
/// products, product feedback, and the existing interaction rules. It never
/// changes which recommendations are selected, and returns nothing when
/// nothing relevant is stored.
library;

import 'package:intl/intl.dart';

import '../models/journal_entry.dart';
import '../models/product_feedback.dart';
import '../models/product_tracker.dart';
import 'peptide_interactions.dart';

class RecommendationContext {
  const RecommendationContext._();

  /// Words that mark a journal note as an irritation / reaction note.
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

  /// Same cut-off the product feedback screen uses for "sensitive" (0–10).
  static const int feedbackIrritationFlag = 5;

  static const int maxNotes = 5;

  static bool isIrritationNote(JournalEntry entry) {
    if (entry.title.trim().toLowerCase() == 'reaction') return true;
    final text = '${entry.title} ${entry.content}'.toLowerCase();
    return irritationWords.any(text.contains);
  }

  static List<String> notes({
    List<JournalEntry> journalEntries = const <JournalEntry>[],
    Map<String, List<JournalEntry>> productJournals =
        const <String, List<JournalEntry>>{},
    List<TrackedProduct> trackedProducts = const <TrackedProduct>[],
    List<ProductFeedbackEntry> productFeedback = const <ProductFeedbackEntry>[],
    List<String> activePeptideNames = const <String>[],
    List<String> recommendedPeptideNames = const <String>[],
  }) {
    final notes = <String>[];
    void add(String note) {
      if (!notes.contains(note)) notes.add(note);
    }

    String day(DateTime date) => DateFormat('MMM d').format(date);
    final irritationTexts = <String>[];

    // 1. Product feedback logged with an irritation score at the flag.
    final flaggedFeedback = <String, ProductFeedbackEntry>{};
    for (final f in productFeedback) {
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
      );
      irritationTexts.add('${f.productName} ${f.notes}'.toLowerCase());
    }

    // 2. Journal irritation notes, tied to a product when one is named.
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

    final flaggedJournal = <({DateTime date, String? product, String text})>[];
    productJournals.forEach((product, entries) {
      for (final e in entries.where(isIrritationNote)) {
        flaggedJournal.add((
          date: e.date,
          product: product.trim().isEmpty ? null : product.trim(),
          text: '$product ${e.title} ${e.content}',
        ));
      }
    });
    for (final e in journalEntries.where(isIrritationNote)) {
      final text = '${e.title} ${e.content}';
      flaggedJournal.add((
        date: e.date,
        product: namedProduct(text),
        text: text,
      ));
    }
    flaggedJournal.sort((a, b) => b.date.compareTo(a.date));
    var unnamedShown = false;
    for (final j in flaggedJournal) {
      irritationTexts.add(j.text.toLowerCase());
      if (j.product != null) {
        add(
          'You previously noted irritation with ${j.product} in your '
          'journal (${day(j.date)}).',
        );
      } else if (!unnamedShown) {
        unnamedShown = true;
        add('You noted a reaction in your journal on ${day(j.date)}.');
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
          add('${peptide.trim()} appeared in an earlier irritation note.');
        }
      }
    }

    // 4. Compatibility warnings already saved with the latest feedback for
    // each product.
    final latestFeedback = <String, ProductFeedbackEntry>{};
    for (final f in productFeedback) {
      final key = f.productName.trim().toLowerCase();
      if (key.isEmpty || f.compatibilityWarnings.isEmpty) continue;
      final prior = latestFeedback[key];
      if (prior == null || f.date.isAfter(prior.date)) latestFeedback[key] = f;
    }
    for (final f in latestFeedback.values) {
      add(
        'When you logged ${f.productName.trim()}, the app noted: '
        '${f.compatibilityWarnings.first}',
      );
    }

    // 5. Existing interaction rules across what is in use and what is shown.
    final items = <InteractionItem>[
      for (final name in recommendedPeptideNames)
        (label: name.trim(), text: name),
      for (final name in activePeptideNames) (label: name.trim(), text: name),
      for (final p in trackedProducts.where((p) => p.endDate == null))
        (label: p.name.trim(), text: '${p.name} ${p.keyIngredients}'),
    ];
    for (final m in interactionMatches(items)) {
      add(
        '${m.a} and ${m.b} are often discussed as a potential interaction. '
        '${m.message}',
      );
    }

    return notes.take(maxNotes).toList();
  }
}
