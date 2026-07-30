import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import '../models/peptide_model.dart';
import '../models/scan_history.dart';
import '../utils/app_prefs.dart';
import '../utils/peptide_service.dart';

/// Photo Gallery
///
/// Shows every scan photo across procedures, peptides, skincare products,
/// and standalone progress scans. Each tile is tagged with a color-coded
/// source badge so the user can immediately tell where the photo came from.
class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key});

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

enum _GalleryFilter { all, procedure, skincare, peptide, general }

enum _PhotoSourceType { procedure, skincare, peptide, general }

class _PhotoSource {
  const _PhotoSource({required this.type, required this.label});
  final _PhotoSourceType type;
  final String label;

  Color get color {
    switch (type) {
      case _PhotoSourceType.procedure:
        return const Color(0xFFB76E79); // rose-gold
      case _PhotoSourceType.skincare:
        return const Color(0xFF4A8A7E); // teal
      case _PhotoSourceType.peptide:
        return const Color(0xFFA47E2F); // antique gold
      case _PhotoSourceType.general:
        return const Color(0xFF7A6E66); // warm gray
    }
  }

  IconData get icon {
    switch (type) {
      case _PhotoSourceType.procedure:
        return Icons.face_retouching_natural;
      case _PhotoSourceType.skincare:
        return Icons.spa_outlined;
      case _PhotoSourceType.peptide:
        return Icons.science_outlined;
      case _PhotoSourceType.general:
        return Icons.image_outlined;
    }
  }
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  bool _loading = true;
  List<ScanHistoryEntry> _allScans = const [];
  Map<String, String> _procedureNameById = const {};
  Map<String, String> _peptideNameById = const {};
  Map<String, Map<String, String?>> _procedurePhotoComparisonById = const {};
  _GalleryFilter _filter = _GalleryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scans = await AppPrefs.getScanEntries();
    final procedures = await AppPrefs.getProcedureEntries();
    List<PeptideEntry> peptides = const [];
    try {
      peptides = await PeptideService.loadAll();
    } catch (_) {}

    final procNames = <String, String>{};
    for (final raw in procedures) {
      final id = (raw['id'] ?? raw['procedureId'] ?? '').toString().trim();
      final name = (raw['type'] ?? raw['name'] ?? '').toString().trim();
      if (id.isNotEmpty && name.isNotEmpty) procNames[id] = name;
    }

    final pepNames = <String, String>{};
    for (final p in peptides) {
      if (p.id.trim().isNotEmpty && p.name.trim().isNotEmpty) {
        pepNames[p.id.trim()] = p.name.trim();
      }
    }

    final withImages =
        scans.where((s) => (s.imagePath ?? '').isNotEmpty).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final procedureIds = withImages
        .map((scan) => (scan.procedureId ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final comparisonRows = await Future.wait(
      procedureIds.map((procedureId) async {
        final comparison = await AppPrefs.getProcedurePhotoComparison(procedureId);
        return MapEntry(procedureId, comparison);
      }),
    );
    final comparisonByProcedure = <String, Map<String, String?>>{
      for (final row in comparisonRows) row.key: row.value,
    };

    if (!mounted) return;
    setState(() {
      _allScans = withImages;
      _procedureNameById = procNames;
      _peptideNameById = pepNames;
      _procedurePhotoComparisonById = comparisonByProcedure;
      _loading = false;
    });
  }

  // ── Source resolution ──────────────────────────────────────────────────
  _PhotoSource _sourceFor(ScanHistoryEntry scan) {
    final procId = scan.procedureId?.trim() ?? '';
    if (procId.isNotEmpty) {
      final name =
          _procedureNameById[procId] ??
          (scan.procedure?.trim().isNotEmpty == true
              ? scan.procedure!.trim()
              : 'Procedure');
      return _PhotoSource(type: _PhotoSourceType.procedure, label: name);
    }
    final pepId = scan.peptideId?.trim() ?? '';
    if (pepId.isNotEmpty) {
      final name = _peptideNameById[pepId] ?? 'Peptide';
      return _PhotoSource(type: _PhotoSourceType.peptide, label: name);
    }
    final product = scan.productName?.trim() ?? '';
    if (product.isNotEmpty) {
      return _PhotoSource(type: _PhotoSourceType.skincare, label: product);
    }
    final legacyProc = scan.procedure?.trim() ?? '';
    if (legacyProc.isNotEmpty && legacyProc.toLowerCase() != 'general') {
      return _PhotoSource(type: _PhotoSourceType.procedure, label: legacyProc);
    }
    return const _PhotoSource(
      type: _PhotoSourceType.general,
      label: 'General Progress',
    );
  }

  List<ScanHistoryEntry> get _visibleScans {
    if (_filter == _GalleryFilter.all) return _allScans;
    return _allScans.where((s) {
      final type = _sourceFor(s).type;
      switch (_filter) {
        case _GalleryFilter.procedure:
          return type == _PhotoSourceType.procedure;
        case _GalleryFilter.skincare:
          return type == _PhotoSourceType.skincare;
        case _GalleryFilter.peptide:
          return type == _PhotoSourceType.peptide;
        case _GalleryFilter.general:
          return type == _PhotoSourceType.general;
        case _GalleryFilter.all:
          return true;
      }
    }).toList();
  }

  String get _filterTitle {
    switch (_filter) {
      case _GalleryFilter.all:
        return 'All Photos';
      case _GalleryFilter.procedure:
        return 'Procedure Photos';
      case _GalleryFilter.skincare:
        return 'Skincare Photos';
      case _GalleryFilter.peptide:
        return 'Peptide Photos';
      case _GalleryFilter.general:
        return 'General Progress Photos';
    }
  }

  static Uint8List? _decodeImagePath(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final raw = path.startsWith('data:')
          ? path.substring(path.indexOf(',') + 1)
          : path;
      final normalized = raw.replaceAll(RegExp(r'\s+'), '');
      final needsPadding = normalized.length % 4;
      final padded = needsPadding == 0
          ? normalized
          : '$normalized${'=' * (4 - needsPadding)}';
      return base64Decode(padded);
    } catch (_) {
      return null;
    }
  }

  void _openPreview(int initialIndex, List<ScanHistoryEntry> scans) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoPreviewScreen(
          scans: scans,
          initialIndex: initialIndex,
          sourceResolver: _sourceFor,
          procedurePhotoComparisonById: _procedurePhotoComparisonById,
        ),
      ),
    );
  }

  _TimelineBadgeData? _timelineBadgeFor(ScanHistoryEntry scan) {
    final procedureId = (scan.procedureId ?? '').trim();
    if (procedureId.isEmpty) return null;

    if (scan.isBaseline) {
      return const _TimelineBadgeData(
        label: 'BASELINE',
        backgroundColor: Color(0xFF2E7D32),
        foregroundColor: Color(0xFFFFF8E1),
      );
    }

    final comparison = _procedurePhotoComparisonById[procedureId];
    final baselineScanId = comparison?['baselineScanId']?.trim();
    final hasBaseline = baselineScanId != null && baselineScanId.isNotEmpty;
    if (!hasBaseline || baselineScanId == scan.id) return null;

    return const _TimelineBadgeData(
      label: 'FOLLOW-UP',
      backgroundColor: Color(0xFF244A73),
      foregroundColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 900
        ? 4
        : screenWidth >= 600
        ? 3
        : 2;
    final scans = _visibleScans;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        title: ClinicalAppBarTitle(
          title: 'Photo Gallery',
          eyebrow: 'Visual archive',
          color: MyApp.textBrown,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(scans.length),
                  _buildFilterChips(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: scans.isEmpty
                        ? _buildEmptyState()
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.78,
                                ),
                            itemCount: scans.length,
                            itemBuilder: (context, index) =>
                                _buildPhotoTile(scans[index], index, scans),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(int visibleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: ClinicalSectionHeader(
        icon: Icons.photo_library_outlined,
        title: _filterTitle,
        eyebrow: 'Visual archive',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.champagneGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.30),
            ),
          ),
          child: Text(
            '$visibleCount photo${visibleCount == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.refinedSlate,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final chips = <(_GalleryFilter, String)>[
      (_GalleryFilter.all, 'All'),
      (_GalleryFilter.procedure, 'Procedures'),
      (_GalleryFilter.skincare, 'Skincare'),
      (_GalleryFilter.peptide, 'Peptides'),
      (_GalleryFilter.general, 'General'),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final filter = chips[i].$1;
          final label = chips[i].$2;
          final selected = _filter == filter;
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => setState(() => _filter = filter),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onChampagneGold : MyApp.textBrown,
            ),
            selectedColor: AppColors.champagneGold,
            backgroundColor: AppColors.cardBackground,
            side: BorderSide(
              color: AppColors.champagneGold.withValues(
                alpha: selected ? 0.0 : 0.40,
              ),
            ),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildPhotoTile(
    ScanHistoryEntry scan,
    int index,
    List<ScanHistoryEntry> scans,
  ) {
    final bytes = _decodeImagePath(scan.imagePath);
    final source = _sourceFor(scan);
    const months = [
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
    final d = scan.timestamp;
    final dateLabel = '${months[d.month - 1]} ${d.day}, ${d.year}';
    final timelineBadge = _timelineBadgeFor(scan);
    return GestureDetector(
      onTap: () => _openPreview(index, scans),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: MyApp.surface,
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.20),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: MyApp.clinicalNavy.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null)
                Image.memory(bytes, fit: BoxFit.cover)
              else
                Container(
                  color: MyApp.champagne,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    color: MyApp.textBrown.withValues(alpha: 0.4),
                    size: 28,
                  ),
                ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: _SourceBadge(source: source),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.0),
                        Colors.black.withValues(alpha: 0.55),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dateLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (timelineBadge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: timelineBadge.backgroundColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            timelineBadge.label,
                            style: TextStyle(
                              color: timelineBadge.foregroundColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _filter != _GalleryFilter.all;
    String message;
    switch (_filter) {
      case _GalleryFilter.procedure:
        message =
            'No procedure photos yet. Take a scan from a procedure to add the first one.';
        break;
      case _GalleryFilter.skincare:
        message =
            'No skincare photos yet. Log a scan from your skincare tracker to populate this gallery.';
        break;
      case _GalleryFilter.peptide:
        message =
            'No peptide photos yet. Take a scan while tracking a peptide to add the first one.';
        break;
      case _GalleryFilter.general:
        message =
            'No standalone progress photos yet. General scans appear here when they aren\u2019t tied to a procedure, peptide, or product.';
        break;
      case _GalleryFilter.all:
        message = _allScans.isEmpty
            ? 'Take your first scan to start building your photo gallery.'
            : 'No photos match this filter.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.champagneGold.withValues(alpha: 0.20),
                    AppColors.goldHover.withValues(alpha: 0.12),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppColors.champagneGold.withValues(alpha: 0.32),
                  width: 0.8,
                ),
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: AppColors.goldHover,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isFiltered ? 'No photos in this category' : 'No photos yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: MyApp.clinicalNavy,
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: MyApp.clinicalSlate,
              ),
            ),
            if (isFiltered) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _filter = _GalleryFilter.all),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldHover,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('Show all photos'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final _PhotoSource source;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: source.color.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(source.icon, size: 11, color: source.color),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                source.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: source.color,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineBadgeData {
  const _TimelineBadgeData({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _ComparisonPair {
  const _ComparisonPair({
    required this.baselineScanId,
    required this.followUpScanId,
  });

  final String baselineScanId;
  final String followUpScanId;
}

class _PhotoPreviewScreen extends StatefulWidget {
  final List<ScanHistoryEntry> scans;
  final int initialIndex;
  final _PhotoSource Function(ScanHistoryEntry) sourceResolver;
  final Map<String, Map<String, String?>> procedurePhotoComparisonById;

  const _PhotoPreviewScreen({
    required this.scans,
    required this.initialIndex,
    required this.sourceResolver,
    required this.procedurePhotoComparisonById,
  });

  @override
  State<_PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<_PhotoPreviewScreen> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scans[_current];
    final source = widget.sourceResolver(scan);
    final comparisonPair = _comparisonPairForScan(scan);
    const months = [
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
    final d = scan.timestamp;
    final dateLabel = '${months[d.month - 1]} ${d.day}, ${d.year}';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (comparisonPair != null)
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _BaselineComparisonViewer(
                      scans: widget.scans,
                      baselineScanId: comparisonPair.baselineScanId,
                      followUpScanId: comparisonPair.followUpScanId,
                      sourceResolver: widget.sourceResolver,
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.compare_arrows_rounded,
                color: Colors.white,
                size: 16,
              ),
              label: const Text(
                'Compare to Baseline',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            Text(
              '$dateLabel  \u00b7  ${_current + 1}/${widget.scans.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.scans.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, index) {
          final bytes = _PhotoGalleryScreenState._decodeImagePath(
            widget.scans[index].imagePath,
          );
          return Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
            ),
          );
        },
      ),
    );
  }

  _ComparisonPair? _comparisonPairForScan(ScanHistoryEntry scan) {
    final procedureId = (scan.procedureId ?? '').trim();
    if (procedureId.isEmpty || scan.isBaseline) return null;

    final procedureScans = widget.scans
        .where((item) => (item.procedureId ?? '').trim() == procedureId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (procedureScans.isEmpty) return null;

    final comparison = widget.procedurePhotoComparisonById[procedureId];
    String? baselineScanId = comparison?['baselineScanId']?.trim();
    if (baselineScanId == null ||
        baselineScanId.isEmpty ||
        !procedureScans.any((entry) => entry.id == baselineScanId)) {
      final flaggedBaseline = procedureScans
          .where((entry) => entry.isBaseline)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      baselineScanId =
          flaggedBaseline.isNotEmpty ? flaggedBaseline.first.id : procedureScans.first.id;
    }

    final followUpScanId = scan.id;
    if (followUpScanId == baselineScanId) return null;

    return _ComparisonPair(
      baselineScanId: baselineScanId,
      followUpScanId: followUpScanId,
    );
  }
}

class _BaselineComparisonViewer extends StatelessWidget {
  const _BaselineComparisonViewer({
    required this.scans,
    required this.baselineScanId,
    required this.followUpScanId,
    required this.sourceResolver,
  });

  final List<ScanHistoryEntry> scans;
  final String baselineScanId;
  final String followUpScanId;
  final _PhotoSource Function(ScanHistoryEntry) sourceResolver;

  @override
  Widget build(BuildContext context) {
    ScanHistoryEntry? findById(String id) {
      for (final scan in scans) {
        if (scan.id == id) return scan;
      }
      return null;
    }

    final baseline = findById(baselineScanId);
    final followUp = findById(followUpScanId);

    if (baseline == null || followUp == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compare to Baseline')),
        body: const Center(
          child: Text('Unable to load baseline/follow-up pair.'),
        ),
      );
    }

    Widget imagePanel({
      required ScanHistoryEntry entry,
      required String label,
      required Color badgeColor,
    }) {
      final bytes = _PhotoGalleryScreenState._decodeImagePath(entry.imagePath);
      final source = sourceResolver(entry);
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borders),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        source.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.refinedSlate,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: bytes != null
                    ? Image.memory(bytes, fit: BoxFit.contain)
                    : const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: AppColors.refinedSlate,
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EC),
      appBar: AppBar(
        title: const Text('Compare to Baseline'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.refinedSlate,
      ),
      body: Row(
        children: [
          imagePanel(
            entry: baseline,
            label: 'BASELINE',
            badgeColor: const Color(0xFF2E7D32),
          ),
          imagePanel(
            entry: followUp,
            label: 'FOLLOW-UP',
            badgeColor: const Color(0xFF244A73),
          ),
        ],
      ),
    );
  }
}
