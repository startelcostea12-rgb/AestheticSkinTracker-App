import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';

/// Legal document hub for AestheticSkinTracker.
///
/// This screen intentionally keeps state local because it only launches
/// external legal links. If legal acceptance/status is added later, that state
/// should live in the app's existing provider/service layer.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  static const String termsUrl = 'https://aestheticskintracker.com/terms';
  static const String privacyUrl = 'https://aestheticskintracker.com/privacy';
  static const String eulaUrl = 'https://aestheticskintracker.com/eula';

  static final Uri _termsUri = Uri.parse(termsUrl);
  static final Uri _privacyUri = Uri.parse(privacyUrl);
  static final Uri _eulaUri = Uri.parse(eulaUrl);

  Future<void> _openLegalUrl(
    BuildContext context,
    Uri uri,
    String label,
  ) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showLaunchError(context, label);
      }
    } catch (_) {
      if (context.mounted) {
        _showLaunchError(context, label);
      }
    }
  }

  void _showLaunchError(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $label. Please try again later.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.refinedSlate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmAlabaster,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.warmAlabaster,
        foregroundColor: AppColors.refinedSlate,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Legal',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= 720
                ? 640.0
                : double.infinity;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                  children: [
                    const _LegalHeaderCard(),
                    const SizedBox(height: 16),
                    _LegalLinkTile(
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      subtitle:
                          'Review the terms for using AestheticSkinTracker.',
                      semanticLabel: 'Open Terms of Service in browser',
                      onTap: () =>
                          _openLegalUrl(context, _termsUri, 'Terms of Service'),
                    ),
                    const SizedBox(height: 12),
                    _LegalLinkTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      subtitle:
                          'Learn how app and wellness tracking data is handled.',
                      semanticLabel: 'Open Privacy Policy in browser',
                      onTap: () =>
                          _openLegalUrl(context, _privacyUri, 'Privacy Policy'),
                    ),
                    const SizedBox(height: 12),
                    _LegalLinkTile(
                      icon: Icons.verified_user_outlined,
                      title: 'End User License Agreement',
                      subtitle: 'View the app license and permitted use terms.',
                      semanticLabel:
                          'Open End User License Agreement in browser',
                      onTap: () => _openLegalUrl(
                        context,
                        _eulaUri,
                        'End User License Agreement',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _LegalFooter(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LegalHeaderCard extends StatelessWidget {
  const _LegalHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _legalCardDecoration(glow: true),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.36),
              ),
            ),
            child: const Icon(
              Icons.gavel_outlined,
              size: 22,
              color: AppColors.goldHover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Legal',
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Access the documents that explain your rights, privacy, and use of AestheticSkinTracker.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppColors.refinedSlate.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final VoidCallback onTap;

  const _LegalLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: _legalCardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.champagneGold.withValues(alpha: 0.10),
                    border: Border.all(
                      color: AppColors.champagneGold.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.goldHover),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.refinedSlate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: AppColors.refinedSlate.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: AppColors.refinedSlate.withValues(alpha: 0.46),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          top: BorderSide(
            color: AppColors.champagneGold.withValues(alpha: 0.42),
            width: 1,
          ),
        ),
      ),
      child: Text(
        'Effective Date: June 19, 2026\nAestheticSkinTracker LLC',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.45,
          fontWeight: FontWeight.w700,
          color: AppColors.refinedSlate.withValues(alpha: 0.68),
        ),
      ),
    );
  }
}

BoxDecoration _legalCardDecoration({bool glow = false}) {
  return BoxDecoration(
    color: AppColors.cardBackground,
    borderRadius: BorderRadius.circular(MyApp.cardRadiusValue),
    border: Border.all(
      color: glow
          ? AppColors.champagneGold.withValues(alpha: 0.34)
          : AppColors.borders.withValues(alpha: 0.92),
      width: glow ? 1.0 : 0.8,
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
          blurRadius: 26,
          spreadRadius: 1,
          offset: const Offset(0, 8),
        ),
    ],
  );
}
