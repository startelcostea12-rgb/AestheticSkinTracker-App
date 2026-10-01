// lib/widgets/paywall_screen.dart
//
// Premium upgrade ("Upgrade to Premium") screen.
//
// Design goals:
//   • Match the clinical patient-portal style (navy / teal / rose-gold,
//     ClinicalSectionHeader, unified card spec).
//   • Clear Free vs Premium value comparison.
//   • Monthly / Annual toggle with savings badge.
//   • Surfaces the one-time Professional Report option as a secondary path.
//   • Testing-mode affordance: an explicit "Activate Test Premium" button
//     that instantly grants Premium locally without payment — visible on
//     web, in debug builds, or when the user has enabled testing mode in
//     Settings.
//
// On real devices the purchase flow drives RevenueCat; on web / desktop /
// testing it falls back to a local-unlock simulation so QA never blocks.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'dart:async' show unawaited;

import '../app_theme.dart';
import '../utils/conversion_analytics.dart';
import '../utils/premium_access.dart';
import 'clinical_section_header.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Offerings? _offerings;
  bool _annual = true;
  bool _purchasing = false;
  bool _restoring = false;
  bool _testingAvailable = false;
  bool _testingActive = false;
  String? _errorMessage;

  static const List<String> _premiumHighlights = <String>[
    'Unlimited Deep Analysis and scan history',
    'AI Recovery Coach with personalized follow-up guidance',
    'Professional Reports for provider conversations',
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    unawaited(
      ConversionAnalytics.track(
        ConversionEvent.paywallView,
        properties: <String, dynamic>{
          'surface': 'paywall_screen',
          'default_annual_selected': _annual,
        },
      ),
    );
    final available = await PremiumAccess.isTestingModeAvailable();
    final active = await PremiumAccess.isTestingPremiumActive();
    if (mounted) {
      setState(() {
        _testingAvailable = available;
        _testingActive = active;
      });
    }
    await _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    if (kIsWeb) return;
    try {
      if (!PremiumAccess.revenueCatConfigured) {
        throw StateError('RevenueCat is not configured for this build');
      }
      final offerings = await Purchases.getOfferings();
      if (mounted) {
        setState(() {
          _offerings = offerings;
          _errorMessage = null;
        });
      }
    } on MissingPluginException catch (e) {
      // Desktop may not register purchases plugin; do not block upgrade flow.
      debugPrint('[Paywall] Missing plugin on this platform: $e');
      if (!mounted) return;
      setState(() {
        _offerings = null;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Live pricing is temporarily unavailable. You can still continue with listed plan pricing.';
      });
      debugPrint('[Paywall] Failed to load offerings: $e');
    }
  }

  Package? get _selectedPackage {
    final current = _offerings?.current;
    if (current == null) return null;
    return _annual
        ? (current.annual ?? current.monthly)
        : (current.monthly ?? current.annual);
  }

  String get _selectedPriceDisplay {
    final pkg = _selectedPackage;
    if (pkg != null) return pkg.storeProduct.priceString;
    return _annual
        ? '${PremiumPlans.annualPriceDisplay} / year'
        : '${PremiumPlans.monthlyPriceDisplay} / month';
  }

  void _finishUnlock() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  Future<void> _purchase() async {
    if (!kIsWeb && _selectedPackage == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Live pricing is temporarily unavailable. You can still continue with listed plan pricing.';
      });
      return;
    }

    unawaited(
      ConversionAnalytics.track(
        ConversionEvent.trialStart,
        properties: <String, dynamic>{
          'surface': 'paywall_screen',
          'billing_cycle': _annual ? 'annual' : 'monthly',
          'channel': (kIsWeb || _selectedPackage == null)
              ? 'simulated'
              : 'store',
        },
      ),
    );

    setState(() {
      _purchasing = true;
      _errorMessage = null;
    });
    try {
      if (kIsWeb) {
        // Web has no store purchase path; keep the local QA simulation.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await PremiumAccess.setPremiumUnlocked(true);
        unawaited(
          ConversionAnalytics.track(
            ConversionEvent.subscribe,
            properties: <String, dynamic>{
              'surface': 'paywall_screen',
              'billing_cycle': _annual ? 'annual' : 'monthly',
              'channel': 'simulated',
            },
          ),
        );
        if (mounted) _showSuccessSnack('Welcome to Premium.');
        _finishUnlock();
        return;
      }

      if (!PremiumAccess.revenueCatConfigured) {
        throw StateError('RevenueCat is not configured for this build');
      }

      final result = await Purchases.purchase(
        PurchaseParams.package(_selectedPackage!),
      );
      final hasEntitlement = result.customerInfo.entitlements.active.isNotEmpty;
      if (hasEntitlement) {
        await PremiumAccess.setPremiumUnlocked(true);
        unawaited(
          ConversionAnalytics.track(
            ConversionEvent.subscribe,
            properties: <String, dynamic>{
              'surface': 'paywall_screen',
              'billing_cycle': _annual ? 'annual' : 'monthly',
              'channel': 'store',
            },
          ),
        );
        if (mounted) _showSuccessSnack('Welcome to Premium.');
        _finishUnlock();
      } else {
        setState(
          () => _errorMessage =
              'Purchase completed but no entitlement was returned. Please contact support.',
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Purchase could not be completed: $e');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restorePurchases() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Restore purchases is available on App Store and Google Play builds.';
      });
      return;
    }

    setState(() {
      _restoring = true;
      _errorMessage = null;
    });

    try {
      if (!PremiumAccess.revenueCatConfigured) {
        throw StateError('RevenueCat is not configured for this build');
      }
      final customerInfo = await Purchases.restorePurchases();
      final hasEntitlement = customerInfo.entitlements.active.isNotEmpty;
      await PremiumAccess.setPremiumUnlocked(hasEntitlement);

      if (!mounted) return;
      if (hasEntitlement) {
        _showSuccessSnack('Purchases restored successfully.');
        _finishUnlock();
      } else {
        setState(() {
          _errorMessage =
              'No active subscription was found for this account yet.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not restore purchases right now: $e';
      });
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _activateTestPremium() async {
    await PremiumAccess.setTestingPremium(true);
    if (!mounted) return;
    setState(() => _testingActive = true);
    _showSuccessSnack('Test Premium activated.');
    _finishUnlock();
  }

  Future<void> _deactivateTestPremium() async {
    await PremiumAccess.resetAllPremium();
    unawaited(
      ConversionAnalytics.track(
        ConversionEvent.churn,
        properties: <String, dynamic>{
          'surface': 'paywall_screen',
          'channel': 'testing_override',
          'reason': 'manual_reset_to_free',
        },
      ),
    );
    if (!mounted) return;
    setState(() => _testingActive = false);
    _showSuccessSnack('Reverted to Free tier.');
  }

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: MyApp.clinicalTeal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyApp.champagne,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: MyApp.textBrown,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const ClinicalAppBarTitle(
          title: 'Upgrade to Premium',
          eyebrow: 'Membership',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(),
              const SizedBox(height: 28),
              const ClinicalSectionHeader(
                icon: Icons.workspace_premium_outlined,
                title: 'Choose your plan',
                eyebrow: 'Membership tiers',
              ),
              const SizedBox(height: 14),
              _buildBillingToggle(),
              const SizedBox(height: 14),
              _buildPremiumCard(),
              const SizedBox(height: 16),
              _buildFreeCard(),
              const SizedBox(height: 28),
              _buildOneTimeReportCard(),
              if (_testingAvailable) ...[
                const SizedBox(height: 28),
                const ClinicalSectionHeader(
                  icon: Icons.bug_report_outlined,
                  title: 'Testing tools',
                  eyebrow: 'Development only',
                ),
                const SizedBox(height: 14),
                _buildTestingCard(),
              ],
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB74646),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Center(
                child: Text(
                  'Cancel anytime · Secure billing via App Store / Google Play',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: MyApp.clinicalMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero ──
  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.18),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [MyApp.goldShimmer, MyApp.roseGold],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MyApp.roseGold.withValues(alpha: 0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PREMIUM MEMBERSHIP',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: MyApp.roseGold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your full luxury recovery suite',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: MyApp.clinicalNavy,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Unlimited tracking for active recovery journeys, including Deep Analysis, AI coaching, and polished reports you can bring into real appointments.',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              fontWeight: FontWeight.w500,
              color: MyApp.clinicalSlate,
            ),
          ),
          const SizedBox(height: 14),
          ..._premiumHighlights.map(_buildHeroPoint),
        ],
      ),
    );
  }

  // ── Billing toggle ──
  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          _toggleSegment(
            label: 'Monthly',
            selected: !_annual,
            onTap: () => setState(() => _annual = false),
          ),
          _toggleSegment(
            label: 'Annual · Save 28%',
            selected: _annual,
            onTap: () => setState(() => _annual = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleSegment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? MyApp.clinicalNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: selected ? Colors.white : MyApp.clinicalSlate,
            ),
          ),
        ),
      ),
    );
  }

  // ── Plan cards ──
  Widget _buildPremiumCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.roseGold.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Premium',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [MyApp.goldShimmer, MyApp.roseGold],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'RECOMMENDED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _annual
                    ? PremiumPlans.annualMonthlyEquivalent
                    : PremiumPlans.monthlyPriceDisplay,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalNavy,
                  height: 1,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '/ month',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ),
            ],
          ),
          if (_annual) ...[
            const SizedBox(height: 4),
            Text(
              'Billed yearly · $_selectedPriceDisplay',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MyApp.clinicalMuted,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Billed monthly · $_selectedPriceDisplay',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MyApp.clinicalMuted,
              ),
            ),
          ],
          const SizedBox(height: 18),
          ...PremiumPlans.premiumValueLines.map(_buildValueRow),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_purchasing || _restoring) ? null : _purchase,
              style: ElevatedButton.styleFrom(
                backgroundColor: MyApp.clinicalNavy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MyApp.clinicalNavy.withValues(
                  alpha: 0.45,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _purchasing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Start Premium · $_selectedPriceDisplay',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: (_purchasing || _restoring) ? null : _restorePurchases,
              icon: _restoring
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded, size: 18),
              label: Text(
                _restoring ? 'Restoring…' : 'Restore purchases',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreeCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.roseGold.withValues(alpha: 0.14),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Free',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MyApp.clinicalNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: MyApp.clinicalSlate.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: MyApp.clinicalSlate.withValues(alpha: 0.30),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  'CURRENT',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: MyApp.clinicalSlate,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Start free with guided tracking, then upgrade only if you want unlimited AI analysis, unlimited scan history, and report-ready recovery support.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: MyApp.clinicalSlate,
            ),
          ),
          const SizedBox(height: 14),
          ...PremiumPlans.freeValueLines.map(_buildValueRow),
        ],
      ),
    );
  }

  Widget _buildOneTimeReportCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.clinicalTeal.withValues(alpha: 0.28),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MyApp.clinicalTeal.withValues(alpha: 0.14),
              border: Border.all(
                color: MyApp.clinicalTeal.withValues(alpha: 0.30),
                width: 0.8,
              ),
            ),
            child: Icon(
              Icons.description_outlined,
              color: MyApp.clinicalTeal,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Single Professional Report',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: MyApp.clinicalNavy,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'One-time unlock for a specific procedure · '
                  '${PremiumPlans.oneTimeReportPriceDisplay}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: MyApp.clinicalSlate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Best if you only need a polished shareable summary for one procedure.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: MyApp.clinicalMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPoint(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: MyApp.clinicalTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
                color: MyApp.clinicalSlate,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestingCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MyApp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.clinicalSlate.withValues(alpha: 0.28),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.science_outlined,
                color: MyApp.clinicalSlate,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _testingActive
                    ? 'Test Premium is ACTIVE'
                    : 'Test Premium is INACTIVE',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _testingActive
                      ? MyApp.clinicalTeal
                      : MyApp.clinicalSlate,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Instantly grant or revoke Premium access locally — no '
            'payment, no store. Use during development and QA only.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: MyApp.clinicalSlate,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingActive ? null : _activateTestPremium,
                  icon: const Icon(Icons.flash_on_rounded, size: 18),
                  label: const Text('Activate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MyApp.clinicalTeal,
                    side: BorderSide(
                      color: MyApp.clinicalTeal.withValues(alpha: 0.55),
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingActive ? _deactivateTestPremium : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset to Free'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MyApp.clinicalSlate,
                    side: BorderSide(
                      color: MyApp.clinicalSlate.withValues(alpha: 0.45),
                      width: 1,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed('/conversion-diagnostics');
              },
              icon: const Icon(Icons.monitor_heart_outlined, size: 18),
              label: const Text('Open Conversion Diagnostics'),
              style: OutlinedButton.styleFrom(
                foregroundColor: MyApp.clinicalSlate,
                side: BorderSide(
                  color: MyApp.clinicalSlate.withValues(alpha: 0.45),
                  width: 1,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueRow(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MyApp.clinicalTeal.withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.check_rounded,
              size: 13,
              color: MyApp.clinicalTeal,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: MyApp.clinicalSlate,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
