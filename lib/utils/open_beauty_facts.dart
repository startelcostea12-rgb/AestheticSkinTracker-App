/// Open Beauty Facts (https://world.openbeautyfacts.org), a free, open
/// community database of cosmetic products, for barcode and name lookups.
/// Data is ODbL-licensed and may be incomplete; nothing is filled in when a
/// field is missing. Every lookup falls back to the local catalog when the
/// service is unreachable or has no match (see [lookupBarcode] and
/// [lookupByName]).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'product_lookup.dart';

/// The service could not be reached or gave an unusable answer (offline,
/// timeout, server error, rate limit, malformed response).
class OpenBeautyFactsUnavailable implements Exception {
  const OpenBeautyFactsUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'OpenBeautyFactsUnavailable: $reason';
}

class OpenBeautyFactsClient {
  OpenBeautyFactsClient({
    http.Client? client,
    this.baseUrl = 'https://world.openbeautyfacts.org',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  /// Open Beauty Facts asks apps to identify themselves.
  static const Map<String, String> _headers = {
    'User-Agent': 'AestheticSkinTracker/1.0 (Flutter)',
    'Accept': 'application/json',
  };

  static const String _fields =
      'code,product_name,product_name_en,brands,ingredients_text,'
      'ingredients_text_en,ingredients';

  Future<Map<String, dynamic>?> _getJson(
    Uri uri, {
    bool allow404 = false,
  }) async {
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers).timeout(timeout);
    } catch (error) {
      throw OpenBeautyFactsUnavailable('$error');
    }
    if (allow404 && response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw OpenBeautyFactsUnavailable('HTTP ${response.statusCode}');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const OpenBeautyFactsUnavailable('malformed response');
  }

  /// The product for an EAN/UPC barcode, or null when it isn't listed.
  Future<LookupProduct?> productByBarcode(String barcode) async {
    final code = barcode.trim();
    if (!RegExp(r'^\d{6,14}$').hasMatch(code)) return null;
    final json = await _getJson(
      Uri.parse('$baseUrl/api/v2/product/$code.json?fields=$_fields'),
      allow404: true,
    );
    if (json == null || json['status'] != 1) return null;
    final product = json['product'];
    if (product is! Map) return null;
    return productFromOpenBeautyFacts(
      Map<String, dynamic>.from(product),
      fallbackBarcode: code,
    );
  }

  /// Up to [limit] products matching [query] by name.
  Future<List<LookupProduct>> searchByName(
    String query, {
    int limit = 10,
  }) async {
    final terms = query.trim();
    if (terms.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': terms,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '$limit',
        'fields': _fields,
      },
    );
    final json = await _getJson(uri);
    final products = json?['products'];
    if (products is! List) return const [];
    return [
      for (final item in products)
        if (item is Map)
          ?productFromOpenBeautyFacts(Map<String, dynamic>.from(item)),
    ].take(limit).toList();
  }

  void close() => _client.close();
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Maps one Open Beauty Facts product. Null when it has no name (search
/// results without a name are not shown); a barcode lookup keeps a named
/// placeholder so the scanned product can still be opened.
LookupProduct? productFromOpenBeautyFacts(
  Map<String, dynamic> json, {
  String? fallbackBarcode,
}) {
  final barcode = _text(json['code']) ?? fallbackBarcode;
  final name =
      _text(json['product_name']) ??
      _text(json['product_name_en']) ??
      (fallbackBarcode == null ? null : 'Unnamed product ($barcode)');
  if (name == null) return null;
  return LookupProduct(
    name: name,
    brand: _text(json['brands']),
    barcode: barcode,
    ingredients: ingredientsFromOpenBeautyFacts(json),
    source: LookupSource.openBeautyFacts,
  );
}

/// The ingredient names exactly as listed (structured list first, then the
/// ingredients text split on top-level commas); null when there are none.
List<String>? ingredientsFromOpenBeautyFacts(Map<String, dynamic> json) {
  final out = <String>[];
  void add(String? raw) {
    final cleaned = raw
        ?.trim()
        .replaceAll(RegExp(r'^[_*\s]+|[_*.\s]+$'), '')
        .trim();
    if (cleaned != null && cleaned.isNotEmpty && !out.contains(cleaned)) {
      out.add(cleaned);
    }
  }

  final structured = json['ingredients'];
  if (structured is List) {
    for (final item in structured) {
      if (item is Map) add(_text(item['text']));
    }
  }
  if (out.isEmpty) {
    final text =
        _text(json['ingredients_text_en']) ?? _text(json['ingredients_text']);
    if (text != null) {
      var depth = 0;
      var start = 0;
      for (var i = 0; i < text.length; i++) {
        final char = text[i];
        if (char == '(' || char == '[') depth++;
        if ((char == ')' || char == ']') && depth > 0) depth--;
        if (char == ',' && depth == 0) {
          add(text.substring(start, i));
          start = i + 1;
        }
      }
      add(text.substring(start));
    }
  }
  return out.isEmpty ? null : out;
}

/// The outcome of a lookup that tries Open Beauty Facts first.
class LookupOutcome {
  const LookupOutcome(this.products, {this.unreachable = false});

  /// Open Beauty Facts results, or local-catalog fallbacks.
  final List<LookupProduct> products;

  /// True when Open Beauty Facts could not be reached (results, if any,
  /// are from the local catalog).
  final bool unreachable;

  bool get fromOpenBeautyFacts =>
      products.isNotEmpty &&
      products.first.source == LookupSource.openBeautyFacts;
}

/// Barcode: Open Beauty Facts, then the local catalog.
Future<LookupOutcome> lookupBarcode(
  String barcode,
  OpenBeautyFactsClient client,
) async {
  var unreachable = false;
  try {
    final product = await client.productByBarcode(barcode);
    if (product != null) return LookupOutcome([product]);
  } on OpenBeautyFactsUnavailable {
    unreachable = true;
  }
  final local = productForBarcode(barcode);
  return LookupOutcome([?local], unreachable: unreachable);
}

/// Name search: Open Beauty Facts (up to [limit]), then the local catalog.
Future<LookupOutcome> lookupByName(
  String query,
  OpenBeautyFactsClient client, {
  int limit = 10,
}) async {
  var unreachable = false;
  try {
    final products = await client.searchByName(query, limit: limit);
    if (products.isNotEmpty) return LookupOutcome(products);
  } on OpenBeautyFactsUnavailable {
    unreachable = true;
  }
  return LookupOutcome(searchProducts(query), unreachable: unreachable);
}
