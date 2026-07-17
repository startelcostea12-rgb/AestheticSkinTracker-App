import 'package:flutter/material.dart';

class PolishedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? margin;
  const PolishedCard({required this.child, this.margin, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB76E79).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFB76E79).withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              gradient: LinearGradient(
                colors: [Color(0xFFE8A8B5), Color(0xFFE0C070)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
