import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/barcode_reader.dart';
import '../utils/open_beauty_facts.dart';
import '../utils/product_lookup.dart';
import 'product_lookup_detail_screen.dart';

/// "Scan or search a product": find a product by name or by barcode and
/// open its basic info. Barcodes and submitted searches try Open Beauty
/// Facts first and fall back to the built-in list; typing filters the
/// built-in list instantly (no network). Free for everyone. No
/// recommendations.
class ProductLookupScreen extends StatefulWidget {
  const ProductLookupScreen({
    super.key,
    this.readBarcode = readProductBarcode,
    this.client,
  });

  /// Camera barcode reader; injectable for tests.
  final Future<BarcodeReadResult> Function() readBarcode;

  /// Open Beauty Facts client; injectable for tests.
  final OpenBeautyFactsClient? client;

  static const String unreachableText =
      'Couldn’t reach Open Beauty Facts — you may be offline or the service '
      'may be busy.';

  @override
  State<ProductLookupScreen> createState() => _ProductLookupScreenState();
}

class _ProductLookupScreenState extends State<ProductLookupScreen> {
  final _query = TextEditingController();
  late final OpenBeautyFactsClient _client =
      widget.client ?? OpenBeautyFactsClient();
  List<LookupProduct> _results = const [];
  List<LookupProduct> _saved = const [];
  String? _barcodeMessage;
  String? _searchNotice;
  bool _scanning = false;
  bool _loading = false;

  /// Bumped on every new lookup so a slow, stale response is ignored.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _query.dispose();
    if (widget.client == null) _client.close();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final saved = await loadSavedLookupProducts();
    if (mounted) setState(() => _saved = saved);
  }

  /// Typing: instant built-in matches, no network.
  void _search(String text) {
    _request++;
    setState(() {
      _results = searchProducts(text);
      _barcodeMessage = null;
      _searchNotice = null;
      _loading = false;
    });
  }

  /// Submitted search: Open Beauty Facts first, then the built-in list.
  Future<void> _searchOnline() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _barcodeMessage = null;
      _searchNotice = null;
    });
    final outcome = await lookupByName(query, _client);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _results = outcome.products;
      _searchNotice = outcome.unreachable
          ? '${ProductLookupScreen.unreachableText} Showing matches from the '
                'built-in list.'
          : outcome.fromOpenBeautyFacts
          ? null
          : 'No matches in Open Beauty Facts. Showing matches from the '
                'built-in list.';
    });
  }

  Future<void> _scanBarcode() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final result = await widget.readBarcode();
    if (!mounted) return;
    setState(() => _scanning = false);
    final String message;
    switch (result.status) {
      case BarcodeReadStatus.cancelled:
        return;
      case BarcodeReadStatus.unsupported:
        message =
            'Barcode scanning isn’t available on this device. '
            'Search by name instead.';
      case BarcodeReadStatus.noBarcode:
        message =
            'No barcode was found in the photo. Try again closer to the '
            'barcode, or search by name.';
      case BarcodeReadStatus.found:
        final code = result.code!;
        final request = ++_request;
        setState(() {
          _loading = true;
          _barcodeMessage = null;
        });
        final outcome = await lookupBarcode(code, _client);
        if (!mounted || request != _request) return;
        setState(() => _loading = false);
        if (outcome.products.isNotEmpty) {
          await _open(outcome.products.first);
          return;
        }
        message = outcome.unreachable
            ? 'Product not found for barcode $code. '
                  '${ProductLookupScreen.unreachableText} Try again when '
                  'connected, or search by name.'
            : 'Product not found for barcode $code in Open Beauty Facts or '
                  'the built-in list. Try searching by name.';
    }
    setState(() => _barcodeMessage = message);
  }

  Future<void> _open(LookupProduct product) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductLookupDetailScreen(product: product),
      ),
    );
    await _loadSaved();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.text.trim().isNotEmpty;
    final muted = AppColors.refinedSlate.withValues(alpha: 0.7);
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        backgroundColor: AppColors.warmAlabaster,
        elevation: 0,
        title: const Text('Scan or search a product'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            key: const ValueKey('product_search_field'),
            controller: _query,
            onChanged: _search,
            onSubmitted: (_) => _searchOnline(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by product or brand name',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                key: const ValueKey('product_search_online_button'),
                tooltip: 'Search Open Beauty Facts',
                icon: const Icon(Icons.travel_explore_rounded),
                onPressed: _loading ? null : _searchOnline,
              ),
              filled: true,
              fillColor: AppColors.cardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('product_scan_barcode_button'),
            onPressed: _scanning || _loading ? null : _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_scanning ? 'Scanning…' : 'Scan barcode'),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              key: ValueKey('product_lookup_loading'),
            ),
            const SizedBox(height: 6),
            Text(
              'Looking up Open Beauty Facts…',
              style: TextStyle(color: muted, fontSize: 12.5),
            ),
          ],
          if (_barcodeMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _barcodeMessage!,
              key: const ValueKey('product_barcode_message'),
              style: const TextStyle(
                color: AppColors.refinedSlate,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Press search to look up Open Beauty Facts, an open community '
            'database; typing filters a built-in list of '
            '${localProductCatalog.length} curated products, which also '
            'works offline. Product info only — not a recommendation.',
            key: const ValueKey('product_catalog_note'),
            style: TextStyle(fontSize: 12, height: 1.35, color: muted),
          ),
          const SizedBox(height: 14),
          if (searching && !_loading) ...[
            if (_searchNotice != null) ...[
              Text(
                _searchNotice!,
                key: const ValueKey('product_search_notice'),
                style: const TextStyle(
                  color: AppColors.refinedSlate,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_results.isEmpty)
              const Text(
                'No products match. Try a brand or a shorter name.',
                key: ValueKey('product_search_empty'),
                style: TextStyle(color: AppColors.refinedSlate),
              ),
            for (final product in _results) _productTile(product),
          ] else if (!searching && _saved.isNotEmpty) ...[
            const Text(
              'Saved for later',
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final product in _saved) _productTile(product),
          ],
        ],
      ),
    );
  }

  Widget _productTile(LookupProduct product) {
    final source = product.source == LookupSource.openBeautyFacts
        ? 'Open Beauty Facts'
        : 'Built-in list';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.cardBackground,
      child: ListTile(
        title: Text(product.name),
        subtitle: Text(
          product.brand == null ? source : '${product.brand} · $source',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(product),
      ),
    );
  }
}
