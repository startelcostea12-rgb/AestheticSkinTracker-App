// Dismissible capture protocol checklist (see protocol_checklist.dart).
// Informational only: it never blocks the shutter.

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/protocol_checklist.dart';

class ProtocolChecklistCard extends StatelessWidget {
  const ProtocolChecklistCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    const ink = AppColors.textStructure;
    return Container(
      key: const ValueKey('protocol_checklist'),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borders),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'New baseline: capture protocol',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                key: const ValueKey('protocol_checklist_close'),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onDismiss,
              ),
            ],
          ),
          for (final item in protocolChecklistItems)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_box_outline_blank_rounded,
                    size: 16,
                    color: ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item, style: const TextStyle(color: ink)),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('protocol_checklist_dismiss'),
              onPressed: onDismiss,
              child: const Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }
}
