// lib/models/peptide_model.dart
// Clinical peptide tracker model — data classes and curated library.

class PeptideEntry {
  final String id;
  final String name;
  final double? concentration; // Percentage (e.g. 5.0)
  final String frequency;
  final DateTime startDate;
  final DateTime? endDate; // null = still active
  final String notes;
  final String
  category; // 'anti-aging' | 'brightening' | 'healing' | 'firming' | 'other'
  /// Optional stack grouping. `null` means this is an individual peptide,
  /// not part of any stack.
  final String? stackId;

  const PeptideEntry({
    required this.id,
    required this.name,
    this.concentration,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.notes = '',
    required this.category,
    this.stackId,
  });

  bool get isActive => endDate == null;

  int get daysTracked =>
      (endDate ?? DateTime.now()).difference(startDate).inDays.abs();

  PeptideEntry copyWith({
    String? name,
    double? concentration,
    bool clearConcentration = false,
    String? frequency,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    String? notes,
    String? category,
    String? stackId,
    bool clearStackId = false,
  }) {
    return PeptideEntry(
      id: id,
      name: name ?? this.name,
      concentration: clearConcentration
          ? null
          : (concentration ?? this.concentration),
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      notes: notes ?? this.notes,
      category: category ?? this.category,
      stackId: clearStackId ? null : (stackId ?? this.stackId),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'concentration': concentration,
    'frequency': frequency,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'notes': notes,
    'category': category,
    'stackId': stackId,
  };

  factory PeptideEntry.fromJson(Map<String, dynamic> json) => PeptideEntry(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    concentration: (json['concentration'] as num?)?.toDouble(),
    frequency: json['frequency']?.toString() ?? 'Once daily',
    startDate:
        DateTime.tryParse(json['startDate']?.toString() ?? '') ??
        DateTime.now(),
    endDate: json['endDate'] != null
        ? DateTime.tryParse(json['endDate'].toString())
        : null,
    notes: json['notes']?.toString() ?? '',
    category: json['category']?.toString() ?? 'other',
    stackId: json['stackId']?.toString().isEmpty ?? true
        ? null
        : json['stackId'].toString(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Peptide Stack — named group of peptides (e.g. "Healing Stack")
// ─────────────────────────────────────────────────────────────────────────────

class PeptideStack {
  final String id;
  final String name;
  final DateTime createdAt;

  /// Procedure this stack tracks against. Set lazily on first scan.
  final String? procedureId;

  const PeptideStack({
    required this.id,
    required this.name,
    required this.createdAt,
    this.procedureId,
  });

  PeptideStack copyWith({String? name, String? procedureId}) => PeptideStack(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    procedureId: procedureId ?? this.procedureId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    if (procedureId != null) 'procedureId': procedureId,
  };

  factory PeptideStack.fromJson(Map<String, dynamic> json) => PeptideStack(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Stack',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    procedureId: json['procedureId']?.toString(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stack Journal — text/voice notes attached to a stack
// ─────────────────────────────────────────────────────────────────────────────

class StackJournalEntry {
  final String id;
  final String stackId;
  final DateTime createdAt;
  final String text;
  final bool isVoice; // true if captured via dictation

  const StackJournalEntry({
    required this.id,
    required this.stackId,
    required this.createdAt,
    required this.text,
    this.isVoice = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'stackId': stackId,
    'createdAt': createdAt.toIso8601String(),
    'text': text,
    'isVoice': isVoice,
  };

  factory StackJournalEntry.fromJson(Map<String, dynamic> json) =>
      StackJournalEntry(
        id: json['id']?.toString() ?? '',
        stackId: json['stackId']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        text: json['text']?.toString() ?? '',
        isVoice: json['isVoice'] == true,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Curated library entry
// ─────────────────────────────────────────────────────────────────────────────

class PeptideLibraryEntry {
  final String name;
  final String inci; // INCI name / alternate name
  final String mechanism;
  final String evidenceLevel; // 'Tier 1' | 'Tier 2' | 'Tier 3'
  final List<String> primaryMetrics; // skin metric labels affected
  final String category;
  final String clinicalNote;

  const PeptideLibraryEntry({
    required this.name,
    required this.inci,
    required this.mechanism,
    required this.evidenceLevel,
    required this.primaryMetrics,
    required this.category,
    required this.clinicalNote,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Curated peptide library (20 entries)
// ─────────────────────────────────────────────────────────────────────────────

const List<PeptideLibraryEntry> kPeptideLibrary = [
  PeptideLibraryEntry(
    name: 'Matrixyl 3000',
    inci: 'Palmitoyl Tripeptide-1 & Palmitoyl Tetrapeptide-7',
    mechanism:
        'Stimulates collagen I, III, and fibronectin synthesis via matrikine signaling.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Fine Lines / Wrinkles', 'Skin Elasticity', 'Texture'],
    category: 'anti-aging',
    clinicalNote:
        'Multiple RCTs show significant wrinkle depth reduction at 3–5% after 8–12 weeks.',
  ),
  PeptideLibraryEntry(
    name: "Matrixyl Synthe'6",
    inci: 'Palmitoyl Lysine/Threonine/Threonine/Lysine/Serine',
    mechanism:
        'Upregulates 6 structural proteins of the dermal–epidermal junction.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Skin Elasticity', 'Texture', 'Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Shown to reduce wrinkle volume up to 36% in 2-month clinical study.',
  ),
  PeptideLibraryEntry(
    name: 'GHK-Cu (Copper Tripeptide-1)',
    inci: 'Copper Tripeptide-1',
    mechanism:
        'Activates wound repair pathways, upregulates SOD and metalloproteinase remodeling.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture', 'Redness / Swelling', 'Skin Elasticity'],
    category: 'healing',
    clinicalNote:
        'Robust evidence for wound healing, scar remodeling, and anti-inflammatory action. Effective at 0.5–2%.',
  ),
  PeptideLibraryEntry(
    name: 'Argireline (Acetyl Hexapeptide-3)',
    inci: 'Acetyl Hexapeptide-3',
    mechanism:
        'Inhibits SNARE complex formation, reducing repetitive muscle micro-contractions.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Most effective at 10% on expression-driven lines. Clinical trials show up to 27% reduction.',
  ),
  PeptideLibraryEntry(
    name: 'Leuphasyl',
    inci: 'Pentapeptide-18',
    mechanism:
        'Enkephalin analog that synergizes with Argireline to reduce muscle acetylcholine release.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Most effective at 4–5% in combination with Acetyl Hexapeptide-3.',
  ),
  PeptideLibraryEntry(
    name: 'SYN-AKE',
    inci: 'Dipeptide Diaminobutyroyl Benzylamide Diacetate',
    mechanism:
        'Waglerin-1 analog; inhibits nicotinic acetylcholine receptor activity.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Effective at 4%. Supplier study shows 52% reduction in wrinkle depth at 4 weeks; limited independent RCTs.',
  ),
  PeptideLibraryEntry(
    name: 'Palmitoyl Tripeptide-5',
    inci: 'Palmitoyl Tripeptide-5',
    mechanism:
        'Activates TGF-β pathway to stimulate collagen and fibronectin synthesis.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Skin Elasticity', 'Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Clinical study shows comparable efficacy to TGF-β at reducing wrinkle volume.',
  ),
  PeptideLibraryEntry(
    name: 'SNAP-8',
    inci: 'Acetyl Octapeptide-3',
    mechanism:
        '8-amino-acid extension of Argireline targeting the SNARE complex more completely.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Supplier data indicates 63% wrinkle depth reduction at 4 weeks at 4%. Limited independent RCT data.',
  ),
  PeptideLibraryEntry(
    name: 'Tripeptide-10 Citrulline',
    inci: 'Tripeptide-10 Citrulline',
    mechanism:
        'Increases decorin production to improve collagen fiber organization.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Texture', 'Skin Elasticity'],
    category: 'anti-aging',
    clinicalNote:
        'Clinically shown to reduce fibrosis-related skin roughness and improve dermal matrix organization.',
  ),
  PeptideLibraryEntry(
    name: 'Carnosine',
    inci: 'Carnosine',
    mechanism:
        'Anti-glycation dipeptide; protects proteins from AGE-induced cross-linking.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Fine Lines / Wrinkles', 'Texture'],
    category: 'anti-aging',
    clinicalNote:
        'Useful in high-sugar diet contexts. Evidence strongest at 1–2%.',
  ),
  PeptideLibraryEntry(
    name: 'AHK-Cu (Copper Tripeptide-3)',
    inci: 'Copper Tripeptide-3',
    mechanism:
        'Hair follicle-targeted copper peptide with anti-inflammatory and repair activity.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture'],
    category: 'healing',
    clinicalNote:
        'Primarily studied for scalp/hair; skin wound repair effects paralleled from GHK-Cu research.',
  ),
  PeptideLibraryEntry(
    name: 'Tetrapeptide-30',
    inci: 'Tetrapeptide-30',
    mechanism:
        'Inhibits pro-melanogenic enzymes (cAMP pathway) to reduce UV-induced pigmentation.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Dark Spots'],
    category: 'brightening',
    clinicalNote:
        'Clinical data shows significant reduction in UV-induced dark spots at 0.01–0.1%.',
  ),
  PeptideLibraryEntry(
    name: 'Oligopeptide-34',
    inci: 'Oligopeptide-34',
    mechanism:
        'Suppresses endothelin-1-triggered tyrosinase activation post-UV exposure.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Dark Spots'],
    category: 'brightening',
    clinicalNote:
        'Effective for post-inflammatory hyperpigmentation; best combined with Tetrapeptide-30.',
  ),
  PeptideLibraryEntry(
    name: 'Dermaxyl',
    inci: 'Palmitoyl Oligopeptide',
    mechanism:
        'Stimulates collagen synthesis and activates epidermal growth factor receptors.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Fine Lines / Wrinkles', 'Texture', 'Skin Elasticity'],
    category: 'anti-aging',
    clinicalNote:
        'Multiple clinical studies demonstrate wrinkle volume reduction and improved skin firmness.',
  ),
  PeptideLibraryEntry(
    name: 'Boostatin (Hexapeptide-14)',
    inci: 'Hexapeptide-14',
    mechanism:
        'Inhibits sebaceous lipid synthesis; reduces visible pore appearance.',
    evidenceLevel: 'Tier 3',
    primaryMetrics: ['Pore Visibility'],
    category: 'other',
    clinicalNote:
        'Emerging pore-targeting peptide; limited independent data. Supplier clinical shows ~15% pore reduction.',
  ),
  PeptideLibraryEntry(
    name: 'Uplevity (Acetyl Tetrapeptide-2)',
    inci: 'Acetyl Tetrapeptide-2',
    mechanism:
        'Improves density and architecture of the dermal-epidermal junction.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Fine Lines / Wrinkles'],
    category: 'firming',
    clinicalNote:
        'Clinical data shows improvement in skin firmness and eyelid contour at 8 weeks.',
  ),
  PeptideLibraryEntry(
    name: 'Tripeptide-29',
    inci: 'Tripeptide-29',
    mechanism:
        'Collagen fragment that stimulates procollagen synthesis via cell-surface receptor.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Procollagen precursor fragment; often combined with copper peptides for synergy.',
  ),
  PeptideLibraryEntry(
    name: 'PEPHA-TIGHT',
    inci: 'Nannochloropsis Oculata Extract',
    mechanism:
        'Tightens keratinocyte cytoskeleton, producing immediate and long-term firming effect.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'firming',
    clinicalNote:
        'Immediate tightening effect; clinically validated firming at 1–2% after 28 days.',
  ),
  PeptideLibraryEntry(
    name: 'EGF (sh-Oligopeptide-1)',
    inci: 'sh-Oligopeptide-1',
    mechanism:
        'Binds EGF receptors to stimulate cell proliferation and wound healing.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture', 'Redness / Swelling', 'Fine Lines / Wrinkles'],
    category: 'healing',
    clinicalNote:
        'Strong clinical evidence for post-procedure healing. Use at 10–100 ppm under medical guidance.',
  ),
  PeptideLibraryEntry(
    name: 'Palmitoyl Tetrapeptide-7',
    inci: 'Palmitoyl Tetrapeptide-7',
    mechanism:
        'Inhibits IL-6 production to reduce skin inflammation and glycation-driven aging.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: [
      'Redness / Swelling',
      'Skin Elasticity',
      'Fine Lines / Wrinkles',
    ],
    category: 'anti-aging',
    clinicalNote:
        'Key component of Matrixyl 3000. Anti-inflammatory and anti-senescence properties validated.',
  ),
  PeptideLibraryEntry(
    name: 'BPC-157',
    inci: 'Body Protection Compound-157',
    mechanism:
        'Promotes angiogenesis and fibroblast migration to accelerate tissue and tendon repair.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture'],
    category: 'healing',
    clinicalNote:
        'Gastric-derived pentadecapeptide. Strong preclinical wound and soft-tissue repair data; topical research emerging.',
  ),
  PeptideLibraryEntry(
    name: 'TB-500',
    inci: 'Thymosin Beta-4 Fragment',
    mechanism:
        'Upregulates actin polymerization and cell migration for accelerated tissue regeneration.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture', 'Skin Elasticity'],
    category: 'healing',
    clinicalNote:
        'Synthetic 17-amino acid fragment of Thymosin Beta-4. Investigated for wound healing, hair growth and post-procedure recovery.',
  ),
  PeptideLibraryEntry(
    name: 'Vitamin C (L-Ascorbic Acid)',
    inci: 'Ascorbic Acid',
    mechanism:
        'Cofactor for collagen hydroxylation; neutralizes ROS and inhibits tyrosinase to brighten skin.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Dark Spots', 'Texture', 'Fine Lines / Wrinkles'],
    category: 'brightening',
    clinicalNote:
        'Gold-standard antioxidant. Most effective at 10–20%, pH < 3.5. Photoprotective and brightening with strong RCT support.',
  ),
  PeptideLibraryEntry(
    name: 'Niacinamide (Vitamin B3)',
    inci: 'Niacinamide',
    mechanism:
        'NAD+ precursor; reinforces ceramide synthesis, regulates sebum and inhibits melanosome transfer.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Pore Visibility', 'Dark Spots', 'Redness / Swelling'],
    category: 'brightening',
    clinicalNote:
        'Well-tolerated at 2–5%. Clinically validated for barrier repair, pigmentation, redness and pore appearance.',
  ),
  PeptideLibraryEntry(
    name: 'Pal-GHK (Palmitoyl Tripeptide-1)',
    inci: 'Palmitoyl Tripeptide-1',
    mechanism:
        'Lipidated GHK analog that signals collagen, elastin and glycosaminoglycan synthesis.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Fine Lines / Wrinkles', 'Skin Elasticity', 'Texture'],
    category: 'anti-aging',
    clinicalNote:
        'Lipid tail improves penetration vs. unbound GHK. Effective at 2–4 ppm; component of Matrixyl 3000.',
  ),
  PeptideLibraryEntry(
    name: 'Epitalon',
    inci: 'Tetrapeptide Ala-Glu-Asp-Gly',
    mechanism:
        'Activates telomerase and pineal melatonin signaling; investigated for cellular longevity.',
    evidenceLevel: 'Tier 3',
    primaryMetrics: ['Fine Lines / Wrinkles', 'Skin Elasticity'],
    category: 'anti-aging',
    clinicalNote:
        'Originally a peptide bioregulator from Khavinson research. Limited Western RCTs; popular in longevity protocols.',
  ),
  PeptideLibraryEntry(
    name: 'Thymosin Alpha-1',
    inci: 'Thymosin Alpha-1 (Tα1)',
    mechanism:
        'Immunomodulatory peptide that supports T-cell function and post-procedure inflammatory resolution.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture'],
    category: 'healing',
    clinicalNote:
        'Approved in several countries for immune modulation. Used adjunctively for post-procedure recovery and chronic inflammation.',
  ),
  PeptideLibraryEntry(
    name: 'Acetyl Tetrapeptide-9',
    inci: 'Acetyl Tetrapeptide-9',
    mechanism:
        'Stimulates lumican expression to increase dermal density and collagen fiber assembly.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Fine Lines / Wrinkles'],
    category: 'firming',
    clinicalNote:
        'Clinical study shows +20% dermal density at 8 weeks at 2–4%. Strong synergy with Matrixyl peptides.',
  ),
  PeptideLibraryEntry(
    name: 'Acetyl Tetrapeptide-22',
    inci: 'Acetyl Tetrapeptide-22',
    mechanism:
        'Down-regulates HSP47 and substance P to reduce skin sensitivity and stress-induced redness.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture'],
    category: 'healing',
    clinicalNote:
        'Anti-stress / desensitizing peptide. Useful in reactive or post-procedure skin at 2–5%.',
  ),
  PeptideLibraryEntry(
    name: 'Hexapeptide-11',
    inci: 'Hexapeptide-11',
    mechanism:
        'Senolytic peptide from yeast fermentation; restores fibroblast activity and barrier renewal.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Texture', 'Skin Elasticity', 'Fine Lines / Wrinkles'],
    category: 'anti-aging',
    clinicalNote:
        'Targets senescent dermal cells. Clinical data shows improved firmness and tone at 2%.',
  ),
  // ───── Growth-hormone secretagogues & GHRH analogs ─────
  PeptideLibraryEntry(
    name: 'Sermorelin',
    inci: 'GHRH (1–29)',
    mechanism:
        'GHRH analog that stimulates pulsatile endogenous growth hormone release from the pituitary.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'body-composition',
    clinicalNote:
        'FDA-approved for pediatric GH deficiency; used off-label in anti-aging at 100–300 mcg subcutaneous nightly.',
  ),
  PeptideLibraryEntry(
    name: 'CJC-1295 (with DAC)',
    inci: 'Mod-GRF (1–29) DAC',
    mechanism:
        'Long-acting GHRH analog; sustains GH/IGF-1 elevation via albumin-binding drug-affinity complex.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'body-composition',
    clinicalNote:
        'Half-life ~6–8 days. Commonly stacked with Ipamorelin at 1–2 mg weekly for lean-mass and recovery support.',
  ),
  PeptideLibraryEntry(
    name: 'Ipamorelin',
    inci: 'Ipamorelin',
    mechanism:
        'Selective ghrelin/GH-secretagogue receptor agonist; triggers GH pulse without raising cortisol or prolactin.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'body-composition',
    clinicalNote:
        'Cleanest of the GHRPs. Typical dose 200–300 mcg 1–3× daily, often combined with CJC-1295.',
  ),
  PeptideLibraryEntry(
    name: 'Hexarelin',
    inci: 'Hexarelin',
    mechanism:
        'Potent GH secretagogue with cardioprotective effects via GHS-R1a and CD36 receptors.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity'],
    category: 'body-composition',
    clinicalNote:
        'Strongest GH pulse of the GHRPs but causes faster receptor desensitization. Cycled use at 100–200 mcg.',
  ),
  PeptideLibraryEntry(
    name: 'Tesamorelin',
    inci: 'Tesamorelin (GHRH analog)',
    mechanism:
        'Stabilized GHRH analog studied for reducing visceral adipose tissue and improving lipid profile; results vary.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture'],
    category: 'body-composition',
    clinicalNote:
        'FDA-approved (Egrifta) for HIV-associated lipodystrophy. Standard dose 2 mg subcutaneous daily.',
  ),
  // ───── GLP-1 / GIP / glucagon receptor agonists ─────
  PeptideLibraryEntry(
    name: 'Semaglutide',
    inci: 'GLP-1 Receptor Agonist',
    mechanism:
        'Long-acting GLP-1 receptor agonist; reduces appetite, slows gastric emptying and improves glycemic control.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture'],
    category: 'body-composition',
    clinicalNote:
        'FDA-approved (Ozempic, Wegovy). STEP trials show ~15% body-weight loss at 2.4 mg weekly over 68 weeks.',
  ),
  PeptideLibraryEntry(
    name: 'Tirzepatide',
    inci: 'GLP-1 / GIP Dual Agonist',
    mechanism:
        'Dual GIP and GLP-1 receptor agonist that amplifies satiety, insulin sensitivity and lipolysis.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture'],
    category: 'body-composition',
    clinicalNote:
        'FDA-approved (Mounjaro, Zepbound). SURMOUNT-1 showed ~20.9% weight loss at 15 mg weekly over 72 weeks.',
  ),
  PeptideLibraryEntry(
    name: 'Retatrutide',
    inci: 'GLP-1 / GIP / Glucagon Triple Agonist',
    mechanism:
        'Investigational triple agonist of GLP-1, GIP and glucagon receptors driving energy expenditure and fat loss.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Texture'],
    category: 'body-composition',
    clinicalNote:
        'Phase 2 data: ~24.2% body-weight loss at 12 mg weekly over 48 weeks. Not yet FDA-approved.',
  ),
  PeptideLibraryEntry(
    name: 'AOD-9604',
    inci: 'hGH Fragment 176–191',
    mechanism:
        'C-terminal fragment of human growth hormone that stimulates lipolysis without affecting blood glucose or IGF-1.',
    evidenceLevel: 'Tier 3',
    primaryMetrics: ['Texture'],
    category: 'body-composition',
    clinicalNote:
        'Originally developed for obesity (Metabolic Pharmaceuticals); modest weight loss in trials. Typical 250–500 mcg daily.',
  ),
  // ───── Cellular energy / mitochondrial ─────
  PeptideLibraryEntry(
    name: 'MOTS-c',
    inci: 'Mitochondrial-Derived Peptide',
    mechanism:
        'Mitochondrial-encoded peptide that activates AMPK, improves insulin sensitivity and exercise capacity.',
    evidenceLevel: 'Tier 3',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'body-composition',
    clinicalNote:
        'Emerging longevity peptide. Animal data shows metabolic and endurance benefits; limited human trials at 5–10 mg weekly.',
  ),
  // ───── Healing / regenerative growth factors ─────
  PeptideLibraryEntry(
    name: 'bFGF (sh-Polypeptide-1)',
    inci: 'sh-Polypeptide-1',
    mechanism:
        'Basic fibroblast growth factor; stimulates fibroblast proliferation, angiogenesis and collagen synthesis.',
    evidenceLevel: 'Tier 1',
    primaryMetrics: ['Texture', 'Skin Elasticity', 'Redness / Swelling'],
    category: 'healing',
    clinicalNote:
        'Used in post-procedure recovery and chronic wound healing. Highly effective at 10–50 ppm topical.',
  ),
  PeptideLibraryEntry(
    name: 'IGF-1 LR3',
    inci: 'Long R3 Insulin-Like Growth Factor-1',
    mechanism:
        'Stabilized IGF-1 analog with extended half-life; drives muscle hypertrophy, satellite-cell activation and skin renewal.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Skin Elasticity', 'Texture'],
    category: 'body-composition',
    clinicalNote:
        'Research peptide with potent anabolic effects. Localized injection 20–50 mcg; monitor for hypoglycemia.',
  ),
  PeptideLibraryEntry(
    name: 'KPV',
    inci: 'Lysine-Proline-Valine',
    mechanism:
        'C-terminal tripeptide of α-MSH; potent anti-inflammatory action via NF-κB suppression.',
    evidenceLevel: 'Tier 2',
    primaryMetrics: ['Redness / Swelling', 'Texture'],
    category: 'healing',
    clinicalNote:
        'Investigated for IBD, eczema and post-procedure inflammation. Topical/oral use at 250–500 mcg daily.',
  ),
];
