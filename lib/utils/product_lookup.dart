/// Product lookup for "Scan or search a product": a small searchable local
/// catalog, saved-for-later products, and adding a product name to the
/// active routine.
///
/// Online lookups go to Open Beauty Facts first (open_beauty_facts.dart);
/// the local catalog, made from the curated style lists
/// (skincare_style_catalog.dart, read only), is the fallback and works
/// offline. Local entries have no barcodes and no ingredient data, so the
/// detail screen says ingredient data is unavailable rather than guessing.
/// No metric-based recommendations are made here.
library;

import 'dart:convert';

import 'app_prefs.dart';
import 'skincare_style_catalog.dart';

/// Where a looked-up product's data came from.
enum LookupSource { local, openBeautyFacts }

class LookupProduct {
  const LookupProduct({
    required this.name,
    this.brand,
    this.description,
    this.style,
    this.barcode,
    this.ingredients,
    this.source = LookupSource.local,
  });

  /// Rebuilds a product saved with [toJson]; null when unreadable.
  static LookupProduct? fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final ingredients = json['ingredients'];
    return LookupProduct(
      name: name,
      brand: json['brand']?.toString(),
      description: json['description']?.toString(),
      barcode: json['barcode']?.toString(),
      ingredients: ingredients is List
          ? [for (final item in ingredients) item.toString()]
          : null,
      source: json['source'] == LookupSource.openBeautyFacts.name
          ? LookupSource.openBeautyFacts
          : LookupSource.local,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': ?brand,
    'description': ?description,
    'barcode': ?barcode,
    'ingredients': ?ingredients,
    'source': source.name,
  };

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

  final LookupSource source;

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

/// AppPrefs key holding saved-for-later products as a JSON list. Each item
/// is a local catalog product name, or a full product map (toJson) for
/// products that came from Open Beauty Facts.
const String savedProductsKey = 'saved_lookup_products';

Future<List<dynamic>> _loadSavedItems() async {
  final raw = await AppPrefs.getString(savedProductsKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : const [];
  } catch (_) {
    return const [];
  }
}

String? _savedItemName(dynamic item) =>
    item is Map ? item['name']?.toString() : item?.toString();

/// Names of the saved products, in saved order.
Future<List<String>> loadSavedProducts() async => [
  for (final item in await _loadSavedItems()) ?_savedItemName(item),
];

/// The saved products themselves (local names resolved via the catalog).
Future<List<LookupProduct>> loadSavedLookupProducts() async => [
  for (final item in await _loadSavedItems())
    if (item is Map)
      ?LookupProduct.fromJson(Map<String, dynamic>.from(item))
    else
      ?productNamed(item.toString()),
];

Future<void> saveProductForLater(String name) async {
  final saved = await _loadSavedItems();
  if (saved.map(_savedItemName).contains(name)) return;
  await AppPrefs.setString(savedProductsKey, jsonEncode([...saved, name]));
}

/// Saves [product]; online products keep their data so they reopen offline.
Future<void> saveLookupProductForLater(LookupProduct product) async {
  if (product.source == LookupSource.local) {
    return saveProductForLater(product.name);
  }
  final saved = await _loadSavedItems();
  if (saved.map(_savedItemName).contains(product.name)) return;
  await AppPrefs.setString(
    savedProductsKey,
    jsonEncode([...saved, product.toJson()]),
  );
}

Future<void> removeSavedProduct(String name) async {
  final saved = await _loadSavedItems();
  await AppPrefs.setString(
    savedProductsKey,
    jsonEncode([...saved.where((item) => _savedItemName(item) != name)]),
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
