import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/report_disclaimer.dart';

class ReportDisclaimerNotice extends StatelessWidget {
  const ReportDisclaimerNotice({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: MyApp.clinicalTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyApp.goldShimmer.withValues(alpha: 0.42)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            color: MyApp.clinicalTeal,
            size: compact ? 18 : 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recoveryReportDisclaimerText,
              style: TextStyle(
                color: MyApp.textBrown.withValues(alpha: 0.88),
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w600,
                height: 1.42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmReportShareDisclaimer(BuildContext context) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Before Sharing'),
      content: const ReportDisclaimerNotice(compact: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: MyApp.goldShimmer,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
  return accepted == true;
}
