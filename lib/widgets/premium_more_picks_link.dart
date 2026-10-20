// The one "See N more picks with Premium" link used by the home
// recommendation sections (For your concerns, Recommended for your style).

import 'package:flutter/material.dart';

String morePicksWithPremiumLabel(int hiddenCount) =>
    'See $hiddenCount more pick${hiddenCount == 1 ? '' : 's'} with Premium';

class PremiumMorePicksLink extends StatelessWidget {
  const PremiumMorePicksLink({
    super.key,
    required this.hiddenCount,
    required this.onPressed,
  });

  final int hiddenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.lock_outline_rounded, size: 16),
        label: Text(morePicksWithPremiumLabel(hiddenCount)),
      ),
    );
  }
}
