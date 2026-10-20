// Shared free-tier upsell wording and the one inline upsell link used by
// the home recommendation sections, so locked content reads the same
// everywhere: buttons say "See Premium", inline links say
// "See ... with Premium" with a lock icon.

import 'package:flutter/material.dart';

/// Label for every button that opens the paywall.
const String kSeePremiumLabel = 'See Premium';

String morePicksWithPremiumLabel(int hiddenCount) =>
    'See $hiddenCount more pick${hiddenCount == 1 ? '' : 's'} with Premium';

/// Inline "See ... with Premium" link with a lock icon.
class PremiumUpsellLink extends StatelessWidget {
  const PremiumUpsellLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
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
        label: Text(label),
      ),
    );
  }
}

/// "See N more picks with Premium".
class PremiumMorePicksLink extends StatelessWidget {
  const PremiumMorePicksLink({
    super.key,
    required this.hiddenCount,
    required this.onPressed,
  });

  final int hiddenCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PremiumUpsellLink(
    label: morePicksWithPremiumLabel(hiddenCount),
    onPressed: onPressed,
  );
}
