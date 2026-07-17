import 'package:flutter/material.dart';

import '../app_theme.dart';

// ── Subscription tier enum (used for dev/mock state) ─────────────────────────
enum MockSubscriptionTier { free, premium, pro }

// ─────────────────────────────────────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────────────────────────────────────
class PaywallSubscriptionScreen extends StatefulWidget {
  const PaywallSubscriptionScreen({super.key});

  @override
  State<PaywallSubscriptionScreen> createState() =>
      _PaywallSubscriptionScreenState();
}

class _PaywallSubscriptionScreenState extends State<PaywallSubscriptionScreen> {
  MockSubscriptionTier _activeTier = MockSubscriptionTier.free;
  bool _selectedYearly = false;

  bool get _isPremium =>
      _activeTier == MockSubscriptionTier.premium ||
      _activeTier == MockSubscriptionTier.pro;

  void _selectTier(MockSubscriptionTier tier) {
    setState(() => _activeTier = tier);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_tierName(tier)} mode enabled for testing.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleUpgrade() => _selectTier(MockSubscriptionTier.premium);

  void _restorePurchases() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Mock restore complete. Real billing connects at launch.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _tierName(MockSubscriptionTier tier) {
    switch (tier) {
      case MockSubscriptionTier.free:
        return 'Free';
      case MockSubscriptionTier.premium:
        return 'Premium';
      case MockSubscriptionTier.pro:
        return 'Pro';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.refinedSlate,
        centerTitle: true,
        title: const Text(
          'Go Premium',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero gradient header ──────────────────────────────────
              _HeroHeader(isPremium: _isPremium),
              // ── Main content ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    // Billing toggle
                    Center(
                      child: _BillingToggle(
                        yearly: _selectedYearly,
                        onToggle: (v) => setState(() => _selectedYearly = v),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Price display
                    _PriceDisplay(yearly: _selectedYearly),
                    const SizedBox(height: 30),
                    // Benefits list
                    const _BenefitsList(),
                    const SizedBox(height: 30),
                    // Primary CTA
                    _PrimaryCtaButton(
                      yearly: _selectedYearly,
                      isPremium: _isPremium,
                      onPressed: _handleUpgrade,
                    ),
                    if (!_isPremium) ...[
                      const SizedBox(height: 9),
                      Text(
                        _selectedYearly
                            ? r'7 days free, then $79.99/year. Cancel anytime.'
                            : r'7 days free, then $9.99/month. Cancel anytime.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.refinedSlate.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Direct purchase (skip trial)
                    _TrialButton(
                      yearly: _selectedYearly,
                      isPremium: _isPremium,
                      onPressed: _handleUpgrade,
                    ),
                    const SizedBox(height: 22),
                    // Trust row
                    const _TrustRow(),
                    const SizedBox(height: 22),
                    // Restore purchases
                    Center(
                      child: TextButton(
                        onPressed: _restorePurchases,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.goldHover,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Restore Purchases'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Legal
                    const _LegalDisclaimer(),
                    const SizedBox(height: 20),
                    // Developer mode (bottom of screen)
                    _DeveloperModeCard(
                      activeTier: _activeTier,
                      onChanged: _selectTier,
                    ),
                    const SizedBox(height: 36),
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

// ── Hero Header ───────────────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final bool isPremium;
  const _HeroHeader({required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.champagneGold.withValues(alpha: 0.22),
            AppColors.champagneGold.withValues(alpha: 0.06),
            AppColors.warmAlabaster,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Icon circle
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.champagneGold.withValues(alpha: 0.35),
                  AppColors.champagneGold.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
            child: Icon(
              isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.auto_awesome_rounded,
              color: AppColors.champagneGold,
              size: 33,
            ),
          ),
          const SizedBox(height: 20),
          if (isPremium)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.mutedSage.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: AppColors.mutedSage.withValues(alpha: 0.45),
                ),
              ),
              child: const Text(
                'Premium Active',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.mutedSage,
                ),
              ),
            )
          else ...[
            const Text(
              'Unlock Your Full Skin\nTransformation Journey',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                height: 1.18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
                color: AppColors.refinedSlate,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              'Go beyond basic tracking with unlimited logs,\nreal vision analysis, and personalized AI guidance.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.52,
                fontWeight: FontWeight.w500,
                color: AppColors.refinedSlate.withValues(alpha: 0.66),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Billing Toggle ────────────────────────────────────────────────────────────
class _BillingToggle extends StatelessWidget {
  final bool yearly;
  final ValueChanged<bool> onToggle;

  const _BillingToggle({required this.yearly, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.borders.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: AppColors.borders.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TogglePill(
            label: 'Monthly',
            selected: !yearly,
            onTap: () => onToggle(false),
          ),
          const SizedBox(width: 3),
          _TogglePill(
            label: 'Yearly',
            badge: 'Save 33%',
            selected: yearly,
            onTap: () => onToggle(true),
          ),
        ],
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final String label;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _TogglePill({
    required this.label,
    required this.selected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.champagneGold : Colors.transparent,
          borderRadius: BorderRadius.circular(46),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.champagneGold.withValues(alpha: 0.42),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected
                    ? AppColors.onChampagneGold
                    : AppColors.refinedSlate.withValues(alpha: 0.62),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.28)
                      : AppColors.champagneGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    color: selected
                        ? AppColors.onChampagneGold
                        : AppColors.goldHover,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Price Display ─────────────────────────────────────────────────────────────
class _PriceDisplay extends StatelessWidget {
  final bool yearly;
  const _PriceDisplay({required this.yearly});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              yearly ? r'$79.99' : r'$9.99',
              style: const TextStyle(
                fontSize: 54,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.5,
                color: AppColors.refinedSlate,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 5),
              child: Text(
                yearly ? '/year' : '/month',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.refinedSlate.withValues(alpha: 0.52),
                ),
              ),
            ),
          ],
        ),
        if (yearly) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.champagneGold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.4),
              ),
            ),
            child: const Text(
              r'Just $6.67/mo — best value',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.goldHover,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            r'or $79.99/yr — save 33%',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.refinedSlate.withValues(alpha: 0.48),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Benefits List ─────────────────────────────────────────────────────────────
class _BenefitsList extends StatelessWidget {
  const _BenefitsList();

  static const _items = [
    _BenefitData(
      Icons.all_inclusive_rounded,
      'Unlimited Procedure Logs & History',
      'Remove the 8-log cap — track every treatment, forever.',
    ),
    _BenefitData(
      Icons.remove_red_eye_rounded,
      'Full Gemini Vision Photo Analysis',
      'Real AI-powered skin assessment directly from your photos.',
    ),
    _BenefitData(
      Icons.insights_rounded,
      'Advanced AI Trend Insights & Progress Reports',
      'See exactly how your skin evolves over time.',
    ),
    _BenefitData(
      Icons.picture_as_pdf_rounded,
      'Export Treatment Journey (PDF)',
      'Download your complete procedure and progress history.',
    ),
    _BenefitData(
      Icons.psychology_rounded,
      'Priority AI Coach Responses',
      'Unlimited, faster, and more personalized AI guidance.',
    ),
    _BenefitData(
      Icons.do_not_disturb_on_rounded,
      'Completely Ad-Free Experience',
      'Pure, elegant skin tracking with zero interruptions.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(MyApp.cardRadiusValue),
        border: Border.all(
          color: AppColors.champagneGold.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.refinedSlate.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          const Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: AppColors.champagneGold,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Everything in Premium',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.refinedSlate,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: AppColors.champagneGold.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < _items.length; i++) ...[
            _BenefitItem(data: _items[i]),
            if (i < _items.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _BenefitData {
  final IconData icon;
  final String title;
  final String subtitle;
  const _BenefitData(this.icon, this.title, this.subtitle);
}

class _BenefitItem extends StatelessWidget {
  final _BenefitData data;
  const _BenefitItem({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.champagneGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.28),
              width: 0.8,
            ),
          ),
          child: Icon(data.icon, size: 18, color: AppColors.goldHover),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.refinedSlate,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColors.refinedSlate.withValues(alpha: 0.60),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: AppColors.goldHover,
        ),
      ],
    );
  }
}

// ── Primary CTA Button ────────────────────────────────────────────────────────
class _PrimaryCtaButton extends StatelessWidget {
  final bool yearly;
  final bool isPremium;
  final VoidCallback onPressed;

  const _PrimaryCtaButton({
    required this.yearly,
    required this.isPremium,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final label = isPremium ? 'Premium Active' : 'Try 7 Days Free';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.champagneGold.withValues(
              alpha: isPremium ? 0.15 : 0.45,
            ),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPremium
              ? AppColors.mutedSage
              : AppColors.champagneGold,
          foregroundColor: AppColors.onChampagneGold,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
}

// ── Trial CTA ─────────────────────────────────────────────────────────────────
class _TrialButton extends StatelessWidget {
  final bool isPremium;
  final bool yearly;
  final VoidCallback onPressed;

  const _TrialButton({
    required this.isPremium,
    required this.yearly,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.refinedSlate,
        side: BorderSide(
          color: AppColors.champagneGold.withValues(alpha: 0.55),
          width: 1.2,
        ),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        isPremium
            ? 'Already Unlocked'
            : yearly
            ? r'Start Premium now — $79.99/yr'
            : r'Start Premium now — $9.99/mo',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

// ── Trust Row ─────────────────────────────────────────────────────────────────
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _TrustBadge(icon: Icons.cancel_outlined, label: 'Cancel anytime'),
        _dot(),
        const _TrustBadge(
          icon: Icons.lock_outline_rounded,
          label: 'Secure payment',
        ),
        _dot(),
        const _TrustBadge(icon: Icons.refresh_rounded, label: '7-day trial'),
      ],
    );
  }

  Widget _dot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.refinedSlate.withValues(alpha: 0.3),
        shape: BoxShape.circle,
      ),
    ),
  );
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: AppColors.refinedSlate.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppColors.refinedSlate.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

// ── Legal Disclaimer ──────────────────────────────────────────────────────────
class _LegalDisclaimer extends StatelessWidget {
  const _LegalDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Subscriptions auto-renew unless cancelled 24 hours before the renewal date. '
      'AestheticSkinTracker is a personal wellness tracker, not a medical device. '
      'Payments are mocked for development — RevenueCat billing connects at launch.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.5,
        color: AppColors.refinedSlate.withValues(alpha: 0.48),
      ),
    );
  }
}

// ── Developer Mode Card ───────────────────────────────────────────────────────
class _DeveloperModeCard extends StatelessWidget {
  final MockSubscriptionTier activeTier;
  final ValueChanged<MockSubscriptionTier> onChanged;

  const _DeveloperModeCard({required this.activeTier, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _paywallCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 17, color: AppColors.goldHover),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Developer subscription state',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stateChip(MockSubscriptionTier.free, 'Free'),
              _stateChip(MockSubscriptionTier.premium, 'Premium'),
              _stateChip(MockSubscriptionTier.pro, 'Pro'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stateChip(MockSubscriptionTier tier, String label) {
    final selected = activeTier == tier;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onChanged(tier),
      selectedColor: AppColors.champagneGold,
      backgroundColor: AppColors.warmAlabaster,
      side: BorderSide(
        color: selected ? AppColors.champagneGold : AppColors.borders,
        width: selected ? 1.4 : 0.8,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: selected ? AppColors.onChampagneGold : AppColors.refinedSlate,
      ),
    );
  }
}

// ── Shared card decoration ────────────────────────────────────────────────────
BoxDecoration _paywallCardDecoration({bool glow = false}) {
  return BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(MyApp.cardRadiusValue),
    border: Border.all(
      color: glow
          ? AppColors.champagneGold.withValues(alpha: 0.38)
          : AppColors.borders.withValues(alpha: 0.92),
      width: glow ? 1.1 : 0.8,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.refinedSlate.withValues(alpha: 0.06),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
      if (glow)
        BoxShadow(
          color: AppColors.champagneGold.withValues(alpha: 0.12),
          blurRadius: 28,
          spreadRadius: 1,
          offset: const Offset(0, 10),
        ),
    ],
  );
}
