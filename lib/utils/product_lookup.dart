/// Product lookup for "Scan or search a product": a small searchable local
/// catalog, saved-for-later products, and adding a product name to the
/// active routine.
///
/// First version limitation: there is no product or barcode API in the
/// project, so lookups run against a local catalog made from the curated
/// style lists (skincare_style_catalog.dart, read only). Those entries have
/// no barcodes and no ingredient data, so a barcode lookup reports "not
/// found" and the detail screen says ingredient data is unavailable rather
/// than guessing. No metric-based recommendations are made here.
library;

import 'dart:convert';

import 'app_prefs.dart';
import 'skincare_style_catalog.dart';

class LookupProduct {
  const LookupProduct({
    required this.name,
    this.brand,
    this.description,
    this.style,
    this.barcode,
    this.ingredients,
  });

  final String name;
  final String? brand;
  final String? description;
  final SkincareStyle? style;

  /// EAN/UPC digits, when the source provides them (none in the local
  /// catalog yet).
  final String? barcode;

  /// Key ingredients, when the source provides them. Null or empty means
  /// "no ingredient data" -- never filled in by guessing.
  final List<String>? ingredients;

  bool get hasIngredients => ingredients?.isNotEmpty ?? false;
}

/// Brand names for the local catalog, matched as a name prefix.
const List<String> _knownBrands = [
  'COSRX',
  'Beauty of Joseon',
  'Anua',
  'Some By Mi',
  'Laneige',
  'Innisfree',
  'Round Lab',
  'Torriden',
  'Isntree',
  'Purito',
  'Youth To The People',
  'Biossance',
  'The Ordinary',
  'Herbivore Botanicals',
  'True Botanicals',
  'Tata Harper',
  'Cocokind',
  'Farmacy',
  'Summer Fridays',
  'Versed',
  'CeraVe',
  'La Roche-Posay',
  'Paula’s Choice',
  'Neutrogena',
  'Vanicream',
  'Cetaphil',
  'Aveeno',
  'SkinCeuticals',
  'Alastin',
  'ZO Skin Health',
  'Obagi',
  'Differin',
  'Revision Skincare',
];

String? brandForProductName(String name) {
  for (final brand in _knownBrands) {
    if (name.startsWith(brand)) return brand;
  }
  return null;
}

/// The local catalog: every curated style product, once each.
final List<LookupProduct> localProductCatalog = [
  for (final products in skincareStyleCatalog.values)
    for (final p in products)
      LookupProduct(
        name: p.name,
        brand: brandForProductName(p.name),
        description: p.description,
        style: p.style,
      ),
];

String _normalize(String text) =>
    text.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ');

/// Case-insensitive search over name, brand and description; every word
/// of the query must match. An empty query returns nothing.
List<LookupProduct> searchProducts(
  String query, {
  List<LookupProduct>? catalog,
}) {
  final words = _normalize(
    query,
  ).split(' ').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final product in catalog ?? localProductCatalog)
      if (words.every(
        _normalize(
          '${product.name} ${product.brand ?? ''} ${product.description ?? ''}',
        ).contains,
      ))
        product,
  ];
}

/// The product with this barcode, or null when the catalog has none.
LookupProduct? productForBarcode(
  String barcode, {
  List<LookupProduct>? catalog,
}) {
  final code = barcode.trim();
  if (code.isEmpty) return null;
  for (final product in catalog ?? localProductCatalog) {
    if (product.barcode == code) return product;
  }
  return null;
}

/// Exact-name lookup (used to reopen saved products).
LookupProduct? productNamed(String name) {
  for (final product in localProductCatalog) {
    if (product.name == name) return product;
  }
  return null;
}

/// AppPrefs key holding saved-for-later product names as a JSON list.
const String savedProductsKey = 'saved_lookup_products';

Future<List<String>> loadSavedProducts() async {
  final raw = await AppPrefs.getString(savedProductsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [for (final item in decoded) item.toString()];
  } catch (_) {
    return const [];
  }
}

Future<void> saveProductForLater(String name) async {
  final saved = await loadSavedProducts();
  if (saved.contains(name)) return;
  await AppPrefs.setString(savedProductsKey, jsonEncode([...saved, name]));
}

Future<void> removeSavedProduct(String name) async {
  final saved = await loadSavedProducts();
  await AppPrefs.setString(
    savedProductsKey,
    jsonEncode([...saved.where((item) => item != name)]),
  );
}

/// Routine periods a product can be added to, as stored in the active
/// routine payload.
enum RoutinePeriod { morning, evening }

extension RoutinePeriodInfo on RoutinePeriod {
  String get stepsKey =>
      this == RoutinePeriod.morning ? 'morningSteps' : 'eveningSteps';
  String get label => this == RoutinePeriod.morning ? 'Morning' : 'Evening';
}

/// Appends [name] to one period of the active routine, keeping every other
/// field. Existing steps keep their positions, so today's checklist ticks
/// stay on the right steps. Returns false when there is no routine or the
/// product is already in that period.
Future<bool> addProductToActiveRoutine(
  String name,
  RoutinePeriod period,
) async {
  final routine = await AppPrefs.getActiveAiRoutine();
  if (routine == null) return false;
  final steps = [
    for (final item in (routine[period.stepsKey] as List? ?? const []))
      item.toString(),
  ];
  if (steps.contains(name)) return false;
  await AppPrefs.saveActiveAiRoutine({
    ...routine,
    period.stepsKey: [...steps, name],
  });
  return true;
}
