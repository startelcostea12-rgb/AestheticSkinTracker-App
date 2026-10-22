// Removing a tracked skincare product: swipe it away in the "Your Active
// Skincare" list, or use Remove on its details screen. Both confirm first.
// Only the tracked-product entry is deleted; past scans, journal entries and
// product feedback stay as they are.

import 'package:flutter/material.dart';

import '../models/product_tracker.dart';
import '../utils/app_prefs.dart';

/// Asks to confirm, then removes [product] from the tracked products.
/// True when it was removed.
Future<bool> confirmAndRemoveTrackedProduct(
  BuildContext context,
  TrackedProduct product,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Remove ${product.name}?'),
      content: const Text(
        'It will no longer be tracked in your skincare. Past scans and '
        'notes for it are kept.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('tracked_product_remove_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await AppPrefs.removeTrackedProduct(product.id);
  return true;
}

/// A tracked-product row that can be swiped left to remove it (after
/// confirming). [onRemoved] runs once it has been removed.
class RemovableTrackedProduct extends StatelessWidget {
  const RemovableTrackedProduct({
    super.key,
    required this.product,
    required this.onRemoved,
    required this.child,
  });

  final TrackedProduct product;
  final VoidCallback onRemoved;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('tracked_product_${product.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmAndRemoveTrackedProduct(context, product),
      onDismissed: (_) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('${product.name} removed.')));
        onRemoved();
      },
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
