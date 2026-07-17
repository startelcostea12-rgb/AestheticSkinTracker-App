import '../models/peptide.dart';

class PeptideSeedData {
  const PeptideSeedData._();

  static final List<Peptide> peptides = List.unmodifiable(<Peptide>[
    const Peptide(
      id: 'bpc-157',
      name: 'BPC-157',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Research logging commonly tracks 250-500 mcg once to twice daily for 4-6 weeks, then a 2-4 week washout with symptom and function checkpoints.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for clean 250 mcg tick-mark dosing on an insulin syringe.',
    ),
    const Peptide(
      id: 'tb-500',
      name: 'TB-500',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Clinical-research style logs often use a loading phase of 2-2.5 mg twice weekly for 4 weeks, followed by maintenance every 7-14 days.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial to yield straightforward 0.1mL increments for titration tracking.',
    ),
    const Peptide(
      id: 'semaglutide',
      name: 'Semaglutide',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Weight-management studies typically titrate weekly from 0.25 mg to 0.5 mg, then 1.0 mg+ based on tolerance, with weekly metabolic and appetite logs.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial to support precise low-dose weekly step-up scheduling.',
    ),
    const Peptide(
      id: 'tirzepatide',
      name: 'Tirzepatide',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Common protocol documentation escalates weekly from 2.5 mg in 4-week blocks as tolerated, with glucose, weight, and GI side-effect monitoring.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for practical weekly dose calibration across titration phases.',
    ),
    const Peptide(
      id: 'retatrutide',
      name: 'Retatrutide',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Triple-agonist research logs generally use conservative once-weekly escalation windows over 12-24 weeks with strict appetite and body-composition tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial to simplify micro-adjustments during early escalation.',
    ),
    const Peptide(
      id: 'cjc-1295-no-dac',
      name: 'CJC-1295 No DAC',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Pulse-based schedules frequently log 100-300 mcg at bedtime or pre-fast windows 5 days weekly for 8-12 weeks, then reassessment.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for clean sub-mg pulse calculations.',
    ),
    const Peptide(
      id: 'ipamorelin',
      name: 'Ipamorelin',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Study logs often use 100-300 mcg one to three times daily in pulse windows for 8-12 weeks, with sleep and recovery metrics tracked.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for repeatable pulse dosing increments.',
    ),
    const Peptide(
      id: 'sermorelin',
      name: 'Sermorelin',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Longitudinal anti-aging logs commonly document 100-300 mcg nightly for 3-6 months with IGF-1 and sleep-quality checkpoint reviews.',
      reconstitutionGuideline:
          'Add 3mL BAC water to a 9mg vial for practical nightly micro-dose titration.',
    ),
    const Peptide(
      id: 'tesamorelin',
      name: 'Tesamorelin',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Clinical protocols often record 2 mg once daily over 12+ weeks with waist, visceral-fat surrogate, and fasting-lipid checkpoints.',
      reconstitutionGuideline:
          'Add 1mL BAC water to a 2mg vial for direct full-dose draw consistency.',
    ),
    const Peptide(
      id: 'epitalon',
      name: 'Epitalon',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Bioregulator-style cycles are usually logged at 5-10 mg daily for 10-20 days, repeated every 4-6 months with sleep and recovery journaling.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial to create clean half-mL and quarter-mL administration options.',
    ),
    const Peptide(
      id: 'ghk-cu-copper-peptide',
      name: 'GHK-Cu (Copper Peptide)',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Recovery-focused logging commonly uses 1-2 mg daily or alternating-day use across 6-8 weeks, with scar quality and inflammation notes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for controlled low-volume research dosing.',
    ),
    const Peptide(
      id: 'aod9604',
      name: 'AOD9604',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Body-composition logs generally track 250-500 mcg once daily for 8-16 weeks with regular anthropometric and appetite trend checks.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for easy 250 mcg step dosing.',
    ),
    const Peptide(
      id: 'melanotan-ii',
      name: 'Melanotan II',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Pigmentation and libido research logs often record low-dose loading over 1-2 weeks then maintenance 2-3 times weekly with adverse-event tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for conservative titration increments.',
    ),
    const Peptide(
      id: 'll-37',
      name: 'LL-37',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Short-course immunology protocols frequently log 100-250 mcg daily for 10-20 days, then pause and reassess inflammatory outcomes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for short-course precision dosing.',
    ),
    const Peptide(
      id: 'kpv',
      name: 'KPV',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Inflammation-focused schedules commonly track 200-500 mcg once to twice daily for 4-8 weeks with GI and skin symptom journaling.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for smooth twice-daily micro-dose planning.',
    ),
    const Peptide(
      id: 'mots-c',
      name: 'MOTS-c',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Metabolic-aging research logs often use 5-15 mg 2-3 times weekly for 4-6 weeks, followed by off-cycle labs and recovery assessment.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for clean mg-level weekly tracking.',
    ),
    const Peptide(
      id: '5-amino-1mq',
      name: '5-Amino-1MQ',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Body-fat reduction studies commonly track daily dosing over 6-12 weeks with strict diet logs, waist measurements, and tolerance notes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for straightforward small-volume daily draws.',
    ),
    const Peptide(
      id: 'selank',
      name: 'Selank',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Nootropic protocols frequently log 250-500 mcg once to twice daily for 10-20 days, then observe carryover effects during washout.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for clean anxiolytic-range micro-dosing.',
    ),
    const Peptide(
      id: 'semax',
      name: 'Semax',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Cognitive performance logs often track 300-600 mcg once to twice daily in 10-14 day blocks with focus, recall, and fatigue journaling.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial to support stable daily cognitive protocol increments.',
    ),
    const Peptide(
      id: 'pt-141',
      name: 'PT-141',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Libido-response logs usually document on-demand dosing with at least 48-hour spacing, including onset timing and side-effect checklists.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for low-volume event-based titration.',
    ),
    const Peptide(
      id: 'thymosin-alpha-1',
      name: 'Thymosin Alpha-1',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Immune-support research logs frequently use 0.8-1.6 mg two to three times weekly for 6-12 weeks with inflammatory marker checkpoints.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for consistent twice-weekly dose pulls.',
    ),
    const Peptide(
      id: 'thymosin-beta-4',
      name: 'Thymosin Beta-4',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Regeneration protocols commonly track 2-5 mg weekly split into multiple administrations over 4-8 weeks with mobility outcomes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial to simplify divided weekly protocol dosing.',
    ),
    const Peptide(
      id: 'igf-1-lr3',
      name: 'IGF-1 LR3',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Anabolic-recovery logs often use 20-50 mcg training-day administration for 4-6 weeks, followed by deload and biomarker review.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 1mg vial for clear 10-25 mcg small-volume increments.',
    ),
    const Peptide(
      id: 'peg-mgf',
      name: 'PEG-MGF',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Recovery-oriented logs generally record 200-400 mcg post-training 2-3 times weekly over 4-8 weeks with soreness and strength notes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 2mg vial for practical post-session incremental dosing.',
    ),
    const Peptide(
      id: 'follistatin-344',
      name: 'Follistatin-344',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Experimental hypertrophy studies usually track short 10-30 day windows with conservative dosing and mandatory post-cycle observation.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 1mg vial to keep administration volumes measurable and controlled.',
    ),
    const Peptide(
      id: 'dsip',
      name: 'DSIP',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Sleep-focused protocols often log 100-300 mcg nightly for 2-4 weeks with sleep-latency and wake-after-sleep-onset tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for low-dose nightly precision.',
    ),
    const Peptide(
      id: 'pinealon',
      name: 'Pinealon',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Neuroprotection studies commonly document 5-10 day cycles repeated quarterly with cognition and stress-resilience notes.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for concise cycle-based dosing increments.',
    ),
    const Peptide(
      id: 'vesugen',
      name: 'Vesugen',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Vascular-aging protocols often track 10-20 day courses with blood-pressure, endurance, and peripheral perfusion observations.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for predictable cycle administration.',
    ),
    const Peptide(
      id: 'foxo4-dri',
      name: 'FOXO4-DRI',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Senolytic research logs generally use intermittent pulse schedules separated by long recovery windows with strict adverse-event tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for conservative pulse dosing precision.',
    ),
    const Peptide(
      id: 'humanin',
      name: 'Humanin',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Mitochondrial-aging protocols often track intermittent weekly dosing for 8-12 weeks with fatigue and metabolic trend logs.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for low-volume weekly administration.',
    ),
    const Peptide(
      id: 'gh-fragment-176-191',
      name: 'GH Fragment 176-191',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Fat-loss protocols commonly record 250-500 mcg once to twice daily in fasted windows for 8-12 weeks with circumference tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for clean 250 mcg increments.',
    ),
    const Peptide(
      id: 'kisspeptin-10',
      name: 'Kisspeptin-10',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Neuroendocrine studies usually log intermittent administration with hormone and libido response timelines over 4-8 weeks.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for precise endocrine-response titration.',
    ),
    const Peptide(
      id: 'hexarelin',
      name: 'Hexarelin',
      category: PeptideCategory.longevity,
      standardProtocol:
          'GH-secretagogue logs frequently use 100-200 mcg once daily in short 4-6 week cycles due to receptor desensitization risk.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 2mg vial for measured low-dose pulse scheduling.',
    ),
    const Peptide(
      id: 'ghrp-2',
      name: 'GHRP-2',
      category: PeptideCategory.longevity,
      standardProtocol:
          'Pulse protocols often track 100-300 mcg one to three times daily around fasting windows with appetite and recovery logs.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for repeatable pulse-based administration.',
    ),
    const Peptide(
      id: 'ghrp-6',
      name: 'GHRP-6',
      category: PeptideCategory.weightLoss,
      standardProtocol:
          'Clinical-research style usage frequently logs 100-300 mcg pulses, with appetite effects documented before protocol adjustments.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for straightforward pulse titration.',
    ),
    const Peptide(
      id: 'ara-290',
      name: 'ARA-290',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Neuropathic-recovery studies often track daily dosing for 2-4 weeks with pain-function scales and sensory logs.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 4mg vial for controlled daily draws.',
    ),
    const Peptide(
      id: 'cartalax',
      name: 'Cartalax',
      category: PeptideCategory.muscleRepair,
      standardProtocol:
          'Connective-tissue support protocols typically log 10-20 day cycles with mobility, stiffness, and recovery tracking.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 10mg vial for even cycle-based dosing.',
    ),
    const Peptide(
      id: 'p21',
      name: 'P21',
      category: PeptideCategory.cognitive,
      standardProtocol:
          'Neuroplasticity research logs generally track conservative daily or alternate-day dosing for 2-6 weeks with cognition scoring.',
      reconstitutionGuideline:
          'Add 2mL BAC water to a 5mg vial for low-volume cognitive protocol control.',
    ),
  ]);
}
