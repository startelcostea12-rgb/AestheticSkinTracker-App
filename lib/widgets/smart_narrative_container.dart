import 'package:flutter/material.dart';

import '../app_theme.dart';

class SmartNarrativeContainer extends StatelessWidget {
  const SmartNarrativeContainer({
    super.key,
    required this.narrativeText,
  });

  final String narrativeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181A20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MyApp.goldShimmer.withValues(alpha: 0.18),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: MyApp.goldShimmer.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF48B774),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF48B774).withValues(alpha: 0.45),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI HEALING INSIGHT',
                style: TextStyle(
                  color: MyApp.goldShimmer,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            narrativeText,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}