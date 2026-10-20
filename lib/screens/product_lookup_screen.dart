import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/barcode_reader.dart';
import '../utils/product_lookup.dart';
import 'product_lookup_detail_screen.dart';

/// "Scan or search a product": find a product by name or by barcode and
/// open its basic info. Free for everyone, no daily limit (lookups are
/// local). No recommendations.
class ProductLookupScreen extends StatefulWidget {
  const ProductLookupScreen({super.key, this.readBarcode = readProductBarcode});

  /// Camera barcode reader; injectable for tests.
  final Future<BarcodeReadResult> Function() readBarcode;

  @override
  State<ProductLookupScreen> createState() => _ProductLookupScreenState();
}

class _ProductLookupScreenState extends State<ProductLookupScreen> {
  final _query = TextEditingController();
  List<LookupProduct> _results = const [];
  List<String> _saved = const [];
  String? _barcodeMessage;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final saved = await loadSavedProducts();
    if (mounted) setState(() => _saved = saved);
  }

  void _search(String text) {
    setState(() {
      _results = searchProducts(text);
      _barcodeMessage = null;
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
        final product = productForBarcode(result.code!);
        if (product != null) {
          setState(() => _barcodeMessage = null);
          await _open(product);
          return;
        }
        message =
            'Product not found for barcode ${result.code}. The built-in '
            'list doesn’t include barcodes yet — search by name instead.';
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
    final savedProducts = [for (final name in _saved) ?productNamed(name)];
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
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by product or brand name',
              prefixIcon: const Icon(Icons.search_rounded),
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
            onPressed: _scanning ? null : _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(_scanning ? 'Scanning…' : 'Scan barcode'),
          ),
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
            'Searches a built-in list of ${localProductCatalog.length} '
            'curated products. Product info only — not a recommendation.',
            key: const ValueKey('product_catalog_note'),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.refinedSlate.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          if (searching) ...[
            if (_results.isEmpty)
              const Text(
                'No products match. Try a brand or a shorter name.',
                key: ValueKey('product_search_empty'),
                style: TextStyle(color: AppColors.refinedSlate),
              ),
            for (final product in _results) _productTile(product),
          ] else if (savedProducts.isNotEmpty) ...[
            const Text(
              'Saved for later',
              style: TextStyle(
                color: AppColors.refinedSlate,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final product in savedProducts) _productTile(product),
          ],
        ],
      ),
    );
  }

  Widget _productTile(LookupProduct product) {
    return Card(
      key: ValueKey('product_result_${product.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.cardBackground,
      child: ListTile(
        title: Text(product.name),
        subtitle: product.brand == null ? null : Text(product.brand!),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _open(product),
      ),
    );
  }
}
