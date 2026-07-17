import 'package:flutter/material.dart';

import '../models/peptide.dart';
import '../utils/peptide_seed_data.dart';

class PeptideTrackerDashboardView extends StatefulWidget {
  const PeptideTrackerDashboardView({super.key});

  @override
  State<PeptideTrackerDashboardView> createState() =>
      _PeptideTrackerDashboardViewState();
}

class _PeptideTrackerDashboardViewState extends State<PeptideTrackerDashboardView>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0F1013);
  static const Color _card = Color(0xFF1A1F2C);
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _roseGold = Color(0xFFB76E79);
  static const Color _textPrimary = Color(0xFFEDE7DB);
  static const Color _textMuted = Color(0xFF9FA6B3);

  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _vialStrengthController = TextEditingController();
  final TextEditingController _bacWaterController = TextEditingController();
  final TextEditingController _targetDoseController = TextEditingController();

  final Set<String> _favoriteIds = <String>{};
  String _searchQuery = '';
  PeptideCategory? _selectedCategory;

  bool _calculating = false;
  String? _calculatorError;
  double? _resultUnits;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _vialStrengthController.dispose();
    _bacWaterController.dispose();
    _targetDoseController.dispose();
    super.dispose();
  }

  List<Peptide> get _filteredPeptides {
    return PeptideSeedData.peptides.where((p) {
      final matchesCategory = _selectedCategory == null || p.category == _selectedCategory;
      final matchesQuery = _searchQuery.isEmpty ||
          p.name.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesQuery;
    }).toList(growable: false);
  }

  Future<void> _generateSyringeBlueprint() async {
    setState(() {
      _calculatorError = null;
      _resultUnits = null;
      _calculating = true;
    });

    try {
      final vialStrength = double.parse(_vialStrengthController.text.trim());
      final bacWater = double.parse(_bacWaterController.text.trim());
      final targetDose = double.parse(_targetDoseController.text.trim());

      final units = await Future<double>(
        () => Peptide.calculateSyringeUnits(
          vialStrengthMg: vialStrength,
          bacWaterMl: bacWater,
          targetDoseMcg: targetDose,
        ),
      );

      if (!mounted) return;
      setState(() {
        _resultUnits = units;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _calculatorError = 'Please enter valid numeric values in all fields.';
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _calculatorError = e.message.toString();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _calculatorError =
              'Calculation failed. Please verify values and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _calculating = false;
        });
      }
    }
  }

  void _toggleFavorite(String id) {
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Peptide Tracker Dashboard',
          style: TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: _textMuted,
          tabs: const [
            Tab(text: 'Peptide Directory Index'),
            Tab(text: 'Precision Syringe Reconstitution Calculator'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDirectoryPanel(),
          _buildCalculatorPanel(),
        ],
      ),
    );
  }

  Widget _buildDirectoryPanel() {
    final items = _filteredPeptides;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Search peptide title...',
              hintStyle: const TextStyle(color: _textMuted),
              prefixIcon: const Icon(Icons.search, color: _gold),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _gold.withValues(alpha: 0.22)),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide(color: _gold, width: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip(label: 'All', category: null),
                const SizedBox(width: 8),
                for (final c in PeptideCategory.values) ...[
                  _categoryChip(label: _labelForCategory(c), category: c),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No peptides match current filters.',
                      style: TextStyle(color: _textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final peptide = items[index];
                      final isFavorite = _favoriteIds.contains(peptide.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.14),
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            peptide.name,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              peptide.reconstitutionGuideline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textMuted,
                                height: 1.35,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            onPressed: () => _toggleFavorite(peptide.id),
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isFavorite ? _roseGold : _textMuted,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculatorPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _numberField(
                  controller: _vialStrengthController,
                  label: 'Vial Strength Concentration (mg)',
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _bacWaterController,
                  label: 'Volume of Bacteriostatic Water Added (mL)',
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _targetDoseController,
                  label: 'Target Requested Dose Amount (mcg)',
                ),
                const SizedBox(height: 18),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE5C25D), _gold],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _calculating ? null : _generateSyringeBlueprint,
                    child: Text(
                      _calculating
                          ? 'CALCULATING...'
                          : 'GENERATE SYRINGE BLUEPRINT',
                      style: const TextStyle(
                        color: Color(0xFF171717),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_calculatorError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC46464)),
              ),
              child: Text(
                _calculatorError!,
                style: const TextStyle(color: Color(0xFFFFB2B2)),
              ),
            ),
          if (_resultUnits != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _roseGold, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: _roseGold.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _roseGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.vaccines_outlined,
                      color: _roseGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Draw syringe precisely to: '
                      '${_resultUnits!.toStringAsFixed(1)} Units '
                      '(Tick Mark ${_resultUnits!.toStringAsFixed(1)} on a standard U-100 1mL needle).',
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textMuted),
        filled: true,
        fillColor: const Color(0xFF151925),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.15)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _gold, width: 1.1),
        ),
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required PeptideCategory? category,
  }) {
    final selected = _selectedCategory == category;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      backgroundColor: _card,
      selectedColor: _gold.withValues(alpha: 0.18),
      side: BorderSide(
        color: selected ? _gold : _gold.withValues(alpha: 0.18),
      ),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? _gold : _textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedCategory = category;
        });
      },
    );
  }

  String _labelForCategory(PeptideCategory c) {
    switch (c) {
      case PeptideCategory.longevity:
        return 'Longevity';
      case PeptideCategory.weightLoss:
        return 'Weight Loss';
      case PeptideCategory.muscleRepair:
        return 'Muscle Repair';
      case PeptideCategory.cognitive:
        return 'Cognitive';
    }
  }
}
