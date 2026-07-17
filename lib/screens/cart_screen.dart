// lib/screens/cart_screen.dart
//
// Shopping cart with quantity controls and checkout.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/product.dart';
import '../utils/cart_service.dart';
import '../widgets/category_artwork.dart';
import '../widgets/clinical_section_header.dart';
import 'product_detail_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    CartService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _load() async {
    await CartService.instance.ensureLoaded();
    if (mounted) setState(() => _loading = false);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkout() async {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Checkout'),
        content: const Text(
          'Your order has been recorded. Secure payment processing will be available soon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MyApp.roseGold,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await CartService.instance.clear();
              if (!mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Order placed — cart cleared')),
              );
            },
            child: const Text('Place Order'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = CartService.instance.items;
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const ClinicalAppBarTitle(
          title: 'Your Cart',
          eyebrow: 'Checkout',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? _buildEmpty()
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final item = items[i];
                        final product = ProductCatalog.byId(item.productId);
                        if (product == null) {
                          return const SizedBox.shrink();
                        }
                        return _CartItemTile(
                          product: product,
                          quantity: item.quantity,
                        );
                      },
                    ),
                  ),
                  _buildCompleteYourRoutine(),
                  _buildSummary(),
                ],
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 72,
              color: MyApp.roseGold.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              'Your cart is empty',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyApp.textBrown,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Browse curated peptides, serums, and recovery essentials in the Store.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: MyApp.textBrown.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Continue Shopping'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.roseGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompleteYourRoutine() {
    final cartIds = CartService.instance.items.map((i) => i.productId).toSet();
    final suggestedIds = <String>{};
    for (final item in CartService.instance.items) {
      final p = ProductCatalog.byId(item.productId);
      if (p == null) continue;
      for (final cid in p.complementsIds) {
        if (!cartIds.contains(cid)) suggestedIds.add(cid);
      }
    }
    final suggestions = ProductCatalog.byIds(suggestedIds).take(6).toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      color: MyApp.champagne,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ClinicalSectionHeader(
            icon: Icons.auto_awesome,
            title: 'Complete Your Routine',
            eyebrow: 'Smart pairings',
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final p = suggestions[i];
                return SizedBox(
                  width: 132,
                  child: _SuggestionCard(
                    product: p,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailScreen(product: p),
                      ),
                    ),
                    onAdd: () async {
                      await CartService.instance.add(p.id);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text('${p.name} added to cart'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final subtotal = CartService.instance.subtotal;
    final shipping = subtotal > 0 ? 6.95 : 0.0;
    final total = subtotal + shipping;
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: MyApp.roseGold.withValues(alpha: 0.18)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryRow('Subtotal', subtotal),
          const SizedBox(height: 6),
          _summaryRow('Shipping', shipping),
          const Divider(height: 22),
          _summaryRow('Total', total, bold: true),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _checkout,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyApp.roseGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(
      fontSize: bold ? 15.5 : 13.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      color: MyApp.textBrown,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('\$${value.toStringAsFixed(2)}', style: style),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.product, required this.quantity});
  final Product product;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: CategoryArtwork(
                product: product,
                glyphSize: 28,
                compact: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: MyApp.textBrown,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${product.price.toStringAsFixed(2)} each',
                  style: TextStyle(
                    fontSize: 12,
                    color: MyApp.textBrown.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _miniBtn(
                      icon: Icons.remove,
                      onTap: () => CartService.instance.setQuantity(
                        product.id,
                        quantity - 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '$quantity',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: MyApp.textBrown,
                        ),
                      ),
                    ),
                    _miniBtn(
                      icon: Icons.add,
                      onTap: () => CartService.instance.setQuantity(
                        product.id,
                        quantity + 1,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: MyApp.textBrown.withValues(alpha: 0.6),
                      ),
                      onPressed: () => CartService.instance.remove(product.id),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBtn({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, size: 16, color: MyApp.textBrown),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.product,
    required this.onTap,
    required this.onAdd,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MyApp.roseGold.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                  child: CategoryArtwork(
                    product: product,
                    glyphSize: 28,
                    monogramSize: 14,
                    compact: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MyApp.textBrown,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\$${product.price.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: MyApp.textBrown,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onAdd,
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: MyApp.roseGold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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
}
