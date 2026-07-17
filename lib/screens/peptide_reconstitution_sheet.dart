import 'package:flutter/material.dart';

import '../app_theme.dart';

class PeptideReconstitutionSheet extends StatefulWidget {
  const PeptideReconstitutionSheet({super.key});

  @override
  State<PeptideReconstitutionSheet> createState() =>
      _PeptideReconstitutionSheetState();
}

class _PeptideReconstitutionSheetState
    extends State<PeptideReconstitutionSheet> {
  final TextEditingController _vialMgController = TextEditingController(
    text: '10',
  );
  final TextEditingController _targetConcentrationController =
      TextEditingController(text: '2');
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = _allCategory;
  final List<String> _recentlyViewed = <String>[];

  static const String _allCategory = 'All';
  static const List<String> _categoryOrder = <String>[
    _allCategory,
    'Anti-aging',
    'Recovery',
    'Neuro',
    'Libido',
    'Research',
  ];

  @override
  void dispose() {
    _vialMgController.dispose();
    _targetConcentrationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  double? get _vialMg => double.tryParse(_vialMgController.text.trim());
  double? get _targetMgPerMl =>
      double.tryParse(_targetConcentrationController.text.trim());

  double? get _requiredMl {
    final vialMg = _vialMg;
    final targetMgPerMl = _targetMgPerMl;
    if (vialMg == null || targetMgPerMl == null) return null;
    if (vialMg <= 0 || targetMgPerMl <= 0) return null;
    return vialMg / targetMgPerMl;
  }

  List<Map<String, dynamic>> get _favoritePeptides {
    return allPeptides
        .where((peptide) => peptide['featured'] == true)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _recentPeptides {
    return _recentlyViewed
        .map(
          (name) => allPeptides.firstWhere(
            (peptide) => peptide['name'] == name,
          ),
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _filteredPeptides {
    final query = _searchController.text.trim().toLowerCase();
    return allPeptides.where((peptide) {
      final category = peptide['category'] as String;
      final categoryMatches =
          _selectedCategory == _allCategory || category == _selectedCategory;
      if (!categoryMatches) return false;

      if (query.isEmpty) return true;
      final haystack = [
        peptide['name'],
        peptide['category'],
        peptide['vialSizes'],
        peptide['reconstitution'],
        peptide['stability'],
        peptide['dosage'],
        peptide['benefits'],
        peptide['notes'],
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  void _markViewed(String peptideName) {
    setState(() {
      _recentlyViewed.remove(peptideName);
      _recentlyViewed.insert(0, peptideName);
      if (_recentlyViewed.length > 6) {
        _recentlyViewed.removeRange(6, _recentlyViewed.length);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredPeptides = _filteredPeptides;
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final height = mediaQuery.size.height;
    final isNarrow = width < 420;
    final horizontalPadding = isNarrow ? 14.0 : 20.0;
    final libraryMaxHeight = height * (isNarrow ? 0.56 : 0.62);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Reconstitution Cheat Sheet'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeroDisclaimerCard(resultMl: _requiredMl),
                const SizedBox(height: 18),
                _CalculatorCard(
                  vialMgController: _vialMgController,
                  targetConcentrationController: _targetConcentrationController,
                  resultMl: _requiredMl,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 18),
                Text('Favorite references', style: MyApp.sectionTitleStyle()),
                const SizedBox(height: 10),
                Text(
                  'Start with the most-used peptides, then filter the full library by category or search term.',
                  style: TextStyle(
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _FeaturedPeptideStrip(
                  peptides: _favoritePeptides,
                  onTap: _markViewed,
                ),
                if (_recentPeptides.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Recently viewed', style: MyApp.sectionTitleStyle()),
                  const SizedBox(height: 10),
                  _FeaturedPeptideStrip(
                    peptides: _recentPeptides,
                    onTap: _markViewed,
                    compact: true,
                  ),
                ],
                const SizedBox(height: 18),
                Text('Full peptide library', style: MyApp.sectionTitleStyle()),
                const SizedBox(height: 10),
                Text(
                  'Sorted alphabetically for maintenance. Search by peptide, benefit, or note, and narrow the list with category chips.',
                  style: TextStyle(
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _SearchField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  resultCount: filteredPeptides.length,
                ),
                const SizedBox(height: 14),
                _CategoryChipRow(
                  selectedCategory: _selectedCategory,
                  onSelected: (category) => setState(() {
                    _selectedCategory = category;
                  }),
                ),
                const SizedBox(height: 14),
                _LibraryResultsSection(
                  peptides: filteredPeptides,
                  maxHeight: libraryMaxHeight,
                  query: _searchController.text.trim(),
                  category: _selectedCategory,
                  onTap: _markViewed,
                ),
                const SizedBox(height: 14),
                const _EducationalFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<Map<String, dynamic>> allPeptides = <Map<String, dynamic>>[
  {
    'name': 'Acetyl Tetrapeptide-5 (Eyeseryl)',
    'category': 'Anti-aging',
    'featured': true,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: low-percentage topical use in eye products',
    'benefits': 'Puffiness support, eye-area smoothing, luxe under-eye formulation work',
    'notes': 'Best treated as a cosmetic ingredient reference rather than an injection-focused entry.',
  },
  {
    'name': 'AOD-9604',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '2mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 2ml BAC for 2mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 1ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.4ml, 1ml, or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 250-500mcg once or twice daily',
    'benefits': 'Body-composition support, metabolic protocol planning, wellness tracking',
    'notes': 'Educational only. Often logged alongside diet, cardio, and body-composition goals.',
  },
  {
    'name': 'ARA-290',
    'category': 'Research',
    'featured': false,
    'vialSizes': '4mg, 8mg, 16mg',
    'reconstitution':
        'For 1mg/ml: add 4ml BAC for 4mg vial, 8ml for 8mg, 16ml for 16mg\nFor 2mg/ml: add 2ml, 4ml, or 8ml\nFor 5mg/ml: add 0.8ml, 1.6ml, or 3.2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 1-4mg depending on research or clinician-directed protocol context',
    'benefits': 'Recovery-interest support, comfort-focused protocol reference, nerve-repair discussions',
    'notes': 'Keep expectations conservative and treat stability windows cautiously after mixing.',
  },
  {
    'name': 'Argireline (Acetyl Hexapeptide-8)',
    'category': 'Anti-aging',
    'featured': true,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: small topical inclusion range in peptide serums or compounded solutions',
    'benefits': 'Expression-line softening, forehead smoothing support, luxe anti-aging layering',
    'notes': 'Most often used in topical aesthetic formulations rather than simple subcutaneous protocols.',
  },
  {
    'name': 'BPC-157',
    'category': 'Recovery',
    'featured': true,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 200-500mcg once or twice daily',
    'benefits': 'Healing support, soft-tissue recovery interest, post-procedure protocol planning',
    'notes': 'Commonly mixed at lower concentration for easier micro-dose measuring.',
  },
  {
    'name': 'Body Protection Compound',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: same general range as BPC-157 in educational discussions',
    'benefits': 'Alias reference for BPC-related healing discussions, tendon support, recovery logging',
    'notes': 'Alias entry included for search discoverability. Treat as the BPC family, not a separate recommendation.',
  },
  {
    'name': 'CJC-1295',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '2mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 2ml BAC for 2mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 1ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.4ml, 1ml, or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-300mcg per dose without DAC, or weekly DAC-oriented protocols when clinician guided',
    'benefits': 'Recovery-stack support, sleep/repair planning, growth-hormone secretagogue reference',
    'notes': 'DAC and non-DAC handling can differ. Label the exact version clearly before mixing.',
  },
  {
    'name': 'Cerebrolysin (peptide mix)',
    'category': 'Neuro',
    'featured': false,
    'vialSizes': '1ml ampoule, 5ml ampoule, 10ml ampoule',
    'reconstitution':
        'Typically supplied as a ready-to-use peptide mixture rather than a lyophilized powder. If sourced differently, follow the exact manufacturer or clinician instructions rather than generic BAC math.',
    'stability': 'Use according to product labeling\nDo not assume freezer stability without product-specific guidance',
    'dosage': 'Typical: varies widely by protocol and route',
    'benefits': 'Cognitive-support reference, neuro-recovery discussions, wellness protocol tracking',
    'notes': 'Included for completeness, but this is not a standard powder-reconstitution entry.',
  },
  {
    'name': 'Copper Peptide GHK',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '5mg, 10mg, 50mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 10ml for 10mg, 50ml for 50mg\nFor 2mg/ml: add 2.5ml, 5ml, or 25ml\nFor 5mg/ml: add 1ml, 2ml, or 10ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: 0.5-2mg daily topical or subcutaneous in educational contexts',
    'benefits': 'Alias search coverage for copper peptide users, collagen support, skin remodeling',
    'notes': 'Alias entry for discoverability. Use the same caution and storage practices as GHK-Cu.',
  },
  {
    'name': 'DSIP (Delta Sleep-Inducing Peptide)',
    'category': 'Neuro',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 100-300mcg in evening-oriented protocols',
    'benefits': 'Sleep-routine support, calming protocol reference, recovery planning',
    'notes': 'Shorter practical handling windows are often preferred after mixing.',
  },
  {
    'name': 'Epitalon (Epithalon)',
    'category': 'Research',
    'featured': false,
    'vialSizes': '10mg, 20mg',
    'reconstitution':
        'For 1mg/ml: add 10ml BAC for 10mg vial or 20ml for 20mg\nFor 2mg/ml: add 5ml or 10ml\nFor 5mg/ml: add 2ml or 4ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 2-10mg daily in short cyclical protocols',
    'benefits': 'Longevity-interest support, recovery-cycle planning, aesthetic wellness stacks',
    'notes': 'Often used in cycles, so write the mixed date clearly and avoid stretching storage windows.',
  },
  {
    'name': 'FOXO4-DRI',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: highly protocol-specific and not standardized for casual use',
    'benefits': 'Emerging longevity-research reference, senescence-related discussions, niche protocol tracking',
    'notes': 'Very much a research-context entry. Keep disclaimers prominent and avoid overconfident assumptions.',
  },
  {
    'name': 'GHK-Cu (Copper Tripeptide-1)',
    'category': 'Anti-aging',
    'featured': true,
    'vialSizes': '5mg, 10mg, 50mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 10ml for 10mg, 50ml for 50mg\nFor 2mg/ml: add 2.5ml, 5ml, or 25ml\nFor 5mg/ml: add 1ml, 2ml, or 10ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: 0.5-2mg daily topical or subcutaneous',
    'benefits': 'Collagen boost, wound healing, anti-aging, skin remodeling',
    'notes': 'Very safe and well-tolerated. Great post-procedure. Educational only.',
  },
  {
    'name': 'GHRP-2',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-300mcg one to three times daily',
    'benefits': 'Secretagogue protocol reference, recovery support, performance-wellness stack tracking',
    'notes': 'Appetite and timing considerations are commonly discussed in user protocols.',
  },
  {
    'name': 'GHRP-6',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-300mcg one to three times daily',
    'benefits': 'Growth-hormone secretagogue reference, recovery planning, wellness tracking',
    'notes': 'Often discussed with appetite effects and meal timing considerations.',
  },
  {
    'name': 'Hexapeptide-9',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: low-percentage topical inclusion in repair-focused formulas',
    'benefits': 'Texture support, resurfacing support, collagen-signaling cosmetic use',
    'notes': 'Usually part of topical peptide blends rather than standalone injection use.',
  },
  {
    'name': 'Hexarelin',
    'category': 'Research',
    'featured': false,
    'vialSizes': '2mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 2ml BAC for 2mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 1ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.4ml, 1ml, or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-300mcg per dose in short-run protocols',
    'benefits': 'Secretagogue reference, repair-stack planning, advanced protocol tracking',
    'notes': 'Often treated as a more aggressive or niche growth-hormone secretagogue option.',
  },
  {
    'name': 'Humanin',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: highly protocol-dependent in longevity-oriented discussions',
    'benefits': 'Cellular resilience discussions, longevity-interest tracking, niche research reference',
    'notes': 'Emerging use case. Keep educational framing explicit.',
  },
  {
    'name': 'Ipamorelin',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '2mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 2ml BAC for 2mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 1ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.4ml, 1ml, or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-300mcg once to three times daily',
    'benefits': 'Recovery support, sleep-stack planning, secretagogue protocol reference',
    'notes': 'Commonly combined with CJC-1295. Keep blended vials labeled precisely.',
  },
  {
    'name': 'KPV (Lysine-Proline-Valine)',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg, 20mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 10ml for 10mg, 20ml for 20mg\nFor 2mg/ml: add 2.5ml, 5ml, or 10ml\nFor 5mg/ml: add 1ml, 2ml, or 4ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: varies by topical, oral, or research-oriented use context',
    'benefits': 'Inflammation-support discussions, barrier comfort planning, gut/skin wellness tracking',
    'notes': 'Route matters. Keep the app language educational and non-prescriptive.',
  },
  {
    'name': 'LL-37 (Cathelicidin)',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: protocol-specific and often treated cautiously',
    'benefits': 'Immune-modulating discussions, wound-healing interest, research-oriented tracking',
    'notes': 'Treat as a more advanced research-context entry with careful safety framing.',
  },
  {
    'name': 'MOTS-c',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg, 15mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 10ml for 10mg, 15ml for 15mg\nFor 2mg/ml: add 2.5ml, 5ml, or 7.5ml\nFor 5mg/ml: add 1ml, 2ml, or 3ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 2.5-10mg in intermittent metabolic-support discussions',
    'benefits': 'Metabolic wellness reference, energy-support tracking, body-composition discussions',
    'notes': 'Many users prefer moderate concentration to reduce draw-volume error.',
  },
  {
    'name': 'Matrixyl (Palmitoyl Pentapeptide-4)',
    'category': 'Anti-aging',
    'featured': true,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical serum inclusion range for daily anti-aging use',
    'benefits': 'Fine-line support, firmness, collagen support, skin-conditioning',
    'notes': 'Most relevant in topical aesthetic formulation work rather than standalone injection math.',
  },
  {
    'name': 'Melanotan I',
    'category': 'Libido',
    'featured': false,
    'vialSizes': '10mg',
    'reconstitution':
        'For 1mg/ml: add 10ml BAC for 10mg vial\nFor 2mg/ml: add 5ml\nFor 5mg/ml: add 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: protocol-specific microgram dosing depending on use context',
    'benefits': 'Pigment-focused reference, tanning-support discussions, niche aesthetic tracking',
    'notes': 'Less commonly surfaced than Melanotan II but useful for broad search coverage.',
  },
  {
    'name': 'Melanotan II',
    'category': 'Libido',
    'featured': false,
    'vialSizes': '10mg',
    'reconstitution':
        'For 1mg/ml: add 10ml BAC for 10mg vial\nFor 2mg/ml: add 5ml\nFor 5mg/ml: add 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 100-500mcg depending on protocol conservatism',
    'benefits': 'Pigment-focused protocol reference, tanning-support discussions, aesthetic planning',
    'notes': 'Side-effect sensitivity matters. Conservative handling and professional guidance are important.',
  },
  {
    'name': 'PT-141 (Bremelanotide)',
    'category': 'Libido',
    'featured': true,
    'vialSizes': '10mg',
    'reconstitution':
        'For 1mg/ml: add 10ml BAC for 10mg vial\nFor 2mg/ml: add 5ml\nFor 5mg/ml: add 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 500mcg-1.75mg in occasional-use protocols',
    'benefits': 'Wellness-stack reference, occasional protocol planning, libido-support discussions',
    'notes': 'Keep this educational only and separate from routine aesthetic skin-use assumptions.',
  },
  {
    'name': 'Palmitoyl Tetrapeptide-7 (Rigin)',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical anti-redness and anti-aging inclusion range',
    'benefits': 'Soothing support, firming routines, cosmetic peptide formulation coverage',
    'notes': 'Useful for complexion-support searches alongside Matrixyl and copper peptides.',
  },
  {
    'name': 'Palmitoyl Tripeptide-5 (Syn-Coll)',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical anti-aging inclusion in peptide creams and serums',
    'benefits': 'Firmness support, collagen stimulation, luxe skin-smoothing routines',
    'notes': 'Usually referenced for cosmetic formulation, not routine injection protocols.',
  },
  {
    'name': 'Pinealon',
    'category': 'Neuro',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: cyclical or protocol-specific use in cognition/longevity communities',
    'benefits': 'Neuro-longevity discussions, cognitive wellness tracking, niche protocol coverage',
    'notes': 'Another research-forward entry where conservative expectations matter.',
  },
  {
    'name': 'SS-31 (Elamipretide)',
    'category': 'Research',
    'featured': false,
    'vialSizes': '5mg, 10mg, 50mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 10ml for 10mg, 50ml for 50mg\nFor 2mg/ml: add 2.5ml, 5ml, or 25ml\nFor 5mg/ml: add 1ml, 2ml, or 10ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: protocol-specific in mitochondrial-support discussions',
    'benefits': 'Mitochondrial wellness reference, recovery-energy discussions, emerging protocol tracking',
    'notes': 'Often treated as a specialty peptide. Keep educational framing explicit.',
  },
  {
    'name': 'Selank',
    'category': 'Neuro',
    'featured': false,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 250-500mcg once or twice daily depending on route',
    'benefits': 'Calming support, stress-management protocol reference, recovery-environment planning',
    'notes': 'Often handled conservatively because frequent temperature swings can reduce confidence in stability.',
  },
  {
    'name': 'Semax',
    'category': 'Neuro',
    'featured': true,
    'vialSizes': '5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial or 10ml for 10mg\nFor 2mg/ml: add 2.5ml or 5ml\nFor 5mg/ml: add 1ml or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 250-500mcg once or twice daily depending on protocol',
    'benefits': 'Focus-support reference, recovery-routine planning, cognitive wellness stacking',
    'notes': 'Commonly tracked in short cycles. Keep route and concentration documented clearly.',
  },
  {
    'name': 'Sermorelin',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '5mg, 9mg, 15mg',
    'reconstitution':
        'For 1mg/ml: add 5ml BAC for 5mg vial, 9ml for 9mg, 15ml for 15mg\nFor 2mg/ml: add 2.5ml, 4.5ml, or 7.5ml\nFor 5mg/ml: add 1ml, 1.8ml, or 3ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 200-500mcg nightly',
    'benefits': 'Recovery planning, sleep-routine support, secretagogue stack reference',
    'notes': 'Often mixed to support smaller nightly draws. Avoid repeated room-temperature exposure.',
  },
  {
    'name': 'Snap-8 (Acetyl Octapeptide-3)',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical expression-line formula inclusion',
    'benefits': 'Forehead and eye-area smoothing support, cosmetic anti-wrinkle formulas',
    'notes': 'Most relevant for topical blending references in aesthetic skincare.',
  },
  {
    'name': 'Syn-Ake',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical smoothing-formula inclusion in small measured percentages',
    'benefits': 'Surface smoothing, expression-line softening, luxe peptide serum formulation',
    'notes': 'Generally discussed in cosmetic formulation rather than injectable use.',
  },
  {
    'name': 'TB-500 (Thymosin Beta-4)',
    'category': 'Recovery',
    'featured': true,
    'vialSizes': '2mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 2ml BAC for 2mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 1ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.4ml, 1ml, or 2ml',
    'stability': 'Fridge: 20-30 days\nFreezer: 3+ months',
    'dosage': 'Typical: 2-5mg weekly, often split across doses',
    'benefits': 'Recovery support, tissue-healing interest, post-procedure wellness stacking',
    'notes': 'Frequently paired with BPC-157 in user-led recovery tracking discussions.',
  },
  {
    'name': 'Thymosin Alpha-1',
    'category': 'Recovery',
    'featured': false,
    'vialSizes': '1.5mg, 5mg, 10mg',
    'reconstitution':
        'For 1mg/ml: add 1.5ml BAC for 1.5mg vial, 5ml for 5mg, 10ml for 10mg\nFor 2mg/ml: add 0.75ml, 2.5ml, or 5ml\nFor 5mg/ml: add 0.3ml, 1ml, or 2ml',
    'stability': 'Fridge: 14-21 days\nFreezer: 2-3 months',
    'dosage': 'Typical: 0.5-1.5mg in immune-support oriented protocols',
    'benefits': 'Immune-support reference, wellness recovery planning, resilience discussions',
    'notes': 'Usually handled carefully with conservative storage windows after mixing.',
  },
  {
    'name': 'Tripeptide-1',
    'category': 'Anti-aging',
    'featured': false,
    'vialSizes': '50mg, 100mg',
    'reconstitution':
        'For 1mg/ml: add 50ml BAC for 50mg vial or 100ml for 100mg\nFor 2mg/ml: add 25ml or 50ml\nFor 5mg/ml: add 10ml or 20ml',
    'stability': 'Fridge: 30 days\nFreezer: 6+ months',
    'dosage': 'Typical: topical peptide-serum inclusion for daily cosmetic support',
    'benefits': 'Repair support, skin-conditioning, collagen-focused topical routines',
    'notes': 'Most often useful as a skincare formulation reference alongside copper peptides.',
  },
];

class _HeroDisclaimerCard extends StatelessWidget {
  final double? resultMl;

  const _HeroDisclaimerCard({required this.resultMl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.cardBackground,
            AppColors.champagneGold.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.28),
        ),
        boxShadow: MyApp.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.champagneGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.science_rounded,
                  color: AppColors.champagneGold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Reference-first mixing support',
                  style: MyApp.cardTitleStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Use this as a quick educational guide for planning BAC water volume, reviewing common storage windows, and checking simple concentration math before you log a peptide protocol.',
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.78),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _GoldBadge(label: 'Educational only'),
              const _GoldBadge(label: 'Not medical advice'),
              if (resultMl != null)
                _GoldBadge(label: 'Calculator: ${resultMl!.toStringAsFixed(2)} ml'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalculatorCard extends StatelessWidget {
  final TextEditingController vialMgController;
  final TextEditingController targetConcentrationController;
  final double? resultMl;
  final VoidCallback onChanged;

  const _CalculatorCard({
    required this.vialMgController,
    required this.targetConcentrationController,
    required this.resultMl,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 430;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('BAC water calculator', style: MyApp.cardTitleStyle()),
              const Spacer(),
              Text(
                'ml needed',
                style: TextStyle(
                  color: AppColors.refinedSlate.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Formula: vial mg ÷ desired mg/ml = ml of BAC water',
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 16),
          if (isNarrow) ...[
            _NumberField(
              label: 'Vial size (mg)',
              controller: vialMgController,
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 12),
            _NumberField(
              label: 'Desired mg/ml',
              controller: targetConcentrationController,
              onChanged: (_) => onChanged(),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Vial size (mg)',
                    controller: vialMgController,
                    onChanged: (_) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: 'Desired mg/ml',
                    controller: targetConcentrationController,
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.champagneGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.26),
              ),
            ),
            child: resultMl == null
                ? Text(
                    'Enter a valid vial size and target concentration to calculate BAC water volume.',
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.70),
                      height: 1.45,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${resultMl!.toStringAsFixed(2)} ml BAC water',
                        style: const TextStyle(
                          color: AppColors.champagneGold,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Example: ${vialMgController.text.trim()} mg ÷ ${targetConcentrationController.text.trim()} mg/ml = ${resultMl!.toStringAsFixed(2)} ml',
                        style: TextStyle(
                          color: AppColors.refinedSlate.withValues(alpha: 0.76),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedPeptideStrip extends StatelessWidget {
  final List<Map<String, dynamic>> peptides;
  final ValueChanged<String> onTap;
  final bool compact;

  const _FeaturedPeptideStrip({
    required this.peptides,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final baseHeight = compact ? 166.0 : 194.0;
    final widthBoost = screenWidth < 390 ? 18.0 : 0.0;
    final textBoost = textScale > 1.0 ? (textScale - 1.0) * 26.0 : 0.0;
    return SizedBox(
      height: baseHeight + widthBoost + textBoost,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: peptides.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final peptide = peptides[index];
          return _FeaturedPeptideCard(
            peptide: peptide,
            compact: compact,
            onTap: () => onTap(peptide['name'] as String),
          );
        },
      ),
    );
  }
}

class _FeaturedPeptideCard extends StatelessWidget {
  final Map<String, dynamic> peptide;
  final bool compact;
  final VoidCallback onTap;

  const _FeaturedPeptideCard({
    required this.peptide,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final isTightLayout = MediaQuery.of(context).size.width < 390 || textScale > 1.0;
    final nameLines = compact ? 2 : (isTightLayout ? 2 : 3);
    final benefitsLines = compact ? 2 : (isTightLayout ? 2 : 3);
    final cardWidth = MediaQuery.of(context).size.width < 390
        ? (compact ? 210.0 : 236.0)
        : (compact ? 220.0 : 260.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AppColors.cardBackground,
                AppColors.champagneGold.withValues(alpha: 0.10),
              ],
            ),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
            ),
            boxShadow: MyApp.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              _CategoryPill(label: peptide['category'] as String),
              const SizedBox(height: 8),
              Text(
                peptide['name'] as String,
                maxLines: nameLines,
                overflow: TextOverflow.ellipsis,
                style: MyApp.cardTitleStyle(),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    peptide['benefits'] as String,
                    maxLines: benefitsLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.refinedSlate.withValues(alpha: 0.74),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryResultsSection extends StatelessWidget {
  final List<Map<String, dynamic>> peptides;
  final double maxHeight;
  final String query;
  final String category;
  final ValueChanged<String> onTap;

  const _LibraryResultsSection({
    required this.peptides,
    required this.maxHeight,
    required this.query,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (peptides.isEmpty) {
      return _EmptySearchState(query: query, category: category);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 220,
        maxHeight: maxHeight,
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: ListView.separated(
          physics: const ClampingScrollPhysics(),
          itemCount: peptides.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (context, index) {
            final item = peptides[index];
            return _PeptideReferenceCard(
              reference: item,
              onTap: () => onTap(item['name'] as String),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryChipRow extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onSelected;

  const _CategoryChipRow({
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _PeptideReconstitutionSheetState._categoryOrder
            .map(
              (category) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ChoiceChip(
                  label: Text(category),
                  selected: selectedCategory == category,
                  onSelected: (_) => onSelected(category),
                  selectedColor: AppColors.champagneGold.withValues(alpha: 0.18),
                  backgroundColor: AppColors.cardBackground,
                  side: BorderSide(
                    color: selectedCategory == category
                        ? AppColors.champagneGold.withValues(alpha: 0.34)
                        : AppColors.borders,
                  ),
                  labelStyle: TextStyle(
                    color: selectedCategory == category
                        ? AppColors.champagneGold
                        : AppColors.refinedSlate.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _PeptideReferenceCard extends StatelessWidget {
  final Map<String, dynamic> reference;
  final VoidCallback onTap;

  const _PeptideReferenceCard({
    required this.reference,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reference['name'] as String,
                          style: MyApp.cardTitleStyle(),
                        ),
                        const SizedBox(height: 8),
                        _CategoryPill(label: reference['category'] as String),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _GoldBadge(label: reference['vialSizes'] as String),
                ],
              ),
              const SizedBox(height: 14),
              _InfoSection(
                title: 'Reconstitution',
                body: reference['reconstitution'] as String,
              ),
              const SizedBox(height: 14),
              _InfoSection(
                title: 'Stability',
                body: reference['stability'] as String,
              ),
              const SizedBox(height: 14),
              _InfoSection(
                title: 'Typical dosage',
                body: reference['dosage'] as String,
              ),
              const SizedBox(height: 14),
              _InfoSection(
                title: 'Benefits',
                body: reference['benefits'] as String,
              ),
              const SizedBox(height: 14),
              _InfoSection(
                title: 'Notes',
                body: reference['notes'] as String,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int resultCount;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.resultCount,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search GHK-Cu, healing, eye-area, neuro, research...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
        helperText: '$resultCount peptides',
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borders),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borders),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.champagneGold,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final String query;
  final String category;

  const _EmptySearchState({required this.query, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No matches found', style: MyApp.cardTitleStyle()),
          const SizedBox(height: 8),
          Text(
            'No peptide references matched ${query.isEmpty ? 'the current filters' : '"$query" in $category'}. Try a broader term or switch categories.',
            style: TextStyle(
              color: AppColors.refinedSlate.withValues(alpha: 0.74),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final String body;

  const _InfoSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.refinedSlate.withValues(alpha: 0.82),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: TextStyle(
            color: AppColors.refinedSlate.withValues(alpha: 0.74),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;

  const _CategoryPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.champagneGold,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EducationalFooter extends StatelessWidget {
  const _EducationalFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.refinedSlate.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.refinedSlate.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        'For educational purposes only. Consult a qualified professional before mixing or using any peptide. Not medical advice.',
        style: TextStyle(
          color: AppColors.refinedSlate.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    );
  }
}

class _GoldBadge extends StatelessWidget {
  final String label;

  const _GoldBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.champagneGold,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _NumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.cardBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borders),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borders),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: AppColors.champagneGold,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}
