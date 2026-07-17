enum PeptideCategory {
  longevity,
  weightLoss,
  muscleRepair,
  cognitive,
}

class Peptide {
  const Peptide({
    required this.id,
    required this.name,
    required this.category,
    required this.standardProtocol,
    required this.reconstitutionGuideline,
  });

  final String id;
  final String name;
  final PeptideCategory category;
  final String standardProtocol;
  final String reconstitutionGuideline;

  static double calculateSyringeUnits({
    required double vialStrengthMg,
    required double bacWaterMl,
    required double targetDoseMcg,
  }) {
    if (vialStrengthMg <= 0) {
      throw ArgumentError('Vial strength must be greater than zero.');
    }
    if (bacWaterMl <= 0) {
      throw ArgumentError(
        'Volume of bacteriostatic water must be greater than zero.',
      );
    }
    if (targetDoseMcg <= 0) {
      throw ArgumentError('Target requested dose must be greater than zero.');
    }

    final concentrationMgPerMl = vialStrengthMg / bacWaterMl;
    if (concentrationMgPerMl <= 0 || concentrationMgPerMl.isNaN) {
      throw ArgumentError(
        'Calculated concentration is invalid. Check your inputs.',
      );
    }

    final targetDoseMg = targetDoseMcg / 1000.0;
    final mlToDraw = targetDoseMg / concentrationMgPerMl;
    if (mlToDraw <= 0 || mlToDraw.isNaN || mlToDraw.isInfinite) {
      throw ArgumentError(
        'Calculated syringe volume is invalid. Verify your values and retry.',
      );
    }

    return mlToDraw * 100.0;
  }
}
