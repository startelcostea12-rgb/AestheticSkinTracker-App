/// ai_recovery_plan.dart
///
/// Procedure-aware AI Recovery Plan generator.
///
/// Combines:
///   • Procedure category (via [ProcedureIntelligence.categoryFor])
///   • Recovery stage (days since procedure start)
///   • Latest scan metrics (esp. redness / texture / pore)
///
/// Produces a structured, clinical-yet-supportive plan rendered by the
/// Procedure Record screen's AI Recovery Plan section.
library ai_recovery_plan;

import '../models/scan_history.dart';
import 'procedure_intelligence.dart';

/// One actionable line in the recovery plan, paired with an optional reason.
class RecoveryPlanItem {
  const RecoveryPlanItem(this.text, {this.reason});
  final String text;

  /// Optional short clinical justification ("because erythema is elevated").
  final String? reason;
}

/// A fully structured, procedure-aware recovery plan.
class AiRecoveryPlan {
  const AiRecoveryPlan({
    required this.phaseLabel,
    required this.phaseDescription,
    required this.summary,
    required this.dailyFocus,
    required this.weeklyFocus,
    required this.avoid,
    required this.redFlags,
  });

  /// e.g. "Day 1–3 · Acute Healing"
  final String phaseLabel;

  /// One-liner explaining what's happening biologically in this phase.
  final String phaseDescription;

  /// 1–2 sentence personalized summary mentioning current metric trends.
  final String summary;

  final List<RecoveryPlanItem> dailyFocus;
  final List<RecoveryPlanItem> weeklyFocus;
  final List<RecoveryPlanItem> avoid;
  final List<RecoveryPlanItem> redFlags;
}

class AiRecoveryPlanEngine {
  /// Build a full recovery plan from the inputs.
  static AiRecoveryPlan generate({
    required String? procedureType,
    required DateTime startDate,
    SkinMetrics? latestMetrics,
    SkinMetrics? baselineMetrics,
    int scanCount = 0,
  }) {
    final daysSince = DateTime.now()
        .difference(startDate)
        .inDays
        .clamp(-30, 999);
    final dayN = daysSince + 1;
    final category = ProcedureIntelligence.categoryFor(procedureType);

    final phase = _phaseFor(category, dayN);

    final summary = _summary(
      category: category,
      procedureType: procedureType,
      dayN: dayN,
      phase: phase,
      latest: latestMetrics,
      baseline: baselineMetrics,
      scanCount: scanCount,
    );

    final canonicalType = (procedureType ?? '').toLowerCase();
    final isMicroneedling =
        canonicalType.contains('microneedl') ||
        canonicalType.contains('rf microneedl') ||
        canonicalType.contains('morpheus');

    return AiRecoveryPlan(
      phaseLabel: '${_dayRangeLabel(phase, dayN)} · ${phase.title}',
      phaseDescription: phase.description,
      summary: summary,
      dailyFocus: _dailyFocus(
        category,
        phase,
        latestMetrics,
        isMicroneedling: isMicroneedling,
      ),
      weeklyFocus: _weeklyFocus(
        category,
        phase,
        latestMetrics,
        dayN: dayN,
        isMicroneedling: isMicroneedling,
      ),
      avoid: _avoid(category, phase, isMicroneedling: isMicroneedling),
      redFlags: _redFlags(category, phase),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Phase modeling
  // ────────────────────────────────────────────────────────────────────────

  static _PhaseBucket _phaseFor(ProcedureCategory category, int dayN) {
    // Surgical / body contouring move slower; injectables / lasers / peptides faster.
    final isSurgical =
        category == ProcedureCategory.surgicalFace ||
        category == ProcedureCategory.bodyContouring ||
        category == ProcedureCategory.hairTransplant;
    if (dayN <= 0) return _PhaseBucket.preOp;
    if (isSurgical) {
      if (dayN <= 3) return _PhaseBucket.acute;
      if (dayN <= 14) return _PhaseBucket.earlyRecovery;
      if (dayN <= 42) return _PhaseBucket.activeHealing;
      if (dayN <= 90) return _PhaseBucket.refinement;
      if (dayN <= 180) return _PhaseBucket.stabilizing;
      return _PhaseBucket.maintenance;
    }
    // Injectables, lasers, peels, microneedling, peptides, general skincare.
    if (dayN <= 2) return _PhaseBucket.acute;
    if (dayN <= 7) return _PhaseBucket.earlyRecovery;
    if (dayN <= 21) return _PhaseBucket.activeHealing;
    if (dayN <= 60) return _PhaseBucket.refinement;
    if (dayN <= 120) return _PhaseBucket.stabilizing;
    return _PhaseBucket.maintenance;
  }

  static String _dayRangeLabel(_PhaseBucket phase, int dayN) {
    switch (phase) {
      case _PhaseBucket.preOp:
        return 'Pre-procedure';
      case _PhaseBucket.acute:
        return 'Day $dayN';
      case _PhaseBucket.earlyRecovery:
        return 'Day $dayN · Week ${((dayN) / 7).ceil()}';
      case _PhaseBucket.activeHealing:
        return 'Week ${((dayN) / 7).ceil()}';
      case _PhaseBucket.refinement:
        return 'Month ${((dayN) / 30).ceil()}';
      case _PhaseBucket.stabilizing:
        return 'Month ${((dayN) / 30).ceil()}';
      case _PhaseBucket.maintenance:
        return 'Month ${((dayN) / 30).ceil()}+';
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // Summary copy
  // ────────────────────────────────────────────────────────────────────────

  static String _summary({
    required ProcedureCategory category,
    required String? procedureType,
    required int dayN,
    required _PhaseBucket phase,
    SkinMetrics? latest,
    SkinMetrics? baseline,
    required int scanCount,
  }) {
    final pt = (procedureType?.trim().isNotEmpty ?? false)
        ? procedureType!.trim()
        : 'your procedure';

    // Build metric callouts when we have data.
    final callouts = <String>[];
    if (latest != null) {
      if (latest.redness >= 6.0) {
        callouts.add('erythema is still elevated');
      } else if (latest.redness <= 3.5 &&
          baseline != null &&
          baseline.redness > 4.5) {
        callouts.add('erythema is fading well');
      }
      if (latest.texture >= 6.0) {
        callouts.add('skin texture remains rough');
      } else if (latest.texture <= 4.0 &&
          baseline != null &&
          baseline.texture > 5.0) {
        callouts.add('texture is smoothing');
      }
      if (latest.pore >= 6.0) {
        callouts.add('pore visibility is high');
      }
    }

    final metricLine = callouts.isEmpty
        ? (scanCount == 0
              ? 'Log a progress scan to personalize this plan with your latest skin metrics.'
              : 'Your latest scan trend looks consistent with expectations for this stage.')
        : 'Latest scan signals: ${callouts.join(', ')}.';

    final phaseLine = switch (phase) {
      _PhaseBucket.preOp =>
        'Pre-procedure window for $pt — focus on a calm, well-hydrated barrier going in.',
      _PhaseBucket.acute =>
        'Day $dayN of $pt — this is the acute window. Minimize stress on the treatment area and let inflammation peak and resolve cleanly.',
      _PhaseBucket.earlyRecovery =>
        'Early recovery from $pt — barrier rebuild and downtime resolution are the priorities.',
      _PhaseBucket.activeHealing =>
        'Active healing phase for $pt — collagen remodeling and pigment normalization are underway.',
      _PhaseBucket.refinement =>
        'Refinement phase for $pt — results are emerging; protect your investment.',
      _PhaseBucket.stabilizing =>
        'Results are stabilizing after $pt — long-term skin quality protocols matter most now.',
      _PhaseBucket.maintenance =>
        'Maintenance phase for $pt — focus on prevention, sun protection, and consistent baseline care.',
    };

    return '$phaseLine $metricLine';
  }

  // ────────────────────────────────────────────────────────────────────────
  // Daily focus — combines phase + metric reactivity
  // ────────────────────────────────────────────────────────────────────────

  static List<RecoveryPlanItem> _dailyFocus(
    ProcedureCategory category,
    _PhaseBucket phase,
    SkinMetrics? latest, {
    bool isMicroneedling = false,
  }) {
    final items = <RecoveryPlanItem>[];

    // Universal early-window items.
    if (phase == _PhaseBucket.acute || phase == _PhaseBucket.earlyRecovery) {
      items.add(
        const RecoveryPlanItem(
          'Cold compresses (10 minutes, 3–4× daily)',
          reason: 'reduces inflammation and swelling',
        ),
      );
      items.add(
        const RecoveryPlanItem(
          'Gentle cleansing morning & night with a non-foaming, fragrance-free cleanser',
        ),
      );
      items.add(
        const RecoveryPlanItem(
          'Bland occlusive moisturizer (Aquaphor / Cicaplast Baume) on the treated area',
          reason: 'supports barrier recovery',
        ),
      );
    }

    // Category-specific daily anchors.
    switch (category) {
      case ProcedureCategory.laserPeel:
        if (phase == _PhaseBucket.acute) {
          if (isMicroneedling) {
            items.add(
              const RecoveryPlanItem(
                'Keep micro-channels dry for the first 4–6 hours — no water, makeup, or active serums',
                reason: 'channels stay open while sealing',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Apply a peptide or growth-factor serum tonight (TNS, Skinbetter A.S.C.)',
                reason: 'open channels maximize absorption for the first 24h',
              ),
            );
          }
          items.add(
            const RecoveryPlanItem(
              'Sleep slightly elevated for the first 3 nights',
              reason: 'limits overnight swelling',
            ),
          );
        }
        if (isMicroneedling &&
            (phase == _PhaseBucket.acute ||
                phase == _PhaseBucket.earlyRecovery)) {
          items.add(
            const RecoveryPlanItem(
              'Hyaluronic-acid serum on damp skin AM & PM',
              reason: 'hydrates micro-channels as they close',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Lukewarm rinses only — no hot showers or steam',
              reason:
                  'heat reopens partially sealed micro-channels and prolongs erythema',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Mineral SPF 50+ every morning, reapply every 2 hours outdoors',
            reason: 'prevents post-inflammatory hyperpigmentation',
          ),
        );
        if (isMicroneedling && phase == _PhaseBucket.earlyRecovery) {
          items.add(
            const RecoveryPlanItem(
              'Resume azelaic acid 10% PM only once tightness fully resolves (typically day 4–5)',
              reason: 'pre-empts PIH while channels are still photoreactive',
            ),
          );
        }
        if (phase == _PhaseBucket.activeHealing ||
            phase == _PhaseBucket.refinement) {
          items.add(
            const RecoveryPlanItem(
              'Add a niacinamide serum (5–10%) before moisturizer',
              reason: 'evens tone and supports the barrier',
            ),
          );
        }
        if (isMicroneedling && phase == _PhaseBucket.activeHealing) {
          items.add(
            const RecoveryPlanItem(
              'Layer a growth-factor or copper-peptide serum AM & PM',
              reason:
                  'you are inside the 3–6 week collagen-stimulation window — every application compounds the result',
            ),
          );
        }
        if (isMicroneedling && phase == _PhaseBucket.refinement) {
          items.add(
            const RecoveryPlanItem(
              'Layer a copper-peptide serum 3×/week',
              reason: 'supports collagen remodeling between sessions',
            ),
          );
        }
        break;
      case ProcedureCategory.injectables:
        if (phase == _PhaseBucket.acute) {
          items.add(
            const RecoveryPlanItem(
              'Stay upright for 4 hours post-injection',
              reason: 'minimizes product migration',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Cool compresses for bruising (no pressure)',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Hydrating serum (hyaluronic acid) under SPF 50',
          ),
        );
        break;
      case ProcedureCategory.surgicalFace:
        if (phase == _PhaseBucket.acute ||
            phase == _PhaseBucket.earlyRecovery) {
          items.add(
            const RecoveryPlanItem(
              'Sleep with head elevated 30–45°',
              reason: 'reduces post-op swelling',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Drain log + incision care exactly as prescribed',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Scar care: silicone gel/strips on incisions once cleared by surgeon',
          ),
        );
        break;
      case ProcedureCategory.bodyContouring:
        if (phase == _PhaseBucket.acute ||
            phase == _PhaseBucket.earlyRecovery) {
          items.add(
            const RecoveryPlanItem(
              'Compression garment 22+ hours/day, removed only to shower',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Short, gentle walks every 1–2 hours during the day',
              reason: 'lowers DVT risk',
            ),
          );
        }
        if (phase == _PhaseBucket.earlyRecovery ||
            phase == _PhaseBucket.activeHealing) {
          items.add(
            const RecoveryPlanItem(
              'Lymphatic massage 3–5×/week per surgeon protocol',
              reason: 'helps swelling resolve evenly',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Protein-forward meals (1.2–1.6 g/kg body weight) + 2.5–3 L water/day',
            reason: 'supports tissue repair',
          ),
        );
        break;
      case ProcedureCategory.hairTransplant:
        if (phase == _PhaseBucket.acute ||
            phase == _PhaseBucket.earlyRecovery) {
          items.add(
            const RecoveryPlanItem(
              'Sleep on a travel pillow, face-up, head elevated',
              reason: 'protects grafts',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Saline mist on grafts every 1–2 hours while awake',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Gentle shampoo from day 4 (or per surgeon) — no rubbing',
          ),
        );
        break;
      case ProcedureCategory.bodyComposition:
        items.add(
          const RecoveryPlanItem(
            'Hit your daily protein target (1.6 g/kg) to protect lean mass',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Resistance training 3–4×/week + 7–10k steps/day',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Hydrate aggressively (2.5–3 L/day) and watch for nausea cues',
          ),
        );
        break;
      case ProcedureCategory.generalSkincare:
        items.add(
          const RecoveryPlanItem(
            'AM: gentle cleanser → vitamin C → moisturizer → SPF 50',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'PM: gentle cleanser → active (retinoid/AHA per tolerance) → barrier cream',
          ),
        );
        break;
    }

    // Metric-reactive additions.
    if (latest != null) {
      if (latest.redness >= 6.0) {
        items.add(
          const RecoveryPlanItem(
            'Add a centella / azelaic-acid calming serum twice daily',
            reason: 'elevated erythema in your latest scan',
          ),
        );
      }
      if (latest.pore >= 6.0 &&
          (phase == _PhaseBucket.refinement ||
              phase == _PhaseBucket.stabilizing ||
              phase == _PhaseBucket.maintenance)) {
        items.add(
          const RecoveryPlanItem(
            'Introduce a low-strength BHA (salicylic 1–2%) 2–3×/week',
            reason: 'pore visibility is elevated',
          ),
        );
      }
    }

    return items;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Weekly focus — bigger-picture habits
  // ────────────────────────────────────────────────────────────────────────

  static List<RecoveryPlanItem> _weeklyFocus(
    ProcedureCategory category,
    _PhaseBucket phase,
    SkinMetrics? latest, {
    required int dayN,
    bool isMicroneedling = false,
  }) {
    final items = <RecoveryPlanItem>[
      const RecoveryPlanItem(
        'Capture a weekly progress scan in matched lighting and angle',
        reason: 'enables trend-aware AI insights from the same baseline',
      ),
      const RecoveryPlanItem(
        'Log one journal entry: tightness, itch, tenderness, sleep quality',
      ),
    ];

    switch (category) {
      case ProcedureCategory.laserPeel:
        if (isMicroneedling) {
          if (phase == _PhaseBucket.acute ||
              phase == _PhaseBucket.earlyRecovery) {
            items.add(
              const RecoveryPlanItem(
                'Hold all actives this week (retinoids, AHA/BHA, vitamin C)',
                reason:
                    'micro-channels are still sealing — actives sting and risk PIH',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Plan a low-stimulation week: limited workouts, no saunas, no facials',
                reason:
                    'sweat and heat extend post-treatment erythema and reopen micro-channels',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Run a peptide or growth-factor serum AM & PM all week',
                reason:
                    'first 7 days are your highest-absorption window — amplifies the collagen response',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Pre-book your next microneedling session 4–6 weeks out',
                reason:
                    'locks in cadence with the dermal remodeling cycle before scheduling drifts',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Layer an azelaic acid 10% or tranexamic acid 3% serum PM from day 5',
                reason:
                    'preempts post-inflammatory hyperpigmentation before pigment activity peaks',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Sleep 7–8 h on a clean silk pillowcase, fresh nightly',
                reason:
                    'reduces friction on sealing channels and supports overnight collagen synthesis',
              ),
            );
          } else if (phase == _PhaseBucket.activeHealing) {
            items.add(
              const RecoveryPlanItem(
                'Reintroduce one active at a time (retinoid first, then vitamin C, then exfoliant)',
                reason: 'protects the rebuilt barrier from irritation',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Schedule your next microneedling session 4–6 weeks from your last',
                reason: 'matches the dermal remodeling cycle',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Add a weekly hydrating sheet or sleeping mask',
                reason: 'amplifies barrier repair between sessions',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Add a 10-minute LED red-light session 2–3× this week',
                reason:
                    'you are inside the peak collagen-stimulation window — photobiomodulation compounds dermal remodeling',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Audit texture and pore-visibility trends in your scan history',
                reason:
                    'week 3–6 is when these metrics typically inflect — confirm response before booking session 2',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Lock in a daily vitamin C 10–15% serum AM under SPF',
                reason:
                    'antioxidant defense + tone-evening during the pigment-vulnerable window',
              ),
            );
          } else {
            items.add(
              const RecoveryPlanItem(
                'Keep an evening retinoid 3–5×/week to sustain collagen turnover',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Plan your full microneedling series (typically 3–6 sessions, 4–6 weeks apart)',
                reason:
                    'a complete series delivers ~400% greater collagen response than a single treatment',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Track pore and texture metrics month-over-month',
                reason:
                    'objective trend confirms whether to extend the series or move to maintenance cadence',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Maintain mineral SPF 50+ daily — even indoors near windows',
                reason: 'UVA penetrates glass and undermines collagen gains',
              ),
            );
          }
        } else {
          if (phase == _PhaseBucket.acute ||
              phase == _PhaseBucket.earlyRecovery) {
            items.add(
              const RecoveryPlanItem(
                'Hold all actives this week (retinoids, AHA/BHA, vitamin C)',
                reason: 'barrier is still rebuilding — actives risk PIH',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'No saunas, hot yoga, or chlorinated pools',
                reason:
                    'heat and chemical exposure extend post-treatment redness',
              ),
            );
          } else if (phase == _PhaseBucket.activeHealing) {
            items.add(
              const RecoveryPlanItem(
                'Reintroduce retinoids gradually — once weekly, then ramp',
              ),
            );
            items.add(
              const RecoveryPlanItem(
                'Discuss the next treatment cadence with your provider',
              ),
            );
          } else {
            items.add(
              const RecoveryPlanItem(
                'Maintenance: peel-grade exfoliation no more than every 2–3 weeks',
              ),
            );
          }
        }
        break;
      case ProcedureCategory.injectables:
        items.add(
          const RecoveryPlanItem(
            'Book a 2-week assessment with your injector for symmetry and touch-ups',
          ),
        );
        if (phase == _PhaseBucket.activeHealing ||
            phase == _PhaseBucket.refinement) {
          items.add(
            const RecoveryPlanItem(
              'Plan your next session 3–4 months out (neuromodulators) / 6–12 months (filler)',
            ),
          );
        }
        items.add(
          const RecoveryPlanItem(
            'Skip high-intensity facial workouts this week (e.g. NuFace + freshly injected areas)',
          ),
        );
        break;
      case ProcedureCategory.surgicalFace:
      case ProcedureCategory.bodyContouring:
        items.add(
          const RecoveryPlanItem(
            'Photograph incisions weekly in identical lighting for your surgeon visits',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Walk daily — build up 10 minutes/day if cleared',
            reason: 'circulation reduces DVT risk and helps swelling resolve',
          ),
        );
        if (phase == _PhaseBucket.activeHealing ||
            phase == _PhaseBucket.refinement) {
          items.add(
            const RecoveryPlanItem(
              'Start silicone scar therapy on closed incisions',
              reason: 'reduces hypertrophic scarring at the 4–8 week mark',
            ),
          );
        }
        break;
      case ProcedureCategory.hairTransplant:
        items.add(
          const RecoveryPlanItem(
            'Track shock-loss vs. new growth weekly — expect shedding at weeks 2–6',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Photograph the recipient + donor zones in matched lighting',
          ),
        );
        if (phase == _PhaseBucket.activeHealing ||
            phase == _PhaseBucket.refinement) {
          items.add(
            const RecoveryPlanItem(
              'Continue minoxidil + finasteride per surgeon protocol',
              reason: 'protects existing hair while transplants mature',
            ),
          );
        }
        break;
      case ProcedureCategory.bodyComposition:
        items.add(
          const RecoveryPlanItem(
            'Weigh in 2× weekly (same time, fasted) and log waist + chest circumference',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Plan resistance training 3–4 sessions — protect lean mass while losing fat',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Meal-prep one high-protein, fiber-forward day to ride out reduced appetite',
          ),
        );
        break;
      case ProcedureCategory.generalSkincare:
        items.add(
          const RecoveryPlanItem(
            'Audit your routine: one targeted active at a time, give it 6 weeks',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Plan one professional treatment per quarter (peel, hydrafacial, or microneedling)',
          ),
        );
        break;
    }

    // Metric-reactive weekly additions.
    if (latest != null) {
      if (latest.redness >= 6.0 &&
          (phase == _PhaseBucket.earlyRecovery ||
              phase == _PhaseBucket.activeHealing)) {
        items.add(
          const RecoveryPlanItem(
            'Add a 5-minute LED red-light session 3–4× this week',
            reason: 'erythema is still elevated — LED accelerates resolution',
          ),
        );
      }
      if (isMicroneedling &&
          latest.darkSpots >= 5.5 &&
          (phase == _PhaseBucket.earlyRecovery ||
              phase == _PhaseBucket.activeHealing ||
              phase == _PhaseBucket.refinement)) {
        items.add(
          const RecoveryPlanItem(
            'Add a tranexamic acid 3% or azelaic acid 10% serum PM 5×/week',
            reason:
                'your hyperpigmentation score is elevated — microneedling can flare PIH if pigment activity is not actively suppressed',
          ),
        );
      }
      if (isMicroneedling &&
          latest.texture >= 5.5 &&
          phase == _PhaseBucket.activeHealing) {
        items.add(
          const RecoveryPlanItem(
            'Hold the line on actives — do not add new exfoliants this week',
            reason:
                'texture is still smoothing from session collagen; new actives blur the signal',
          ),
        );
      }
      if (latest.elasticity > 0 &&
          latest.elasticity <= 4.0 &&
          (phase == _PhaseBucket.refinement ||
              phase == _PhaseBucket.stabilizing)) {
        items.add(
          const RecoveryPlanItem(
            'Add a peptide moisturizer (Matrixyl 3000) nightly',
            reason:
                'elasticity is trending low — peptides reinforce dermal tone',
          ),
        );
      }
    }

    return items;
  }

  // ────────────────────────────────────────────────────────────────────────
  // What to avoid
  // ────────────────────────────────────────────────────────────────────────

  static List<RecoveryPlanItem> _avoid(
    ProcedureCategory category,
    _PhaseBucket phase, {
    bool isMicroneedling = false,
  }) {
    final items = <RecoveryPlanItem>[];

    if (phase == _PhaseBucket.acute || phase == _PhaseBucket.earlyRecovery) {
      items.add(
        const RecoveryPlanItem(
          'Direct sun exposure — full mineral SPF + wide-brim hat',
        ),
      );
      items.add(const RecoveryPlanItem('Exfoliants, retinoids, AHA/BHA acids'));
      items.add(
        const RecoveryPlanItem(
          'Sweating heavily (intense workouts, saunas, hot yoga)',
        ),
      );
      items.add(
        const RecoveryPlanItem('Alcohol — slows healing and worsens swelling'),
      );
    }

    switch (category) {
      case ProcedureCategory.laserPeel:
        items.add(
          const RecoveryPlanItem(
            'Picking, scrubbing, or peeling flaking skin',
            reason: 'risks PIH and scarring',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Vitamin C serums until redness fully resolves',
          ),
        );
        if (isMicroneedling) {
          items.add(
            const RecoveryPlanItem(
              'Makeup for 24 hours, gym/sweat for 48 hours',
              reason: 'micro-channels are an open entry point for bacteria',
            ),
          );
          items.add(
            const RecoveryPlanItem(
              'Stacking microneedling with other treatments inside 4 weeks',
            ),
          );
        }
        break;
      case ProcedureCategory.injectables:
        if (phase == _PhaseBucket.acute) {
          items.add(
            const RecoveryPlanItem('Massaging or pressing on the treated area'),
          );
          items.add(
            const RecoveryPlanItem(
              'Dental work for 2 weeks (for facial filler)',
            ),
          );
        }
        break;
      case ProcedureCategory.surgicalFace:
        items.add(
          const RecoveryPlanItem(
            'Bending, lifting >5 lbs, or straining for the first 2 weeks',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Nicotine in any form — it sabotages vascular healing',
          ),
        );
        break;
      case ProcedureCategory.bodyContouring:
        items.add(
          const RecoveryPlanItem(
            'Sitting directly on buttocks (for BBL) for 6+ weeks',
          ),
        );
        items.add(
          const RecoveryPlanItem(
            'Removing your compression garment except to shower',
          ),
        );
        break;
      case ProcedureCategory.hairTransplant:
        items.add(
          const RecoveryPlanItem(
            'Hats, helmets, or anything that touches the grafts (first 10 days)',
          ),
        );
        items.add(
          const RecoveryPlanItem('Scratching, even when itchy — pat-tap only'),
        );
        break;
      case ProcedureCategory.bodyComposition:
        items.add(
          const RecoveryPlanItem(
            'Aggressive calorie deficits — protect lean mass while losing fat',
          ),
        );
        items.add(
          const RecoveryPlanItem('Skipping protein on heavy training days'),
        );
        break;
      case ProcedureCategory.generalSkincare:
        items.add(
          const RecoveryPlanItem('Stacking multiple new actives at once'),
        );
        break;
    }

    return items;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Red flags — when to contact your provider
  // ────────────────────────────────────────────────────────────────────────

  static List<RecoveryPlanItem> _redFlags(
    ProcedureCategory category,
    _PhaseBucket phase,
  ) {
    final base = <RecoveryPlanItem>[
      const RecoveryPlanItem(
        'Fever above 38°C / 100.4°F or worsening pain after day 3',
      ),
      const RecoveryPlanItem(
        'Spreading redness, warmth, or pus — possible infection',
      ),
      const RecoveryPlanItem(
        'New asymmetry, severe swelling, or unexplained bruising',
      ),
    ];

    switch (category) {
      case ProcedureCategory.injectables:
        base.add(
          const RecoveryPlanItem(
            'Blanching, severe pain, or skin discoloration — possible vascular event, contact injector immediately',
          ),
        );
        break;
      case ProcedureCategory.surgicalFace:
      case ProcedureCategory.bodyContouring:
        base.add(
          const RecoveryPlanItem(
            'Calf pain, swelling, or shortness of breath — call your surgeon urgently (DVT/PE risk)',
          ),
        );
        base.add(
          const RecoveryPlanItem(
            'Unexpected drainage, gaping incision, or sutures coming apart',
          ),
        );
        break;
      case ProcedureCategory.laserPeel:
        base.add(
          const RecoveryPlanItem(
            'Blistering, weeping, or skin that fails to scab over by day 5',
          ),
        );
        break;
      case ProcedureCategory.hairTransplant:
        base.add(
          const RecoveryPlanItem(
            'Grafts that dislodge or bleed beyond the first 48 hours',
          ),
        );
        break;
      case ProcedureCategory.bodyComposition:
        base.add(
          const RecoveryPlanItem(
            'Persistent vomiting, severe abdominal pain, or signs of pancreatitis',
          ),
        );
        break;
      case ProcedureCategory.generalSkincare:
        // Generic red flags above suffice.
        break;
    }

    return base;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal phase model
// ─────────────────────────────────────────────────────────────────────────────

enum _PhaseBucket {
  preOp,
  acute,
  earlyRecovery,
  activeHealing,
  refinement,
  stabilizing,
  maintenance,
}

extension _PhaseBucketX on _PhaseBucket {
  String get title {
    switch (this) {
      case _PhaseBucket.preOp:
        return 'Pre-Procedure';
      case _PhaseBucket.acute:
        return 'Acute Healing';
      case _PhaseBucket.earlyRecovery:
        return 'Early Recovery';
      case _PhaseBucket.activeHealing:
        return 'Active Healing';
      case _PhaseBucket.refinement:
        return 'Refinement';
      case _PhaseBucket.stabilizing:
        return 'Results Stabilizing';
      case _PhaseBucket.maintenance:
        return 'Maintenance';
    }
  }

  String get description {
    switch (this) {
      case _PhaseBucket.preOp:
        return 'Calm, well-hydrated skin entering the procedure heals faster and scars less.';
      case _PhaseBucket.acute:
        return 'Inflammatory peak. Your body is mobilizing repair signals — minimize external stressors.';
      case _PhaseBucket.earlyRecovery:
        return 'Initial downtime resolves and your barrier rebuilds. Visible improvements begin.';
      case _PhaseBucket.activeHealing:
        return 'Collagen remodeling and pigment normalization. Results compound week over week.';
      case _PhaseBucket.refinement:
        return 'Most visible change happens now. Protect the result — sun and sleep matter.';
      case _PhaseBucket.stabilizing:
        return 'Tissue is locking in its final form. Consistent maintenance preserves the result.';
      case _PhaseBucket.maintenance:
        return 'You are in the long-term protection window. Prevention is the highest-leverage habit.';
    }
  }
}
