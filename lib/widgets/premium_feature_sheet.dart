import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/premium_access.dart';
import 'paywall_screen.dart';

class PremiumRouteGate extends StatefulWidget {
  const PremiumRouteGate({super.key, required this.child});

  final Widget child;

  @override
  State<PremiumRouteGate> createState() => _PremiumRouteGateState();
}

class _PremiumRouteGateState extends State<PremiumRouteGate> {
  late final Future<bool> _premium = PremiumAccess.isPremiumUser();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _premium,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data! ? widget.child : const PaywallScreen();
      },
    );
  }
}

Future<bool> requirePremiumAccess(BuildContext context) async {
  final premium = await PremiumAccess.isPremiumUser();
  if (!context.mounted) return false;
  if (premium) return true;
  await Navigator.of(context).pushNamed('/paywall');
  return false;
}

/// Shows a polished "Premium feature" bottom sheet — used when a free user
/// taps into a paywall-protected area (e.g. Peptide Tracker, AI Coach, etc.).
///
/// Returns `true` if the user successfully unlocked premium via the paywall
/// (i.e. the caller should proceed with the original action), `false`
/// otherwise.
Future<bool> showPremiumFeatureSheet(
  BuildContext context, {
  required String featureName,
  required String description,
  required IconData icon,
  List<({IconData icon, String label})>? perks,
}) async {
  final defaultPerks =
      perks ??
      const [
        (icon: Icons.auto_awesome_rounded, label: 'Unlimited access'),
        (icon: Icons.psychology_alt_rounded, label: 'AI-powered insights'),
        (icon: Icons.lock_open_rounded, label: 'All premium tools'),
      ];

  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  MyApp.champagne.withValues(alpha: 0.55),
                  MyApp.roseGold.withValues(alpha: 0.18),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: MyApp.roseGold.withValues(alpha: 0.18),
                  blurRadius: 26,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: MyApp.goldShimmer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [MyApp.goldShimmer, MyApp.roseGold],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MyApp.goldShimmer.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(icon, color: Colors.white, size: 34),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: MyApp.goldShimmer.withValues(
                                    alpha: 0.6,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.lock_rounded,
                                size: 13,
                                color: MyApp.roseGold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: MyApp.roseGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: MyApp.roseGold.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Text(
                        'PREMIUM FEATURE',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: MyApp.roseGold,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      featureName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: MyApp.textBrown,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: MyApp.textBrown.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ...defaultPerks.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: MyApp.roseGold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              p.icon,
                              size: 18,
                              color: MyApp.roseGold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.label,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: MyApp.textBrown,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: MyApp.goldShimmer,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Unlock Premium',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 15.5,
                        ),
                      ),
                      onPressed: () async {
                        Navigator.of(sheetCtx).pop(false);
                        final result = await Navigator.of(
                          context,
                        ).pushNamed('/paywall');
                        final nowPremium = await PremiumAccess.isPremiumUser();
                        if (context.mounted && nowPremium && result != false) {
                          // Caller will read true via outer await
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyApp.roseGold,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetCtx).pop(false),
                      child: Text(
                        'Maybe later',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MyApp.textBrown.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Cancel anytime · Your data stays private',
                      style: TextStyle(
                        fontSize: 11,
                        color: MyApp.textBrown.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (!context.mounted) return false;
  // Re-check premium after the sheet closes — in case the user successfully
  // upgraded via the paywall route.
  return await PremiumAccess.isPremiumUser();
}
