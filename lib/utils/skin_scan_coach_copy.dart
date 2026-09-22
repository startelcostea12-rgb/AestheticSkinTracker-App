class SkinScanCoachCopy {
  const SkinScanCoachCopy._();

  static String buildInsight({
    required Map<String, double> scores,
    required Map<String, dynamic> metricMatrix,
    required Map<String, double> trendDeltas,
    required bool isFollowUp,
    required double sensitivitySignal,
  }) {
    final topConcerns = _topConcerns(scores);
    final barrierStressed =
        sensitivitySignal >= 4.0 ||
        (scores['redness'] ?? 0) >= 4.0 ||
        (scores['rosacea_intensity'] ?? 0) >= 4.0;

    final sentences = <String>[];
    if (topConcerns.isEmpty) {
      sentences.add(
        isFollowUp
            ? 'This follow-up reads fairly steady versus baseline, so the safest move is to keep the routine simple and consistent.'
            : 'Starting point shows a fairly calm overall pattern, so this scan is best used as your benchmark rather than a progress claim.',
      );
    } else {
      final leadPhrase = _joinWithCommasAndAnd(
        topConcerns
            .take(3)
            .map(
              (entry) =>
                  '${entry.label} at ${entry.value.toStringAsFixed(1)}/10',
            )
            .toList(),
      );
      sentences.add(
        isFollowUp
            ? 'This follow-up centers on $leadPhrase.'
            : 'Starting point shows $leadPhrase.',
      );
    }

    final highest = topConcerns.isEmpty
        ? 0.0
        : topConcerns.map((entry) => entry.value).reduce((a, b) => a > b ? a : b);
    if (highest >= 4.0) {
      sentences.add(
        barrierStressed
            ? 'That pattern usually means calm-first care should lead, because the barrier looks a little reactive and the skin will tolerate less when actives are stacked.'
            : 'That pattern usually means one or two focused steps will help more than a long routine, because the main signals are still doing the talking.',
      );
    } else if (topConcerns.isNotEmpty) {
      sentences.add(
        'The scan is showing a lighter concern pattern overall, so the goal is to keep the skin steady and avoid overcorrecting too early.',
      );
    }

    if (isFollowUp) {
      final trendSentences = _trendSentences(trendDeltas);
      if (trendSentences.isEmpty) {
        sentences.add(
          'Most of the measured pattern looks stable versus baseline, which is useful because it means the current routine is at least holding its ground.',
        );
      } else {
        sentences.addAll(trendSentences.take(2));
      }
    } else {
      sentences.add(
        barrierStressed
            ? 'Prioritize a gentle cleanse, a barrier moisturizer, and daily SPF first, then introduce only one calm active if the skin is already tolerating it.'
            : 'Prioritize a gentle cleanse, a barrier moisturizer, and daily SPF first, then choose only one targeted active based on whether redness, pigment, texture, or breakouts are the leading concern.',
      );
    }

    final rosaceaSignal = scores['rosacea_intensity'] ?? 0;
    final acneSignal = scores['acne_severity'] ?? 0;
    if (rosaceaSignal >= 4.0 || sensitivitySignal >= 4.0) {
      sentences.add(
        'Avoid fragrance, menthol, scrubs, and high-strength acids for now, because those are more likely to aggravate redness or stinging than to help this pattern.',
      );
    } else if (acneSignal >= 3.5) {
      sentences.add(
        'Breakout care should stay targeted rather than stacked, so keep any acne step spot-only or very limited until the barrier stays calm.',
      );
    } else {
      final pigmentSignal = scores['pigment'] ?? 0;
      final textureSignal = scores['texture'] ?? 0;
      final wrinkleSignal = scores['wrinkle'] ?? 0;
      final visibleTargets = <String>[
        if (pigmentSignal >= 3.5) 'tone support for pigment',
        if (textureSignal >= 3.5) 'texture support',
        if (wrinkleSignal >= 3.5) 'firmness and line support',
      ];
      if (visibleTargets.isNotEmpty) {
        sentences.add(
          'The routine should stay centered on ${_joinWithCommasAndAnd(visibleTargets)} rather than on multiple actives at once.',
        );
      }
    }

    return sentences.where((sentence) => sentence.trim().isNotEmpty).take(6).join(' ');
  }

  static String buildRoutineHeader({
    required Map<String, double> scores,
    required bool isFollowUp,
    required bool barrierStressed,
    required double sensitivitySignal,
  }) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final concernParts = <String>[
      if (redness >= 4.0) 'redness ${redness.toStringAsFixed(1)}',
      if (rosacea >= 4.0) 'rosacea ${rosacea.toStringAsFixed(1)}',
      if (acne >= 3.5) 'breakouts ${acne.toStringAsFixed(1)}',
      if (texture >= 3.5) 'texture ${texture.toStringAsFixed(1)}',
      if (pigment >= 3.5) 'pigment ${pigment.toStringAsFixed(1)}',
      if (wrinkle >= 3.5) 'wrinkles ${wrinkle.toStringAsFixed(1)}',
    ];

    final concernText = concernParts.isEmpty
        ? 'a fairly calm baseline overall'
        : _joinWithCommasAndAnd(concernParts);

    if (isFollowUp) {
      if (barrierStressed || sensitivitySignal >= 4.0) {
        return 'The follow-up is still reading as a calm-first day, with barrier support more important than pushing stronger actives. The main signals are $concernText, so keep the plan simple and steady.';
      }
      return 'The follow-up is centered on $concernText, which means the best move is to keep one clear routine in place and only adjust a single step if the skin is already tolerating it.';
    }

    if (barrierStressed || sensitivitySignal >= 4.0) {
      return 'Starting point shows $concernText, and the barrier looks a bit reactive, so the routine should stay gentle, fragrance-free, and low-spirited on actives until the skin feels calmer.';
    }

    return 'Starting point shows $concernText, so I would build around a gentle cleanse, hydration, barrier support, and one targeted active rather than trying to do everything at once.';
  }

  static ({List<String> amSteps, List<String> pmSteps}) buildRoutine({
    required Map<String, double> scores,
    required bool isFollowUp,
    required double sensitivitySignal,
    required bool barrierStressed,
  }) {
    final redness = scores['redness'] ?? 0;
    final rosacea = scores['rosacea_intensity'] ?? 0;
    final acne = scores['acne_severity'] ?? 0;
    final pigment = scores['pigment'] ?? 0;
    final texture = scores['texture'] ?? 0;
    final wrinkle = scores['wrinkle'] ?? 0;
    final inflammation = [
      redness,
      rosacea,
      acne,
    ].reduce((a, b) => a > b ? a : b);
    final calmFirst = inflammation >= 4 || barrierStressed || sensitivitySignal >= 4;
    final allowActives = !calmFirst && isFollowUp;

    final am = <String>[
      calmFirst
          ? 'Gentle low-pH cleanser or a water rinse if your skin is dry, so the barrier stays quiet while redness and sensitivity settle.'
          : 'Gentle low-pH cleanser to lift overnight oil and sunscreen without stripping the skin that this scan is trying to protect.',
      calmFirst
          ? 'Centella or heartleaf toner / essence, because that is the calmest way to support a reactive barrier before any active treatment.'
          : pigment >= 3.5
          ? 'Hydrating toner or essence, because the scan shows tone support is useful and hydration keeps brightening steps better tolerated.'
          : texture >= 3.5 || wrinkle >= 3.5
          ? 'Peptide-friendly hydrating essence, because texture and firmness work best when the skin is comfortable first.'
          : 'Simple hydrating essence, because the skin does not need extra noise in the morning.',
      calmFirst
          ? 'Ceramide moisturizer only, or a niacinamide 2-5% serum if you already know your skin tolerates it, so the morning stays barrier-first.'
          : acne >= 3.5
          ? 'Niacinamide 2-5% serum or a light breakout-support serum, because the scan shows acne is present but the routine should still avoid stacking actives.'
          : pigment >= 3.5
          ? 'Niacinamide 2-5% serum, because it fits uneven tone and visible redness without pushing the skin too hard.'
          : 'Ceramide moisturizer, because keeping water in the skin is still the safest way to support the current scan pattern.',
      'Broad-spectrum SPF 30+, because it protects collagen, pigment, redness, and any progress this scan is tracking.',
    ];

    final pm = <String>[
      'Gentle cleanse, and if you wore sunscreen or makeup, double cleanse first so the evening routine starts from a clean surface.',
      calmFirst
          ? 'Centella, snail mucin, or a bland hydrating serum tonight, because the scan says calming the barrier should come before any stronger treatment.'
          : allowActives && (texture >= 3.5 || wrinkle >= 3.5)
          ? 'GHK-Cu Copper Tripeptide-1 at night, because texture and firmness concerns respond best when the barrier is calm and the routine stays consistent.'
          : allowActives && pigment >= 3.5
          ? 'GHK-Cu Copper Tripeptide-1 or another gentle peptide serum, because the scan favors quiet repair more than aggressive exfoliation.'
          : 'Hydrating serum or peptide step only if the skin stays comfortable, because the routine does not need to be overloaded.',
      calmFirst
          ? 'Ceramide barrier cream, because sealing the routine with lipids is the safest way to keep the skin quiet while redness or sensitivity is visible.'
          : acne >= 3.5
          ? 'Barrier cream plus a spot-only acne patch on active blemishes, because breakout support should stay targeted instead of turning into a full-face stack.'
          : 'Barrier cream, because this scan still benefits more from steady repair than from piling on more treatment steps.',
      calmFirst
          ? 'Skip acids, retinoids, and scrubs for now; if you want a weekly active later, wait until the skin is calm for several nights in a row.'
          : allowActives && (texture >= 3.5 || wrinkle >= 3.5 || pigment >= 3.5)
          ? 'If you add an exfoliant later, keep it to one calm night a week and do not stack it with GHK-Cu or spot acne care.'
          : 'If the skin feels stable, keep any extra treatment step optional rather than mandatory so you do not crowd the routine.',
    ];

    return (amSteps: am, pmSteps: pm);
  }

  static List<({String key, String label, double value})> _topConcerns(
    Map<String, double> scores,
  ) {
    final concerns = <({String key, String label, double value})>[
      (key: 'redness', label: 'redness / flushing', value: scores['redness'] ?? 0),
      (key: 'rosacea_intensity', label: 'rosacea-pattern reactivity', value: scores['rosacea_intensity'] ?? 0),
      (key: 'acne_severity', label: 'breakout activity', value: scores['acne_severity'] ?? 0),
      (key: 'texture', label: 'texture roughness', value: scores['texture'] ?? 0),
      (key: 'pigment', label: 'uneven tone / marks', value: scores['pigment'] ?? 0),
      (key: 'wrinkle', label: 'fine lines / wrinkles', value: scores['wrinkle'] ?? 0),
    ]..sort((a, b) => b.value.compareTo(a.value));

    return concerns.where((entry) => entry.value >= 0.5).take(3).toList();
  }

  static List<String> _trendSentences(Map<String, double> trendDeltas) {
    if (trendDeltas.isEmpty) return const [];

    final trendSpecs = <({String key, String label})>[
      (key: 'localized_redness', label: 'Redness'),
      (key: 'texture_smoothness', label: 'Texture'),
      (key: 'pigment_load', label: 'Pigment'),
      (key: 'wrinkle_load', label: 'Wrinkles'),
      (key: 'breakout_activity', label: 'Breakouts'),
      (key: 'rosacea_severity', label: 'Rosacea reactivity'),
    ];
    final sentences = <String>[];
    for (final spec in trendSpecs) {
      final delta = trendDeltas[spec.key];
      if (delta == null || !delta.isFinite) continue;
      if (delta.abs() < 1.0) {
        sentences.add('${spec.label} is stable versus baseline, so there is no need to chase a bigger change right now.');
      } else if (delta < 0) {
        sentences.add('${spec.label} has improved versus baseline.');
      } else {
        sentences.add('${spec.label} has worsened versus baseline.');
      }
      if (sentences.length >= 2) break;
    }
    return sentences;
  }

  static String _joinWithCommasAndAnd(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items.first} and ${items.last}';
    return '${items.sublist(0, items.length - 1).join(', ')}, and ${items.last}';
  }
}