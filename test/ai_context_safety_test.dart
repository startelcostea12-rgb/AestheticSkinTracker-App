import 'dart:convert';

import 'package:aesthetic_skin_tracker/models/procedure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_intelligence_engine.dart';
import 'package:aesthetic_skin_tracker/utils/premium_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

ScanHistoryEntry _scan({required String id, required String? procedureId}) {
  return ScanHistoryEntry(
    id: id,
    timestamp: DateTime.parse('2026-09-29T10:00:00Z'),
    imagePath: 'photo.jpg',
    procedureId: procedureId,
    estimatedSkinAge: 0,
    metrics: const <String, double>{'wrinkle_load': 12.3},
    rawPayload: const <String, dynamic>{
      'metric_matrix': <String, dynamic>{'wrinkle_load': 12.3},
      'trend_lock_reasons': <String, dynamic>{
        'wrinkle_load': 'lighting_mismatch',
      },
    },
  );
}

Procedure _procedure() {
  return Procedure(
    id: 'procedure-1',
    type: 'Microneedling',
    provider: 'Clinic',
    startDate: DateTime(2026, 9, 1),
    numSessions: 1,
  );
}

void main() {
  test('AI scan context contains no metric names, values, or deltas', () {
    final context = AiIntelligenceEngine.buildAiScanContext(
      scans: [_scan(id: 'scan-1', procedureId: 'procedure-1')],
    );
    final encoded = jsonEncode(context);

    expect(encoded, contains('matched'));
    expect(encoded, contains('lighting_mismatch'));
    expect(encoded, isNot(contains('wrinkle_load')));
    expect(encoded, isNot(contains('12.3')));
  });

  test('procedure id miss scopes coach scans to zero', () {
    final scoped = PremiumRecoveryService.scopeScansToProcedure([
      _scan(id: 'scan-1', procedureId: 'different-procedure'),
    ], _procedure());

    expect(scoped, isEmpty);
  });
}
