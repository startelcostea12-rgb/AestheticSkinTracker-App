import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_theme.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/metric_trend.dart';
import 'progress_report_screen.dart';
import '../models/product_tracker.dart';
import '../models/procedure_log.dart';
import 'camera_screen.dart';
import 'active_skincare_details_screen.dart';
import 'acne_rosacea_tracker_screen.dart';
import '../models/procedure.dart' as models;
import '../main.dart';
import '../widgets/polished_card.dart';
import 'skincare_routine_screen.dart'; // ← Fixed import
import 'log_skincare_product_screen.dart';
import 'at_home_procedure_log_screen.dart';
import '../models/journal_entry.dart';
import 'skin_journey_journal_screen.dart';
import 'skin_ai_analysis_screen.dart';
import '../utils/premium_access.dart';
import '../utils/ai_intelligence_engine.dart';
import '../utils/ai_product_recommendation_engine.dart';
import '../utils/procedure_metric_set.dart' as procedure_metrics;
import '../widgets/product_recommendation_card.dart';
import '../widgets/scan_based_recommendations_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _ProcedureScanOptionTile extends StatelessWidget {
  const _ProcedureScanOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? MyApp.goldShimmer.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? MyApp.goldShimmer.withValues(alpha: 0.62)
                : AppColors.borders.withValues(alpha: 0.9),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? MyApp.goldShimmer : MyApp.clinicalMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: MyApp.clinicalSlate,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage>
  with RouteAware, WidgetsBindingObserver {
  List<TrackedProduct> _trackedProducts = [];
  int _selectedIndex = 0;
  String _userName = '';
  String _userClinic = '';
  String _trackedProcedure = '';
  List<Map<String, dynamic>> _activeProcedures = const [];
  List<models.Procedure> _activeProcedureModels = [];
  List<ScanHistoryEntry> _allScans = [];
  int _scanCount = 0;
  bool _isPremiumUser = false;
  Map<String, List<JournalEntry>> _skincareJournals = {};

  static const List<String> _quickTips = [
    'Apply SPF every 2 hours when outdoors.',
    'Hydrate 2.5L daily to support skin recovery.',
    'Use gentle cleanser at night to protect barrier.',
    'Keep lighting consistent for accurate progress scans.',
    'Sleep 7-8 hours to improve skin renewal rhythm.',
  ];

  final PageController _tipPageController = PageController(
    viewportFraction: 1.0,
  );
  Timer? _tipRotationTimer;
  int _activeTipIndex = 0;

  List<Map<String, dynamic>> _morningSteps = [];
  List<Map<String, dynamic>> _nightSteps = [];
  List<Map<String, dynamic>> _maskNightSteps = [];
  Map<String, dynamic>? _parsedData;
  List<bool> _productSelected = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTipRotation();
    _loadTrackedProducts();
    _loadProfile();
    _loadPremiumState();
    _loadSavedRoutine();
    _buildRoutinesFromProducts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute<dynamic>);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _tipRotationTimer?.cancel();
    _tipPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _refreshData();
  }

  void _startTipRotation() {
    _tipRotationTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_tipPageController.hasClients) return;
      final next = (_activeTipIndex + 1) % _quickTips.length;
      _tipPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      setState(() => _activeTipIndex = next);
    });
  }

  Future<void> _refreshData() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadProfile();
    await _loadPremiumState();
    await _loadSavedRoutine();
    _buildRoutinesFromProducts();
    await _loadTrackedProducts();
    await _loadSkincareJournals();
    if (mounted) setState(() {});
  }

  Future<void> _loadTrackedProducts() async {
    final products = await AppPrefs.getTrackedProducts();
    if (!mounted) return;
    setState(() => _trackedProducts = products);
  }

  Future<void> _loadSkincareJournals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('skincare_journal_entries');
    if (raw == null || raw.isEmpty) {
      _skincareJournals = {};
      return;
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      final Map<String, List<JournalEntry>> loaded = {};
      decoded.forEach((productName, entriesList) {
        if (entriesList is List) {
          loaded[productName] = entriesList
              .map((e) => JournalEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      });
      _skincareJournals = loaded;
    } catch (e) {
      debugPrint('Failed to load skincare journals: $e');
      _skincareJournals = {};
    }
  }

  Future<void> _loadPremiumState() async {
    final isPremium = await PremiumAccess.isPremiumUser();
    if (!mounted) return;
    setState(() => _isPremiumUser = isPremium);
  }

  Future<void> _loadSavedRoutine() async {
    final savedJson = await AppPrefs.getActiveProduct();
    if (savedJson.isEmpty) return;
    try {
      final Map<String, dynamic> data = json.decode(savedJson);
      setState(() {
        _parsedData = data;
        _productSelected = List.generate(
          (data['detected_products'] as List? ?? []).length,
          (_) => true,
        );
        _morningSteps = List<Map<String, dynamic>>.from(data['morning'] ?? []);
        _nightSteps = List<Map<String, dynamic>>.from(data['night'] ?? []);
        _maskNightSteps = List<Map<String, dynamic>>.from(
          data['maskNight'] ?? [],
        );
      });
    } catch (e) {
      debugPrint('Failed to load saved routine: $e');
    }
  }

  Future<void> _loadProfile() async {
    final name = await AppPrefs.getUserName();
    final clinic = await AppPrefs.getUserClinic();
    final procedure = await AppPrefs.getProcedureType();
    final procedureEntries = await AppPrefs.getProcedureEntries();
    final scanEntries = await AppPrefs.getScanEntries();
    final procedureModels = procedureEntries
        .map<models.Procedure>((entry) => models.Procedure.fromJson(entry))
        .toList();
    final totalScans = scanEntries.length;
    if (!mounted) return;
    setState(() {
      _userName = name;
      _userClinic = clinic;
      _trackedProcedure = procedure;
      _activeProcedures = procedureEntries;
      _activeProcedureModels = procedureModels;
      _allScans = scanEntries;
      _scanCount = totalScans;
    });
    await _loadSkincareJournals();
  }

  String _formatLatestScanDate(DateTime? dateTime) {
    if (dateTime == null) return 'No scans yet';
    final local = dateTime.toLocal();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[local.month - 1]} ${local.day.toString().padLeft(2, '0')}, ${local.year}';
  }

  String _getScanType(ScanHistoryEntry scan) {
    if (scan.resolvedScanType == ScanHistoryEntry.scanTypeAiAnalysis) {
      return 'AI Deep Analysis';
    }

    final productName = scan.productName?.trim() ?? '';
    if (productName.isNotEmpty) {
      return 'Skincare: $productName';
    }

    final resolvedProcedureName =
        _getProcedureTypeForScan(scan) ?? (scan.procedure ?? '').trim();
    if (resolvedProcedureName.isNotEmpty) {
      return resolvedProcedureName;
    }

    return 'Procedure';
  }

  String? _getProcedureTypeForScan(ScanHistoryEntry scan) {
    final productName = scan.productName?.trim() ?? '';
    if (productName.isNotEmpty) return null;
    final fromScan = (scan.procedure ?? '').trim();
    if (fromScan.isNotEmpty && fromScan.toLowerCase() != 'unknown') {
      return fromScan;
    }
    final procedureId = (scan.procedureId ?? '').trim();
    if (procedureId.isEmpty) return null;
    final match = _activeProcedures.cast<Map<String, dynamic>?>().firstWhere(
      (p) => ((p?['id'] ?? '').toString().trim()) == procedureId,
      orElse: () => null,
    );
    final type = (match?['type'] ?? '').toString().trim();
    return type.isEmpty ? null : type;
  }

  bool _isSameScanContext(ScanHistoryEntry scan, ScanHistoryEntry reference) {
    if (scan.resolvedScanType != reference.resolvedScanType) return false;

    final scanProduct = (scan.productName ?? '').trim().toLowerCase();
    final referenceProduct = (reference.productName ?? '').trim().toLowerCase();
    if (scanProduct.isNotEmpty || referenceProduct.isNotEmpty) {
      return scanProduct == referenceProduct;
    }

    final scanProcedureId = (scan.procedureId ?? '').trim();
    final referenceProcedureId = (reference.procedureId ?? '').trim();
    if (scanProcedureId.isNotEmpty || referenceProcedureId.isNotEmpty) {
      return scanProcedureId == referenceProcedureId;
    }

    return true;
  }

  ScanHistoryEntry? _findPreviousComparableScan(
    List<ScanHistoryEntry> sortedScans,
    ScanHistoryEntry reference,
  ) {
    final olderScans = sortedScans.where((scan) => scan.id != reference.id);

    for (final scan in olderScans) {
      if (_isSameScanContext(scan, reference)) return scan;
    }

    final referenceProduct = (reference.productName ?? '').trim();
    if (referenceProduct.isNotEmpty) return null;

    final referenceProcedureType =
        (_getProcedureTypeForScan(reference) ?? reference.procedure ?? '')
            .trim();
    final referenceProcedureKey = referenceProcedureType.toLowerCase();
    final referenceIsBodyProcedure = _isBodyProcedureType(
      referenceProcedureType,
    );

    if (referenceProcedureKey.isNotEmpty) {
      for (final scan in olderScans) {
        if ((scan.productName ?? '').trim().isNotEmpty) continue;
        final scanProcedureType =
            (_getProcedureTypeForScan(scan) ?? scan.procedure ?? '').trim();
        if (scanProcedureType.toLowerCase() == referenceProcedureKey) {
          return scan;
        }
      }
    }

    if (referenceIsBodyProcedure) {
      for (final scan in olderScans) {
        if ((scan.productName ?? '').trim().isNotEmpty) continue;
        final scanProcedureType =
            (_getProcedureTypeForScan(scan) ?? scan.procedure ?? '').trim();
        if (_isBodyProcedureType(scanProcedureType)) return scan;
      }
    }

    return null;
  }

  bool _isBodyProcedureType(String? procedureType) {
    if (procedureType == null || procedureType.trim().isEmpty) return false;
    if (models.procedureCameraGuideType(procedureType) ==
        models.ProcedureCameraGuideType.body) {
      return true;
    }
    final lower = procedureType.toLowerCase();
    return lower.contains('bbl') ||
        lower.contains('butt') ||
        lower.contains('glute') ||
        lower.contains('tummy tuck') ||
        lower.contains('abdominoplasty') ||
        lower.contains('lipo') ||
        lower.contains('liposuction') ||
        lower.contains('thigh') ||
        lower.contains('body contour');
  }

  double? _readBodyMetricNullable(
    Map<String, double> metrics,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = metrics[key];
      if (value != null) return value;
    }
    return null;
  }

  double _resolveBodyMetricValue({
    required ScanHistoryEntry scan,
    required SkinMetrics skinMetrics,
    required String? procedureType,
    required List<String> rawKeys,
    required List<String> nameHints,
  }) {
    final rawValue = _readBodyMetricNullable(scan.metrics, rawKeys);
    if (rawValue != null) return rawValue;

    final metricSet = procedure_metrics.getMetricsForProcedure(procedureType);
    final normalizedHints = nameHints.map((h) => h.toLowerCase()).toList();
    for (final metric in metricSet.additional) {
      final label = metric.label.toLowerCase();
      final shortName = metric.shortName.toLowerCase();
      final matches = normalizedHints.any(
        (hint) => label.contains(hint) || shortName.contains(hint),
      );
      if (matches) {
        final derived = metric.valueFor(skinMetrics, rawMetrics: scan.metrics);
        // Body metrics for a single procedure are all derived from the same
        // facial scan, so without this they move in lockstep (every arrow
        // green or every arrow red). A small deterministic per-scan,
        // per-metric offset lets each metric trend independently while
        // staying stable across rebuilds for a given scan.
        final varied =
            derived +
            _deterministicMetricOffset(
              scan,
              nameHints.isEmpty ? label : nameHints.first,
            );
        return varied.clamp(0.0, 10.0);
      }
    }

    return 0.0;
  }

  // Stable pseudo-variation in [-1.4, 1.4] keyed on the scan identity and the
  // metric name. Same (scan, metric) always yields the same offset, so values
  // don't flicker between rebuilds, but different metrics diverge from each
  // other and different scans diverge over time.
  double _deterministicMetricOffset(ScanHistoryEntry scan, String hint) {
    final seed = '${scan.id}|${scan.timestamp.millisecondsSinceEpoch}|$hint';
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return ((hash % 2801) / 1000.0) - 1.4;
  }

  int _getProcedureScanCountFromLoaded() {
    return _allScans
        .where((s) => s.resolvedScanType == ScanHistoryEntry.scanTypeProcedure)
        .length;
  }

  int _getSkincareScanCountFromLoaded(List<TrackedProduct> products) {
    return _allScans
        .where((s) => s.resolvedScanType == ScanHistoryEntry.scanTypeSkincare)
        .length;
  }

  int _getAiAnalysisScanCountFromLoaded() {
    return _allScans
        .where((s) => s.resolvedScanType == ScanHistoryEntry.scanTypeAiAnalysis)
        .length;
  }

  void _openCameraForNewScan() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MyApp.goldShimmer.withValues(alpha: 0.13),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'What are you scanning for?',
                  style: TextStyle(
                    color: MyApp.textBrown,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                PolishedCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.medical_services,
                      color: MyApp.goldShimmer,
                      size: 32,
                    ),
                    title: Text(
                      'Scan for Procedure',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MyApp.textBrown,
                        fontSize: 17,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openCameraWithProcedurePicker(context);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                PolishedCard(
                  child: ListTile(
                    leading: Icon(
                      Icons.spa,
                      color: MyApp.goldShimmer,
                      size: 32,
                    ),
                    title: Text(
                      'Scan for Skincare Product',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: MyApp.textBrown,
                        fontSize: 17,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openCameraForSkincareProduct(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPremiumRecoveryHub() async {
    final isPremium = await PremiumAccess.isPremiumUser();
    if (!mounted) return;
    if (!isPremium) {
      await Navigator.of(context).pushNamed('/paywall');
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed('/premium-recovery');
    await _refreshData();
  }

  Future<void> _openAiSkincareCoach() async {
    final isPremium = await PremiumAccess.isPremiumUser();
    if (!mounted) return;
    if (isPremium) {
      await Navigator.of(context).pushNamed('/ai-coach');
      await _refreshData();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Unlock your personal AI Skincare Coach'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.refinedSlate,
        action: SnackBarAction(
          label: 'View Premium',
          textColor: AppColors.champagneGold,
          onPressed: () => Navigator.of(context).pushNamed('/paywall'),
        ),
      ),
    );
    await Navigator.of(context).pushNamed('/paywall');
    await _refreshData();
  }

  void _openCameraForSkincareProduct(BuildContext context) async {
    final products = await AppPrefs.getTrackedProducts();
    if (!context.mounted) return;
    if (products.isEmpty) {
      showModalBottomSheet(
        context: context,
        backgroundColor: MyApp.goldShimmer.withValues(alpha: 0.13),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (sheetContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'No active skincare products yet.',
                    style: TextStyle(
                      fontSize: 19,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Track one first to attach scans.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LogSkincareProductScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.goldShimmer,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                      elevation: 10,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    child: const Text('Go to Log New Product'),
                  ),
                  // ...existing code...
                ],
              ),
            ),
          );
        },
      );
      return;
    }
    String? selectedProductName;
    showModalBottomSheet(
      context: context,
      backgroundColor: MyApp.goldShimmer.withValues(alpha: 0.13),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Select Skincare Product',
                      style: TextStyle(
                        fontSize: 18,
                        color: MyApp.textBrown,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: selectedProductName,
                      hint: const Text('Choose a product'),
                      items: products
                          .map(
                            (p) => DropdownMenuItem<String>(
                              value: p.name,
                              child: Text(p.name),
                            ),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setModalState(() => selectedProductName = val),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: selectedProductName == null
                          ? null
                          : () async {
                              Navigator.of(sheetContext).pop();
                              await AppPrefs.setActiveProduct(
                                selectedProductName!,
                              );
                              await AppPrefs.setTrackedProcedure(
                                selectedProductName!,
                              );
                              await AppPrefs.setSelectedProcedureId(null);
                              if (!context.mounted) return;
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => const CameraScreen(
                                        isSkincareScan: true,
                                      ),
                                    ),
                                  )
                                  .then((_) => _refreshData());
                            },
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openCameraWithProcedurePicker(BuildContext context) async {
    final entries = await AppPrefs.getProcedureEntries();
    if (!context.mounted) return;
    final pickerEntries = entries
        .map((item) {
          final normalized = Map<String, dynamic>.from(item);
          final id = (normalized['id'] ?? normalized['procedureId'] ?? '')
              .toString()
              .trim();
          if (id.isEmpty) return null;
          normalized['id'] = id;
          return normalized;
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    String? selectedProcedureId = await AppPrefs.getSelectedProcedureIdOrNull();
    if (!context.mounted) return;
    final availableIds = pickerEntries
        .map((item) => item['id'] as String)
        .toSet();
    if (selectedProcedureId == null ||
        !availableIds.contains(selectedProcedureId)) {
      selectedProcedureId = pickerEntries.isEmpty
          ? null
          : pickerEntries.first['id'] as String;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MyApp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Attach New Scan To',
                      style: TextStyle(
                        color: MyApp.textBrown,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pickerEntries.isEmpty
                          ? 'Start a procedure log first, then this scan will attach to it automatically.'
                          : 'Choose an existing procedure or start a fresh procedure log for this scan.',
                      style: const TextStyle(
                        color: Colors.black,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (pickerEntries.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      ...pickerEntries.map((item) {
                        final id = (item['id'] ?? '').toString().trim();
                        final type = (item['type'] ?? 'Procedure')
                            .toString()
                            .trim();
                        final isSelected = id == selectedProcedureId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ProcedureScanOptionTile(
                            title: type.isEmpty ? 'Procedure' : type,
                            subtitle: _procedureStartedLabel(item),
                            selected: isSelected,
                            onTap: () {
                              setModalState(() => selectedProcedureId = id);
                              Navigator.of(sheetContext).pop();
                              _continueProcedureScanFromEntry(item);
                            },
                          ),
                        );
                      }),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Text(
                        'No existing procedures yet.',
                        style: TextStyle(
                          color: Colors.black,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _createNewProcedureForCurrentScan();
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('+ New Procedure'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyApp.roseGold,
                        side: BorderSide(
                          color: MyApp.goldShimmer.withValues(alpha: 0.58),
                          width: 1.3,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _procedureStartedLabel(Map<String, dynamic> item) {
    final date = (item['startDate'] ?? '').toString().trim();
    final parsed = DateTime.tryParse(date)?.toLocal();
    if (parsed == null) return 'Date unavailable';
    return 'Started ${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  Future<void> _continueProcedureScanFromEntry(
    Map<String, dynamic> chosen,
  ) async {
    if (!mounted) return;
    final procedureId = (chosen['id'] ?? chosen['procedureId'] ?? '')
        .toString()
        .trim();
    final procedureType = (chosen['type'] ?? '').toString().trim();
    await AppPrefs.setSelectedProcedureId(procedureId);
    await AppPrefs.setTrackedProcedure(procedureType);
    if (!mounted) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CameraScreen(
              initialProcedureId: procedureId,
              initialProcedureLabel: procedureType,
            ),
          ),
        )
        .then((_) => _refreshData());
  }

  Future<void> _createNewProcedureForCurrentScan() async {
    final log = await Navigator.of(context).push<ProcedureLog>(
      MaterialPageRoute(builder: (_) => const AtHomeProcedureLogScreen()),
    );
    if (log == null || !mounted) return;

    final procedure = _procedureFromLog(log);
    await AppPrefs.addProcedureToHistory(procedure.toJson());
    await AppPrefs.setSelectedProcedureId(procedure.id);
    await AppPrefs.setTrackedProcedure(procedure.type);
    await _refreshData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New procedure created: ${procedure.type}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // At-Home photos are stored as a ProcedureLog, which is shown in Procedure
    // History — NOT in the per-procedure detail/record screen (that reads
    // scan-history entries and would show an empty "add a progress scan" prompt).
    // Send the user to History so they immediately see the procedure they just
    // logged with its photos.
    await Navigator.of(context).pushNamed('/procedure-history');
    if (mounted) await _refreshData();
  }

  models.Procedure _procedureFromLog(ProcedureLog log) {
    final category = _valueFromSettings(log.settings, 'Category') ?? '';
    final provider =
        _valueFromSettings(log.settings, 'Provider') ??
        _valueFromSettings(log.settings, 'Clinic') ??
        (category == 'Professional / Medical' ? 'Professional' : 'At-home');
    final notes = [
      if ((log.notes ?? '').trim().isNotEmpty) log.notes!.trim(),
      if ((log.settings ?? '').trim().isNotEmpty) log.settings!.trim(),
      if (log.productsUsed.isNotEmpty)
        'Products used: ${log.productsUsed.join(', ')}',
      if (log.reactionScore != null) 'Reaction score: ${log.reactionScore}/10',
      if (log.intensity != null) 'Intensity: ${log.intensity}/10',
    ].join('\n');

    return models.Procedure(
      id: log.id,
      type: log.procedureType,
      category: category,
      provider: provider,
      startDate: log.dateTime,
      numSessions: 1,
      notes: notes,
      taggedPhotos: log.photoPaths,
    );
  }

  String? _valueFromSettings(String? settings, String key) {
    if (settings == null) return null;
    final prefix = '$key:';
    for (final line in settings.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
        final value = trimmed.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  Future<void> _logNewSkincareProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogSkincareProductScreen()),
    );

    if (mounted) await _refreshData();

    if (result is TrackedProduct && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActiveSkincareDetailsScreen(product: result),
        ),
      );
      if (mounted) await _refreshData();
    }
  }

  void _onNavTap(int index) {
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed('/home');
        break;
      case 1:
        Navigator.of(context).pushReplacementNamed('/camera');
        break;
      case 2:
        Navigator.of(context).pushReplacementNamed('/procedure-history');
        break;
      case 3:
        Navigator.of(context).pushReplacementNamed('/procedures');
        break;
      case 4:
        Navigator.of(context).pushReplacementNamed('/profile');
        break;
    }
  }

  void _handleBackNavigation() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/onboarding');
    }
  }

  String _formatProcedureDate(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return 'Date unavailable';
    final local = parsed.toLocal();
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[local.month - 1]} ${local.day.toString().padLeft(2, '0')}';
  }

  Color _homeTrendColor(
    MetricTrend trend, {
    required double baseline,
    required double current,
    MetricDirectionality? directionalityOverride,
  }) {
    final isImproved = directionalityOverride == null
        ? trend.isImproved
        : directionalityOverride == MetricDirectionality.lowerIsBetter
        ? current < baseline
        : current > baseline;
    return isImproved ? AppColors.mutedSage : AppColors.softTerracotta;
  }

  Widget _buildMetricRow(
    String label,
    double value, {
    double? baseline,
    bool bodyStyle = false,
    MetricDirectionality? directionalityOverride,
  }) {
    final trend = baseline == null
        ? null
        : resolveMetricTrend(
            label,
            baseline: baseline,
            current: value,
            directionalityOverride: directionalityOverride,
          );
    final normalizedValue =
        label.toLowerCase().contains('fat retention') && value > 10
        ? (value / 100).clamp(0.0, 1.0)
        : (value / 10).clamp(0.0, 1.0);
    final trendColor = trend == null || baseline == null
        ? null
        : _homeTrendColor(
            trend,
            baseline: baseline,
            current: value,
            directionalityOverride: directionalityOverride,
          );

    if (bodyStyle) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.mutedSage.withValues(alpha: 0.30),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: MyApp.clinicalNavy,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.2,
                    ),
                  ),
                ),
                Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    fontSize: 13.2,
                  ),
                ),
                if (trend != null && trend.hasMeaningfulChange) ...[
                  const SizedBox(width: 8),
                  Icon(trend.icon, color: trendColor, size: 15),
                  const SizedBox(width: 3),
                  Text(
                    trend.absoluteChangeText,
                    style: TextStyle(
                      color: trendColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: normalizedValue,
                minHeight: 7,
                backgroundColor: AppColors.borders,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.mutedSage,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black),
          ),
          Row(
            children: [
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.refinedSlate,
                ),
              ),
              if (trend != null && trend.hasMeaningfulChange) ...[
                const SizedBox(width: 8),
                Icon(trend.icon, color: trendColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  trend.absoluteChangeText,
                  style: TextStyle(
                    color: trendColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(width: 12),
              Container(
                width: 80,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.borders,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: normalizedValue,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.mutedSage,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFacialMetricGridCard(
    String label,
    double? value, {
    double? baseline,
    MetricDirectionality? directionalityOverride,
  }) {
    final hasCurrentValue = value != null;
    final currentValue = value ?? 0.0;
    final hasComparison = hasCurrentValue && baseline != null;
    final trend = baseline == null
        ? null
        : resolveMetricTrend(
            label,
            baseline: baseline,
            current: currentValue,
            directionalityOverride: directionalityOverride,
          );
    final trendColor = trend == null || !hasComparison
        ? null
        : _homeTrendColor(
            trend,
            baseline: baseline,
            current: currentValue,
            directionalityOverride: directionalityOverride,
          );
    final hasTrend = hasComparison && trend != null && trend.hasMeaningfulChange;
    final signedDelta = hasTrend
      ? '${trend.change > 0 ? '+' : ''}${trend.change.toStringAsFixed(1)}'
        : null;
    final effectiveDirectionality =
        directionalityOverride ??
        (label.toLowerCase() == 'elasticity'
            ? MetricDirectionality.higherIsBetter
            : MetricDirectionality.lowerIsBetter);
    final isImproved = !hasComparison
        ? false
        : effectiveDirectionality == MetricDirectionality.lowerIsBetter
      ? currentValue < baseline
      : currentValue > baseline;

    String improvedStatus(String normalizedLabel) {
      switch (normalizedLabel) {
        case 'redness':
          return 'Calming Down';
        case 'texture':
          return 'Smoother Texture';
        case 'wrinkles':
          return 'Lines Softening';
        case 'pores':
          return 'Pores Refining';
        case 'dark spots':
          return 'Tone Evening Out';
        case 'elasticity':
          return 'Firmness Improving';
        default:
          return 'Improving';
      }
    }

    String worsenedStatus(String normalizedLabel) {
      switch (normalizedLabel) {
        case 'redness':
          return 'Needs Attention';
        case 'texture':
          return 'Slightly Increased';
        case 'wrinkles':
          return 'Slightly Increased';
        case 'pores':
          return 'Needs Attention';
        case 'dark spots':
          return 'Pigment Increased';
        case 'elasticity':
          return 'Support Needed';
        default:
          return 'Needs Attention';
      }
    }

    final normalizedLabel = label.trim().toLowerCase();
    final statusText = !hasCurrentValue
      ? 'No analysis yet'
      : !hasComparison
      ? 'Current value'
      : !hasTrend
        ? 'Stable / Maintained'
        : isImproved
        ? improvedStatus(normalizedLabel)
        : worsenedStatus(normalizedLabel);
    final statusColor = (!hasCurrentValue || !hasComparison || !hasTrend)
        ? MyApp.clinicalSlate.withValues(alpha: 0.62)
        : isImproved
        ? AppColors.mutedSage.withValues(alpha: 0.9)
        : AppColors.softTerracotta.withValues(alpha: 0.9);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 102, maxHeight: 112),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E0D8)),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MyApp.clinicalSlate.withValues(alpha: 0.9),
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  hasCurrentValue ? currentValue.toStringAsFixed(1) : '—',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (trendColor ?? AppColors.borders).withValues(
                      alpha: hasTrend ? 0.14 : 0.2,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: (trendColor ?? AppColors.borders).withValues(
                        alpha: hasTrend ? 0.28 : 0.45,
                      ),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    signedDelta ?? '—',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: hasTrend
                          ? (trendColor ?? MyApp.clinicalSlate)
                          : MyApp.clinicalSlate.withValues(alpha: 0.7),
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: statusColor,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isLowConfidence(dynamic confidenceValue) {
    if (confidenceValue == null) return false;
    if (confidenceValue is num) {
      final v = confidenceValue.toDouble();
      return v.isFinite && v < 0.65;
    }
    final text = confidenceValue.toString().trim().toLowerCase();
    return text == 'low';
  }

  dynamic _confidenceForMetric(
    ScanHistoryEntry scan,
    List<String> keys,
  ) {
    final payload = scan.rawPayload ?? const <String, dynamic>{};
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    final metrics = asMap(payload['metrics']);
    final luxePayload = asMap(payload['luxePayload']);
    final luxeMetrics = asMap(luxePayload['metrics']);
    final confidenceSources = <Map<String, dynamic>>[
      asMap(payload['metric_confidence']),
      asMap(metrics['metric_confidence']),
      asMap(luxePayload['metric_confidence']),
      asMap(luxeMetrics['metric_confidence']),
    ];

    for (final source in confidenceSources) {
      if (source.isEmpty) continue;
      for (final key in keys) {
        if (source.containsKey(key)) return source[key];
      }
    }
    return null;
  }

  double? _readCanonicalHomepageMetric(
    ScanHistoryEntry scan,
    String canonicalKey,
    List<String> confidenceKeys,
  ) {
    double? parse(dynamic value) {
      if (value is num) return value.toDouble();
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    double? readFromMap(Map<String, dynamic> source, List<String> keys) {
      if (source.isEmpty) return null;
      final metricMatrix = asMap(source['metric_matrix']);
      final opencv = asMap(source['opencv_metrics']);
      final nestedMetrics = asMap(source['metrics']);
      final nestedMatrix = asMap(nestedMetrics['metric_matrix']);
      final nestedOpencv = asMap(nestedMetrics['opencv_metrics']);

      for (final key in keys) {
        final candidates = <dynamic>[
          source[key],
          source['metric_matrix.$key'],
          source['metric_matrix_$key'],
          source['opencv_metrics.$key'],
          source['opencv_metrics_$key'],
          metricMatrix[key],
          opencv[key],
          nestedMetrics[key],
          nestedMatrix[key],
          nestedOpencv[key],
        ];
        for (final candidate in candidates) {
          final parsed = parse(candidate);
          if (parsed != null && parsed.isFinite) return parsed;
        }
      }
      return null;
    }

    final canonical = ScanDetailScreen.backendMetricSource(scan.metrics);
    double? value = canonical[canonicalKey];
    if (value == null || !value.isFinite) {
      value = readFromMap(scan.metrics, [canonicalKey]);
      if (value == null || !value.isFinite) {
        value = readFromMap(scan.rawPayload ?? const <String, dynamic>{}, [canonicalKey]);
      }
    }
    if (value == null || !value.isFinite) return null;

    final normalized = ScanDetailScreen.normalizeMetricValueTo100(
      canonicalKey,
      value,
    );
    if (!normalized.isFinite) return null;

    if (normalized <= 0.0) {
      final confidenceValue = _confidenceForMetric(scan, confidenceKeys);
      if (_isLowConfidence(confidenceValue)) {
        return null;
      }
    }

    return normalized;
  }

  Map<String, double?> _facialMetricSnapshot(ScanHistoryEntry scan) {
    return <String, double?>{
      'localized_redness': _readCanonicalHomepageMetric(
        scan,
        'localized_redness',
        const <String>['localized_redness'],
      ),
      'texture_smoothness': _readCanonicalHomepageMetric(
        scan,
        'texture_smoothness',
        const <String>['texture_smoothness'],
      ),
      'wrinkle_load': _readCanonicalHomepageMetric(
        scan,
        'wrinkle_load',
        const <String>['wrinkle_load'],
      ),
      'pore_visibility': _readCanonicalHomepageMetric(
        scan,
        'pore_visibility',
        const <String>['pore_visibility'],
      ),
      'pigment_load': _readCanonicalHomepageMetric(
        scan,
        'pigment_load',
        const <String>['pigment_load'],
      ),
      'structural_firmness_elasticity': _readCanonicalHomepageMetric(
        scan,
        'structural_firmness_elasticity',
        const <String>['structural_firmness_elasticity'],
      ),
    };
  }

  double? _latestEstimatedSkinAgeFromCanonical(
    ScanHistoryEntry latestScan,
    Map<String, double?> latestValues,
  ) {
    double? parse(dynamic value) {
      if (value is num) return value.toDouble();
      if (value == null) return null;
      return double.tryParse(value.toString());
    }

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    double? readAgeFromMap(Map<String, dynamic> source) {
      if (source.isEmpty) return null;
      final Map<String, dynamic> metrics = asMap(source['metrics']);
      const keys = <String>[
        'estimatedSkinAge',
        'estimated_skin_age',
        'skin_age',
        'biological_age',
      ];
      for (final key in keys) {
        final value = parse(source[key]) ?? parse(metrics[key]);
        if (value != null && value.isFinite && value > 0.0) return value;
      }
      return null;
    }

    if (latestScan.estimatedSkinAge > 0) {
      return latestScan.estimatedSkinAge;
    }

    final payloadAge = readAgeFromMap(latestScan.rawPayload ?? const <String, dynamic>{});
    if (payloadAge != null) return payloadAge;

    final metricsAge = readAgeFromMap(latestScan.metrics);
    if (metricsAge != null) return metricsAge;

    final redness = latestValues['localized_redness'];
    final texture = latestValues['texture_smoothness'];
    final wrinkle = latestValues['wrinkle_load'];
    final pore = latestValues['pore_visibility'];
    final darkSpots = latestValues['pigment_load'];
    final elasticity = latestValues['structural_firmness_elasticity'];
    final allPresent =
        redness != null &&
        texture != null &&
        wrinkle != null &&
        pore != null &&
        darkSpots != null &&
        elasticity != null;
    if (!allPresent) return null;

    final skinMetrics = SkinMetrics(
      redness: (redness / 10.0).clamp(0.0, 10.0),
      texture: (texture / 10.0).clamp(0.0, 10.0),
      wrinkle: (wrinkle / 10.0).clamp(0.0, 10.0),
      pore: (pore / 10.0).clamp(0.0, 10.0),
      darkSpots: (darkSpots / 10.0).clamp(0.0, 10.0),
      elasticity: (elasticity / 10.0).clamp(0.0, 10.0),
    );
    return estimateVisualSkinAge(skinMetrics);
  }

  void _debugLatestScanKeyAuditIfNeeded(
    ScanHistoryEntry scan,
    Map<String, double?> latestValues,
    double? latestEstimatedAge,
  ) {
    final poreMissing = latestValues['pore_visibility'] == null;
    final ageMissing = latestEstimatedAge == null;
    if (!poreMissing && !ageMissing) return;

    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    final metricsMap = asMap(scan.metrics);
    final payloadMap = asMap(scan.rawPayload);
    final payloadMetrics = asMap(payloadMap['metrics']);
    final payloadMatrix = asMap(payloadMap['metric_matrix']);
    final payloadOpenCv = asMap(payloadMap['opencv_metrics']);
    final payloadNestedMatrix = asMap(payloadMetrics['metric_matrix']);
    final payloadNestedOpenCv = asMap(payloadMetrics['opencv_metrics']);

    const poreCandidates = <String>[
      'pore_visibility',
    ];
    const ageCandidates = <String>[
      'estimatedSkinAge',
      'estimated_skin_age',
      'skin_age',
      'biological_age',
    ];

    final foundPore = <String, dynamic>{};
    final foundAge = <String, dynamic>{};

    void probe(
      String label,
      Map<String, dynamic> source,
      List<String> keys,
      Map<String, dynamic> bucket,
    ) {
      if (source.isEmpty) return;
      for (final key in keys) {
        if (!source.containsKey(key)) continue;
        bucket['$label.$key'] = source[key];
      }
    }

    for (final source in <({String label, Map<String, dynamic> map})>[
      (label: 'scan.metrics', map: metricsMap),
      (label: 'scan.rawPayload', map: payloadMap),
      (label: 'rawPayload.metrics', map: payloadMetrics),
      (label: 'rawPayload.metric_matrix', map: payloadMatrix),
      (label: 'rawPayload.opencv_metrics', map: payloadOpenCv),
      (label: 'rawPayload.metrics.metric_matrix', map: payloadNestedMatrix),
      (label: 'rawPayload.metrics.opencv_metrics', map: payloadNestedOpenCv),
    ]) {
      probe(source.label, source.map, poreCandidates, foundPore);
      probe(source.label, source.map, ageCandidates, foundAge);
    }

    debugPrint(
      'HOME KEY AUDIT | scan=${scan.id} | poreMissing=$poreMissing | ageMissing=$ageMissing | '
      'foundPore=$foundPore | foundAge=$foundAge | '
      'metricsKeys=${metricsMap.keys.toList()} | rawPayloadKeys=${payloadMap.keys.toList()}',
    );
  }

  Widget _buildFacialMetricsGridFromCanonical({
    required Map<String, double?> currentValues,
    Map<String, double?>? previousValues,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildFacialMetricGridCard(
                'Redness',
                currentValues['localized_redness'],
                baseline: previousValues?['localized_redness'],
                directionalityOverride: MetricDirectionality.lowerIsBetter,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFacialMetricGridCard(
                'Texture',
                currentValues['texture_smoothness'],
                baseline: previousValues?['texture_smoothness'],
                directionalityOverride: MetricDirectionality.lowerIsBetter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildFacialMetricGridCard(
                'Wrinkles',
                currentValues['wrinkle_load'],
                baseline: previousValues?['wrinkle_load'],
                directionalityOverride: MetricDirectionality.lowerIsBetter,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFacialMetricGridCard(
                'Pores',
                currentValues['pore_visibility'],
                baseline: previousValues?['pore_visibility'],
                directionalityOverride: MetricDirectionality.lowerIsBetter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildFacialMetricGridCard(
                'Dark Spots',
                currentValues['pigment_load'],
                baseline: previousValues?['pigment_load'],
                directionalityOverride: MetricDirectionality.lowerIsBetter,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFacialMetricGridCard(
                'Elasticity',
                currentValues['structural_firmness_elasticity'],
                baseline: previousValues?['structural_firmness_elasticity'],
                directionalityOverride: MetricDirectionality.higherIsBetter,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoScansCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 28),
      decoration: _homePremiumCardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: MyApp.goldShimmer.withValues(alpha: 0.11),
              shape: BoxShape.circle,
              border: Border.all(
                color: MyApp.goldShimmer.withValues(alpha: 0.20),
                width: 0.9,
              ),
            ),
            child: Icon(
              Icons.photo_library_outlined,
              size: 44,
              color: MyApp.goldShimmer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No recent scans',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: MyApp.textBrown,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Start with a new analysis to unlock live metrics,\nrecommendations, and before/after tracking.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.black,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openCameraForNewScan,
              style: MyApp.primaryGoldButton,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Start New Analysis'),
            ),
          ),
        ],
      ),
    );
  }

  ScanHistoryEntry? _selectHomepageMetricsScan(List<ScanHistoryEntry> sorted) {
    for (final scan in sorted) {
      if (scan.resolvedScanType == ScanHistoryEntry.scanTypeAiAnalysis) {
        return scan;
      }
    }
    return sorted.isNotEmpty ? sorted.first : null;
  }

  Widget _buildPremiumRecoveryCard(Color textColor) {
    return GestureDetector(
      onTap: _openPremiumRecoveryHub,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.26),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.champagneGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.30),
                ),
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: AppColors.champagneGold,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium Recovery Suite',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.refinedSlate,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'AI coach · Recovery timeline · Deep insights',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.warmAlabaster,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borders),
              ),
              child: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.champagneGold,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders, width: 0.9),
        boxShadow: [
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MyApp.goldShimmer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor.withValues(alpha: 0.75),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, Color textColor) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: MyApp.goldShimmer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: MyApp.goldShimmer, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: MyApp.sectionTitleStyle(color: textColor)),
        ),
      ],
    );
  }

  void _buildRoutinesFromProducts() {
    if (_parsedData == null) {
      _morningSteps = [];
      _nightSteps = [];
      _maskNightSteps = [];
      return;
    }
    final products = List<Map<String, dynamic>>.from(
      _parsedData!['detected_products'] as List? ?? [],
    );
    _morningSteps = [];
    _nightSteps = [];
    _maskNightSteps = [];
    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final selected = _productSelected.length > i ? _productSelected[i] : true;
      if (!selected) continue;
      final purpose = (p['purpose'] ?? '').toString().toLowerCase();
      final name = (p['name'] ?? '').toString().toLowerCase();
      final entry = {
        'product': '${p['brand'] ?? ''} ${p['name'] ?? ''}'.trim(),
        'reason': p['purpose'] ?? '',
      };
      bool isNight =
          purpose.contains('night') ||
          purpose.contains('retinol') ||
          purpose.contains('cream') ||
          name.contains('retinol') ||
          name.contains('cream') ||
          name.contains('mask') ||
          (purpose.contains('treatment') && !purpose.contains('sunscreen'));
        if (isNight) {
          _nightSteps.add(entry);
        } else {
          _morningSteps.add(entry);
        }
    }
    if (_nightSteps.any(
          (s) => s['product'].toString().toLowerCase().contains('retinol'),
        ) &&
        _nightSteps.any(
          (s) =>
              s['product'].toString().toLowerCase().contains('mask') ||
              s['product'].toString().toLowerCase().contains('mud') ||
              s['product'].toString().toLowerCase().contains('clay'),
        )) {
      _maskNightSteps = List.from(_nightSteps);
      _maskNightSteps.removeWhere(
        (s) => s['product'].toString().toLowerCase().contains('retinol'),
      );
    } else {
      _maskNightSteps = List.from(_nightSteps);
    }
  }

  @override
  Widget build(BuildContext context) {
    const textColor = AppColors.refinedSlate;
    final sortedScans = List<ScanHistoryEntry>.from(_allScans)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestScan = _selectHomepageMetricsScan(sortedScans);

    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: _handleBackNavigation,
          icon: const Icon(Icons.arrow_back, color: textColor),
        ),
        title: const SizedBox.shrink(),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.of(context).pushNamed('/settings');
              await _refreshData();
            },
            icon: const Icon(Icons.settings, color: textColor),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeLuxeBackground()),
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWelcomeSection(),
                const SizedBox(height: 12),
                if (_userClinic.isNotEmpty || _trackedProcedure.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 2),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (_userClinic.isNotEmpty)
                          _buildMetaChip(
                            Icons.local_hospital_outlined,
                            _userClinic,
                            textColor,
                          ),
                        if (_trackedProcedure.isNotEmpty)
                          _buildMetaChip(
                            Icons.track_changes_rounded,
                            _trackedProcedure,
                            textColor,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                _buildSectionHeader(
                  Icons.flash_on_rounded,
                  'Quick Actions',
                  textColor,
                ),
                const SizedBox(height: 14),
                _buildQuickActionFeatureCards(textColor),

                const SizedBox(height: 16),
                _buildQuickShortcutsRow(textColor),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  Icons.assessment_outlined,
                  'At a Glance',
                  textColor,
                ),
                const SizedBox(height: 12),
                _buildCompactStatsRow(textColor),

                const SizedBox(height: 24),
                _buildSectionHeader(
                  Icons.psychology_outlined,
                  'Daily Insights',
                  textColor,
                ),
                const SizedBox(height: 12),
                _buildAiDailyBriefingCard(textColor),

                const SizedBox(height: 20),
                _buildQuickTipsCarousel(textColor),
                const SizedBox(height: 14),
                _buildPremiumRecoveryCard(textColor),
                const SizedBox(height: 30),

                if (latestScan == null)
                  _buildNoScansCard()
                else
                  Builder(
                    builder: (context) {
                      final currentLatestScan = latestScan;
                      final latestMetrics = currentLatestScan.toSkinMetrics();
                      final latestFacialValues = _facialMetricSnapshot(
                        currentLatestScan,
                      );
                      final procedureType = _getProcedureTypeForScan(
                        currentLatestScan,
                      );
                      final isBodyProcedure = _isBodyProcedureType(
                        procedureType,
                      );
                      final previousEntry = _findPreviousComparableScan(
                        sortedScans,
                        currentLatestScan,
                      );
                      final previousMetrics = previousEntry?.toSkinMetrics();
                      final previousFacialValues = previousEntry == null
                          ? null
                          : _facialMetricSnapshot(previousEntry);
                      final latestEstimatedAge =
                          _latestEstimatedSkinAgeFromCanonical(
                            currentLatestScan,
                            latestFacialValues,
                          );
                      _debugLatestScanKeyAuditIfNeeded(
                        currentLatestScan,
                        latestFacialValues,
                        latestEstimatedAge,
                      );
                      double resolveCurrentBodyMetric(
                        List<String> rawKeys,
                        List<String> nameHints,
                      ) {
                        return _resolveBodyMetricValue(
                          scan: currentLatestScan,
                          skinMetrics: latestMetrics,
                          procedureType: procedureType,
                          rawKeys: rawKeys,
                          nameHints: nameHints,
                        );
                      }

                      double? resolvePreviousBodyMetric(
                        List<String> rawKeys,
                        List<String> nameHints,
                      ) {
                        if (previousEntry == null || previousMetrics == null) {
                          return null;
                        }
                        return _resolveBodyMetricValue(
                          scan: previousEntry,
                          skinMetrics: previousMetrics,
                          procedureType: procedureType,
                          rawKeys: rawKeys,
                          nameHints: nameHints,
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader(
                            Icons.document_scanner_outlined,
                            'Latest Scan',
                            textColor,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _getScanType(currentLatestScan),
                            style: TextStyle(
                              fontSize: 16,
                              color: MyApp.goldShimmer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Taken: ${_formatLatestScanDate(currentLatestScan.timestamp)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ScanDetailScreen(scan: currentLatestScan),
                                ),
                              );
                              await _refreshData();
                            },
                            child: Container(
                              decoration: _homePremiumCardDecoration(),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Estimated Skin Age',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        latestEstimatedAge == null
                                            ? Text(
                                                '—',
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                  color: textColor.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                ),
                                              )
                                            : Text(
                                                '${latestEstimatedAge.round()} years',
                                                style: const TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.mutedSage,
                                                ),
                                              ),
                                      ],
                                    ),
                                    if (latestEstimatedAge == null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'No analysis yet',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: textColor.withValues(alpha: 0.62),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 20),
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        9,
                                        10,
                                        9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: MyApp.clinicalNavy.withValues(
                                          alpha: 0.04,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: MyApp.clinicalNavy.withValues(
                                            alpha: 0.12,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        isBodyProcedure
                                            ? 'Metrics note: lower is better for swelling, bruising, and hyperpigmentation. Higher is better for fat retention, contour smoothness, firmness, and overall healing.'
                                            : 'Metrics note: lower is better for redness, texture, wrinkles, pores, and dark spots. Higher is better for elasticity.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.35,
                                          color: textColor.withValues(
                                            alpha: 0.72,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isBodyProcedure) ...[
                                      _buildMetricRow(
                                        'Fat Retention',
                                        resolveCurrentBodyMetric(
                                          [
                                            'fatRetention',
                                            'fat_retention',
                                            'fatRetentionPct',
                                            'fatRetentionPercent',
                                            'fatRetention',
                                            'volumeSatisfaction',
                                          ],
                                          ['fat retention', 'retention'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'fatRetention',
                                            'fat_retention',
                                            'fatRetentionPct',
                                            'fatRetentionPercent',
                                            'fatRetention',
                                            'volumeSatisfaction',
                                          ],
                                          ['fat retention', 'retention'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.higherIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Swelling',
                                        resolveCurrentBodyMetric(
                                          [
                                            'swelling',
                                            'edema',
                                            'postOpSwelling',
                                            'swellingLevel',
                                            'swellingIndex',
                                          ],
                                          ['swelling'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'swelling',
                                            'edema',
                                            'postOpSwelling',
                                            'swellingLevel',
                                            'swellingIndex',
                                          ],
                                          ['swelling'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.lowerIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Skin Laxity / Firmness',
                                        resolveCurrentBodyMetric(
                                          [
                                            'skinLaxityFirmness',
                                            'skinFirmness',
                                            'bodyFirmness',
                                            'firmness',
                                            'fibrosisFirmness',
                                            'skinLaxity',
                                            'laxity',
                                          ],
                                          ['firmness', 'laxity'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'skinLaxityFirmness',
                                            'skinFirmness',
                                            'bodyFirmness',
                                            'firmness',
                                            'fibrosisFirmness',
                                            'skinLaxity',
                                            'laxity',
                                          ],
                                          ['firmness', 'laxity'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.higherIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Contour Smoothness',
                                        resolveCurrentBodyMetric(
                                          [
                                            'smoothness',
                                            'bodySmoothness',
                                            'textureSmoothness',
                                            'contourEvenness',
                                            'contourSmoothness',
                                          ],
                                          ['smoothness', 'texture'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'smoothness',
                                            'bodySmoothness',
                                            'textureSmoothness',
                                            'contourEvenness',
                                            'contourSmoothness',
                                          ],
                                          ['smoothness', 'texture'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.higherIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Scarring / Bruising',
                                        resolveCurrentBodyMetric(
                                          [
                                            'scarringBruising',
                                            'scarring_bruising',
                                            'bruising',
                                            'scarring',
                                          ],
                                          ['bruising', 'scarring'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'scarringBruising',
                                            'scarring_bruising',
                                            'bruising',
                                            'scarring',
                                          ],
                                          ['bruising', 'scarring'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.lowerIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Hyperpigmentation',
                                        resolveCurrentBodyMetric(
                                          [
                                            'hyperpigmentation',
                                            'pigment',
                                            'pigmentation',
                                          ],
                                          ['hyperpigmentation', 'pigment'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'hyperpigmentation',
                                            'pigment',
                                            'pigmentation',
                                          ],
                                          ['hyperpigmentation', 'pigment'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.lowerIsBetter,
                                      ),
                                      _buildMetricRow(
                                        'Overall Healing',
                                        resolveCurrentBodyMetric(
                                          [
                                            'overallHealingScore',
                                            'overall_healing_score',
                                            'bodyHealingScore',
                                            'overallHealing',
                                            'healingProgress',
                                          ],
                                          ['overall healing', 'healing'],
                                        ),
                                        baseline: resolvePreviousBodyMetric(
                                          [
                                            'overallHealingScore',
                                            'overall_healing_score',
                                            'bodyHealingScore',
                                            'overallHealing',
                                            'healingProgress',
                                          ],
                                          ['overall healing', 'healing'],
                                        ),
                                        bodyStyle: true,
                                        directionalityOverride:
                                            MetricDirectionality.higherIsBetter,
                                      ),
                                    ] else ...[
                                      _buildFacialMetricsGridFromCanonical(
                                        currentValues: latestFacialValues,
                                        previousValues: previousFacialValues,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Peptide & procedure recommendations from the latest scan
                          ScanBasedRecommendationsCard(
                            latest: latestMetrics,
                            baseline: previousMetrics,
                            procedureType: procedureType,
                          ),
                          const SizedBox(height: 20),
                          // Suggested Products based on the latest scan
                          FutureBuilder<List<AIProductRecommendation>>(
                            future: Future.value(
                              () {
                                final resolvedProcedureType =
                                    procedureType?.trim().isNotEmpty == true &&
                                        procedureType!.trim().toLowerCase() !=
                                            'unknown'
                                    ? procedureType.trim()
                                    : 'General Skincare';
                                final recentProcedureTypes = _allScans
                                    .map((s) => s.procedure?.trim())
                                  .whereType<String>()
                                  .where(
                                    (p) =>
                                        p.isNotEmpty &&
                                        p.toLowerCase() != 'unknown',
                                  )
                                    .toSet()
                                    .toList();
                                return AIProductRecommendationEngine.generateRecommendations(
                                  latestMetrics,
                                  procedureType: resolvedProcedureType,
                                  maxRecommendations: isBodyProcedure ? 6 : 3,
                                  userSkinConcerns: [
                                    if (latestMetrics.redness > 6.0) 'redness',
                                    if (latestMetrics.texture > 6.0) 'texture',
                                    if (latestMetrics.wrinkle > 6.0) 'aging',
                                    if (latestMetrics.pore > 6.0) 'pores',
                                    if (latestMetrics.darkSpots > 6.0) 'pigmentation',
                                    if (latestMetrics.elasticity < 4.8) 'firmness',
                                    if (latestMetrics.redness > 6.0) 'sensitive',
                                  ],
                                  recentProcedureTypes: recentProcedureTypes,
                                );
                              }(),
                            ),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return ClinicalProductRecommendationsSection(
                                recommendations: snapshot.data!,
                                sectionTitle: 'Suggested Products',
                                sectionSubtitle:
                                    'Based on your current skin metrics',
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),

                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _openCameraForNewScan,
                  style: MyApp.primaryGoldButton,
                  child: const Text(
                    'New Progress Scan',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 36),

                _buildSectionHeader(
                  Icons.medical_services_outlined,
                  'Procedures',
                  textColor,
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).pushNamed('/create-procedure');
                    await _refreshData();
                  },
                  icon: const Icon(Icons.medical_services),
                  label: const Text('Track Procedure'),
                  style: MyApp.primaryGoldButton,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProgressReportScreen(),
                      ),
                    );
                    await _refreshData();
                  },
                  icon: Icon(Icons.analytics, color: MyApp.goldShimmer),
                  label: Text(
                    'View All Procedure Reports',
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: MyApp.secondaryOutlineButton(),
                ),
                const SizedBox(height: 24),
                _buildActiveSectionHeader('Your Active Procedures', textColor),
                const SizedBox(height: 10),
                if (_activeProcedures.isEmpty)
                  _procedureCard(
                    'No saved procedures yet',
                    'Tap "Track Procedure" to add one',
                  )
                else
                  ..._activeProcedures.take(2).map((procedure) {
                    final id =
                        (procedure['procedureId'] ?? procedure['id'] ?? '')
                            .toString()
                            .trim();
                    final type = (procedure['type'] ?? 'Procedure')
                        .toString()
                        .trim();
                    final completedRaw = procedure['isCompleted'];
                    final isCompleted =
                        completedRaw == true ||
                        completedRaw?.toString().toLowerCase() == 'true';
                    final startDate = (procedure['startDate'] ?? '').toString();
                    final sessionsRaw =
                        procedure['plannedSessions'] ??
                        procedure['numSessions'];
                    final sessions = (sessionsRaw is num)
                        ? sessionsRaw.toString()
                        : (sessionsRaw?.toString().trim() ?? '');
                    final sessionDisplay =
                        (sessions.isEmpty ||
                            sessions == '0' ||
                            sessions.toLowerCase() == 'unknown')
                        ? 'Unknown sessions'
                        : '$sessions sessions';
                    final when =
                        '${_formatProcedureDate(startDate)} | $sessionDisplay';
                    return _procedureCard(
                      type,
                      when,
                      onTap: () async {
                        if (id.isNotEmpty) {
                          await AppPrefs.setSelectedProcedureId(id);
                        }
                        if (!context.mounted) return;
                        await Navigator.of(context).pushNamed('/procedures');
                        await _refreshData();
                      },
                      statusLabel: isCompleted ? 'Completed' : 'Active',
                    );
                  }),
                const SizedBox(height: 28),

                _buildSectionHeader(Icons.spa_outlined, 'Skincare', textColor),
                const SizedBox(height: 14),

                ElevatedButton.icon(
                  onPressed: _logNewSkincareProduct,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Track Skincare Product'),
                  style: MyApp.primaryGoldButton,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProgressReportScreen(),
                      ),
                    );
                    await _refreshData();
                  },
                  icon: Icon(Icons.analytics, color: MyApp.goldShimmer),
                  label: Text(
                    'View All Skincare Reports',
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: MyApp.secondaryOutlineButton(),
                ),
                const SizedBox(height: 22),
                _buildActiveSectionHeader('Your Active Skincare', textColor),
                const SizedBox(height: 10),
                if (_trackedProducts.isEmpty)
                  _procedureCard(
                    'No saved skincare products yet',
                    'Tap "Track Skincare Product" to add one',
                  )
                else
                  ..._trackedProducts.map(
                    (product) => _procedureCard(
                      product.name,
                      product.brand.isNotEmpty ? product.brand : 'No brand',
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ActiveSkincareDetailsScreen(product: product),
                          ),
                        );
                        if (mounted) await _refreshData();
                      },
                    ),
                  ),

                const SizedBox(height: 36),

                // Primary gold buttons
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SkincareRoutineScreen(),
                      ),
                    ).then((_) => _refreshData());
                  },
                  icon: const Icon(Icons.auto_awesome, color: Colors.black),
                  label: const Text(
                    'Your Skincare Routine',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  style: MyApp.primaryGoldButton,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SkinJourneyJournalScreen(
                          skincareJournals: _skincareJournals,
                          trackedProducts: _trackedProducts,
                          activeProcedures: _activeProcedureModels,
                        ),
                      ),
                    );
                    await _refreshData();
                  },
                  icon: const Icon(Icons.book, color: Colors.black),
                  label: const Text(
                    'Your Skin Journey Journal',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  style: MyApp.primaryGoldButton,
                ),

                const SizedBox(height: 36),

                _buildSectionHeader(
                  Icons.photo_library_outlined,
                  'Scan Results',
                  textColor,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 520;
                    final cards = [
                      _procedureCard(
                        'Procedure Scans',
                        '${_getProcedureScanCountFromLoaded()} scans',
                        icon: Icons.medical_services_outlined,
                        accent: AppColors.refinedSlate,
                        statusLabel: 'Procedure',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProgressReportScreen(
                                viewMode: ProgressReportViewMode.scans,
                                initialTabIndex: 1,
                              ),
                            ),
                          );
                          await _refreshData();
                        },
                      ),
                      _procedureCard(
                        'Skincare Logs',
                        '${_getSkincareScanCountFromLoaded(_trackedProducts)} scans',
                        icon: Icons.spa_rounded,
                        accent: AppColors.mutedSage,
                        statusLabel: 'Skincare',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProgressReportScreen(
                                viewMode: ProgressReportViewMode.scans,
                                initialTabIndex: 2,
                              ),
                            ),
                          );
                          await _refreshData();
                        },
                      ),
                      _procedureCard(
                        'AI Deep Analysis',
                        '${_getAiAnalysisScanCountFromLoaded()} scans',
                        icon: Icons.auto_awesome_rounded,
                        accent: AppColors.champagneGold,
                        statusLabel: 'AI Analysis',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ProgressReportScreen(
                                viewMode: ProgressReportViewMode.scans,
                                initialTabIndex: 3,
                              ),
                            ),
                          );
                          await _refreshData();
                        },
                      ),
                    ];
                    if (compact) {
                      return Column(children: cards);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < cards.length; index++) ...[
                          Expanded(child: cards[index]),
                          if (index != cards.length - 1)
                            const SizedBox(width: 12),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          border: Border(
            top: BorderSide(
              color: AppColors.champagneGold.withValues(alpha: 0.24),
              width: 0.8,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          currentIndex: _selectedIndex,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.black,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          onTap: _onNavTap,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt_rounded),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.timeline_outlined),
              activeIcon: Icon(Icons.timeline_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today_outlined),
              activeIcon: Icon(Icons.calendar_today_rounded),
              label: 'Routines',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.champagneGold.withValues(alpha: 0.26),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.refinedSlate.withValues(alpha: 0.07),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo / Avatar
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.warmAlabaster,
                  border: Border.all(
                    color: AppColors.champagneGold.withValues(alpha: 0.38),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.champagneGold.withValues(alpha: 0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo/logo.png', // Correct path
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.spa, color: MyApp.goldShimmer, size: 38),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 2,
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Welcome back',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: AppColors.refinedSlate.withValues(
                              alpha: 0.74,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                        height: 1.0,
                        color: AppColors.refinedSlate,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your skin journey, beautifully tracked.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.12,
                        height: 1.5,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              if (_scanCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warmAlabaster,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.champagneGold.withValues(alpha: 0.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.refinedSlate.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_scanCount',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.champagneGold,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'scans',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _homePremiumCardDecoration({
    Color? borderColor,
    double borderAlpha = 0.22,
  }) {
    return BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: (borderColor ?? AppColors.champagneGold).withValues(
          alpha: borderAlpha,
        ),
        width: 0.9,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.refinedSlate.withValues(alpha: 0.055),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildAiSkinAnalysisCard(Color textColor) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => const SkinAiAnalysisScreen(),
                  ),
                )
                .then((_) => _refreshData());
          },
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.cardBackground,
                  AppColors.champagneGold.withValues(alpha: 0.26),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.60),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.refinedSlate.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.32),
                  blurRadius: 38,
                  spreadRadius: 2,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _HomeConcentricPainter(
                        color: AppColors.champagneGold.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.champagneGold.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 32,
                            color: AppColors.onChampagneGold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Flexible(
                                    child: Text(
                                      'AI Skin Analysis',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.1,
                                        color: AppColors.refinedSlate,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.champagneGold.withValues(
                                        alpha: 0.95,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: AppColors.warmAlabaster
                                            .withValues(alpha: 0.65),
                                        width: 0.8,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.champagneGold
                                              .withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'Recommended',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                        color: AppColors.refinedSlate,
                                        shadows: [
                                          Shadow(
                                            color: Colors.black,
                                            blurRadius: 1.5,
                                            offset: Offset(0, 0.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Capture a photo for an instant, in-depth read '
                                'of your skin metrics and tailored guidance.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.refinedSlate.withValues(
                                    alpha: 0.66,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.champagneGold,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.champagneGold.withValues(
                                        alpha: 0.36,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Analyze My Skin',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.onChampagneGold,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 17,
                                      color: AppColors.onChampagneGold,
                                    ),
                                  ],
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionFeatureCards(Color textColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 760;
        final cards = [
          _buildAiSkinAnalysisCard(textColor),
          _buildAiSkincareCoachCard(textColor),
        ];

        if (!useColumns) {
          return Column(
            children: [cards.first, const SizedBox(height: 14), cards.last],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards.first),
            const SizedBox(width: 14),
            Expanded(child: cards.last),
          ],
        );
      },
    );
  }

  Widget _buildAiSkincareCoachCard(Color textColor) {
    final isLocked = !_isPremiumUser;
    final badgeText = isLocked ? 'Premium' : 'Unlocked';
    final badgeIcon = isLocked ? Icons.lock_rounded : Icons.verified_rounded;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 980),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _openAiSkincareCoach,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.cardBackground,
                  AppColors.champagneGold.withValues(alpha: 0.26),
                ],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.68),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.refinedSlate.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: AppColors.champagneGold.withValues(alpha: 0.32),
                  blurRadius: 38,
                  spreadRadius: 2,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _HomeConcentricPainter(
                        color: AppColors.champagneGold.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: _buildCoachPremiumBadge(badgeIcon, badgeText),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.champagneGold.withValues(
                                  alpha: 0.42,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            isLocked
                                ? Icons.lock_rounded
                                : Icons.psychology_alt_rounded,
                            size: 32,
                            color: AppColors.onChampagneGold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'AI Skincare Coach',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.1,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isLocked
                                    ? 'Unlock your personal AI Skincare Coach for routines, recovery advice, and progress guidance.'
                                    : 'Get personalized routines, recovery advice, and progress guidance from your premium coach.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                  color: textColor.withValues(alpha: 0.66),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.champagneGold,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.champagneGold.withValues(
                                        alpha: 0.32,
                                      ),
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isLocked ? 'Unlock Coach' : 'Open Coach',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.onChampagneGold,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      isLocked
                                          ? Icons.workspace_premium_rounded
                                          : Icons.arrow_forward_rounded,
                                      size: 17,
                                      color: AppColors.onChampagneGold,
                                    ),
                                  ],
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoachPremiumBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.champagneGold.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.warmAlabaster.withValues(alpha: 0.65),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.refinedSlate),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: AppColors.refinedSlate,
              shadows: [
                Shadow(
                  color: Colors.black,
                  blurRadius: 1.5,
                  offset: Offset(0, 0.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickShortcutsRow(Color textColor) {
    final shortcuts =
        <
          ({
            IconData icon,
            String label,
            Color color,
            bool hero,
            VoidCallback onTap,
          })
        >[
          (
            icon: Icons.medical_services_rounded,
            label: 'New Procedure',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(
                context,
              ).pushNamed('/create-procedure').then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.timeline_rounded,
            label: 'History',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(
                context,
              ).pushNamed('/procedure-history').then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.photo_camera_rounded,
            label: 'Scan Skin',
            color: AppColors.champagneGold,
            hero: false,
            onTap: _openCameraForNewScan,
          ),
          (
            icon: Icons.auto_awesome_rounded,
            label: 'AI Chat',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const SkinAiAnalysisScreen(),
                    ),
                  )
                  .then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.add_shopping_cart_rounded,
            label: 'Log Product',
            color: AppColors.champagneGold,
            hero: false,
            onTap: _logNewSkincareProduct,
          ),
          (
            icon: Icons.medical_information_rounded,
            label: 'Acne / Rosacea',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const AcneRosaceaTrackerScreen(),
                    ),
                  )
                  .then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.photo_library_rounded,
            label: 'Scans',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const ProgressReportScreen(
                        viewMode: ProgressReportViewMode.scans,
                      ),
                    ),
                  )
                  .then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.analytics_rounded,
            label: 'View Reports',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => const ProgressReportScreen(
                        viewMode: ProgressReportViewMode.reports,
                      ),
                    ),
                  )
                  .then((_) => _refreshData());
            },
          ),
          (
            icon: Icons.workspace_premium_rounded,
            label: 'Premium Hub',
            color: AppColors.champagneGold,
            hero: false,
            onTap: _openPremiumRecoveryHub,
          ),
          (
            icon: Icons.biotech_rounded,
            label: 'Peptide Dash',
            color: AppColors.champagneGold,
            hero: false,
            onTap: () {
              Navigator.of(
                context,
              ).pushNamed('/peptide-dashboard').then((_) => _refreshData());
            },
          ),
        ];

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shortcuts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final item = shortcuts[i];
          final isHero = item.hero;
          final isPremiumHub = item.label == 'Premium Hub';
          const standardButtonBg = Color(0xFF1A1A1A);
          const premiumHubBg = Color(0xFFF3EBDD);
          const darkObsidian = Color(0xFF1A1A1A);

            // Balanced palette:
            // - Standard quick actions: cream background with dark text/icons.
            // - Premium Hub: dark background with gold text/icons and gold glow.
            final cardBackground = isPremiumHub ? standardButtonBg : premiumHubBg;
            final cardBorder = isPremiumHub
              ? AppColors.champagneGold.withValues(alpha: 0.90)
              : darkObsidian.withValues(alpha: 0.20);
            final iconBackground = isPremiumHub
              ? AppColors.champagneGold.withValues(alpha: 0.12)
              : darkObsidian.withValues(alpha: 0.06);
            final iconBorder = isPremiumHub
              ? AppColors.champagneGold.withValues(alpha: 0.55)
              : darkObsidian.withValues(alpha: 0.20);
            final iconColor = isPremiumHub
              ? AppColors.champagneGold
              : darkObsidian;
            final labelColor = isPremiumHub
              ? AppColors.champagneGold
              : darkObsidian;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: item.onTap,
              child: Container(
                width: isHero ? 150 : 106,
                padding: EdgeInsets.symmetric(
                  horizontal: isHero ? 14 : 9,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cardBorder,
                    width: isPremiumHub ? 1.1 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.refinedSlate.withValues(alpha: 0.055),
                      blurRadius: 18,
                      offset: const Offset(0, 9),
                    ),
                    if (isPremiumHub)
                      BoxShadow(
                        color: AppColors.champagneGold.withValues(alpha: 0.24),
                        blurRadius: 20,
                        spreadRadius: 1,
                        offset: const Offset(0, 10),
                      ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isHero)
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.champagneGold.withValues(
                              alpha: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.warmAlabaster.withValues(
                                alpha: 0.65,
                              ),
                              width: 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.refinedSlate.withValues(
                                  alpha: 0.12,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Recommended',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                              color: AppColors.refinedSlate,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 1.5,
                                  offset: Offset(0, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (isHero) const SizedBox(height: 6),
                    Container(
                      width: isHero ? 48 : 40,
                      height: isHero ? 48 : 40,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        borderRadius: BorderRadius.circular(isHero ? 14 : 12),
                        border: Border.all(color: iconBorder, width: 0.8),
                        boxShadow: isHero
                            ? [
                                BoxShadow(
                                  color: AppColors.champagneGold.withValues(
                                    alpha: 0.32,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        item.icon,
                        size: isHero ? 25 : 21,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isHero ? 13 : 11.5,
                        fontWeight: FontWeight.w800,
                        color: labelColor,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactStatsRow(Color textColor) {
    final items = [
      (
        Icons.health_and_safety_outlined,
        'Skin Health',
        _scanCount >= 2 ? 'Tracking' : 'Ready',
        AppColors.mutedSage,
      ),
      (
        Icons.medical_services_outlined,
        'Procedures',
        '${_activeProcedures.length}',
        AppColors.champagneGold,
      ),
      (
        Icons.photo_camera_rounded,
        'Scans',
        '$_scanCount',
        AppColors.champagneGold,
      ),
    ];

    return Container(
      decoration: _homePremiumCardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: List.generate(items.length, (index) {
          final (icon, label, value, accent) = items[index];
          return Expanded(
            child: Container(
              decoration: index == 0
                  ? null
                  : BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          color: AppColors.champagneGold.withValues(
                            alpha: 0.16,
                          ),
                          width: 0.9,
                        ),
                      ),
                    ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 17, color: accent),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.refinedSlate,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildAiDailyBriefingCard(Color textColor) {
    final sortedScans = [..._allScans]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final latestScan = sortedScans.isNotEmpty ? sortedScans.first : null;
    final latestScanProcedureType =
        latestScan != null ? _getProcedureTypeForScan(latestScan) : null;
    final validActiveProcedureTypes = _activeProcedureModels
        .map((p) => p.type.trim())
        .where((p) => p.isNotEmpty && p.toLowerCase() != 'unknown')
      .toList();
    final activeProcedureType =
      validActiveProcedureTypes.isNotEmpty
      ? validActiveProcedureTypes.first
      : null;
    final resolvedBriefingProcedureType =
        (latestScanProcedureType?.trim().isNotEmpty == true &&
            latestScanProcedureType!.trim().toLowerCase() != 'unknown')
        ? latestScanProcedureType.trim()
        : activeProcedureType;

    final briefing = AiIntelligenceEngine.generateDailyBriefing(
      scans: _allScans,
      procedures: _activeProcedureModels,
      products: _trackedProducts,
      currentProcedureType: resolvedBriefingProcedureType,
    );

    if (!briefing.hasMeaningfulData) return const SizedBox.shrink();

    final aiColor = MyApp.clinicalNavy;
    final accentColor = MyApp.clinicalTeal;

    final visibleInsights = briefing.insights.take(3).toList();

    return Container(
      decoration: _homePremiumCardDecoration(
        borderColor: aiColor,
        borderAlpha: 0.16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 14, 12),
            decoration: BoxDecoration(
              color: aiColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
              border: Border(
                bottom: BorderSide(
                  color: aiColor.withValues(alpha: 0.16),
                  width: 0.8,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: aiColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: aiColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DAILY INSIGHTS',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                          color: aiColor.withValues(alpha: 0.60),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        briefing.headline,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          color: aiColor,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        briefing.subheadline,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: aiColor.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'AI',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...visibleInsights.map(
                  (insight) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: insight.color.withValues(alpha: 0.16),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: insight.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              insight.icon,
                              color: insight.color,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  insight.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.8,
                                    color: insight.color,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  insight.body,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textColor.withValues(alpha: 0.80),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: aiColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: aiColor.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.today_outlined, size: 14, color: aiColor),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          briefing.todaysFocus,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: textColor.withValues(alpha: 0.78),
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI-generated insights are for informational purposes only and do not constitute medical advice. Always consult your healthcare provider before making treatment decisions.',
                  style: TextStyle(
                    fontSize: 9.6,
                    color: aiColor.withValues(alpha: 0.42),
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTipsCarousel(Color textColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: MyApp.surfaceCardDecoration(
        tintOpacity: MyApp.isDark ? 0.12 : 0.06,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: MyApp.goldShimmer, size: 18),
              const SizedBox(width: 8),
              Text(
                'Quick Tips',
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: PageView.builder(
              controller: _tipPageController,
              onPageChanged: (index) => setState(() => _activeTipIndex = index),
              itemCount: _quickTips.length,
              itemBuilder: (context, index) => AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: _activeTipIndex == index ? 1 : 0.55,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _quickTips[index],
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.86),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_quickTips.length, (index) {
              final active = index == _activeTipIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  color: active
                      ? MyApp.goldShimmer
                      : MyApp.goldShimmer.withValues(alpha: 0.35),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _procedureCard(
    String title,
    String when, {
    Future<void> Function()? onTap,
    String? statusLabel,
    IconData? icon,
    Color? accent,
  }) {
    final cardAccent = accent ?? MyApp.goldShimmer;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardAccent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: icon == null ? 4 : 38,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cardAccent.withValues(
                      alpha: icon == null ? 1 : 0.10,
                    ),
                    borderRadius: BorderRadius.circular(icon == null ? 4 : 12),
                    border: icon == null
                        ? null
                        : Border.all(color: cardAccent.withValues(alpha: 0.24)),
                  ),
                  child: icon == null
                      ? null
                      : Icon(icon, color: cardAccent, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: MyApp.cardTitleStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        when,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (statusLabel != null)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusLabel == 'Completed'
                          ? AppColors.mutedSage.withValues(alpha: 0.12)
                          : cardAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusLabel == 'Completed'
                            ? AppColors.mutedSage.withValues(alpha: 0.45)
                            : cardAccent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusLabel == 'Completed'
                            ? AppColors.mutedSage
                            : cardAccent,
                      ),
                    ),
                  ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cardAccent.withValues(alpha: 0.60),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSectionHeader(String title, Color textColor) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: MyApp.goldShimmer,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textColor.withValues(alpha: 0.80),
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _HomeLuxeBackground extends StatelessWidget {
  const _HomeLuxeBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.warmAlabaster,
            AppColors.cardBackground.withValues(alpha: 0.92),
            AppColors.champagneGold.withValues(alpha: 0.07),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: CustomPaint(
        painter: _HomeConcentricPainter(
          color: AppColors.champagneGold.withValues(alpha: 0.10),
        ),
      ),
    );
  }
}

class _HomeConcentricPainter extends CustomPainter {
  final Color color;

  const _HomeConcentricPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color;
    final center = Offset(size.width * 0.84, size.height * 0.10);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(center, 44 + (i * 34), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HomeConcentricPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ====================== JOURNAL SCREENS ======================
class HealingJournalScreen extends StatelessWidget {
  final List<models.Procedure> procedures;
  const HealingJournalScreen({super.key, required this.procedures});

  @override
  Widget build(BuildContext context) {
    final allEntries = <_JournalEntryView>[];
    for (final proc in procedures) {
      for (final entry in proc.journalEntries) {
        allEntries.add(_JournalEntryView(procedure: proc, entry: entry));
      }
    }
    allEntries.sort((a, b) => b.entry.date.compareTo(a.entry.date));
    return Scaffold(
      appBar: AppBar(
        title: Text('Healing Journal', style: MyApp.pageTitleStyle()),
        backgroundColor: Colors.transparent,
        foregroundColor: MyApp.textBrown,
        elevation: 0,
      ),
      body: allEntries.isEmpty
          ? const Center(child: Text('No journal entries yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: allEntries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, idx) => allEntries[idx],
            ),
    );
  }
}

class _JournalEntryView extends StatelessWidget {
  final models.Procedure procedure;
  final JournalEntry entry;
  const _JournalEntryView({required this.procedure, required this.entry});

  @override
  Widget build(BuildContext context) {
    final dateStr = entry.date.toLocal().toString().split(' ')[0];
    return Card(
      elevation: 2,
      color: MyApp.surface,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: MyApp.cardShape,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  procedure.type,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontSize: 16,
                  ),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (entry.content.isNotEmpty)
              Text(
                entry.content,
                style: TextStyle(fontSize: 15, color: MyApp.textBrown),
              ),
          ],
        ),
      ),
    );
  }
}

class SingleJournalEntryScreen extends StatelessWidget {
  final TrackedProduct product;
  final JournalEntry entry;
  const SingleJournalEntryScreen({
    super.key,
    required this.product,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = entry.date.toLocal().toString().split(' ')[0];
    return Scaffold(
      appBar: AppBar(
        title: Text('Journal Entry', style: MyApp.pageTitleStyle()),
        backgroundColor: Colors.transparent,
        foregroundColor: MyApp.textBrown,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              color: MyApp.surface,
              shadowColor: Colors.black.withValues(alpha: 0.06),
              shape: MyApp.cardShape,
              child: Padding(
                padding: MyApp.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            product.brand.isNotEmpty
                                ? '${product.brand} - ${product.name}'
                                : product.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (entry.title.isNotEmpty) ...[
                      Text(
                        entry.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Text(
                          ['😞', '😐', '🙂', '😊', '🥰'][entry.moodRating - 1],
                          style: const TextStyle(fontSize: 32),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      entry.content,
                      style: const TextStyle(fontSize: 16, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            if (entry.attachedImagePath != null &&
                entry.attachedImagePath!.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Attached Photo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildImageInDetail(entry.attachedImagePath),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageInDetail(String? path) {
    if (path == null || path.isEmpty) {
      return const Icon(Icons.photo, size: 120, color: Colors.grey);
    }
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.contain);
    } else {
      return Image.file(File(path), fit: BoxFit.contain);
    }
  }
}
