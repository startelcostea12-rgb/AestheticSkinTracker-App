// lib/widgets/report_paywall_sheet.dart
//
// Clinical "Unlock Professional Report" bottom sheet shown to FREE users
// when they tap "Generate Professional Report" / "Export Report".
//
// Two CTAs:
//   1. Buy this single report for the one-time price (ReportPurchase).
//   2. Upgrade to Premium for unlimited reports (routes to /paywall).
//
// Returns `true` from the showXxx helper when the report should now be
// generated (either because the one-time purchase succeeded, or because
// the user became premium during the upgrade flow).

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/premium_access.dart';
import '../utils/report_purchase.dart';
import 'clinical_section_header.dart';

/// Shows the clinical paywall sheet for the Professional Report.
///
/// Returns `true` if the user is now entitled to generate the report.
Future<bool> showReportPaywallSheet(
  BuildContext context, {
  required String procedureId,
  String? procedureName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _ReportPaywallSheet(
      procedureId: procedureId,
      procedureName: procedureName,
    ),
  );
  return result == true;
}

class _ReportPaywallSheet extends StatefulWidget {
  const _ReportPaywallSheet({
    required this.procedureId,
    required this.procedureName,
  });

  final String procedureId;
  final String? procedureName;

  @override
  State<_ReportPaywallSheet> createState() => _ReportPaywallSheetState();
}

class _ReportPaywallSheetState extends State<_ReportPaywallSheet> {
  bool _purchasing = false;

  Future<void> _buyOneTime() async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    final ok = await ReportPurchase.purchaseReport(
      procedureId: widget.procedureId,
    );
    if (!mounted) return;
    setState(() => _purchasing = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase could not be completed.')),
      );
    }
  }

  Future<void> _upgradeToPremium() async {
    final navigator = Navigator.of(context);
    await navigator.pushNamed('/paywall');
    if (!mounted) return;
    final premium = await PremiumAccess.isPremiumUser();
    if (premium) {
      navigator.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final procLabel = (widget.procedureName ?? '').trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: MyApp.champagne,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Grabber.
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: MyApp.clinicalNavy.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  const ClinicalSectionHeader(
                    icon: Icons.description_outlined,
                    eyebrow: 'Professional Report',
                    title: 'Unlock your progress report',
                  ),
                  const SizedBox(height: 14),

                  Text(
                    procLabel.isEmpty
                        ? 'A surgeon-ready, fully formatted PDF of your '
                              'recovery — metrics, AI insights, before/after, '
                              'and milestones in one document.'
                        : 'A surgeon-ready, fully formatted PDF of your '
                              '$procLabel recovery — metrics, AI insights, '
                              'before/after, and milestones in one document.',
                    style: TextStyle(
                      color: MyApp.textBrown,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Value bullets.
                  ..._valueBullets.map(_buildBullet),

                  const SizedBox(height: 22),

                  // ── Single-report card ──────────────────────────────────
                  _OptionCard(
                    eyebrow: 'ONE-TIME PURCHASE',
                    title: 'Unlock this report',
                    body:
                        'Get the full Professional Report PDF for this '
                        'procedure. Yours to keep — re-download anytime.',
                    priceLine: ReportPurchase.priceDisplay,
                    priceSuffix: 'one-time',
                    accent: MyApp.clinicalTeal,
                    actionLabel:
                        'Unlock Report · ${ReportPurchase.priceDisplay}',
                    actionIcon: Icons.lock_open_rounded,
                    loading: _purchasing,
                    onPressed: _buyOneTime,
                  ),
                  const SizedBox(height: 14),

                  // ── Premium card ────────────────────────────────────────
                  _OptionCard(
                    eyebrow: 'BEST VALUE',
                    title: 'Upgrade to Premium',
                    body:
                        'Unlimited Professional Reports across every '
                        'procedure, plus the full premium recovery suite.',
                    priceLine: 'Premium',
                    priceSuffix: 'unlimited reports',
                    accent: MyApp.roseGold,
                    actionLabel: 'See Premium',
                    actionIcon: Icons.workspace_premium_rounded,
                    outlined: true,
                    onPressed: _upgradeToPremium,
                  ),

                  const SizedBox(height: 18),

                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        'Not now',
                        style: TextStyle(
                          color: MyApp.clinicalMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const _valueBullets = <_BulletData>[
    _BulletData(
      Icons.medical_information_outlined,
      'Surgeon-ready format with full progress metrics',
    ),
    _BulletData(Icons.compare_outlined, 'Before & after photos with timeline'),
    _BulletData(
      Icons.insights_outlined,
      'AI insights, redness, texture & elasticity',
    ),
    _BulletData(
      Icons.event_available_outlined,
      'Recovery milestones and confidence score',
    ),
  ];

  Widget _buildBullet(_BulletData b) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(b.icon, size: 18, color: MyApp.clinicalTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              b.label,
              style: TextStyle(
                color: MyApp.clinicalNavy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletData {
  final IconData icon;
  final String label;
  const _BulletData(this.icon, this.label);
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.priceLine,
    required this.priceSuffix,
    required this.accent,
    required this.actionLabel,
    required this.actionIcon,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String priceLine;
  final String priceSuffix;
  final Color accent;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onPressed;
  final bool loading;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: outlined ? 0.55 : 0.20),
          width: outlined ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: MyApp.clinicalNavy.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  eyebrow,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                priceLine,
                style: TextStyle(
                  color: MyApp.clinicalNavy,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                priceSuffix,
                style: TextStyle(
                  color: MyApp.clinicalMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: MyApp.clinicalNavy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              color: MyApp.textBrown,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: outlined
                ? OutlinedButton.icon(
                    icon: Icon(actionIcon, size: 18, color: accent),
                    label: Text(
                      actionLabel,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    onPressed: loading ? null : onPressed,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(actionIcon, size: 18, color: Colors.white),
                    label: Text(
                      loading ? 'Processing…' : actionLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    onPressed: loading ? null : onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
