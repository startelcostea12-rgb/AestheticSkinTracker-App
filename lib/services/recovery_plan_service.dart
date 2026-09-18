import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/procedure.dart';
import '../models/recovery_plan.dart';

class RecoveryPlanService {
  const RecoveryPlanService._();

  static const String assetPath = 'lib/data/recovery_plans.json';

  static Future<List<RecoveryPlan>> loadPlans() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (decoded['plans'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => RecoveryPlan.fromJson(Map<String, dynamic>.from(item)))
        .where((plan) => plan.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<RecoveryPlan?> planForProcedureType(String procedureType) async {
    final canonical = canonicalProcedureType(procedureType);
    for (final plan in await loadPlans()) {
      if (canonicalProcedureType(plan.procedureType) == canonical) {
        return plan;
      }
    }
    return null;
  }

  static Future<RecoveryPlan?> planById(String? planId) async {
    final id = planId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final plan in await loadPlans()) {
      if (plan.id == id) return plan;
    }
    return null;
  }
}
