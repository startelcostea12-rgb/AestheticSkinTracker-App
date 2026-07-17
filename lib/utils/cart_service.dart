// lib/utils/cart_service.dart
//
// Lightweight in-memory + persistent shopping cart for the Product Store.
// Backed by SharedPreferences. Exposes a ChangeNotifier so the cart icon
// in the AppBar can show a live badge.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';

class CartItem {
  final String productId;
  int quantity;

  CartItem({required this.productId, this.quantity = 1});

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    productId: (json['productId'] ?? '').toString(),
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  );
}

class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  static const String _key = 'product_store_cart_v1';

  final List<CartItem> _items = [];
  bool _loaded = false;

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (sum, i) => sum + i.quantity);
  bool get isEmpty => _items.isEmpty;

  double get subtotal {
    var total = 0.0;
    for (final item in _items) {
      final product = ProductCatalog.byId(item.productId);
      if (product != null) total += product.price * item.quantity;
    }
    return total;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _items.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) {
              _items.add(CartItem.fromJson(Map<String, dynamic>.from(entry)));
            }
          }
        }
      } catch (_) {
        // Corrupt cart — ignore and start fresh.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  Future<void> add(String productId, {int quantity = 1}) async {
    await ensureLoaded();
    final existing = _items.indexWhere((e) => e.productId == productId);
    if (existing >= 0) {
      _items[existing].quantity += quantity;
    } else {
      _items.add(CartItem(productId: productId, quantity: quantity));
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setQuantity(String productId, int quantity) async {
    await ensureLoaded();
    final idx = _items.indexWhere((e) => e.productId == productId);
    if (idx < 0) return;
    if (quantity <= 0) {
      _items.removeAt(idx);
    } else {
      _items[idx].quantity = quantity;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String productId) async {
    await ensureLoaded();
    _items.removeWhere((e) => e.productId == productId);
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    await ensureLoaded();
    _items.clear();
    await _persist();
    notifyListeners();
  }
}
