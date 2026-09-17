import 'package:flutter_test/flutter_test.dart';

import 'package:aesthetic_skin_tracker/models/peptide_model.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/widgets/bridge_card.dart';

void main() {
  group('BridgeCard peptide correlation insight', () {
    test('shows for a genuine improved metric when peptide started before the baseline', () {
      final baseline = ScanHistoryEntry(
        id: 'baseline-1',
        timestamp: DateTime(2024, 1, 3),
        procedureId: 'proc-1',
        metrics: {'localized_redness': 8.0},
        estimatedSkinAge: 31.0,
        rawPayload: {'trend_status': {'localized_redness': 'improved'}},
      );
      final latest = ScanHistoryEntry(
        id: 'latest-1',
        timestamp: DateTime(2024, 1, 21),
        procedureId: 'proc-1',
        metrics: {'localized_redness': 3.0},
        estimatedSkinAge: 29.0,
        rawPayload: {'trend_status': {'localized_redness': 'improved'}},
      );
      final peptide = PeptideEntry(
        id: 'pep-1',
        name: 'GHK-Cu',
        frequency: 'Once daily',
        startDate: DateTime(2024, 1, 1),
        category: 'healing',
      );

      final insight = BridgeCard.computePeptideTrendInsight(
        scans: [baseline, latest],
        latest: latest,
        activePeptides: [peptide],
      );

      expect(
        insight,
        'Since starting GHK-Cu, your redness has trended down.',
      );
    });

    test('does not show for stable or insufficient_signal trend status', () {
      final baseline = ScanHistoryEntry(
        id: 'baseline-2',
        timestamp: DateTime(2024, 2, 1),
        procedureId: 'proc-2',
        metrics: {'localized_redness': 7.0},
        estimatedSkinAge: 30.0,
      );
      final latest = ScanHistoryEntry(
        id: 'latest-2',
        timestamp: DateTime(2024, 2, 14),
        procedureId: 'proc-2',
        metrics: {'localized_redness': 6.5},
        estimatedSkinAge: 29.5,
        rawPayload: {'trend_status': {'localized_redness': 'stable'}},
      );
      final peptide = PeptideEntry(
        id: 'pep-2',
        name: 'GHK-Cu',
        frequency: 'Once daily',
        startDate: DateTime(2024, 1, 25),
        category: 'healing',
      );

      expect(
        BridgeCard.computePeptideTrendInsight(
          scans: [baseline, latest],
          latest: latest,
          activePeptides: [peptide],
        ),
        isNull,
      );

      final insufficient = ScanHistoryEntry(
        id: 'latest-3',
        timestamp: DateTime(2024, 2, 16),
        procedureId: 'proc-2',
        metrics: {'localized_redness': 6.7},
        estimatedSkinAge: 29.6,
        rawPayload: {'trend_status': {'localized_redness': 'insufficient_signal'}},
      );

      expect(
        BridgeCard.computePeptideTrendInsight(
          scans: [baseline, insufficient],
          latest: insufficient,
          activePeptides: [peptide],
        ),
        isNull,
      );
    });

    test('does not show when the peptide started after the baseline comparison window', () {
      final baseline = ScanHistoryEntry(
        id: 'baseline-3',
        timestamp: DateTime(2024, 3, 1),
        procedureId: 'proc-3',
        metrics: {'rosacea_severity': 7.0},
        estimatedSkinAge: 30.0,
        rawPayload: {'trend_status': {'rosacea_severity': 'improved'}},
      );
      final latest = ScanHistoryEntry(
        id: 'latest-4',
        timestamp: DateTime(2024, 3, 18),
        procedureId: 'proc-3',
        metrics: {'rosacea_severity': 4.0},
        estimatedSkinAge: 29.0,
        rawPayload: {'trend_status': {'rosacea_severity': 'improved'}},
      );
      final peptide = PeptideEntry(
        id: 'pep-3',
        name: 'Niacinamide',
        frequency: 'Once daily',
        startDate: DateTime(2024, 3, 5),
        category: 'brightening',
      );

      expect(
        BridgeCard.computePeptideTrendInsight(
          scans: [baseline, latest],
          latest: latest,
          activePeptides: [peptide],
        ),
        isNull,
      );
    });
  });
}
