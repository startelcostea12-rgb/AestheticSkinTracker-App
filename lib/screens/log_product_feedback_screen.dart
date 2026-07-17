// lib/screens/log_product_feedback_screen.dart
//
// 5-question product feedback form. On submit, runs the on-device AI
// analyzer over the user's responses + the current active skincare stack,
// persists the resulting ProductFeedbackEntry, and shows a clinical-style
// rating / summary / warnings card.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/product_tracker.dart';
import '../models/product_feedback.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/product_feedback_ai.dart';
import '../widgets/clinical_section_header.dart';

class LogProductFeedbackScreen extends StatefulWidget {
  final TrackedProduct product;
  const LogProductFeedbackScreen({super.key, required this.product});

  @override
  State<LogProductFeedbackScreen> createState() =>
      _LogProductFeedbackScreenState();
}

class _LogProductFeedbackScreenState extends State<LogProductFeedbackScreen> {
  // Defaults assume a neutral starting position.
  int _irritation = 0;
  int _hydration = 5;
  int _texture = 5;
  int _redness = 0;
  int _satisfaction = 6;
  final TextEditingController _notes = TextEditingController();

  bool _submitting = false;
  ProductFeedbackAiResult? _result;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    // Pull the rest of the active stack and (best-effort) the latest scan.
    final allProducts = await AppPrefs.getTrackedProducts();
    final others = allProducts
        .where((p) => p.id != widget.product.id && p.endDate == null)
        .toList(growable: false);

    SkinMetrics? latestMetrics;
    try {
      final scans = await AppPrefs.getScanEntries();
      if (scans.isNotEmpty) {
        scans.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        latestMetrics = scans.first.toSkinMetrics();
      }
    } catch (_) {
      latestMetrics = null;
    }

    final responses = ProductFeedbackResponses(
      irritation: _irritation,
      hydration: _hydration,
      textureImprovement: _texture,
      redness: _redness,
      satisfaction: _satisfaction,
      notes: _notes.text.trim(),
    );

    final aiResult = ProductFeedbackAnalyzer.analyze(
      product: widget.product,
      responses: responses,
      otherActiveProducts: others,
      scanMetrics: latestMetrics,
    );

    final entry = ProductFeedbackEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      productId: widget.product.id,
      productName: widget.product.name,
      date: DateTime.now(),
      irritation: _irritation,
      hydration: _hydration,
      textureImprovement: _texture,
      redness: _redness,
      satisfaction: _satisfaction,
      notes: _notes.text.trim(),
      aiRating: aiResult.rating,
      aiSummary: aiResult.summary,
      compatibilityWarnings: aiResult.compatibilityWarnings,
      pairingSuggestions: aiResult.pairingSuggestions,
      naturalAlternatives: aiResult.naturalAlternatives,
    );

    await AppPrefs.addProductFeedback(entry);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _result = aiResult;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        title: const Text('Product Feedback'),
        backgroundColor: MyApp.champagne,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIntroCard(textColor),
              const SizedBox(height: 16),
              if (_result == null) ..._buildForm(textColor),
              if (_result != null) _buildResultCard(_result!, textColor),
              const SizedBox(height: 16),
              _buildDisclaimer(textColor),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildIntroCard(Color textColor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClinicalSectionHeader(
              icon: Icons.science_outlined,
              title: 'How is your skin responding?',
              eyebrow: widget.product.name,
            ),
            const SizedBox(height: 10),
            Text(
              'Answer five short questions about your experience with this product. '
              'Our on-device analysis will combine your responses with your active '
              'routine to flag compatibility issues and suggest improvements.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: textColor.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildForm(Color textColor) {
    return [
      _buildSliderCard(
        textColor,
        title: 'Irritation or stinging',
        eyebrow: '0 = none · 10 = severe',
        icon: Icons.flash_on_outlined,
        value: _irritation,
        lowIsGood: true,
        onChanged: (v) => setState(() => _irritation = v),
      ),
      const SizedBox(height: 12),
      _buildSliderCard(
        textColor,
        title: 'Hydration and comfort',
        eyebrow: '0 = tight / dry · 10 = optimally hydrated',
        icon: Icons.water_drop_outlined,
        value: _hydration,
        lowIsGood: false,
        onChanged: (v) => setState(() => _hydration = v),
      ),
      const SizedBox(height: 12),
      _buildSliderCard(
        textColor,
        title: 'Texture improvement',
        eyebrow: '0 = no change · 10 = noticeably smoother',
        icon: Icons.auto_awesome_outlined,
        value: _texture,
        lowIsGood: false,
        onChanged: (v) => setState(() => _texture = v),
      ),
      const SizedBox(height: 12),
      _buildSliderCard(
        textColor,
        title: 'Redness or flushing',
        eyebrow: '0 = none · 10 = persistent visible redness',
        icon: Icons.local_fire_department_outlined,
        value: _redness,
        lowIsGood: true,
        onChanged: (v) => setState(() => _redness = v),
      ),
      const SizedBox(height: 12),
      _buildSliderCard(
        textColor,
        title: 'Overall satisfaction',
        eyebrow: '0 = strongly dislike · 10 = love it',
        icon: Icons.favorite_border,
        value: _satisfaction,
        lowIsGood: false,
        onChanged: (v) => setState(() => _satisfaction = v),
      ),
      const SizedBox(height: 12),
      _buildNotesCard(textColor),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.auto_graph_rounded, size: 18),
          label: Text(_submitting ? 'Analyzing…' : 'Get AI analysis'),
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: MyApp.roseGold,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildSliderCard(
    Color textColor, {
    required String title,
    required String eyebrow,
    required IconData icon,
    required int value,
    required bool lowIsGood,
    required ValueChanged<int> onChanged,
  }) {
    final swatch = lowIsGood
        ? _swatchForReverse(value)
        : _swatchForNormal(value);
    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: swatch, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      Text(
                        eyebrow,
                        style: TextStyle(
                          fontSize: 11,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: swatch.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: swatch.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$value / 10',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: swatch,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: swatch,
                inactiveTrackColor: swatch.withValues(alpha: 0.2),
                thumbColor: swatch,
                overlayColor: swatch.withValues(alpha: 0.18),
                valueIndicatorColor: swatch,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '$value',
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(Color textColor) {
    return Card(
      elevation: 1.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notes_outlined,
                  color: textColor.withValues(alpha: 0.7),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Optional notes',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Anything else worth flagging? (e.g. burning '
                    'after vitamin C layer, breakouts on jawline…)',
                hintStyle: TextStyle(
                  color: textColor.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: MyApp.goldShimmer.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: MyApp.goldShimmer.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ProductFeedbackAiResult result, Color textColor) {
    return Card(
      elevation: 2.2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ClinicalSectionHeader(
              icon: Icons.insights_outlined,
              title: 'AI Analysis',
              eyebrow: 'On-device smart heuristic',
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _RatingBadge(rating: result.rating),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    result.summary,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: textColor.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              ],
            ),
            if (result.compatibilityWarnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              _BulletList(
                title: 'Compatibility warnings',
                icon: Icons.warning_amber_rounded,
                accent: Colors.orange.shade700,
                items: result.compatibilityWarnings,
                textColor: textColor,
              ),
            ],
            if (result.pairingSuggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _BulletList(
                title: 'Suggested pairings',
                icon: Icons.lightbulb_outline,
                accent: MyApp.roseGold,
                items: result.pairingSuggestions,
                textColor: textColor,
              ),
            ],
            if (result.naturalAlternatives.isNotEmpty) ...[
              const SizedBox(height: 16),
              _BulletList(
                title: 'Natural alternatives',
                icon: Icons.eco_outlined,
                accent: MyApp.clinicalTeal,
                items: result.naturalAlternatives,
                textColor: textColor,
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Log another'),
                    onPressed: () => setState(() {
                      _result = null;
                      _irritation = 0;
                      _hydration = 5;
                      _texture = 5;
                      _redness = 0;
                      _satisfaction = 6;
                      _notes.clear();
                    }),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MyApp.roseGold,
                      side: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Done'),
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.roseGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimer(Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: textColor.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is AI guidance generated on-device from your responses '
              'and routine — not medical advice. For persistent reactivity, '
              'breakouts, or concerns, consult a board-certified dermatologist.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Swatch helpers ────────────────────────────────────────────────────────

  Color _swatchForNormal(int v) {
    // Higher is better → red → amber → green
    if (v <= 3) return Colors.red.shade400;
    if (v <= 6) return Colors.amber.shade700;
    return Colors.green.shade600;
  }

  Color _swatchForReverse(int v) {
    // Higher is worse → green → amber → red
    if (v <= 3) return Colors.green.shade600;
    if (v <= 6) return Colors.amber.shade700;
    return Colors.red.shade400;
  }
}

class _RatingBadge extends StatelessWidget {
  final double rating;
  const _RatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    final color = rating >= 7.5
        ? Colors.green.shade600
        : rating >= 5.5
        ? Colors.amber.shade700
        : Colors.red.shade400;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
              ),
            ),
            Text(
              '/ 10',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<String> items;
  final Color textColor;
  const _BulletList({
    required this.title,
    required this.icon,
    required this.accent,
    required this.items,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    s,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: textColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
