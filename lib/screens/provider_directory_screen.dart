// lib/screens/provider_directory_screen.dart
//
// Smart, in-app provider directory. Users enter a zip code (or load their
// saved one), filter by board certification / rating / distance, and pick
// a provider to auto-fill into the procedure form.
//
// Returns the selected [Provider] via `Navigator.pop(context, provider)`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../models/provider_directory.dart';
import '../utils/app_prefs.dart';
import '../widgets/clinical_section_header.dart';

class ProviderDirectoryScreen extends StatefulWidget {
  const ProviderDirectoryScreen({
    super.key,
    this.initialZip,
    this.procedureType,
  });

  final String? initialZip;

  /// When the directory is opened from the procedure-logging flow, this
  /// is the procedure the user is currently logging (e.g. "Microneedling",
  /// "Botox", "Halo Laser"). When non-null the results are ranked
  /// specialists-first and matching cards show a "Best Match" badge.
  final String? procedureType;

  @override
  State<ProviderDirectoryScreen> createState() =>
      _ProviderDirectoryScreenState();
}

class _ProviderDirectoryScreenState extends State<ProviderDirectoryScreen> {
  late final TextEditingController _zipController;
  late final TextEditingController _queryController;

  bool _boardCertifiedOnly = true;
  double? _maxDistanceMiles;
  double _minRating = 4.0;
  bool _loadingPrefs = true;

  String _activeZip = '';
  String _activeLabel = ''; // Human-friendly resolved location label
  String _activeQuery = '';
  bool _isSearching = false;
  bool _zipInvalid = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _zipController = TextEditingController(text: widget.initialZip ?? '');
    _queryController = TextEditingController();
    _queryController.addListener(_onQueryChanged);
    _loadSavedZip();
    _loadUserProviders();
  }

  Future<void> _loadUserProviders() async {
    await ProviderDirectory.loadUserProviders();
    if (mounted) setState(() {});
  }

  // Triggered only by direct user typing (onChanged), NOT by programmatic
  // text assignment, so saved-location loading won't double-fire.
  void _onZipFieldChanged(String value) {
    final zip = value.trim();
    _debounce?.cancel();
    if (zip.isEmpty) {
      setState(() {
        _activeZip = '';
        _activeLabel = '';
        _zipInvalid = false;
        _isSearching = false;
      });
      return;
    }
    // 2 chars covers UK "M2" / city stubs; numerics still need 3.
    if (zip.length >= 2) {
      setState(() {
        _isSearching = true;
        _zipInvalid = false;
      });
      _debounce = Timer(const Duration(milliseconds: 500), _applyZipSearch);
    }
  }

  void _clearZip() {
    _debounce?.cancel();
    _zipController.clear();
    setState(() {
      _activeZip = '';
      _activeLabel = '';
      _zipInvalid = false;
      _isSearching = false;
    });
  }

  Future<void> _loadSavedZip() async {
    final savedZip = await AppPrefs.getUserZipCode();
    if (!mounted) return;
    setState(() {
      if (_zipController.text.trim().isEmpty && savedZip.isNotEmpty) {
        _zipController.text = savedZip;
        _activeZip = savedZip;
      } else {
        _activeZip = _zipController.text.trim();
      }
      _loadingPrefs = false;
    });
    if (_activeZip.isNotEmpty) {
      await AppPrefs.setUserZipCode(_activeZip);
    }
  }

  void _onQueryChanged() {
    setState(() {
      _activeQuery = _queryController.text.trim();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _zipController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _applyZipSearch() async {
    final raw = _zipController.text.trim();
    // Resolve to a global location (US zip, Canadian/UK postal, or city/country).
    final resolved = ProviderDirectory.resolveLocation(raw);
    // Input is "invalid" only when the user typed something we can't place.
    final invalid = raw.isNotEmpty && resolved == null;
    setState(() {
      _activeZip = (raw.isEmpty || invalid) ? '' : raw;
      _activeLabel = resolved?.label ?? '';
      _isSearching = false;
      _zipInvalid = invalid;
    });
    if (raw.isNotEmpty && !invalid) {
      await AppPrefs.setUserZipCode(raw);
    }
  }

  Future<void> _useSavedLocation() async {
    final savedZip = await AppPrefs.getUserZipCode();
    if (!mounted) return;
    if (savedZip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Save your zip code in Settings to enable quick lookup.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    _zipController.text = savedZip;
    await _applyZipSearch();
  }

  @override
  Widget build(BuildContext context) {
    final matches = ProviderDirectory.search(
      zip: _activeZip.isEmpty ? null : _activeZip,
      minRating: _minRating,
      boardCertifiedOnly: _boardCertifiedOnly,
      maxDistanceMiles: _maxDistanceMiles,
      query: _activeQuery.isEmpty ? null : _activeQuery,
      procedureType: widget.procedureType,
    );

    // Closest provider distance — drives header text and far-results banner.
    final closestMiles =
        (_activeZip.isNotEmpty &&
            matches.isNotEmpty &&
            matches.first.distanceMiles != null)
        ? matches.first.distanceMiles!
        : null;

    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.clinicalNavy,
        title: const ClinicalAppBarTitle(
          title: 'Find a Provider',
          eyebrow: 'Board-certified clinicians',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loadingPrefs
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchPanel(),
                  _buildFilterPanel(),
                  const Divider(height: 1, color: Colors.black12),
                  Expanded(child: _buildResults(matches, closestMiles)),
                ],
              ),
      ),
    );
  }

  // ── Search panel ──────────────────────────────────────────────────────
  Widget _buildSearchPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ClinicalSectionHeader(
            icon: Icons.location_on_outlined,
            title: 'Search by Location',
            eyebrow: 'Find nearby providers',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _zipController,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(40)],
                  onChanged: _onZipFieldChanged,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _applyZipSearch();
                  },
                  decoration: _buildInputDecoration(
                    hint: 'Zip, postal code, or city',
                    icon: Icons.public_rounded,
                    suffix: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                              ),
                            ),
                          )
                        : _zipController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: _clearZip,
                            color: MyApp.clinicalSlate,
                            tooltip: 'Clear',
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () {
                    _debounce?.cancel();
                    _applyZipSearch();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MyApp.roseGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Invalid zip-code error (fewer than 3 digits)
          if (_zipInvalid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: MyApp.roseGold,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "We couldn't place that location. Try a zip, postal code, or city name (e.g. \"London\", \"M5V 3A1\", \"Seoul\").",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: MyApp.roseGold,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _useSavedLocation,
              icon: const Icon(Icons.my_location_rounded, size: 16),
              label: const Text(
                'Use saved zip code',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyApp.clinicalTeal,
                side: BorderSide(color: MyApp.clinicalTeal, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            decoration: _buildInputDecoration(
              hint: 'Try: "best halo laser near me"',
              icon: Icons.auto_awesome_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────
  Widget _buildFilterPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FILTERS',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: MyApp.clinicalSlate,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFilterChip(
                label: 'Board Certified',
                icon: Icons.verified_rounded,
                selected: _boardCertifiedOnly,
                onChanged: (v) => setState(() => _boardCertifiedOnly = v),
              ),
              _buildFilterChip(
                label: '4.0+ Rating',
                icon: Icons.star_rounded,
                selected: _minRating >= 4.0,
                onChanged: (v) => setState(() => _minRating = v ? 4.0 : 0.0),
              ),
              _buildDistanceDropdown(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceDropdown() {
    final label = _maxDistanceMiles == null
        ? 'Distance'
        : _maxDistanceMiles == 10
        ? '< 10 mi'
        : _maxDistanceMiles == 15
        ? '< 15 mi'
        : _maxDistanceMiles == 30
        ? '< 30 mi'
        : '< 50 mi';
    final isSelected = _maxDistanceMiles != null;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          builder: (_) => Container(
            color: MyApp.champagne,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        'Maximum Distance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: MyApp.clinicalNavy,
                        ),
                      ),
                    ),
                    for (final dist in [10.0, 15.0, 30.0, 50.0])
                      ListTile(
                        title: Text(
                          dist == 10
                              ? 'Within 10 miles'
                              : dist == 15
                              ? 'Within 15 miles'
                              : dist == 30
                              ? 'Within 30 miles'
                              : 'Within 50 miles',
                          style: TextStyle(
                            fontSize: 15,
                            color: MyApp.clinicalNavy,
                            fontWeight: _maxDistanceMiles == dist
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                        trailing: _maxDistanceMiles == dist
                            ? Icon(
                                Icons.check_rounded,
                                color: MyApp.clinicalTeal,
                              )
                            : null,
                        onTap: () {
                          setState(() => _maxDistanceMiles = dist);
                          Navigator.pop(context);
                        },
                      ),
                    ListTile(
                      title: Text(
                        'No distance limit',
                        style: TextStyle(
                          fontSize: 15,
                          color: MyApp.clinicalNavy,
                          fontWeight: _maxDistanceMiles == null
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      trailing: _maxDistanceMiles == null
                          ? Icon(Icons.check_rounded, color: MyApp.clinicalTeal)
                          : null,
                      onTap: () {
                        setState(() => _maxDistanceMiles = null);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? MyApp.roseGold : MyApp.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? MyApp.roseGold
                : MyApp.clinicalSlate.withValues(alpha: 0.25),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_car_outlined,
              size: 14,
              color: isSelected ? Colors.white : MyApp.roseGold,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : MyApp.clinicalSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? MyApp.clinicalTeal : MyApp.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? MyApp.clinicalTeal
                : MyApp.clinicalSlate.withValues(alpha: 0.25),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : MyApp.clinicalTeal,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : MyApp.clinicalSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────
  Widget _buildResults(List<ProviderMatch> matches, double? closestMiles) {
    if (matches.isEmpty) return _buildEmpty();

    // Providers are considered "nearby" if the closest is within 100 miles.
    const nearbyThreshold = 100.0;
    final hasZip = _activeZip.isNotEmpty;
    final displayLabel = _activeLabel.isNotEmpty ? _activeLabel : _activeZip;
    final isFar = closestMiles != null && closestMiles > nearbyThreshold;
    // Show the far-results banner only when no distance filter is active
    // (distance-filter empty state is handled separately by _buildDistanceFallback).
    final showBanner = isFar && _maxDistanceMiles == null;

    final procedureType = widget.procedureType?.trim();
    final hasProcedure = procedureType != null && procedureType.isNotEmpty;
    final specialistCount = matches.where((m) => m.isSpecialistMatch).length;
    final forSuffix = hasProcedure ? ' for $procedureType' : '';

    final title = hasZip
        ? (isFar
              ? 'Sorted by distance from $displayLabel$forSuffix'
              : 'Providers near $displayLabel$forSuffix')
        : (hasProcedure ? 'Providers$forSuffix' : 'Available Providers');
    final hasQuery = _activeQuery.isNotEmpty;
    final aiRanked = hasProcedure || hasQuery;
    final baseEyebrow = hasZip && closestMiles != null
        ? (isFar
              ? 'Closest: ${closestMiles.round()} mi away'
              : '${matches.length} match${matches.length == 1 ? '' : 'es'} · closest ${closestMiles.round()} mi')
        : '${matches.length} match${matches.length == 1 ? '' : 'es'} found';
    final eyebrow = aiRanked
        ? 'AI-ranked by relevance · $baseEyebrow'
        : baseEyebrow;

    // Optional context line when a procedure is set and at least one
    // specialist match was found.
    final showProcedureContext = hasProcedure && specialistCount > 0;
    final headerExtras = showProcedureContext ? 1 : 0;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: matches.length + 1 + headerExtras + (showBanner ? 1 : 0) + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ClinicalSectionHeader(
              icon: Icons.local_hospital_outlined,
              title: title,
              eyebrow: eyebrow,
            ),
          );
        }
        if (showProcedureContext && i == 1) {
          return _buildProcedureContextChip(procedureType, specialistCount);
        }
        if (showBanner && i == 1 + headerExtras) {
          return _buildFarResultsBanner(closestMiles);
        }
        // Trailing "Add a Provider" footer.
        if (i == matches.length + 1 + headerExtras + (showBanner ? 1 : 0)) {
          return _buildAddProviderFooter();
        }
        final index = i - 1 - headerExtras - (showBanner ? 1 : 0);
        final match = matches[index];
        return _ProviderCard(
          match: match,
          procedureType: widget.procedureType,
          onTap: () => Navigator.of(context).pop(match.provider),
        );
      },
    );
  }

  /// Bottom-of-list footer that lets users add their own provider to the
  /// directory. Saves locally and re-runs the search.
  Widget _buildAddProviderFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        onPressed: _openAddProviderSheet,
        icon: const Icon(Icons.add_business_rounded, size: 17),
        label: const Text(
          'Add a Provider',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: MyApp.roseGold,
          side: BorderSide(color: MyApp.roseGold, width: 1.2),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddProviderSheet() async {
    final added = await showModalBottomSheet<Provider>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddProviderSheet(),
    );
    if (added == null || !mounted) return;
    setState(() {}); // Refresh search results to include the new provider.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${added.name} added to your directory.'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Subtle teal info chip shown directly under the results header when a
  /// procedureType is supplied and one or more specialists matched.
  Widget _buildProcedureContextChip(String procedureType, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: MyApp.clinicalTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: MyApp.clinicalTeal.withValues(alpha: 0.22),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 15, color: MyApp.clinicalTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count provider${count == 1 ? '' : 's'} specialise in $procedureType.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: MyApp.clinicalNavy,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Inline banner shown when all results are more than 100 miles away.
  Widget _buildFarResultsBanner(double closestMiles) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: MyApp.clinicalTeal.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: MyApp.clinicalTeal.withValues(alpha: 0.22),
          width: 0.9,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_searching_rounded,
                size: 15,
                color: MyApp.clinicalTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No providers within 100 miles of\u00a0${_activeLabel.isNotEmpty ? _activeLabel : _activeZip}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Showing all providers sorted by distance. '
            'The closest is ${closestMiles.round()} miles away.',
            style: TextStyle(
              fontSize: 12,
              color: MyApp.clinicalSlate,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text(
                'Enter Provider Manually',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyApp.roseGold,
                side: BorderSide(color: MyApp.roseGold, width: 1.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    // When a valid zip + distance filter produced no results, show the
    // targeted fallback with a one-tap "expand search" action.
    if (_activeZip.isNotEmpty && _maxDistanceMiles != null) {
      return _buildDistanceFallback();
    }
    // Generic empty state (no zip, or only query/rating/cert filters)
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MyApp.roseGold.withValues(alpha: 0.15),
                    MyApp.clinicalTeal.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyApp.roseGold.withValues(alpha: 0.28),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 40,
                color: MyApp.roseGold,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No providers match your search',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: MyApp.clinicalNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters, search terms, or zip code.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: MyApp.clinicalSlate,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  _debounce?.cancel();
                  setState(() {
                    _boardCertifiedOnly = true;
                    _minRating = 4.0;
                    _maxDistanceMiles = null;
                    _activeQuery = '';
                    _queryController.clear();
                  });
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text(
                  'Reset Filters',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyApp.clinicalTeal,
                  side: BorderSide(color: MyApp.clinicalTeal, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Enter Provider Manually',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyApp.roseGold,
                  side: BorderSide(color: MyApp.roseGold, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when a valid zip + distance filter returns zero results.
  /// Lets the user instantly expand the search to all providers sorted
  /// by distance, or go back and enter a provider manually.
  Widget _buildDistanceFallback() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    MyApp.clinicalTeal.withValues(alpha: 0.15),
                    MyApp.roseGold.withValues(alpha: 0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyApp.clinicalTeal.withValues(alpha: 0.28),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.location_off_rounded,
                size: 40,
                color: MyApp.clinicalTeal,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No providers within '
              '${_maxDistanceMiles!.round()} miles',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: MyApp.clinicalNavy,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No providers in our directory are within your selected range'
              ' of ${_activeLabel.isNotEmpty ? _activeLabel : _activeZip}. '
              'You can expand to see all providers sorted by distance — '
              'or enter a provider manually on the previous screen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: MyApp.clinicalSlate,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            // Primary CTA: expand search
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => setState(() => _maxDistanceMiles = null),
                icon: const Icon(Icons.expand_outlined, size: 17),
                label: const Text(
                  'Show All Providers (sorted by distance)',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: MyApp.clinicalTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Secondary CTA: manual entry
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text(
                  'Enter Provider Manually',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MyApp.roseGold,
                  side: BorderSide(color: MyApp.roseGold, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Tertiary: try different distance
            TextButton(
              onPressed: () {
                setState(() => _maxDistanceMiles = null);
              },
              child: Text(
                'Or try a different distance filter',
                style: TextStyle(
                  fontSize: 12.5,
                  color: MyApp.clinicalSlate,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: MyApp.roseGold.withValues(alpha: 0.8)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: MyApp.clinicalSlate.withValues(alpha: 0.15),
          width: 0.9,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: MyApp.clinicalSlate.withValues(alpha: 0.15),
          width: 0.9,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: MyApp.roseGold, width: 1.4),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Provider card
// ═════════════════════════════════════════════════════════════════════════

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.match,
    required this.onTap,
    this.procedureType,
  });

  final ProviderMatch match;
  final VoidCallback onTap;
  final String? procedureType;

  @override
  Widget build(BuildContext context) {
    final p = match.provider;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MyApp.roseGold.withValues(alpha: 0.22),
            width: 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: MyApp.clinicalNavy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Best Match for [Procedure]" badge — only when this card is
            // marked as a specialist for the supplied procedureType.
            if (match.isSpecialistMatch &&
                procedureType != null &&
                procedureType!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: MyApp.clinicalTeal,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.30),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Best Match for ${procedureType!.trim()}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            // Provider header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        MyApp.goldShimmer.withValues(alpha: 0.85),
                        MyApp.roseGold.withValues(alpha: 0.75),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: MyApp.roseGold.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_hospital_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: MyApp.clinicalNavy,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          if (p.boardCertified && p.rating >= 4.8)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: MyApp.roseGold.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: MyApp.roseGold.withValues(
                                      alpha: 0.32,
                                    ),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: MyApp.roseGold,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Top Rated',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: MyApp.roseGold,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.clinicName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: MyApp.clinicalTeal,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.cityState,
                        style: TextStyle(
                          fontSize: 12,
                          color: MyApp.clinicalSlate,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _DistancePill(label: match.distanceLabel),
                    const SizedBox(height: 8),
                    _RatingBadge(rating: p.rating),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Specialties
            if (p.specialties.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in p.specialties.take(4))
                      Builder(
                        builder: (_) {
                          final isMatch =
                              ProviderDirectory.specialtyMatchesProcedure(
                                s,
                                procedureType,
                              );
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isMatch
                                  ? MyApp.roseGold.withValues(alpha: 0.18)
                                  : MyApp.clinicalTeal.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isMatch
                                    ? MyApp.roseGold.withValues(alpha: 0.55)
                                    : MyApp.clinicalTeal.withValues(
                                        alpha: 0.22,
                                      ),
                                width: isMatch ? 1.1 : 0.7,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMatch) ...[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 11,
                                    color: MyApp.roseGold,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  s,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: isMatch
                                        ? MyApp.roseGold
                                        : MyApp.clinicalTeal,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            // Footer: board certified + select action
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (p.boardCertified) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: MyApp.clinicalTeal.withValues(alpha: 0.28),
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_rounded,
                          size: 13,
                          color: MyApp.clinicalTeal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Board Certified',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: MyApp.clinicalTeal,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                ] else
                  const Spacer(),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: MyApp.roseGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Select',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 14),
                      ],
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
}

class _DistancePill extends StatelessWidget {
  const _DistancePill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: MyApp.roseGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.28),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: MyApp.roseGold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});
  final double rating;
  @override
  Widget build(BuildContext context) {
    final full = rating.floor();
    final hasHalf = (rating - full) >= 0.5;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < full
                ? Icons.star_rounded
                : (i == full && hasHalf
                      ? Icons.star_half_rounded
                      : Icons.star_outline_rounded),
            size: 14,
            color: MyApp.goldShimmer,
          ),
        const SizedBox(width: 5),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: MyApp.clinicalNavy,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

// ── Add-a-Provider bottom sheet ──────────────────────────────────────
//
// Simple in-app form that lets users save a provider locally. The
// provider is auto-geo-located via `ProviderDirectory.resolveLocation`
// using the city/country the user typed, so future searches can sort
// it by distance alongside the curated list.
class _AddProviderSheet extends StatefulWidget {
  const _AddProviderSheet();
  @override
  State<_AddProviderSheet> createState() => _AddProviderSheetState();
}

class _AddProviderSheetState extends State<_AddProviderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _clinicCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _specialtiesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _clinicCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _specialtiesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    final clinic = _clinicCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final stateOrCountry = _stateCtrl.text.trim();
    final specialties = _specialtiesCtrl.text
        .split(RegExp(r'[,;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Try to geo-locate by city, then "city, state", then state/country.
    final resolved =
        ProviderDirectory.resolveLocation(city) ??
        ProviderDirectory.resolveLocation('$city $stateOrCountry') ??
        ProviderDirectory.resolveLocation(stateOrCountry);

    final provider = Provider(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      clinicName: clinic.isEmpty ? name : clinic,
      address: '',
      city: city,
      state: stateOrCountry,
      zip: '',
      lat: resolved?.lat ?? 0.0,
      lng: resolved?.lng ?? 0.0,
      rating: 4.7,
      specialties: specialties.isEmpty
          ? const ['General Aesthetics']
          : specialties,
      boardCertified: true,
    );

    await ProviderDirectory.addUserProvider(provider);
    if (!mounted) return;
    Navigator.of(context).pop(provider);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: MyApp.champagne,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MyApp.clinicalSlate.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.add_business_rounded,
                        size: 20,
                        color: MyApp.roseGold,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Add a Provider',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: MyApp.clinicalNavy,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Saved locally to your directory. They\u2019ll appear '
                    'in future searches alongside our curated list.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: MyApp.clinicalSlate,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sheetField(
                    controller: _nameCtrl,
                    label: 'Provider name',
                    hint: 'e.g. Provider name',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _sheetField(
                    controller: _clinicCtrl,
                    label: 'Clinic / Medspa',
                    hint: 'e.g. Glow Aesthetics',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _sheetField(
                          controller: _cityCtrl,
                          label: 'City',
                          hint: 'e.g. Seoul',
                          required: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _sheetField(
                          controller: _stateCtrl,
                          label: 'State / Country',
                          hint: 'e.g. South Korea',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sheetField(
                    controller: _specialtiesCtrl,
                    label: 'Specialties',
                    hint: 'Botox, Filler, Microneedling',
                    helper: 'Comma-separated. Used for procedure matching.',
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        _saving ? 'Saving…' : 'Save Provider',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: MyApp.roseGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MyApp.clinicalSlate,
                        ),
                      ),
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

  Widget _sheetField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? helper,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            color: MyApp.clinicalSlate,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty)
                    ? '$label is required'
                    : null
              : null,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: MyApp.clinicalSlate.withValues(alpha: 0.15),
                width: 0.9,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: MyApp.clinicalSlate.withValues(alpha: 0.15),
                width: 0.9,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: MyApp.roseGold, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
