import 'dart:convert';
import 'dart:io' show File, Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../utils/app_prefs.dart';
import '../widgets/clinical_section_header.dart';
import 'acne_rosacea_tracker_screen.dart';

/// Full-screen, friendly detail view for a single Recovery Assessment metric.
/// Opened from the Log Recovery Assessment list. Provides:
///   • A clear current-score hero with adjustable slider.
///   • Procedure-aware week-by-week healing context.
///   • "What to Expect" for the current recovery phase.
///   • Practical tips to maintain results.
///   • A dedicated, persistent per-metric journaling area.
class RecoveryMetricDetailScreen extends StatefulWidget {
  const RecoveryMetricDetailScreen({
    super.key,
    required this.procedureId,
    required this.procedureStartDate,
    required this.isBBL,
    required this.metricDef,
    required this.currentValue,
    this.previousValue,
  });

  final String procedureId;
  final DateTime procedureStartDate;
  final bool isBBL;
  final Map<String, dynamic> metricDef;
  final double currentValue;
  final double? previousValue;

  @override
  State<RecoveryMetricDetailScreen> createState() =>
      _RecoveryMetricDetailScreenState();
}

class _RecoveryMetricDetailScreenState
    extends State<RecoveryMetricDetailScreen> {
  late double _value;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, String>> _notes = [];
  bool _loadingNotes = true;

  String get _key => widget.metricDef['key'] as String;
  String get _label => widget.metricDef['label'] as String;
  IconData get _icon => widget.metricDef['icon'] as IconData;
  double get _min => widget.metricDef['min'] as double;
  double get _max => widget.metricDef['max'] as double;
  bool get _lowerBetter => widget.metricDef['lowerBetter'] as bool;
  int get _daysSince =>
      DateTime.now().difference(widget.procedureStartDate).inDays + 1;

  @override
  void initState() {
    super.initState();
    _value = widget.currentValue;
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final all = await AppPrefs.getBBLMetricNotes(widget.procedureId);
    if (!mounted) return;
    setState(() {
      _notes = List<Map<String, String>>.from(all[_key] ?? const []);
      _loadingNotes = false;
    });
  }

  Future<void> _deleteNote(String timestamp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text(
          'This will remove the journal entry and any attached photo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppPrefs.deleteBBLMetricNote(widget.procedureId, _key, timestamp);
    await _loadNotes();
  }

  /// Persists picked image bytes to a stable reference: app docs file path on
  /// native, base64 data URL on web. Returns null on failure.
  Future<String?> _persistPickedPhoto(XFile picked) async {
    try {
      final bytes = await picked.readAsBytes();
      if (kIsWeb) {
        return 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory(
        '${docs.path}${Platform.pathSeparator}recovery_metric_photos',
      );
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeKey = _key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
      final file = File(
        '${folder.path}${Platform.pathSeparator}${widget.procedureId}_${safeKey}_$stamp.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<XFile?> _pickPhoto(ImageSource source) async {
    try {
      return await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
    } catch (_) {
      return null;
    }
  }

  void _openNoteComposer({Map<String, String>? existing}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NoteComposerSheet(
        initialNote: existing?['note'] ?? '',
        initialPhoto: existing?['photo'],
        hint: _journalHint(),
        pickPhoto: _pickPhoto,
        persistPhoto: _persistPickedPhoto,
        onSubmit: (text, photoRef, clearPhoto) async {
          if (existing == null) {
            await AppPrefs.addBBLMetricNote(
              widget.procedureId,
              _key,
              text,
              photo: photoRef,
            );
          } else {
            await AppPrefs.updateBBLMetricNote(
              widget.procedureId,
              _key,
              existing['timestamp'] ?? '',
              note: text,
              photo: photoRef,
              clearPhoto: clearPhoto,
            );
          }
          await _loadNotes();
        },
      ),
    );
  }

  void _viewPhotoFullScreen(String photoRef) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, __, ___) => _FullScreenPhotoViewer(photoRef: photoRef),
      ),
    );
  }

  // ── Color logic mirrors the source screen's _bblMetricColor ──────────────
  Color _metricColor(double v) {
    if (_lowerBetter) {
      if (v <= 3) return const Color(0xFF2E7D32);
      if (v <= 6) return const Color(0xFFF57F17);
      return const Color(0xFFC62828);
    }
    final ratio = v / _max;
    if (ratio >= 0.70) return const Color(0xFF2E7D32);
    if (ratio >= 0.45) return const Color(0xFFF57F17);
    return const Color(0xFFC62828);
  }

  String get _displayValue => _key == 'fatRetentionPct'
      ? '${_value.round()}%'
      : _value.toStringAsFixed(1);

  String get _phaseLabel {
    final d = _daysSince;
    if (d <= 5) return 'Peak Swelling Phase';
    if (d <= 14) return 'Early Recovery';
    if (d <= 42) return 'Active Healing Phase';
    if (d <= 75) return 'Contour Refinement';
    if (d <= 150) return 'Final Shaping Phase';
    return 'Results Stabilizing';
  }

  // ── Procedure-aware copy for each section ────────────────────────────────
  List<_PhaseRow> _weekByWeek() {
    final d = _daysSince;
    bool isCurrent(int from, int to) => d >= from && d <= to;
    switch (_key) {
      case 'fatRetentionPct':
        return [
          _PhaseRow(
            'Week 1–2',
            'Fat cells establish blood supply. '
                'Strict no-pressure positioning is critical right now.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–6',
            'Roughly 20–40% of transferred fat naturally '
                'reabsorbs. This is expected and surgeons over-transfer for it.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Week 7–12',
            'Surviving fat stabilizes. Final retention '
                'percentage becomes meaningful around Week 8–10.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4–6',
            'Mature result: 60–80% retention is the '
                'clinical gold standard. Trend matters more than any one reading.',
            d >= 85,
          ),
        ];
      case 'volumeSatisfaction':
        return [
          _PhaseRow(
            'Week 1–2',
            'Swelling makes everything look larger and '
                'sometimes asymmetric. This is not the result.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–8',
            '"Ugly duckling" phase — shape can look uneven '
                'as edema and fibrosis develop. Trust the process.',
            isCurrent(15, 56),
          ),
          _PhaseRow(
            'Month 3–4',
            'Swelling resolves significantly. True shape '
                'emerging. Most patients see major improvement here.',
            isCurrent(57, 120),
          ),
          _PhaseRow(
            'Month 4–6+',
            'Final result fully visible. Volume and '
                'symmetry now reflect the lasting outcome.',
            d > 120,
          ),
        ];
      case 'contourEvenness':
        return [
          _PhaseRow(
            'Week 1–2',
            'Diffuse swelling masks contour. Lumpiness is '
                'not yet meaningful to assess.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–6',
            'Fibrosis (firm, lumpy spots) actively forming. '
                'Start manual lymphatic drainage now — it directly improves this score.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Week 7–12',
            'With weekly MLD, evenness should climb steadily. '
                'Compression garment compliance matters here.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4–6',
            'Most fibrosis resolves. Persistent firm areas '
                'are treatable — discuss with your provider.',
            d >= 85,
          ),
        ];
      case 'fibrosisLevel':
        return [
          _PhaseRow(
            'Week 1–2',
            'Tissue inflamed and firm — this is normal '
                'post-op swelling, not yet fibrosis.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–6',
            'Fibrosis peaks. Score will likely rise here. '
                'MLD 2–3x weekly is the single most effective intervention.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Week 7–12',
            'With consistent MLD, firmness softens steadily. '
                'Avoid aggressive self-massage on hard areas.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4–6',
            'Most fibrosis resolved. Lingering hard nodules '
                'can be treated with ultrasound or clinical massage.',
            d >= 85,
          ),
        ];
      // ── Acne family ─────────────────────────────────────────────────
      case 'acneSeverity':
        return [
          _PhaseRow(
            'Week 1–2',
            'Topical actives often cause an initial '
                '"purge" — surface comedones flush as cell turnover accelerates. '
                'Expect a brief uptick before improvement.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–6',
            'Inflammation visibly calms. Active lesion '
                'count typically drops 30–50%. Stay consistent — don\'t add '
                'new actives yet.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Week 7–12',
            'Comedonal load clears as turnover normalizes. '
                'Post-inflammatory marks fade more slowly than the spots themselves.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4+',
            'Maintenance phase — minimum effective '
                'dose of your actives, reinforced with SPF and barrier care.',
            d >= 85,
          ),
        ];
      case 'cysticAcneSeverity':
        return [
          _PhaseRow(
            'Week 1–2',
            'Active cysts are tender and slow to resolve. '
                'Topicals alone rarely move this metric — discuss systemic '
                'options with your provider.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–8',
            'On oral antibiotic / spironolactone / '
                'isotretinoin therapy you should start seeing fewer new '
                'cysts. Existing nodules can take weeks to fully resolve.',
            isCurrent(15, 56),
          ),
          _PhaseRow(
            'Month 3–4',
            'Significant reduction in new-cyst formation. '
                'PIH and atrophic scarring become the focus next — track '
                'separately from active disease.',
            isCurrent(57, 120),
          ),
          _PhaseRow(
            'Month 5+',
            'Sustained remission with maintenance therapy. '
                'Scar revision can be considered once the skin is clear for 6 months.',
            d > 120,
          ),
        ];
      case 'hormonalAcneSeverity':
        return [
          const _PhaseRow(
            'Cycle days 21–28',
            'Pre-menstrual flare — jawline and '
                'chin lesions typically appear 7–10 days before menses as '
                'progesterone falls.',
            true,
          ),
          const _PhaseRow(
            'Cycle days 1–14',
            'Estrogen rises, sebum drops, skin '
                'usually clears partly. Use this window to push exfoliating '
                'actives.',
            false,
          ),
          const _PhaseRow(
            'Month 2–3 of therapy',
            'Spironolactone or combined OCP '
                'starts producing visible reduction in flare severity.',
            false,
          ),
          const _PhaseRow(
            'Month 4–6 of therapy',
            'Cycle-related breakouts are '
                'noticeably milder or absent. Track flares against a cycle '
                'log for the clearest picture.',
            false,
          ),
        ];
      // ── Rosacea family ──────────────────────────────────────────────
      case 'rosaceaSeverity':
        return [
          _PhaseRow(
            'Week 1–2',
            'Strip every potentially irritating product. '
                'Use only a gentle non-foaming cleanser, a ceramide-rich '
                'moisturizer, and mineral SPF 30+ daily.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–6',
            'Prescription topicals (azelaic acid, '
                'ivermectin, metronidazole) reach steady state. Papulopustular '
                'lesions visibly reduce.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Week 7–12',
            'Background erythema softens. Trigger '
                'journaling shows the strongest 2–3 personal triggers — '
                'targeted avoidance amplifies medication response.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4+',
            'Stable maintenance. Vascular laser / IPL '
                'can now be considered for persistent telangiectasia and '
                'background redness.',
            d >= 85,
          ),
        ];
      case 'rosaceaFlushing':
        return [
          _PhaseRow(
            'Days 1–14',
            'Identify your triggers — log every flush '
                'with the time, food/drink, temperature, stress, and skincare '
                'used. Patterns emerge fast.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Weeks 3–6',
            'With strict trigger avoidance plus barrier '
                'repair, flush frequency typically drops 40–60%.',
            isCurrent(15, 42),
          ),
          _PhaseRow(
            'Weeks 7–12',
            'Topical alpha-agonists (brimonidine, '
                'oxymetazoline) can reduce the visible redness component of '
                'each flush on demand.',
            isCurrent(43, 84),
          ),
          _PhaseRow(
            'Month 4+',
            'Vascular intervention becomes appropriate '
                'when flushing remains frequent despite trigger control.',
            d >= 85,
          ),
        ];
      case 'visibleBloodVessels':
        return [
          _PhaseRow(
            'Week 1–4',
            'Topical therapy does not erase visible '
                'capillaries — it controls the underlying inflammation that '
                'feeds them.',
            isCurrent(1, 28),
          ),
          _PhaseRow(
            'Week 4–12',
            'With sustained inflammation control and '
                'strict UV protection, new vessels stop forming.',
            isCurrent(29, 84),
          ),
          _PhaseRow(
            'Month 4+',
            'Vascular laser (PDL, KTP) or IPL clears '
                'existing telangiectasia — typically 2–4 sessions for full '
                'effect.',
            d >= 85,
          ),
          const _PhaseRow(
            'Long-term',
            'Daily mineral SPF, gentle skincare, and '
                'trigger avoidance prevent recurrence.',
            false,
          ),
        ];
      // ── General sensitivity ─────────────────────────────────────────
      case 'skinSensitivity':
        return [
          _PhaseRow(
            'Week 1–2',
            'Pull all actives. Cleanser, moisturizer, '
                'SPF only. Stinging and burning settle as the barrier '
                'rehydrates.',
            isCurrent(1, 14),
          ),
          _PhaseRow(
            'Week 3–4',
            'Reintroduce one active at a time, 2–3 '
                'nights per week, monitoring for stinging or visible flush.',
            isCurrent(15, 28),
          ),
          _PhaseRow(
            'Week 5–8',
            'A well-tolerated routine emerges. '
                'Reactivity scores should drop steadily.',
            isCurrent(29, 56),
          ),
          _PhaseRow(
            'Month 3+',
            'Stable, low-reactivity baseline. Layered '
                'actives can be reintroduced very gradually with continued '
                'barrier support.',
            d > 56,
          ),
        ];
    }
    return const [];
  }

  String _whatToExpect() {
    final d = _daysSince;
    switch (_key) {
      case 'fatRetentionPct':
        if (d <= 14) {
          return 'Right now, fat cells are fragile and establishing blood supply. '
              'Any direct pressure on the buttocks can kill grafted cells. Stay '
              'off your butt — use the foam pillow under your thighs for every '
              'seated moment, and sleep prone or on your side.';
        }
        if (d <= 42) {
          return 'Your body is naturally reabsorbing 20–40% of transferred fat. '
              'Surgeons plan for this and over-transfer to compensate. Keep up '
              'protein-rich nutrition (1.4 g/kg/day) and your faja routine.';
        }
        if (d <= 84) {
          return 'Retention is stabilizing. Volume you have at Week 8–10 is '
              'roughly what you keep long-term. Continue positioning discipline '
              'until your surgeon clears you.';
        }
        return 'Your final retention is now meaningful. 60–80% is the clinical '
            'gold standard. Healthy weight maintenance preserves this for years.';
      case 'volumeSatisfaction':
        if (d <= 14) {
          return 'Many patients feel their best in the first few days (swelling '
              'creates volume) then worry around Week 2–4 as it resolves. This '
              'is the most common pattern — not a problem with your result.';
        }
        if (d <= 56) {
          return 'You are in the "ugly duckling" window. Shape often looks '
              'uneven, smaller than expected, or oddly distributed. Photos '
              'today rarely reflect your final outcome.';
        }
        if (d <= 120) {
          return 'Your true shape is emerging. Most patients see a clear, '
              'noticeable improvement in satisfaction between Month 3 and Month 4.';
        }
        return 'You are seeing your real result. If you have any concerns, '
            'this is the right time to discuss them with your surgeon.';
      case 'contourEvenness':
        if (d <= 14) {
          return 'Skin will feel firm and look uneven due to swelling. Hands-off '
              'until your surgeon clears MLD (usually around Day 5–7).';
        }
        if (d <= 42) {
          return 'Lumpy or rope-like spots are normal fibrosis forming. They '
              'respond beautifully to professional lymphatic drainage — book '
              'a certified MLD therapist 2–3x weekly.';
        }
        if (d <= 84) {
          return 'You should see evenness climbing now. If a spot stays hard '
              'or grows, raise it at your next surgeon visit early rather than late.';
        }
        return 'Final smoothness is showing. Persistent irregularities are '
            'treatable with ultrasound therapy or focused MLD.';
      case 'fibrosisLevel':
        if (d <= 14) {
          return 'Tissue feels stiff and dense — this is acute edema, not yet '
              'true fibrosis. Compression and elevation help most right now.';
        }
        if (d <= 42) {
          return 'Fibrosis is peaking. You may feel cord-like or marble-like '
              'firmness. This is the single most important window to start '
              'consistent MLD — earlier is dramatically more effective.';
        }
        if (d <= 84) {
          return 'Fibrosis should be softening week over week. Stay on your '
              'MLD schedule even when areas feel better — relapse is common '
              'if you stop early.';
        }
        return 'Most fibrosis resolves by Month 4–6. Any remaining hard nodules '
            'can be addressed with a clinical massage or ultrasound protocol.';
      // ── Acne / rosacea family ─────────────────────────────────────
      case 'acneSeverity':
        if (d <= 14) {
          return 'A brief "purge" is normal as actives accelerate cell turnover. '
              'Inflamed comedones surface before clearing. Consistency over '
              'aggression — pick one active, low frequency, daily SPF.';
        }
        if (d <= 42) {
          return 'You should see roughly a 30–50% reduction in active lesions. '
              'Post-inflammatory marks lag behind the spots themselves — '
              'don\'t confuse the two when assessing progress.';
        }
        if (d <= 84) {
          return 'Most actives reach near-maximum effect by Week 12. If lesion '
              'count has not dropped meaningfully, escalate the regimen with '
              'your provider rather than stacking more actives yourself.';
        }
        return 'You are in maintenance — minimum effective dose of actives plus '
            'rigorous SPF. Track flares and adjust earlier rather than later.';
      case 'cysticAcneSeverity':
        return 'Cystic acne rarely responds to topicals alone. The clinical '
            'priorities are: stop new cysts from forming (systemic therapy), '
            'reduce inflammation in existing nodules (warm compress, intralesional '
            'cortisone), and never squeeze. Scarring risk is highest with this '
            'subtype — early systemic intervention prevents permanent damage.';
      case 'hormonalAcneSeverity':
        return 'Hormonal acne follows your cycle. Expect predictable pre-menstrual '
            'flares along the jawline and chin. The strongest interventions are '
            'hormonal (spironolactone, combined OCP) — topicals support but rarely '
            'control this subtype on their own. A cycle journal is more useful '
            'than weekly photos.';
      case 'rosaceaSeverity':
        if (d <= 14) {
          return 'Strip your routine. Most rosacea flares are driven or '
              'amplified by an overloaded actives regimen. Cleanser, '
              'ceramide moisturizer, and mineral SPF only.';
        }
        if (d <= 84) {
          return 'Prescription topicals (azelaic acid, ivermectin, '
              'metronidazole) are reaching steady state. Papulopustular '
              'lesions should be visibly reducing. Trigger logging is '
              'amplifying the result.';
        }
        return 'You are in maintenance. Erythema and visible vessels respond '
            'next — typically with vascular laser or IPL once active disease '
            'is well controlled.';
      case 'rosaceaFlushing':
        return 'Flushing is driven by triggers — most commonly heat, alcohol, '
            'spicy food, exercise, UV, and stress. A trigger journal is the '
            'single most powerful intervention. Topical alpha-agonists '
            '(brimonidine, oxymetazoline) provide on-demand redness relief '
            'but do not change the underlying tendency to flush.';
      case 'visibleBloodVessels':
        return 'Telangiectasia do not resolve with topicals — they are fixed '
            'dilated capillaries. The treatment pathway is: control underlying '
            'inflammation first (months), then clear visible vessels with '
            'vascular laser (PDL/KTP) or IPL across 2–4 sessions. Daily mineral '
            'SPF prevents new vessels from forming.';
      case 'skinSensitivity':
        if (d <= 14) {
          return 'Your barrier is reactive. Pull every active. Cleanser, '
              'ceramide-rich moisturizer, mineral SPF only. Stinging and '
              'burning should settle within 7–10 days.';
        }
        if (d <= 56) {
          return 'Reintroduce one active at a time, 2–3 nights per week. '
              'If reactivity climbs, pull back immediately. Niacinamide 2–4% '
              'and panthenol are well-tolerated barrier supporters.';
        }
        return 'A stable, low-reactivity baseline lets you layer actives '
            'gradually. Continue the barrier-first foundation under every '
            'targeted treatment.';
    }
    return '';
  }

  List<String> _tipsToMaintain() {
    switch (_key) {
      case 'fatRetentionPct':
        return const [
          'Use your BBL foam pillow for every seated moment through Week 8.',
          'Protein intake: 1.4 g/kg of body weight per day, minimum.',
          'No nicotine, vaping, or secondhand smoke — directly kills fat cells.',
          'Stay hydrated (2–3 L/day) to support fat-cell metabolism.',
          'Keep a stable weight — large fluctuations reshape grafted fat.',
        ];
      case 'volumeSatisfaction':
        return const [
          'Photograph weekly in the same lighting and pose to track real change.',
          'Resist comparing to others or to social-media results.',
          'Discuss any disappointment with your surgeon at Month 3 (not earlier).',
          'Maintain a healthy stable weight — major loss shrinks the result.',
          'Trust the timeline: most "fixed" results are simply waited results.',
        ];
      case 'contourEvenness':
        return const [
          'Book a certified MLD therapist — 2–3 sessions per week through Week 8.',
          'Wear your compression garment as prescribed (Stage 1 → Stage 2).',
          'Stay well hydrated to support lymphatic clearance.',
          'Avoid aggressive self-massage on lumpy spots.',
          'Sleep position matters: avoid pressing on healing areas.',
        ];
      case 'fibrosisLevel':
        return const [
          'Manual lymphatic drainage (MLD) by a certified therapist is gold standard.',
          'Faja compression: keep 22+ hrs/day through Week 4–6.',
          'Warm (not hot) showers help tissues stay supple.',
          'Gentle stretching and walking — no high-impact activity until cleared.',
          'Discuss persistent hard nodules with your surgeon — treatable.',
        ];
      // ── Acne family ─────────────────────────────────────────────────
      case 'acneSeverity':
        return const [
          'Mineral or broad-spectrum chemical SPF 30+ every morning, no exceptions.',
          'One active at a time — adding two new products at once masks which is working.',
          'Don\'t pick, pop, or scrub. Mechanical trauma is the leading cause of scarring.',
          'Fragrance-free, non-comedogenic cleanser AM and PM (double-cleanse if you wear SPF or makeup).',
          'Consistent retinoid 4–5 nights/week beats high-strength used sporadically.',
          'Photograph monthly in the same lighting — week-to-week change is hard to see.',
        ];
      case 'cysticAcneSeverity':
        return const [
          'Never squeeze a cyst — it pushes inflammation deeper and triples scarring risk.',
          'Warm compress 10 minutes 2–3x/day reduces tenderness on active cysts.',
          'Book a dermatologist appointment — topicals alone rarely control cystic disease.',
          'Intralesional cortisone (kenalog) can shrink a painful cyst in 24–48 hours.',
          'If three or more cysts in a month, ask about oral antibiotics, spironolactone, or isotretinoin.',
          'Track tenderness and cyst count weekly — surface appearance lags behind real progress.',
        ];
      case 'hormonalAcneSeverity':
        return const [
          'Keep a cycle journal — note flare timing relative to menses to confirm hormonal pattern.',
          'Discuss spironolactone or a combined oral contraceptive with your provider.',
          'Increase frequency of your retinoid in the 10 days before menses, not after a flare hits.',
          'Manage cortisol — sleep, protein, and stress regulation all blunt hormonal flares.',
          'Avoid dairy and high-glycemic foods if you notice a correlation in your journal.',
          'Photograph the jawline and chin separately — these are the dominant flare zones.',
        ];
      // ── Rosacea family ──────────────────────────────────────────────
      case 'rosaceaSeverity':
        return const [
          'Mineral SPF (zinc oxide / titanium dioxide) every morning, year-round.',
          'Ceramide-rich, fragrance-free moisturizer AM and PM. Barrier first, always.',
          'Avoid hot water, abrasive cleansing, scrubs, AHAs, BHAs, and high-strength retinoids during flares.',
          'Prescription topicals: azelaic acid 15%, ivermectin 1%, or metronidazole as first-line.',
          'Cool environment, fragrance-free laundry, silk pillowcase — every micro-trigger adds up.',
          'Photograph weekly under identical lighting — improvement is gradual.',
        ];
      case 'rosaceaFlushing':
        return const [
          'Keep a trigger journal: time, temperature, food, drink, stress, and skincare used.',
          'Common triggers to test: hot drinks, alcohol (especially red wine), spicy food, exercise heat, UV, stress.',
          'Cool the face quickly with chilled water or a refrigerated jade roller during a flush.',
          'Topical brimonidine or oxymetazoline can blunt redness on demand, but daily use can rebound.',
          'Beta-blockers (e.g., low-dose propranolol) are sometimes used off-label for stubborn flushing — ask your dermatologist.',
          'Manage stress and sleep — autonomic load directly drives flushing frequency.',
        ];
      case 'visibleBloodVessels':
        return const [
          'Mineral SPF daily — UV is the strongest driver of new vessel formation.',
          'No hot showers, saunas, or steam treatments on the face.',
          'Gentle barrier-first skincare reduces the inflammation that feeds vessels.',
          'Vascular laser (PDL, KTP) or IPL clears existing telangiectasia in 2–4 sessions.',
          'Avoid vasodilating triggers during the 2 weeks pre- and post-laser.',
          'Topicals will not erase fixed vessels — set expectations and plan a vascular procedure.',
        ];
      // ── General sensitivity ─────────────────────────────────────────
      case 'skinSensitivity':
        return const [
          'Simplify to three steps: gentle cleanser, ceramide moisturizer, mineral SPF.',
          'Patch-test every new product behind the ear or on the inner forearm for 7 days.',
          'Reintroduce actives one at a time, 2–3 nights/week before increasing frequency.',
          'Niacinamide 2–4% and panthenol are well-tolerated barrier supporters.',
          'Avoid fragrance, essential oils, denatured alcohol, and high-strength acids during flare-ups.',
          'Lukewarm water only — heat strips lipids and amplifies reactivity.',
        ];
    }
    return const [];
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final color = _metricColor(_value);
    final phases = _weekByWeek();
    final tips = _tipsToMaintain();
    final expect = _whatToExpect();

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.clinicalNavy,
        title: ClinicalAppBarTitle(
          title: _label,
          eyebrow: 'Day $_daysSince · $_phaseLabel',
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _heroCard(color),
          if (_acneRosaceaTrackerKeys.contains(_key)) ...[
            const SizedBox(height: 14),
            _acneRosaceaTrackerLink(),
          ],
          const SizedBox(height: 22),
          const ClinicalSectionHeader(
            icon: Icons.calendar_month_rounded,
            title: 'Week-by-Week Healing',
            eyebrow: 'Procedure timeline',
          ),
          const SizedBox(height: 12),
          _weekByWeekCard(phases, color),
          const SizedBox(height: 22),
          ClinicalSectionHeader(
            icon: Icons.lightbulb_outline_rounded,
            title: 'What to Expect Now',
            eyebrow: _phaseLabel,
          ),
          const SizedBox(height: 12),
          _expectCard(expect, color),
          const SizedBox(height: 22),
          const ClinicalSectionHeader(
            icon: Icons.spa_outlined,
            title: 'Tips to Maintain Results',
            eyebrow: 'Practical care',
          ),
          const SizedBox(height: 12),
          _tipsCard(tips),
          const SizedBox(height: 22),
          ClinicalSectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Your Notes',
            eyebrow: 'Personal journal',
            trailing: _notes.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.32),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      '${_notes.length}',
                      style: TextStyle(
                        color: MyApp.clinicalTeal,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          _journalCard(),
          const SizedBox(height: 28),
          _saveButton(color),
        ],
      ),
    );
  }

  static const Set<String> _acneRosaceaTrackerKeys = {
    'acneSeverity',
    'cysticAcneSeverity',
    'hormonalAcneSeverity',
    'rosaceaSeverity',
    'rosaceaFlushing',
    'visibleBloodVessels',
    'skinSensitivity',
  };

  Widget _acneRosaceaTrackerLink() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: MyApp.roseGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.32),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  MyApp.goldShimmer.withValues(alpha: 0.30),
                  MyApp.roseGold.withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.medical_information_outlined,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dedicated Acne & Rosacea Tracker',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: MyApp.textBrown,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Log flares & triggers · tailored guidance for cystic, '
                  'hormonal, rosacea, sensitivity.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: MyApp.textBrown.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AcneRosaceaTrackerScreen(initialMetricKey: _key),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.roseGold,
              side: BorderSide(color: MyApp.roseGold.withValues(alpha: 0.55)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Open',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(Color color) {
    final diff = widget.previousValue == null
        ? null
        : (_value - widget.previousValue!);
    final improving = diff == null
        ? null
        : (_lowerBetter ? diff < 0 : diff > 0);
    final divisions = _key == 'fatRetentionPct' ? 100 : 20;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.clinicalNavy.withValues(alpha: 0.96),
            MyApp.clinicalTeal.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.45),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: MyApp.goldShimmer.withValues(alpha: 0.55),
                    width: 0.8,
                  ),
                ),
                child: Icon(_icon, color: MyApp.goldShimmer, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CURRENT SCORE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: MyApp.goldShimmer.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _displayValue,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (_key != 'fatRetentionPct') ...[
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              '/10',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (diff != null && diff.abs() >= 0.5)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (improving == true
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828))
                            .withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          (improving == true
                                  ? const Color(0xFF8BC34A)
                                  : const Color(0xFFEF9A9A))
                              .withValues(alpha: 0.6),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        improving == true
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 13,
                        color: improving == true
                            ? const Color(0xFFC5E1A5)
                            : const Color(0xFFFFCDD2),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        diff > 0
                            ? '+${diff.abs().toStringAsFixed(1)}'
                            : '-${diff.abs().toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (widget.metricDef['hint'] as String?) ?? '',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: MyApp.goldShimmer,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: 0.15),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            ),
            child: Slider(
              value: _value,
              min: _min,
              max: _max,
              divisions: divisions,
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _lowerBetter ? 'Better' : 'Worse',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
              Text(
                _lowerBetter ? 'Worse' : 'Better',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekByWeekCard(List<_PhaseRow> phases, Color color) {
    if (phases.isEmpty) {
      return _plainCard(
        child: Text(
          'No timeline available for this metric.',
          style: TextStyle(
            color: MyApp.clinicalSlate,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      );
    }
    return _plainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < phases.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == phases.length - 1 ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: phases[i].current
                          ? LinearGradient(
                              colors: [MyApp.goldShimmer, MyApp.roseGold],
                            )
                          : null,
                      color: phases[i].current
                          ? null
                          : MyApp.clinicalSlate.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      phases[i].current
                          ? Icons.flag_rounded
                          : Icons.circle_outlined,
                      size: 15,
                      color: phases[i].current
                          ? Colors.white
                          : MyApp.clinicalSlate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              phases[i].title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: phases[i].current
                                    ? MyApp.roseGold
                                    : MyApp.clinicalNavy,
                                letterSpacing: 0.2,
                              ),
                            ),
                            if (phases[i].current) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: MyApp.roseGold.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'YOU ARE HERE',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: MyApp.roseGold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          phases[i].body,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: MyApp.clinicalNavy.withValues(alpha: 0.85),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _expectCard(String text, Color color) {
    if (text.isEmpty) {
      return _plainCard(
        child: Text(
          'No specific guidance for this phase yet — check back as your '
          'recovery progresses.',
          style: TextStyle(
            color: MyApp.clinicalSlate,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MyApp.roseGold.withValues(alpha: 0.10),
            MyApp.goldShimmer.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.30),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [MyApp.goldShimmer, MyApp.roseGold],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lightbulb_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: MyApp.clinicalNavy.withValues(alpha: 0.92),
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipsCard(List<String> tips) {
    if (tips.isEmpty) {
      return _plainCard(
        child: Text(
          'Tips coming soon for this metric.',
          style: TextStyle(
            color: MyApp.clinicalSlate,
            fontSize: 12.5,
            height: 1.45,
          ),
        ),
      );
    }
    return _plainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tips.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == tips.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1, right: 10),
                    decoration: BoxDecoration(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: MyApp.clinicalTeal,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tips[i],
                      style: TextStyle(
                        color: MyApp.clinicalNavy.withValues(alpha: 0.92),
                        height: 1.45,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

  Widget _journalCard() {
    return _plainCard(
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
                      'How does this feel today?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: MyApp.clinicalNavy,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add a note or attach a photo to track your '
                      'progress over time.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MyApp.clinicalSlate,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openNoteComposer(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add a Note'),
              style: FilledButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (_loadingNotes)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 16,
                    color: MyApp.clinicalSlate.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No notes yet. Your first entry will appear here.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MyApp.clinicalSlate,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 14),
            Divider(
              height: 1,
              color: MyApp.clinicalSlate.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            for (var i = _notes.length - 1; i >= 0; i--)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _noteTile(_notes[i]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _noteTile(Map<String, String> entry) {
    final ts = DateTime.tryParse(entry['timestamp'] ?? '');
    final dateLabel = ts == null
        ? ''
        : '${ts.month}/${ts.day}/${ts.year} · ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
    final photo = entry['photo'];
    final hasPhoto = photo != null && photo.isNotEmpty;
    final noteText = entry['note'] ?? '';

    return InkWell(
      onTap: () => _openNoteComposer(existing: entry),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: MyApp.clinicalTeal.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: MyApp.clinicalTeal.withValues(alpha: 0.18),
            width: 0.7,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto) ...[
              GestureDetector(
                onTap: () => _viewPhotoFullScreen(photo),
                child: Hero(
                  tag: 'note-photo-${entry['timestamp']}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: MyApp.roseGold.withValues(alpha: 0.45),
                          width: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _NotePhotoThumb(photoRef: photo),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (dateLabel.isNotEmpty)
                        Expanded(
                          child: Text(
                            dateLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: MyApp.clinicalTeal,
                            ),
                          ),
                        ),
                      if (hasPhoto)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.photo_outlined,
                            size: 13,
                            color: MyApp.roseGold.withValues(alpha: 0.85),
                          ),
                        ),
                    ],
                  ),
                  if (noteText.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      noteText,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: MyApp.clinicalNavy.withValues(alpha: 0.92),
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Photo only',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: MyApp.clinicalSlate,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  tooltip: 'Edit note',
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 17,
                    color: MyApp.clinicalTeal,
                  ),
                  onPressed: () => _openNoteComposer(existing: entry),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: 'Delete note',
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: MyApp.clinicalSlate,
                  ),
                  onPressed: () => _deleteNote(entry['timestamp'] ?? ''),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton(Color color) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).pop<double>(_value),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Save & Return'),
        style: FilledButton.styleFrom(
          backgroundColor: MyApp.roseGold,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _plainCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: MyApp.surfaceCardDecoration(tintOpacity: 0.05),
      child: child,
    );
  }

  String _journalHint() {
    switch (_key) {
      case 'fatRetentionPct':
        return 'e.g., Volume feels stable this week. Sticking to pillow protocol and protein goals.';
      case 'volumeSatisfaction':
        return 'e.g., Feeling more confident in clothes today. Side view still looks asymmetric.';
      case 'contourEvenness':
        return 'e.g., Right hip still feels lumpy. Booked extra MLD session this week.';
      case 'fibrosisLevel':
        return 'e.g., Inner thigh softening, outer thigh still firm. MLD therapist noticed improvement.';
    }
    return 'Capture how you are feeling, side effects, or anything worth remembering for next time.';
  }
}

class _PhaseRow {
  final String title;
  final String body;
  final bool current;
  const _PhaseRow(this.title, this.body, this.current);
}

/// Small thumbnail that loads either a file (native) or network/data URL (web).
class _NotePhotoThumb extends StatelessWidget {
  const _NotePhotoThumb({required this.photoRef, this.fit = BoxFit.cover});

  final String photoRef;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || photoRef.startsWith('data:') || photoRef.startsWith('http')) {
      return Image.network(
        photoRef,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    final f = File(photoRef);
    return Image.file(
      f,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    color: MyApp.clinicalSlate.withValues(alpha: 0.12),
    alignment: Alignment.center,
    child: Icon(
      Icons.broken_image_outlined,
      color: MyApp.clinicalSlate,
      size: 18,
    ),
  );
}

class _FullScreenPhotoViewer extends StatelessWidget {
  const _FullScreenPhotoViewer({required this.photoRef});
  final String photoRef;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: _NotePhotoThumb(
                    photoRef: photoRef,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable composer for adding or editing a metric note with an optional
/// attached photo. Pops via the caller-supplied [onSubmit] callback.
class _NoteComposerSheet extends StatefulWidget {
  const _NoteComposerSheet({
    required this.initialNote,
    required this.initialPhoto,
    required this.hint,
    required this.pickPhoto,
    required this.persistPhoto,
    required this.onSubmit,
  });

  final String initialNote;
  final String? initialPhoto;
  final String hint;
  final Future<XFile?> Function(ImageSource source) pickPhoto;
  final Future<String?> Function(XFile picked) persistPhoto;

  /// (noteText, photoRef, clearPhoto) — photoRef may be the original or a new
  /// persisted reference; clearPhoto means the user removed an existing photo.
  final Future<void> Function(
    String noteText,
    String? photoRef,
    bool clearPhoto,
  )
  onSubmit;

  @override
  State<_NoteComposerSheet> createState() => _NoteComposerSheetState();
}

class _NoteComposerSheetState extends State<_NoteComposerSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote,
  );
  String? _photoRef;
  bool _photoChanged = false;
  bool _photoCleared = false;
  bool _saving = false;
  bool _pickingPhoto = false;

  @override
  void initState() {
    super.initState();
    _photoRef = widget.initialPhoto;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isEditing =>
      widget.initialNote.isNotEmpty ||
      (widget.initialPhoto != null && widget.initialPhoto!.isNotEmpty);

  Future<void> _choosePhoto(ImageSource source) async {
    setState(() => _pickingPhoto = true);
    try {
      final picked = await widget.pickPhoto(source);
      if (picked == null) return;
      final ref = await widget.persistPhoto(picked);
      if (ref == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not attach photo.')),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _photoRef = ref;
        _photoChanged = true;
        _photoCleared = false;
      });
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _showPhotoSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: MyApp.roseGold),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _choosePhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: MyApp.roseGold,
              ),
              title: const Text(
                kIsWeb ? 'Upload from device' : 'Choose from Gallery',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _choosePhoto(ImageSource.gallery);
              },
            ),
            if (_photoRef != null && _photoRef!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _photoRef = null;
                    _photoCleared = true;
                    _photoChanged = false;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    final hasPhoto = _photoRef != null && _photoRef!.isNotEmpty;
    if (text.isEmpty && !hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a note or attach a photo before saving.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    // For new notes (no initialPhoto), pass the picked photoRef.
    // For edits, only pass a new photoRef when it changed; clear if removed.
    final String? submitPhoto = _photoChanged ? _photoRef : null;
    await widget.onSubmit(text, submitPhoto, _photoCleared);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final showPhoto = _photoRef != null && _photoRef!.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MyApp.clinicalSlate.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [MyApp.goldShimmer, MyApp.roseGold],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Edit Note' : 'New Note',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: MyApp.clinicalNavy,
                            ),
                          ),
                          Text(
                            _isEditing
                                ? 'Update your text or attached photo.'
                                : 'Capture how you are feeling today.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: MyApp.clinicalSlate,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: MyApp.clinicalSlate,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _controller,
                  minLines: 4,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: !_isEditing,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: MyApp.clinicalNavy,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      color: MyApp.clinicalSlate.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: MyApp.champagne.withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: MyApp.clinicalSlate.withValues(alpha: 0.18),
                        width: 0.7,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: MyApp.clinicalSlate.withValues(alpha: 0.18),
                        width: 0.7,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: MyApp.roseGold.withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.attach_file_rounded,
                      size: 14,
                      color: MyApp.clinicalSlate,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PHOTO (OPTIONAL)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        color: MyApp.clinicalSlate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (showPhoto) _photoPreview() else _photoEmptyState(),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: MyApp.clinicalNavy,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: BorderSide(
                            color: MyApp.clinicalSlate.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(_isEditing ? 'Save Changes' : 'Save Note'),
                        style: FilledButton.styleFrom(
                          backgroundColor: MyApp.roseGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoPreview() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              border: Border.all(
                color: MyApp.roseGold.withValues(alpha: 0.45),
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: _NotePhotoThumb(photoRef: _photoRef!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photo attached',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap below to replace or remove.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: MyApp.clinicalSlate,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickingPhoto ? null : _showPhotoSourceSheet,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                    label: const Text('Replace'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MyApp.clinicalTeal,
                      side: BorderSide(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _pickingPhoto
                        ? null
                        : () {
                            setState(() {
                              _photoRef = null;
                              _photoCleared = true;
                              _photoChanged = false;
                            });
                          },
                    icon: const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Remove'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _photoEmptyState() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickingPhoto
                ? null
                : () => _choosePhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 17),
            label: const Text('Take Photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.clinicalNavy,
              side: BorderSide(color: MyApp.roseGold.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickingPhoto
                ? null
                : () => _choosePhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 17),
            label: const Text(kIsWeb ? 'Upload' : 'Gallery'),
            style: OutlinedButton.styleFrom(
              foregroundColor: MyApp.clinicalNavy,
              side: BorderSide(color: MyApp.roseGold.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
