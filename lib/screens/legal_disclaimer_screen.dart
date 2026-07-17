import 'package:flutter/material.dart';

import '../app_theme.dart';

class LegalDisclaimerScreen extends StatelessWidget {
  const LegalDisclaimerScreen({super.key});

  void _showPolicy(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title will open when legal documents are connected.'),
        behavior: SnackBarBehavior.floating,
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
        title: const Text(
          'Legal & Disclaimer',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _HeaderCard(),
            const SizedBox(height: 16),
            _DisclaimerCard(),
            const SizedBox(height: 16),
            _ProfessionalGuidanceCard(),
            const SizedBox(height: 16),
            _LegalLinksCard(
              onPrivacyTap: () => _showPolicy(context, 'Privacy Policy'),
              onTermsTap: () => _showPolicy(context, 'Terms of Service'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _legalCardDecoration(glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.champagneGold.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.34),
              ),
            ),
            child: const Icon(
              Icons.health_and_safety_outlined,
              color: AppColors.goldHover,
              size: 22,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Legal & Disclaimer',
            style: TextStyle(
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: AppColors.refinedSlate,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Important information about how AestheticSkinTracker should be used and understood.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: AppColors.refinedSlate.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _legalCardDecoration(glow: true),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Use of this app',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.refinedSlate,
            ),
          ),
          SizedBox(height: 14),
          _LegalBullet(
            text:
                'AestheticSkinTracker is a personal wellness and tracking tool only.',
          ),
          _LegalBullet(text: 'It is not a medical device.'),
          _LegalBullet(
            text:
                'It is not intended for diagnosis or to provide medical advice.',
          ),
          _LegalBullet(text: 'It is not HIPAA compliant.'),
        ],
      ),
    );
  }
}

class _ProfessionalGuidanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _legalCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.medical_services_outlined,
            size: 20,
            color: AppColors.goldHover,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'For any medical concern, symptom, diagnosis, treatment decision, or question about your recovery or skin health, consult a qualified healthcare professional.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: AppColors.refinedSlate.withValues(alpha: 0.80),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinksCard extends StatelessWidget {
  final VoidCallback onPrivacyTap;
  final VoidCallback onTermsTap;

  const _LegalLinksCard({required this.onPrivacyTap, required this.onTermsTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _legalCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Legal documents',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.refinedSlate,
            ),
          ),
          const SizedBox(height: 12),
          _LegalLinkButton(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: onPrivacyTap,
          ),
          const SizedBox(height: 10),
          _LegalLinkButton(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: onTermsTap,
          ),
        ],
      ),
    );
  }
}

class _LegalBullet extends StatelessWidget {
  final String text;

  const _LegalBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppColors.goldHover,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.42,
                fontWeight: FontWeight.w700,
                color: AppColors.refinedSlate.withValues(alpha: 0.84),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LegalLinkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.warmAlabaster,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.champagneGold.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.goldHover),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.refinedSlate,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.refinedSlate.withValues(alpha: 0.44),
              ),
            ],
          ),
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
