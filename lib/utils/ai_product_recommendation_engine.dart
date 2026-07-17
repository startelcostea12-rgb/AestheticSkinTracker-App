import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'procedure_intelligence.dart';

/// Represents a clinically-relevant product recommendation with affiliate link.
class AIProductRecommendation {
  final String productName;
  final String brand;
  final String clinicalReason;
  final String usageGuidance;
  final String
  evidenceLevel; // "Clinical consensus", "Evidence-backed", "Proven efficacy"
  final String affiliateLink;
  final String imageUrl;
  final String category; // "Recovery Support", "Maintenance", "Prevention"

  AIProductRecommendation({
    required this.productName,
    required this.brand,
    required this.clinicalReason,
    required this.usageGuidance,
    required this.evidenceLevel,
    required this.affiliateLink,
    required this.imageUrl,
    required this.category,
  });
}

/// Lightweight skin-signal context derived from on-device CV report metrics.
/// Values are normalized to a 0..10 interpretation unless specified.
class CvSkinMetricsContext {
  final double? hydrationLevel;
  final double? oilinessLevel;
  final double? poreVisibility;
  final double? sensitivityLevel;
  final double? rednessLevel;
  final double? textureRoughness;
  final double? collagenElasticity;
  final double? poreSizeMm;

  const CvSkinMetricsContext({
    this.hydrationLevel,
    this.oilinessLevel,
    this.poreVisibility,
    this.sensitivityLevel,
    this.rednessLevel,
    this.textureRoughness,
    this.collagenElasticity,
    this.poreSizeMm,
  });
}

/// AI-driven product recommendation engine that analyzes skin metrics
/// and suggests clinically relevant products based on highest-priority issues.
class AIProductRecommendationEngine {
  static String? _cleanProcedureType(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return null;
    final lower = normalized.toLowerCase();
    if (lower == 'unknown' || lower == 'n/a' || lower == 'null') return null;
    return normalized;
  }

  static String _resolveProcedureType({
    String? procedureType,
    List<String>? recentProcedureTypes,
  }) {
    final direct = _cleanProcedureType(procedureType);
    if (direct != null) {
      return direct;
    }

    if (recentProcedureTypes != null) {
      for (final candidate in recentProcedureTypes) {
        final normalized = _cleanProcedureType(candidate);
        if (normalized != null) {
          return normalized;
        }
      }
    }

    return 'General Skincare';
  }

  // ── Procedure-specific curated catalogs ──────────────────────────────────
  // These take priority over metric-based lookup when a matching procedure is detected.

  static const List<Map<String, String>> _bodyContouringProducts = [
    {
      'name': 'Arnica Montana Gel',
      'brand': 'Boiron',
      'reason':
          'Arnica is the gold standard topical for post-surgical bruising and swelling. Directly targets the inflammation and ecchymosis common after BBL and liposuction.',
      'guidance':
          'Apply gently to bruised and swollen areas (avoid open incision sites) 2–3 times daily starting day 3 post-op. Continue until bruising resolves.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=boiron+arnica+montana+gel',
      'image': 'https://via.placeholder.com/200x200?text=Arnica+Gel',
      'category': 'Recovery Support',
    },
    {
      'name': 'Bromelain + Quercetin Supplement',
      'brand': 'Now Foods',
      'reason':
          'Bromelain (pineapple enzyme) has strong clinical evidence for reducing post-surgical swelling, bruising, and pain after body contouring procedures.',
      'guidance':
          'Take 500mg bromelain between meals twice daily. Begin 48 hours post-op and continue for 3–4 weeks. Do not take on empty stomach initially.',
      'evidence': 'Proven efficacy',
      'link': 'https://www.amazon.com/s?k=bromelain+quercetin+supplement',
      'image': 'https://via.placeholder.com/200x200?text=Bromelain',
      'category': 'Recovery Support',
    },
    {
      'name': 'Stage 2 Compression Faja / Garment',
      'brand': 'Ann Chery / Marena',
      'reason':
          'Stage 2 compression garments are non-negotiable for BBL and lipo results. They control swelling, support skin retraction, prevent fibrosis, and define the final contour.',
      'guidance':
          'Wear 22+ hours/day weeks 3–8. Transition to lighter compression through month 3. Follow your surgeon\'s specific garment schedule.',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=stage+2+compression+faja+post+surgery',
      'image': 'https://via.placeholder.com/200x200?text=Compression+Faja',
      'category': 'Recovery Support',
    },
    {
      'name': 'Lymphatic Drainage Massage Oil',
      'brand': 'Maelys / Palmer\'s',
      'reason':
          'Manual lymphatic drainage (MLD) starting week 3–4 reduces fibrosis, accelerates swelling resolution, and improves final contour after lipo and BBL.',
      'guidance':
          'Use during self-massage sessions. Apply oil and use light circular strokes toward lymph nodes. 20 min sessions, 3–5 times/week.',
      'evidence': 'Evidence-backed',
      'link':
          'https://www.amazon.com/s?k=lymphatic+drainage+massage+oil+post+surgery',
      'image': 'https://via.placeholder.com/200x200?text=Lymphatic+Oil',
      'category': 'Recovery Support',
    },
    {
      'name': 'Silicone Scar Sheets — Body Size',
      'brand': 'ScarAway',
      'reason':
          'Medical-grade silicone is the most evidence-backed treatment for post-surgical scars. Prevents hypertrophic or keloid scarring at incision sites.',
      'guidance':
          'Apply over fully closed incisions (not open wounds). Wear 12+ hours/day. Reusable — wash daily. Start as soon as incisions fully close.',
      'evidence': 'Proven efficacy',
      'link': 'https://www.amazon.com/s?k=scaraway+silicone+sheets+body',
      'image': 'https://via.placeholder.com/200x200?text=Scar+Sheets',
      'category': 'Recovery Support',
    },
    {
      'name': 'High-Protein Collagen Supplement',
      'brand': 'Vital Proteins',
      'reason':
          'Adequate protein intake is critical for fat graft survival and wound healing. Collagen peptides provide amino acids directly required for tissue repair.',
      'guidance':
          'Mix 1–2 scoops (20–40g protein) into water or smoothie daily. Combine with Vitamin C for enhanced collagen synthesis.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=vital+proteins+collagen+peptides',
      'image': 'https://via.placeholder.com/200x200?text=Collagen+Protein',
      'category': 'Maintenance',
    },
    {
      'name': 'Body Broad-Spectrum SPF 50 Spray',
      'brand': 'Neutrogena',
      'reason':
          'UV exposure on healing surgical scars causes permanent hyperpigmentation. Body SPF spray protects incision sites and treated skin during the 3-month scar maturation window.',
      'guidance':
          'Spray on all treated areas before sun exposure. Reapply every 2 hours. Non-greasy formula safe over healing skin (avoid open wounds).',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=neutrogena+body+sunscreen+spf+50+spray',
      'image': 'https://via.placeholder.com/200x200?text=Body+SPF',
      'category': 'Prevention',
    },
    {
      'name': 'Fragrance-Free Body Moisturizer',
      'brand': 'CeraVe',
      'reason':
          'Hydrating the treated skin supports elasticity and skin retraction after liposuction. Ceramide-based formula repairs barrier without irritating post-surgical skin.',
      'guidance':
          'Apply twice daily to treated areas after wounds are fully closed. Massage in gently — this also provides light lymphatic stimulation.',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=cerave+fragrance+free+body+moisturizer',
      'image': 'https://via.placeholder.com/200x200?text=Body+Moisturizer',
      'category': 'Maintenance',
    }, // ── Phase 2 additions ────────────────────────────────────────────────────
    {
      'name': 'Stage 1 Compression Faja (Weeks 1–3)',
      'brand': 'Marena / Medical-Z',
      'reason':
          'The Stage 1 faja provides maximum compression (20–30 mmHg) critical for fat-graft survival, edema control, and preventing seroma in the first 3 weeks after BBL or lipo. Tighter than Stage 2.',
      'guidance':
          'Wear 23 hours/day for the first 3 weeks. Remove only to shower. Your surgeon will advise when to transition to Stage 2 (typically Week 3–6). Wash daily.',
      'evidence': 'Proven efficacy',
      'link':
          'https://www.amazon.com/s?k=stage+1+compression+faja+post+surgery',
      'image': 'https://via.placeholder.com/200x200?text=Stage+1+Faja',
      'category': 'Recovery Support',
    },
    {
      'name': 'BBL Recovery Foam Cushion / Pillow',
      'brand': 'BBL Pillow Co. / Bombshell Booty Pillow',
      'reason':
          'Sitting directly on transferred fat grafts in the first 8 weeks compresses and kills fragile new fat cells, reducing final volume retention by 20–40%. A BBL cushion transfers weight to the thighs instead of the buttocks.',
      'guidance':
          'Use whenever seated for the first 8 weeks. Place under thighs so buttocks are suspended. Use in chairs, cars, and at work. Sleeping prone is preferred.',
      'evidence': 'Clinical consensus',
      'link': 'https://www.amazon.com/s?k=bbl+recovery+pillow+cushion',
      'image': 'https://via.placeholder.com/200x200?text=BBL+Cushion',
      'category': 'Recovery Support',
    },
    {
      'name': 'Vitamin C 1000mg + Zinc Supplement',
      'brand': 'Garden of Life / NOW Foods',
      'reason':
          'Vitamin C is a co-factor for collagen synthesis and directly supports wound healing, fat-graft vascularisation, and scar remodelling. Zinc accelerates cellular repair at surgical sites.',
      'guidance':
          'Take 1000mg Vitamin C and 15–30mg Zinc daily with food. Begin on day of surgery and continue for 3 months. Do not exceed 2000mg Vitamin C/day.',
      'evidence': 'Evidence-backed',
      'link':
          'https://www.amazon.com/s?k=vitamin+c+1000mg+zinc+supplement+wound+healing',
      'image': 'https://via.placeholder.com/200x200?text=Vit+C+Zinc',
      'category': 'Maintenance',
    },
    {
      'name': 'Oral Arnica Montana 30C Pellets',
      'brand': 'Boiron',
      'reason':
          'Oral arnica provides systemic anti-inflammatory and anti-ecchymotic action beyond what topical gel can achieve. Most effective in Days 1–7 for reducing deep bruising across the treated body area.',
      'guidance':
          'Dissolve 5 pellets under tongue 3–5 times daily for the first 7 days. Take 15 minutes before or after food. Safe alongside standard post-op medications.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=boiron+arnica+montana+30c+pellets',
      'image': 'https://via.placeholder.com/200x200?text=Arnica+Pellets',
      'category': 'Recovery Support',
    },
  ];

  static const List<Map<String, String>> _hairTransplantProducts = [
    {
      'name': 'Sulfate-Free Gentle Shampoo',
      'brand': 'Pura D\'or / Nizoral',
      'reason':
          'Sulfate-free formulas cleanse grafts and donor sites without disrupting the healing scalp barrier. Standard sulfate shampoos strip protective sebum from healing follicles.',
      'guidance':
          'Begin gentle washing per your surgeon\'s protocol (typically day 3–7). Apply using only fingertips with light tapping — never rub or scrub. Rinse gently.',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=sulfate+free+gentle+shampoo+hair+transplant',
      'image': 'https://via.placeholder.com/200x200?text=Gentle+Shampoo',
      'category': 'Recovery Support',
    },
    {
      'name': 'Aloe Vera Scalp Soothing Gel',
      'brand': 'Seven Minerals',
      'reason':
          'Pure aloe vera reduces scalp redness and inflammation at graft sites. Anti-inflammatory compounds soothe itching (nerve regeneration) without disrupting scab formation.',
      'guidance':
          'Apply a thin layer to itchy areas (not to fresh scabs). Refrigerate for enhanced cooling effect. Do not use until cleared by your surgeon (usually week 2+).',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=aloe+vera+scalp+soothing+gel+pure',
      'image': 'https://via.placeholder.com/200x200?text=Scalp+Aloe',
      'category': 'Recovery Support',
    },
    {
      'name': 'Arnica Montana Supplement (Oral)',
      'brand': 'Boiron',
      'reason':
          'Oral arnica reduces scalp swelling and bruising at the donor site. Particularly effective in the first 5–7 days post-transplant.',
      'guidance':
          'Dissolve 5 pellets under tongue 3 times daily for 5 days post-op. Take 15 minutes before or after eating. Safe for concurrent medications.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=boiron+arnica+montana+oral+pellets',
      'image': 'https://via.placeholder.com/200x200?text=Arnica+Oral',
      'category': 'Recovery Support',
    },
    {
      'name': 'Minoxidil 5% Topical Solution',
      'brand': 'Kirkland / Rogaine',
      'reason':
          'Minoxidil reduces shock loss duration and supports new growth after transplant. Clinically proven to accelerate the recovery of transplanted and native follicles.',
      'guidance':
          'Apply 1ml to recipient area twice daily. Begin only when cleared by your surgeon (typically month 1–2). Consistent daily use required for results.',
      'evidence': 'Proven efficacy',
      'link': 'https://www.amazon.com/s?k=minoxidil+5+percent+solution',
      'image': 'https://via.placeholder.com/200x200?text=Minoxidil+5%25',
      'category': 'Maintenance',
    },
    {
      'name': 'Biotin + Saw Palmetto Supplement',
      'brand': 'Nutrafol / Sports Research',
      'reason':
          'Biotin supports keratin production for healthy hair shaft growth. Saw Palmetto is a clinically-studied DHT blocker that protects native follicles from miniaturisation.',
      'guidance':
          'Take daily with food. Allow 3–6 months for meaningful hair density response. Combine with adequate dietary protein (1.2–1.6g/kg body weight).',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=biotin+saw+palmetto+hair+supplement',
      'image': 'https://via.placeholder.com/200x200?text=Biotin+DHT',
      'category': 'Maintenance',
    },
    {
      'name': 'Scalp UV Protection Spray SPF 30',
      'brand': 'Neutrogena',
      'reason':
          'UV exposure on healing grafts causes pigmentation changes and may impair graft survival. Scalp SPF spray is essential during outdoor activity for the first 3 months.',
      'guidance':
          'Spray on scalp before sun exposure. Reapply every 2 hours. Avoid direct spray on scabs in early weeks — use fingers to apply carefully.',
      'evidence': 'Clinical consensus',
      'link': 'https://www.amazon.com/s?k=scalp+sunscreen+spray+spf+30',
      'image': 'https://via.placeholder.com/200x200?text=Scalp+SPF',
      'category': 'Prevention',
    },
  ];

  static const List<Map<String, String>> _injectablesProducts = [
    {
      'name': 'Arnica Montana Cream',
      'brand': 'Boiron',
      'reason':
          'Arnica is the most recommended topical for injection-site bruising. Reduces ecchymosis duration by up to 50% when applied promptly after treatment.',
      'guidance':
          'Apply gently to bruised areas 2–3 times daily. Begin within hours of treatment. Avoid direct pressure over filler sites.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=boiron+arnica+cream+bruise',
      'image': 'https://via.placeholder.com/200x200?text=Arnica+Cream',
      'category': 'Recovery Support',
    },
    {
      'name': 'Bromelain Supplement (500mg)',
      'brand': 'Now Foods',
      'reason':
          'Bromelain taken orally reduces bruising and swelling from injections. Most effective when started 24 hours before treatment and continued for 3–5 days.',
      'guidance':
          'Take 500mg twice daily between meals. Avoid on an empty stomach. Particularly useful for lip fillers and larger volume treatments.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=bromelain+500mg+supplement',
      'image': 'https://via.placeholder.com/200x200?text=Bromelain',
      'category': 'Recovery Support',
    },
    {
      'name': 'Centella Asiatica Barrier Cream',
      'brand': 'COSRX',
      'reason':
          'Supports skin barrier recovery at injection sites and reduces post-injection redness. Safe for use near filler areas without disrupting treatment results.',
      'guidance':
          'Apply morning and evening to treated areas starting 24 hours post-injection. Avoid direct pressure over fresh filler deposits for 2 weeks.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=cosrx+centella+asiatica+cream',
      'image': 'https://via.placeholder.com/200x200?text=Centella+Cream',
      'category': 'Recovery Support',
    },
    {
      'name': 'Niacinamide 10% Serum',
      'brand': 'The Ordinary',
      'reason':
          'Niacinamide reduces post-injection redness and supports skin firmness. Works synergistically with filler treatment to improve overall tone and texture.',
      'guidance':
          'Apply after cleansing, 1–2 times daily. Avoid injection sites for the first 48 hours. Resume full routine at week 2.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=the+ordinary+niacinamide+10',
      'image': 'https://via.placeholder.com/200x200?text=Niacinamide',
      'category': 'Maintenance',
    },
    {
      'name': 'Broad-Spectrum Sunscreen SPF 50',
      'brand': 'EltaMD',
      'reason':
          'UV exposure activates melanocytes near injection sites, potentially causing PIH. Daily SPF is essential post-injectables, especially over bruised areas.',
      'guidance':
          'Apply every morning. Mineral-only formulas recommended in the first week (no rubbing — just dab over injection sites). Reapply at midday.',
      'evidence': 'Clinical consensus',
      'link': 'https://www.amazon.com/s?k=eltamd+spf+50+mineral+sunscreen',
      'image': 'https://via.placeholder.com/200x200?text=SPF+50',
      'category': 'Prevention',
    },
  ];

  // ── Metric-based product database (facial / general skincare) ──────────────
  static const Map<String, List<Map<String, String>>> _productDatabase = {
    'redness': [
      {
        'name': 'Medical-Grade Silicone Gel Sheeting',
        'brand': 'Scar Away',
        'reason':
            'With elevated redness, medical-grade silicone provides hydration and occlusion to accelerate healing. Clinically proven to reduce erythema and improve scar appearance.',
        'guidance':
            'Apply to affected areas for 12+ hours daily. Replace sheets every 12 hours. Results visible in 4–8 weeks.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=scar+away+silicone+gel+sheets',
        'image': 'https://via.placeholder.com/200x200?text=Silicone+Sheets',
        'category': 'Recovery Support',
      },
      {
        'name': 'Centella Asiatica Soothing Cream',
        'brand': 'COSRX',
        'reason':
            'Rich in active compounds that support skin barrier recovery. Ideal when redness is elevated—helps reduce inflammation and promote healing.',
        'guidance':
            'Apply morning and evening after cleansing. Layer under moisturizer for enhanced effect.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=cosrx+centella+asiatica+cream',
        'image': 'https://via.placeholder.com/200x200?text=Centella+Cream',
        'category': 'Recovery Support',
      },
      {
        'name': 'Azelaic Acid 20% Suspension',
        'brand': 'The Ordinary',
        'reason':
            'Excellent for reducing post-treatment erythema. Azelaic acid has anti-inflammatory and antioxidant properties specifically targeting redness.',
        'guidance':
            'Apply after cleansing, 1–2 times daily. May cause slight tingling initially. Introduce slowly.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=the+ordinary+azelaic+acid+20',
        'image': 'https://via.placeholder.com/200x200?text=Azelaic+Acid',
        'category': 'Recovery Support',
      },
    ],
    'texture': [
      {
        'name': 'Hyaluronic Acid Hydrating Serum',
        'brand': 'Olay',
        'reason':
            'When texture is rough, hydration is key. Hyaluronic acid draws moisture into skin, plumping fine irregularities and improving smoothness.',
        'guidance':
            'Apply to damp skin before moisturizer. Use morning and evening.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=olay+hyaluronic+acid+serum',
        'image': 'https://via.placeholder.com/200x200?text=HA+Serum',
        'category': 'Recovery Support',
      },
      {
        'name': 'Niacinamide 10% Serum',
        'brand': 'The Ordinary',
        'reason':
            'Niacinamide improves skin barrier function and has been shown to reduce roughness and improve skin smoothness. Perfect post-procedure.',
        'guidance':
            'Apply after cleansing. 1–2 times daily. Works synergistically with most serums.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=the+ordinary+niacinamide+10',
        'image': 'https://via.placeholder.com/200x200?text=Niacinamide',
        'category': 'Recovery Support',
      },
      {
        'name': 'Gentle Physical Exfoliant',
        'brand': 'La Roche-Posay',
        'reason':
            'Once healed, gentle exfoliation accelerates cell turnover and improves texture uniformity. Avoid first 2 weeks post-treatment.',
        'guidance':
            'Use 2–3 times weekly after full healing (post-treatment week 3+). Massage gently for 1–2 minutes.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=la+roche+posay+gentle+exfoliant',
        'image': 'https://via.placeholder.com/200x200?text=Exfoliant',
        'category': 'Maintenance',
      },
    ],
    'wrinkles': [
      {
        'name': 'Retinol 0.5% Night Serum',
        'brand': 'Paula\'s Choice',
        'reason':
            'Retinol stimulates collagen production and cellular turnover. Essential for wrinkle reduction. Start low after procedures to avoid irritation.',
        'guidance':
            'Begin 2–3 weeks post-procedure. Use 2–3 times weekly at night, increasing frequency as tolerance builds. Always follow with moisturizer.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=paulas+choice+retinol+serum',
        'image': 'https://via.placeholder.com/200x200?text=Retinol+Serum',
        'category': 'Maintenance',
      },
      {
        'name': 'Peptide Complex Cream',
        'brand': 'Drunk Elephant',
        'reason':
            'Peptides signal fibroblasts to increase collagen. Works synergistically with laser/microneedling to enhance fine line improvement.',
        'guidance':
            'Apply morning and evening. Layer as final step after serums. Use consistently for 8+ weeks for visible results.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=drunk+elephant+peptide+cream',
        'image': 'https://via.placeholder.com/200x200?text=Peptide+Cream',
        'category': 'Maintenance',
      },
      {
        'name': 'Vitamin C 15% Serum',
        'brand': 'Skinceuticals',
        'reason':
            'Vitamin C is a potent antioxidant that supports collagen synthesis and brightens skin. Ideal when fine lines are present.',
        'guidance':
            'Apply in morning before sunscreen. Use 2–3 times weekly initially, building to daily use.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=skinceuticals+vitamin+c+15',
        'image': 'https://via.placeholder.com/200x200?text=Vitamin+C',
        'category': 'Maintenance',
      },
    ],
    'pores': [
      {
        'name': 'BHA Salicylic Acid Exfoliant',
        'brand': 'Paula\'s Choice',
        'reason':
            'BHA penetrates pores to dissolve sebum and exfoliate internal walls. Reduces pore appearance and prevents congestion.',
        'guidance':
            'Start 1–2 weeks post-procedure. Use 2–3 times weekly. Not recommended during active healing or with peeling.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=paulas+choice+bha+salicylic',
        'image': 'https://via.placeholder.com/200x200?text=BHA+Exfoliant',
        'category': 'Maintenance',
      },
      {
        'name': 'Pore-Minimizing Primer',
        'brand': 'Benefit',
        'reason':
            'When pore size is still elevated, a silicone-based primer visually minimizes appearance while skin continues healing.',
        'guidance':
            'Apply to clean, moisturized skin as makeup base or standalone.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=benefit+pore+minimizing+primer',
        'image': 'https://via.placeholder.com/200x200?text=Pore+Primer',
        'category': 'Recovery Support',
      },
      {
        'name': 'Clay Mask with Charcoal',
        'brand': 'Aztec Secret',
        'reason':
            'Draws impurities and excess oil from pores. Use post-healing to maintain pore clarity and prevent congestion.',
        'guidance':
            'Use 1 time weekly after initial healing. Apply for 10–15 minutes, then rinse with warm water.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=aztec+secret+clay+mask+charcoal',
        'image': 'https://via.placeholder.com/200x200?text=Clay+Mask',
        'category': 'Maintenance',
      },
    ],
    'darkSpots': [
      {
        'name': 'Hydroquinone 4% Fade Cream',
        'brand': 'Prescription-strength (consult provider)',
        'reason':
            'Gold-standard for hyperpigmentation. Hydroquinone inhibits tyrosinase and prevents melanin production.',
        'guidance':
            'Apply to affected spots twice daily for 12+ weeks. Sun protection mandatory. Consult provider before use.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=hydroquinone+4+percent+cream',
        'image': 'https://via.placeholder.com/200x200?text=Hydroquinone',
        'category': 'Maintenance',
      },
      {
        'name': 'Niacinamide + Vitamin C Serum',
        'brand': 'Mad Hippie',
        'reason':
            'Niacinamide regulates melanin and reduces uneven tone. Combined with Vitamin C, offers antioxidant protection and brightening.',
        'guidance':
            'Apply morning and evening. Works best with consistent sun protection. Results visible in 4–8 weeks.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=mad+hippie+niacinamide+vitamin+c',
        'image': 'https://via.placeholder.com/200x200?text=Niacinamide+VitC',
        'category': 'Maintenance',
      },
      {
        'name': 'Broad-Spectrum Sunscreen SPF 50+',
        'brand': 'EltaMD',
        'reason':
            'UV exposure worsens dark spots. Sunscreen is non-negotiable for fading hyperpigmentation. Use daily without fail.',
        'guidance':
            'Apply 15 minutes before sun exposure. Reapply every 2 hours.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=eltamd+broad+spectrum+spf+50',
        'image': 'https://via.placeholder.com/200x200?text=Sunscreen+SPF50',
        'category': 'Prevention',
      },
    ],
    'hydration': [
      {
        'name': 'Ceramide Barrier Repair Cream',
        'brand': 'CeraVe',
        'reason':
            'Ceramides restore barrier lipids and reduce transepidermal water loss. Ideal when hydration appears below your baseline.',
        'guidance':
            'Apply morning and evening as the final step. Use on damp skin for better water retention.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=cerave+ceramide+cream',
        'image': 'https://via.placeholder.com/200x200?text=Ceramide+Cream',
        'category': 'Recovery Support',
      },
      {
        'name': 'Hyaluronic Acid 2% + B5 Serum',
        'brand': 'The Ordinary',
        'reason':
            'Humectant hydration helps visibly plump dryness-related roughness and supports rebound hydration after procedures.',
        'guidance':
            'Apply to slightly damp skin, then seal with moisturizer. Use twice daily.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=the+ordinary+hyaluronic+acid+2+b5',
        'image': 'https://via.placeholder.com/200x200?text=HA+2%25+B5',
        'category': 'Recovery Support',
      },
      {
        'name': 'Squalane + Panthenol Moisture Serum',
        'brand': 'La Roche-Posay',
        'reason':
            'Supports long-wear hydration comfort and calms dehydration tightness without heaviness.',
        'guidance':
            'Use at night under moisturizer or as a daytime moisture booster before SPF.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=squalane+panthenol+serum',
        'image': 'https://via.placeholder.com/200x200?text=Squalane+Serum',
        'category': 'Maintenance',
      },
    ],
    'oiliness': [
      {
        'name': 'Niacinamide 10% Oil-Balance Serum',
        'brand': 'The Ordinary',
        'reason':
            'Niacinamide helps regulate sebum activity and improves shine control while still supporting barrier function.',
        'guidance':
            'Apply 1–2 pumps after cleansing, morning and evening. Follow with lightweight moisturizer.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=niacinamide+10+serum',
        'image': 'https://via.placeholder.com/200x200?text=Oil+Balance+Serum',
        'category': 'Maintenance',
      },
      {
        'name': 'Salicylic Acid 2% BHA Liquid',
        'brand': 'Paula\'s Choice',
        'reason':
            'BHA penetrates oil-prone areas to reduce congestion and mattify pores over time.',
        'guidance':
            'Use at night 2–3 times weekly. Skip during high sensitivity/redness flare windows.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=paulas+choice+bha+2+percent',
        'image': 'https://via.placeholder.com/200x200?text=BHA+2%25',
        'category': 'Maintenance',
      },
      {
        'name': 'Kaolin Clay Purifying Mask',
        'brand': 'Innisfree',
        'reason':
            'Helps absorb excess oil and reduce greasy-zone shine when used conservatively.',
        'guidance':
            'Use once weekly for 10 minutes on the T-zone only, then hydrate afterward.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=kaolin+clay+mask',
        'image': 'https://via.placeholder.com/200x200?text=Clay+Mask',
        'category': 'Maintenance',
      },
    ],
    'sensitivity': [
      {
        'name': 'Centella + Ceramide Recovery Balm',
        'brand': 'Dr. Jart+',
        'reason':
            'Designed for reactive skin, combining calming Centella with barrier lipids for post-scan comfort support.',
        'guidance':
            'Apply a thin layer morning and evening on reactive zones. Avoid friction during application.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=centella+ceramide+recovery+balm',
        'image': 'https://via.placeholder.com/200x200?text=Recovery+Balm',
        'category': 'Recovery Support',
      },
      {
        'name': 'Thermal Spring Water Mist',
        'brand': 'Avène',
        'reason':
            'Lightweight soothing support for heat-prone, sensitive skin without active irritation risk.',
        'guidance':
            'Mist after cleansing and before moisturizer, or throughout the day for redness comfort.',
        'evidence': 'Clinical consensus',
        'link': 'https://www.amazon.com/s?k=avene+thermal+spring+water',
        'image': 'https://via.placeholder.com/200x200?text=Thermal+Mist',
        'category': 'Recovery Support',
      },
      {
        'name': 'Fragrance-Free Barrier Moisturizer',
        'brand': 'Vanicream',
        'reason':
            'Reduces trigger load in sensitivity-prone routines while supporting hydration and barrier resilience.',
        'guidance':
            'Use twice daily and pair with mineral SPF in daytime.',
        'evidence': 'Proven efficacy',
        'link': 'https://www.amazon.com/s?k=vanicream+moisturizing+cream',
        'image': 'https://via.placeholder.com/200x200?text=Barrier+Moisturizer',
        'category': 'Recovery Support',
      },
    ],
    'elasticity': [
      {
        'name': 'Collagen Peptide Supplement',
        'brand': 'Vital Proteins',
        'reason':
            'Oral collagen supplements support dermal collagen synthesis from within. Evidence suggests improved skin elasticity when taken consistently.',
        'guidance':
            'Mix 1 scoop into morning coffee or water. Take daily for 8+ weeks. Best with vitamin C.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=vital+proteins+collagen+peptides',
        'image': 'https://via.placeholder.com/200x200?text=Collagen+Peptides',
        'category': 'Maintenance',
      },
      {
        'name': 'Bakuchiol Night Cream',
        'brand': 'Augustinus Bader',
        'reason':
            'Natural retinol alternative that stimulates collagen and improves elasticity without irritation. Ideal post-procedure.',
        'guidance':
            'Apply at night as final moisturizing layer. Use daily for best results.',
        'evidence': 'Evidence-backed',
        'link': 'https://www.amazon.com/s?k=augustinus+bader+bakuchiol+cream',
        'image': 'https://via.placeholder.com/200x200?text=Bakuchiol+Cream',
        'category': 'Maintenance',
      },
      {
        'name': 'Peptide + Hyaluronic Acid Moisturizer',
        'brand': 'Neutrogena',
        'reason':
            'Peptides and HA work together to support skin firmness and plumpness. Improves visible elasticity by maintaining dermal hydration.',
        'guidance':
            'Use 2–3 pumps, morning and evening. Apply after serums as final moisturizing step.',
        'evidence': 'Evidence-backed',
        'link':
            'https://www.amazon.com/s?k=neutrogena+peptide+hyaluronic+acid+moisturizer',
        'image': 'https://via.placeholder.com/200x200?text=Peptide+HA+Cream',
        'category': 'Recovery Support',
      },
    ],
  };

  static const List<Map<String, String>> _liposuctionProducts = [
    {
      'name': 'Arnica Montana Gel',
      'brand': 'Boiron',
      'reason':
          'Arnica is commonly used to support bruise and swelling recovery after liposuction. It fits the early post-op phase without introducing BBL-specific guidance.',
      'guidance':
          'Apply gently to bruised skin once your incision sites are closed enough for topical use, typically starting a few days after surgery if your surgeon approves.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=boiron+arnica+montana+gel',
      'image': 'https://via.placeholder.com/200x200?text=Arnica+Gel',
      'category': 'Recovery Support',
    },
    {
      'name': 'Compression Garment / Faja',
      'brand': 'Marena / Ann Chery',
      'reason':
          'Compression is one of the main recovery tools after liposuction. It helps control swelling, support contour retraction, and reduce the chance of prolonged firmness.',
      'guidance':
          'Wear exactly as your surgeon directed, often most of the day during the early recovery window. Make sure the garment fits evenly and does not bunch.',
      'evidence': 'Clinical consensus',
      'link': 'https://www.amazon.com/s?k=post+lipo+compression+garment',
      'image': 'https://via.placeholder.com/200x200?text=Compression+Garment',
      'category': 'Recovery Support',
    },
    {
      'name': 'Bromelain Supplement',
      'brand': 'Now Foods',
      'reason':
          'Bromelain is often used to help with bruising and swelling during liposuction recovery. It supports the early healing phase without BBL-only positioning advice.',
      'guidance':
          'Take only if cleared by your surgeon or care team. Use between meals and avoid if it conflicts with prescribed medications.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=bromelain+supplement',
      'image': 'https://via.placeholder.com/200x200?text=Bromelain',
      'category': 'Recovery Support',
    },
    {
      'name': 'Lymphatic Drainage Massage Oil',
      'brand': 'Maelys / Palmer\'s',
      'reason':
          'Manual lymphatic drainage is frequently used after liposuction to help resolve swelling and firmness while contour settles.',
      'guidance':
          'Use during gentle massage sessions only after your surgeon or therapist says it is appropriate. Keep pressure light and follow the direction provided.',
      'evidence': 'Evidence-backed',
      'link':
          'https://www.amazon.com/s?k=lymphatic+drainage+massage+oil+post+surgery',
      'image': 'https://via.placeholder.com/200x200?text=Lymphatic+Oil',
      'category': 'Recovery Support',
    },
    {
      'name': 'Silicone Scar Sheets',
      'brand': 'ScarAway',
      'reason':
          'Silicone is a standard option for incision healing and scar support after liposuction once the skin is fully closed.',
      'guidance':
          'Apply only after incisions are closed. Wear consistently as directed and replace according to product instructions.',
      'evidence': 'Proven efficacy',
      'link': 'https://www.amazon.com/s?k=scaraway+silicone+sheets',
      'image': 'https://via.placeholder.com/200x200?text=Scar+Sheets',
      'category': 'Recovery Support',
    },
    {
      'name': 'High-Protein Collagen Supplement',
      'brand': 'Vital Proteins',
      'reason':
          'Adequate protein intake supports tissue repair and post-liposuction recovery. Collagen peptides can help patients stay consistent with nutritional support.',
      'guidance':
          'Use daily as part of a protein-forward diet. Pair with vitamin C if your provider approves supplements.',
      'evidence': 'Evidence-backed',
      'link': 'https://www.amazon.com/s?k=vital+proteins+collagen+peptides',
      'image': 'https://via.placeholder.com/200x200?text=Collagen+Protein',
      'category': 'Maintenance',
    },
    {
      'name': 'Body Broad-Spectrum SPF 50 Spray',
      'brand': 'Neutrogena',
      'reason':
          'Healing incision sites and bruised skin can darken with UV exposure, so daily sun protection matters after liposuction.',
      'guidance':
          'Apply to exposed areas before sun exposure and reapply as directed. Do not use on open wounds.',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=neutrogena+body+sunscreen+spf+50+spray',
      'image': 'https://via.placeholder.com/200x200?text=Body+SPF',
      'category': 'Prevention',
    },
    {
      'name': 'Fragrance-Free Body Moisturizer',
      'brand': 'CeraVe',
      'reason':
          'A barrier-supporting moisturizer helps the skin remain comfortable as contour retraction continues after liposuction.',
      'guidance':
          'Use after wounds are fully closed and massage in gently if cleared by your surgeon.',
      'evidence': 'Clinical consensus',
      'link':
          'https://www.amazon.com/s?k=cerave+fragrance+free+body+moisturizer',
      'image': 'https://via.placeholder.com/200x200?text=Body+Moisturizer',
      'category': 'Maintenance',
    },
  ];

  /// Generate 2–4 personalized product recommendations based on the procedure type
  /// and current skin metrics.
  ///
  /// Procedure-specific catalogs take full priority for body contouring, hair transplant,
  /// and injectables. Facial procedures use metric-based selection filtered to relevant metrics.
  static List<AIProductRecommendation> generateRecommendations(
    SkinMetrics currentMetrics, {
    SkinMetrics? baselineMetrics,
    int maxRecommendations = 4,
    String? procedureType,
    CvSkinMetricsContext? cvMetrics,
    List<String>? userSkinConcerns,
    List<String>? recentProcedureTypes,
  }) {
    final directProcedureType = _cleanProcedureType(procedureType);
    final cleanedRecentProcedureTypes = recentProcedureTypes
        ?.map(_cleanProcedureType)
        .whereType<String>()
        .toList();
    final resolvedProcedureType = _resolveProcedureType(
      procedureType: directProcedureType,
      recentProcedureTypes: cleanedRecentProcedureTypes,
    );
    baselineMetrics ??= const SkinMetrics(
      redness: 5.5,
      texture: 5.5,
      wrinkle: 5.5,
      pore: 5.5,
      darkSpots: 5.0,
      elasticity: 5.5,
    );

    final category = ProcedureIntelligence.categoryFor(resolvedProcedureType);
    final bodySubtype = ProcedureIntelligence.bodyContouringSubtype(
      resolvedProcedureType,
    );

    // ── Procedure-specific curated catalogs ──────────────────────────────────
    List<Map<String, String>>? catalog;
    switch (category) {
      case ProcedureCategory.bodyContouring:
        catalog = switch (bodySubtype) {
          ProcedureBodyContouringSubtype.bbl => _bodyContouringProducts,
          ProcedureBodyContouringSubtype.liposuction => _liposuctionProducts,
          ProcedureBodyContouringSubtype.other => _liposuctionProducts,
        };
        break;
      case ProcedureCategory.hairTransplant:
        catalog = _hairTransplantProducts;
        break;
      case ProcedureCategory.injectables:
        catalog = _injectablesProducts;
        break;
      case ProcedureCategory.bodyComposition:
        // Body-composition / peptide weight-loss protocols don't pair with
        // facial-skincare product recs. The scan-based recommendation engine
        // surfaces body-focused peptides and body procedures (CoolSculpting,
        // EmSculpt NEO, BodyTite RF, Liposuction, Lymphatic Drainage Massage)
        // separately in this context.
        return const [];
      default:
        catalog = null;
    }

    final highSensitivityOrRedness =
        ((cvMetrics?.sensitivityLevel ?? 0) >= 6.5) ||
        ((cvMetrics?.rednessLevel ?? 0) >= 6.0);

    if (catalog != null) {
      final sortedCatalog = [...catalog]
        ..sort(
          (a, b) => _catalogFitScore(
            b,
            cvMetrics: cvMetrics,
            userSkinConcerns: userSkinConcerns,
            highSensitivityOrRedness: highSensitivityOrRedness,
            procedureType: resolvedProcedureType,
            recentProcedureTypes: recentProcedureTypes,
          ).compareTo(
            _catalogFitScore(
              a,
              cvMetrics: cvMetrics,
              userSkinConcerns: userSkinConcerns,
              highSensitivityOrRedness: highSensitivityOrRedness,
              procedureType: resolvedProcedureType,
              recentProcedureTypes: recentProcedureTypes,
            ),
          ),
        );
      return catalog
          .isEmpty
          ? const []
          : sortedCatalog
          .take(maxRecommendations)
          .map(
            (p) => AIProductRecommendation(
              productName: p['name']!,
              brand: p['brand']!,
              clinicalReason: p['reason']!,
              usageGuidance: p['guidance']!,
              evidenceLevel: p['evidence']!,
              affiliateLink: p['link']!,
              imageUrl: p['image']!,
              category: p['category']!,
            ),
          )
          .toList();
    }

    // ── Metric-based selection for facial / general procedures ──────────────
    final priorities = _mergePriorities(
      _identifyPriorityIssues(currentMetrics, baselineMetrics),
      _identifyCvPriorities(cvMetrics),
    );
    final relevantKeys = ProcedureIntelligence.relevantMetrics(procedureType);
    final isGeneral = category == ProcedureCategory.generalSkincare;

    final sortedPriorities = isGeneral
        ? priorities
        : [
            ...priorities.where(
              (p) => relevantKeys.contains(_canonicalKey(p.metricKey)),
            ),
            ...priorities.where(
              (p) => !relevantKeys.contains(_canonicalKey(p.metricKey)),
            ),
          ];

    final recommendations = <AIProductRecommendation>[];
    for (final priority in sortedPriorities) {
      if (recommendations.length >= maxRecommendations) break;
      final products = _productDatabase[priority.metricKey];
      if (products == null || products.isEmpty) continue;
      final selected = _selectBestProduct(
        products,
        metricKey: priority.metricKey,
        currentValue: priority.currentValue,
        improvement: priority.improvement,
        cvMetrics: cvMetrics,
        userSkinConcerns: userSkinConcerns,
        highSensitivityOrRedness: highSensitivityOrRedness,
        procedureType: resolvedProcedureType,
        recentProcedureTypes: recentProcedureTypes,
      );
      recommendations.add(
        AIProductRecommendation(
          productName: selected['name']!,
          brand: selected['brand']!,
          clinicalReason: _personalizeReason(
            selected['reason']!,
            priority.metricKey,
            priority.currentValue,
            priority.improvement,
            cvMetrics: cvMetrics,
          ),
          usageGuidance: selected['guidance']!,
          evidenceLevel: selected['evidence']!,
          affiliateLink: selected['link']!,
          imageUrl: selected['image']!,
          category: selected['category']!,
        ),
      );
    }

    return recommendations;
  }

  /// Identifies priority issues by comparing current vs baseline metrics.
  static List<_MetricPriority> _identifyPriorityIssues(
    SkinMetrics current,
    SkinMetrics baseline,
  ) {
    final priorities = <_MetricPriority>[];

    final lowerIsBetter = [
      ('redness', current.redness, baseline.redness),
      ('texture', current.texture, baseline.texture),
      ('wrinkles', current.wrinkle, baseline.wrinkle),
      ('pores', current.pore, baseline.pore),
      ('darkSpots', current.darkSpots, baseline.darkSpots),
    ];

    for (final (key, curVal, baseVal) in lowerIsBetter) {
      final delta = baseVal - curVal;
      priorities.add(
        _MetricPriority(
          metricKey: key,
          currentValue: curVal,
          baselineValue: baseVal,
          delta: delta,
          severity: curVal,
          improvement: delta,
        ),
      );
    }

    final elasticityDelta = current.elasticity - baseline.elasticity;
    priorities.add(
      _MetricPriority(
        metricKey: 'elasticity',
        currentValue: current.elasticity,
        baselineValue: baseline.elasticity,
        delta: elasticityDelta,
        severity: (10 - current.elasticity),
        improvement: elasticityDelta,
      ),
    );

    priorities.sort((a, b) {
      final scoreA = (a.severity * 1.5) - (a.improvement.abs() * 0.5);
      final scoreB = (b.severity * 1.5) - (b.improvement.abs() * 0.5);
      return scoreB.compareTo(scoreA);
    });

    return priorities;
  }

  static Map<String, String> _selectBestProduct(
    List<Map<String, String>> products,
    {
    required String metricKey,
    required double currentValue,
    required double improvement,
    CvSkinMetricsContext? cvMetrics,
    List<String>? userSkinConcerns,
    required bool highSensitivityOrRedness,
    String? procedureType,
    List<String>? recentProcedureTypes,
    }
  ) {
    if (products.isEmpty) return {};

    final guarded = highSensitivityOrRedness
        ? products.where((p) => !_isStrongActiveProduct(p)).toList()
        : products;
    final candidates = guarded.isNotEmpty ? guarded : products;

    if (candidates.length == 1) return candidates.first;

    final sorted = [...candidates]
      ..sort(
        (a, b) => _productScoreForMetric(
          b,
          metricKey: metricKey,
          currentValue: currentValue,
          improvement: improvement,
          cvMetrics: cvMetrics,
          userSkinConcerns: userSkinConcerns,
          highSensitivityOrRedness: highSensitivityOrRedness,
          procedureType: procedureType,
          recentProcedureTypes: recentProcedureTypes,
        ).compareTo(
          _productScoreForMetric(
            a,
            metricKey: metricKey,
            currentValue: currentValue,
            improvement: improvement,
            cvMetrics: cvMetrics,
            userSkinConcerns: userSkinConcerns,
            highSensitivityOrRedness: highSensitivityOrRedness,
            procedureType: procedureType,
            recentProcedureTypes: recentProcedureTypes,
          ),
        ),
      );

    if (currentValue > 6.5) return sorted.first;
    if (currentValue > 5.0) {
      return sorted.length > 1 ? sorted[1] : sorted.first;
    }
    return sorted.length > 2 ? sorted[2] : sorted.first;
  }

  static String _personalizeReason(
    String baseReason,
    String metricKey,
    double currentValue,
    double improvement,
    {CvSkinMetricsContext? cvMetrics}
  ) {
    final rounded = currentValue.toStringAsFixed(1);
    final improvementStr = improvement > 0
        ? 'improving by ${improvement.toStringAsFixed(1)}'
        : 'stable at $rounded';
    String explainableTail = '';
    switch (metricKey) {
      case 'hydration':
        final pct = cvMetrics?.hydrationLevel != null
            ? ((cvMetrics!.hydrationLevel! * 10).round())
            : null;
        explainableTail = pct != null
          ? ' Great for your current dryness level ($pct%).'
            : ' Great for your current dryness level.';
        break;
      case 'oiliness':
        explainableTail = ' This is a strong fit for your current oil-control needs.';
        break;
      case 'sensitivity':
        explainableTail =
            ' Chosen to support barrier calm and reduce irritation risk right now.';
        break;
      case 'elasticity':
      case 'texture':
        explainableTail =
            ' Selected to support collagen quality and smoother surface texture.';
        break;
    }
    switch (metricKey) {
      case 'redness':
        return 'With erythema at $rounded, $baseReason$explainableTail';
      case 'texture':
        return 'Your skin texture quality reads $rounded—$baseReason$explainableTail';
      case 'wrinkles':
        return 'Rhytid depth currently registers $rounded—$baseReason$explainableTail';
      case 'pores':
        return 'Pore visibility registers at $rounded—$baseReason$explainableTail';
      case 'darkSpots':
        return 'Hyperpigmentation severity is $rounded—$baseReason$explainableTail';
      case 'hydration':
        return 'Hydration support target is $rounded—$baseReason$explainableTail';
      case 'oiliness':
        return 'Oil-control need currently reads $rounded—$baseReason$explainableTail';
      case 'sensitivity':
        return 'Skin reactivity currently reads $rounded—$baseReason$explainableTail';
      case 'elasticity':
        return 'With skin laxity at $rounded and $improvementStr, $baseReason$explainableTail';
      default:
        return '$baseReason$explainableTail';
    }
  }

  static List<_MetricPriority> _identifyCvPriorities(CvSkinMetricsContext? cv) {
    if (cv == null) return const [];
    final out = <_MetricPriority>[];

    void addHigherIsConcern(String key, double? v) {
      if (v == null) return;
      out.add(
        _MetricPriority(
          metricKey: key,
          currentValue: v.clamp(0.0, 10.0),
          baselineValue: 5.0,
          delta: 0.0,
          severity: v.clamp(0.0, 10.0),
          improvement: 0.0,
        ),
      );
    }

    void addLowerIsConcern(String key, double? v) {
      if (v == null) return;
      final normalized = (10 - v).clamp(0.0, 10.0);
      out.add(
        _MetricPriority(
          metricKey: key,
          currentValue: normalized,
          baselineValue: 5.0,
          delta: 0.0,
          severity: normalized,
          improvement: 0.0,
        ),
      );
    }

    addLowerIsConcern('hydration', cv.hydrationLevel);
    addHigherIsConcern('oiliness', cv.oilinessLevel);
    addHigherIsConcern('pores', cv.poreVisibility);
    addHigherIsConcern('sensitivity', cv.sensitivityLevel);
    addHigherIsConcern('redness', cv.rednessLevel);
    addHigherIsConcern('texture', cv.textureRoughness);
    addLowerIsConcern('elasticity', cv.collagenElasticity);

    return out;
  }

  static List<_MetricPriority> _mergePriorities(
    List<_MetricPriority> base,
    List<_MetricPriority> cv,
  ) {
    if (cv.isEmpty) return base;
    final merged = <String, _MetricPriority>{};
    for (final p in [...base, ...cv]) {
      final key = p.metricKey;
      final existing = merged[key];
      if (existing == null || p.severity > existing.severity) {
        merged[key] = p;
      }
    }
    final out = merged.values.toList()
      ..sort((a, b) {
        final scoreA = (a.severity * 1.5) - (a.improvement.abs() * 0.5);
        final scoreB = (b.severity * 1.5) - (b.improvement.abs() * 0.5);
        return scoreB.compareTo(scoreA);
      });
    return out;
  }

  static bool _isStrongActiveProduct(Map<String, String> product) {
    final blob =
        '${product['name'] ?? ''} ${product['reason'] ?? ''} ${product['guidance'] ?? ''}'
            .toLowerCase();
    const strongActives = [
      'retinol',
      'hydroquinone',
      'bha',
      'salicylic',
      'aha',
      'glycolic',
      'exfoliant',
      'peel',
    ];
    return strongActives.any(blob.contains);
  }

  static int _catalogFitScore(
    Map<String, String> product, {
    CvSkinMetricsContext? cvMetrics,
    List<String>? userSkinConcerns,
    required bool highSensitivityOrRedness,
    String? procedureType,
    List<String>? recentProcedureTypes,
  }) {
    return _productScoreForMetric(
      product,
      metricKey: 'general',
      currentValue: 5.0,
      improvement: 0.0,
      cvMetrics: cvMetrics,
      userSkinConcerns: userSkinConcerns,
      highSensitivityOrRedness: highSensitivityOrRedness,
      procedureType: procedureType,
      recentProcedureTypes: recentProcedureTypes,
    );
  }

  static int _productScoreForMetric(
    Map<String, String> product, {
    required String metricKey,
    required double currentValue,
    required double improvement,
    CvSkinMetricsContext? cvMetrics,
    List<String>? userSkinConcerns,
    required bool highSensitivityOrRedness,
    String? procedureType,
    List<String>? recentProcedureTypes,
  }) {
    final blob =
        '${product['name'] ?? ''} ${product['reason'] ?? ''} ${product['guidance'] ?? ''} ${product['category'] ?? ''}'
            .toLowerCase();

    int score = 0;

    bool hasAny(List<String> keys) => keys.any(blob.contains);

    switch (metricKey) {
      case 'hydration':
        if (hasAny(['hyaluronic', 'ceramide', 'barrier', 'centella', 'soothing'])) score += 9;
        if (hasAny(['moisturizer', 'hydration'])) score += 5;
        break;
      case 'oiliness':
        if (hasAny(['mattify', 'oil', 'sebum', 'clay', 'bha', 'niacinamide'])) score += 8;
        break;
      case 'sensitivity':
      case 'redness':
        if (hasAny(['centella', 'soothing', 'barrier', 'silicone', 'arnica', 'azelaic'])) score += 9;
        if (hasAny(['fragrance-free', 'gentle'])) score += 4;
        break;
      case 'texture':
      case 'elasticity':
      case 'wrinkles':
        if (hasAny(['peptide', 'collagen', 'bakuchiol', 'elasticity'])) score += 8;
        if (hasAny(['retinol'])) score += 5;
        break;
      case 'pores':
        if (hasAny(['pore', 'bha', 'niacinamide', 'clay'])) score += 8;
        break;
      default:
        if (hasAny(['barrier', 'recovery', 'maintenance'])) score += 3;
    }

    if (highSensitivityOrRedness && _isStrongActiveProduct(product)) score -= 9;
    if (currentValue >= 7) score += 2;
    if (improvement > 0.8) score -= 1;

    final concernsBlob = (userSkinConcerns ?? const <String>[])
        .join(' ')
        .toLowerCase();
    if (concernsBlob.isNotEmpty) {
      if (concernsBlob.contains('dry') && hasAny(['hyaluronic', 'ceramide', 'barrier'])) score += 3;
      if (concernsBlob.contains('sensitive') && hasAny(['soothing', 'centella', 'fragrance-free'])) score += 3;
      if (concernsBlob.contains('oil') && hasAny(['oil', 'mattify', 'clay', 'bha'])) score += 3;
      if (concernsBlob.contains('aging') && hasAny(['peptide', 'collagen', 'elasticity'])) score += 3;
    }

    final procedureBlob =
        '${procedureType ?? ''} ${(recentProcedureTypes ?? const <String>[]).join(' ')}'.toLowerCase();
    if (procedureBlob.contains('laser') || procedureBlob.contains('peel') || procedureBlob.contains('microneed')) {
      if (hasAny(['barrier', 'soothing', 'spf', 'centella'])) score += 2;
      if (_isStrongActiveProduct(product)) score -= 3;
    }

    return score;
  }

  static String _canonicalKey(String key) {
    switch (key) {
      case 'wrinkles':
        return 'wrinkle';
      case 'pores':
        return 'pore';
      case 'hydration':
        return 'hydration';
      case 'oiliness':
        return 'oiliness';
      case 'sensitivity':
        return 'sensitivity';
      default:
        return key;
    }
  }
}

/// Internal model tracking metric priority for analysis.
class _MetricPriority {
  final String metricKey;
  final double currentValue;
  final double baselineValue;
  final double delta;
  final double severity;
  final double improvement;

  _MetricPriority({
    required this.metricKey,
    required this.currentValue,
    required this.baselineValue,
    required this.delta,
    required this.severity,
    required this.improvement,
  });
}
