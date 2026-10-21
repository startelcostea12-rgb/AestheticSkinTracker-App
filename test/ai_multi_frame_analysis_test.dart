import 'dart:io';
import 'dart:typed_data';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/skin_ai_analysis_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/models/scan_history.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:aesthetic_skin_tracker/utils/trend_lock_reason.dart';
import 'package:aesthetic_skin_tracker/widgets/luxe_report_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI baseline metric matrix source', () {
    test('matrix value wins over a conflicting metrics value', () {
      final baseline = aiBaselineMetricMatrixFromPayload({
        'metric_matrix': {'texture_smoothness': 57.3},
        'metrics': {'texture_smoothness': 25.23},
      });

      expect(baseline['texture_smoothness'], 57.3);
    });

    test('metrics-only value is not used as a baseline', () {
      final baseline = aiBaselineMetricMatrixFromPayload({
        'metrics': {'texture_smoothness': 25.23},
      });

      expect(baseline.containsKey('texture_smoothness'), isFalse);
    });
  });

  Map<String, dynamic> rednessPayload({
    required String cheekSide,
    required double p10,
    required double p95,
    required List<double> frameP95,
    String? cheekSideConvention = cheekSideConventionSubjectAnatomical,
    bool? bothCheeksInDeadZone,
    String? region,
    double? redness,
    String? branch,
  }) => <String, dynamic>{
    if (redness != null)
      'metric_matrix': <String, dynamic>{'localized_redness': redness},
    'image_quality': <String, dynamic>{
      if (branch != null) 'redness_branch': branch,
      if (region != null) 'localized_redness_mask_kind': region,
      'redness_cheek_side': cheekSide,
      if (cheekSideConvention != null)
        'cheek_side_convention': cheekSideConvention,
      if (bothCheeksInDeadZone != null)
        'redness_both_cheeks_in_dead_zone': bothCheeksInDeadZone,
      'redness_cheek_p10_a_after_wb': p10,
      'redness_cheek_p95_a_after_wb': p95,
    },
    aiScanPerFrameDiagnosticsKey: <Map<String, dynamic>>[
      for (var index = 0; index < frameP95.length; index++)
        <String, dynamic>{
          'frame_number': index + 1,
          'cheek_p95_a_after_wb': frameP95[index],
        },
    ],
  };

  group('redness capture mismatch trend lock', () {
    test(
      'cheek-side matcher requires two known, different physical cheeks',
      () {
        final baseline = rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 10.0],
          p10: 4.0,
          p95: 10.0,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: baseline,
          ),
          isTrue,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: rednessPayload(
              cheekSide: 'left',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
          ),
          isFalse,
        );
        expect(
          aiScanHasCheekSideMismatch(
            currentPayload: rednessPayload(
              cheekSide: '',
              frameP95: const [10.0, 10.0],
              p10: 4.0,
              p95: 10.0,
            ),
            baselinePayload: baseline,
          ),
          isFalse,
        );
      },
    );

    group('single cheek vs both cheeks at low redness', () {
      ({
        Map<String, String> trendStatus,
        Map<String, double> trendDeltas,
        Map<String, String> trendLockReasons,
        Set<String> rednessLockReasons,
        bool cheekLockSkippedLowValues,
        bool regionLockSkippedLowValues,
      })
      compare({
        required String baselineSide,
        required String currentSide,
        double? baselineRedness,
        double? currentRedness,
        String? baselineRegion,
        String? currentRegion,
      }) => downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: baselineSide,
          region: baselineRegion,
          redness: baselineRedness,
          frameP95: const [10.0, 10.5, 10.2],
          p10: 4.0,
          p95: 10.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: currentSide,
          region: currentRegion,
          redness: currentRedness,
          frameP95: const [10.1, 10.6, 10.3],
          p10: 4.1,
          p95: 10.1,
        ),
      );

      test('baseline left + current both, both <= 5.0: no cheek_mismatch', () {
        final result = compare(
          baselineSide: 'left',
          currentSide: 'both',
          baselineRedness: 1.43,
          currentRedness: 3.13,
        );
        expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        expect(result.cheekLockSkippedLowValues, isTrue);
        expect(result.trendStatus['localized_redness'], 'stable');
      });

      test('baseline both + current left, both <= 5.0: no cheek_mismatch', () {
        final result = compare(
          baselineSide: 'both',
          currentSide: 'left',
          baselineRedness: 5.0,
          currentRedness: 0.0,
        );
        expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        expect(result.cheekLockSkippedLowValues, isTrue);
      });

      test('same sides still compare, with no skip flag', () {
        final result = compare(
          baselineSide: 'left',
          currentSide: 'left',
          baselineRedness: 3.0,
          currentRedness: 4.0,
        );
        expect(result.rednessLockReasons, isEmpty);
        expect(result.cheekLockSkippedLowValues, isFalse);
        expect(result.trendStatus['localized_redness'], 'stable');
      });

      // "both" means baseline_p95_anchor: no cheek lock whatever the
      // values (the low-value flag is only set for the low-value skip).
      test('one value above 5.0: no cheek lock ("both" is anchored)', () {
        final result = compare(
          baselineSide: 'left',
          currentSide: 'both',
          baselineRedness: 1.43,
          currentRedness: 5.1,
        );
        expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        expect(result.cheekLockSkippedLowValues, isFalse);
      });

      test('a missing value: no cheek lock ("both" is anchored)', () {
        final result = compare(
          baselineSide: 'both',
          currentSide: 'left',
          currentRedness: 2.0,
        );
        expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        expect(result.cheekLockSkippedLowValues, isFalse);
      });

      test('left vs right at low values still locks', () {
        final result = compare(
          baselineSide: 'right',
          currentSide: 'left',
          baselineRedness: 1.0,
          currentRedness: 2.0,
        );
        expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
        expect(result.cheekLockSkippedLowValues, isFalse);
      });

      group('single cheek vs both with matching values', () {
        test('left vs both, 9.3 vs 9.3: no cheek_mismatch', () {
          final result = compare(
            baselineSide: 'left',
            currentSide: 'both',
            baselineRedness: 9.3,
            currentRedness: 9.3,
          );
          expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
          expect(result.trendLockReasons['localized_redness'], isNull);
          expect(result.trendStatus['localized_redness'], 'stable');
          // No new export field: the low-value flag stays false.
          expect(result.cheekLockSkippedLowValues, isFalse);
        });

        test('both vs right within 1.0 (9.3 vs 10.3): no cheek_mismatch', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'right',
            baselineRedness: 9.3,
            currentRedness: 10.3,
          );
          expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        });

        test('left vs both, 9.3 vs 12.0: no cheek lock (method changed)', () {
          final result = compare(
            baselineSide: 'left',
            currentSide: 'both',
            baselineRedness: 9.3,
            currentRedness: 12.0,
          );
          expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
          expect(result.cheekLockSkippedLowValues, isFalse);
        });

        test('left vs right still locks, even with equal values', () {
          for (final (baseline, current) in const [(9.3, 9.3), (9.3, 12.0)]) {
            final result = compare(
              baselineSide: 'right',
              currentSide: 'left',
              baselineRedness: baseline,
              currentRedness: current,
            );
            expect(
              result.trendLockReasons['localized_redness'],
              'cheek_mismatch',
              reason: '$baseline vs $current',
            );
          }
        });

        test('dead-zone flag still skips the lock', () {
          final result = downgradeRednessTrendForCaptureMismatch(
            trendStatus: const {'localized_redness': 'stable'},
            trendDeltas: const {'localized_redness': 0.0},
            trendLockReasons: const {},
            baselinePayload: rednessPayload(
              cheekSide: 'left',
              redness: 9.3,
              bothCheeksInDeadZone: true,
              frameP95: const [10.0, 10.5, 10.2],
              p10: 4.0,
              p95: 10.0,
            ),
            currentPayload: rednessPayload(
              cheekSide: 'right',
              redness: 14.0,
              frameP95: const [10.1, 10.6, 10.3],
              p10: 4.1,
              p95: 10.1,
            ),
          );
          expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
        });
      });

      test('with real regions at low values, redness now compares', () {
        // left is read from left_cheek and both from u_zone: the cheek and
        // region locks are both skipped at these low values.
        final result = compare(
          baselineSide: 'left',
          currentSide: 'both',
          baselineRegion: 'left_cheek',
          currentRegion: 'u_zone',
          baselineRedness: 1.43,
          currentRedness: 3.13,
        );
        expect(result.cheekLockSkippedLowValues, isTrue);
        expect(result.regionLockSkippedLowValues, isTrue);
        expect(result.rednessLockReasons, isEmpty);
        expect(result.trendStatus['localized_redness'], 'stable');
      });

      group('region lock at low values', () {
        test('left_cheek vs u_zone, both <= 5.0: no region_mismatch', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'both',
            baselineRegion: 'left_cheek',
            currentRegion: 'u_zone',
            baselineRedness: 0.0,
            currentRedness: 1.97,
          );
          expect(result.rednessLockReasons, isNot(contains('region_mismatch')));
          expect(result.regionLockSkippedLowValues, isTrue);
          expect(result.trendLockReasons, isEmpty);
        });

        test('u_zone vs right_cheek, both <= 5.0: no region_mismatch', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'both',
            baselineRegion: 'u_zone',
            currentRegion: 'right_cheek',
            baselineRedness: 5.0,
            currentRedness: 4.2,
          );
          expect(result.rednessLockReasons, isNot(contains('region_mismatch')));
          expect(result.regionLockSkippedLowValues, isTrue);
        });

        test('one value above 5.0 still locks as region_mismatch', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'both',
            baselineRegion: 'left_cheek',
            currentRegion: 'u_zone',
            baselineRedness: 1.0,
            currentRedness: 6.0,
          );
          expect(
            result.trendLockReasons['localized_redness'],
            'region_mismatch',
          );
          expect(result.regionLockSkippedLowValues, isFalse);
        });

        test('a missing value still locks as region_mismatch', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'both',
            baselineRegion: 'u_zone',
            currentRegion: 'left_cheek',
            currentRedness: 2.0,
          );
          expect(
            result.trendLockReasons['localized_redness'],
            'region_mismatch',
          );
          expect(result.regionLockSkippedLowValues, isFalse);
        });

        test(
          'left_cheek vs right_cheek is not a single-cheek vs U-zone skip',
          () {
            final result = compare(
              baselineSide: 'both',
              currentSide: 'both',
              baselineRegion: 'left_cheek',
              currentRegion: 'right_cheek',
              baselineRedness: 1.0,
              currentRedness: 2.0,
            );
            expect(
              result.trendLockReasons['localized_redness'],
              'region_mismatch',
            );
            expect(result.regionLockSkippedLowValues, isFalse);
          },
        );

        test('same regions still compare, with no skip flag', () {
          final result = compare(
            baselineSide: 'both',
            currentSide: 'both',
            baselineRegion: 'u_zone',
            currentRegion: 'u_zone',
            baselineRedness: 2.0,
            currentRedness: 3.0,
          );
          expect(result.rednessLockReasons, isEmpty);
          expect(result.regionLockSkippedLowValues, isFalse);
          expect(result.trendStatus['localized_redness'], 'stable');
        });
      });

      test('the skip flag is exported', () {
        final scan = ScanHistoryEntry(
          id: 'cheek-skip',
          timestamp: DateTime.utc(2026, 10, 10, 19, 10, 22),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: const <String, dynamic>{
            'metric_matrix': <String, dynamic>{'localized_redness': 3.13},
            rednessCheekLockSkippedLowValuesKey: true,
            rednessRegionLockSkippedLowValuesKey: true,
          },
        );
        final rows = AiScanDataCsvExporter.format([
          scan,
        ], registryBaselineScanIds: const {}).split('\r\n');
        final header = rows.first.split(',');
        final values = rows[1].split(',');
        expect(
          values[header.indexOf('redness_cheek_lock_skipped_low_values')],
          'true',
        );
        expect(
          values[header.indexOf('redness_region_lock_skipped_low_values')],
          'true',
        );
      });
    });

    group('dead-zone zero and region changes', () {
      const status = {'localized_redness': 'stable'};
      const deltas = {'localized_redness': 0.0};

      test('a 0.0 redness score never takes cast_mismatch', () {
        final result = downgradeRednessTrendForCaptureMismatch(
          trendStatus: status,
          trendDeltas: deltas,
          trendLockReasons: const {},
          baselinePayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            frameP95: const [15.778, 15.586, 16.963],
            p10: 7.386,
            p95: 15.778,
          ),
          currentPayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            redness: 0.0,
            frameP95: const [12.968, 13.076, 11.714],
            p10: 5.173,
            p95: 12.968,
          ),
        );

        expect(result.rednessLockReasons, isNot(contains('cast_mismatch')));
        expect(result.trendLockReasons, isEmpty);
        expect(result.trendStatus['localized_redness'], 'stable');
      });

      test('a dead-zone flag on either scan skips the cast check', () {
        final result = downgradeRednessTrendForCaptureMismatch(
          trendStatus: const {'localized_redness': 'improved'},
          trendDeltas: const {'localized_redness': 12.0},
          trendLockReasons: const {},
          baselinePayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            bothCheeksInDeadZone: true,
            frameP95: const [10.0, 10.5, 10.2],
            p10: 4.0,
            p95: 10.0,
          ),
          currentPayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            redness: 6.0,
            frameP95: const [16.0, 16.4, 16.2],
            p10: 9.0,
            p95: 16.0,
          ),
        );

        expect(result.rednessLockReasons, isEmpty);
        expect(result.trendStatus['localized_redness'], 'improved');
      });

      test('left_cheek vs u_zone locks as region_mismatch, not cast', () {
        // The 12:41:03 scan against the 10:21:11 baseline.
        final result = downgradeRednessTrendForCaptureMismatch(
          trendStatus: status,
          trendDeltas: deltas,
          trendLockReasons: const {},
          baselinePayload: rednessPayload(
            cheekSide: 'left',
            region: 'left_cheek',
            bothCheeksInDeadZone: true,
            frameP95: const [15.778, 15.586, 16.963],
            p10: 7.386,
            p95: 15.778,
          ),
          currentPayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            bothCheeksInDeadZone: true,
            redness: 0.0,
            frameP95: const [12.968, 13.076, 11.714],
            p10: 5.173,
            p95: 12.968,
          ),
        );

        expect(result.rednessLockReasons, contains('region_mismatch'));
        expect(result.rednessLockReasons, isNot(contains('cast_mismatch')));
        expect(result.trendLockReasons['localized_redness'], 'region_mismatch');
        expect(result.trendStatus.containsKey('localized_redness'), isFalse);
        expect(trendLockReasonShortLabel('region_mismatch'), isNotNull);
        expect(knownTrendLockReasons, contains('region_mismatch'));
      });

      test('same region with a real redness value can still cast-lock', () {
        final result = downgradeRednessTrendForCaptureMismatch(
          trendStatus: const {'localized_redness': 'worsened'},
          trendDeltas: const {'localized_redness': -40.0},
          trendLockReasons: const {},
          baselinePayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            frameP95: const [10.0, 10.5, 10.2],
            p10: 4.0,
            p95: 10.0,
          ),
          currentPayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            redness: 14.0,
            frameP95: const [16.0, 16.4, 16.2],
            p10: 9.0,
            p95: 16.0,
          ),
        );

        expect(result.rednessLockReasons, contains('cast_mismatch'));
        expect(result.trendLockReasons['localized_redness'], 'cast_mismatch');
        expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      });

      test('a missing region on one scan keeps the existing cast check', () {
        final result = downgradeRednessTrendForCaptureMismatch(
          trendStatus: const {'localized_redness': 'worsened'},
          trendDeltas: const {'localized_redness': -40.0},
          trendLockReasons: const {},
          baselinePayload: rednessPayload(
            cheekSide: 'both',
            frameP95: const [10.0, 10.5, 10.2],
            p10: 4.0,
            p95: 10.0,
          ),
          currentPayload: rednessPayload(
            cheekSide: 'both',
            region: 'u_zone',
            redness: 14.0,
            frameP95: const [16.0, 16.4, 16.2],
            p10: 9.0,
            p95: 16.0,
          ),
        );

        expect(result.trendLockReasons['localized_redness'], 'cast_mismatch');
      });
    });

    test('does not create a lock when no redness trend verdict exists', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {},
        trendDeltas: const {},
        trendLockReasons: const {},
        baselinePayload: const {},
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [12.0, 12.5, 12.2],
          p10: 4.5,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus, isEmpty);
      expect(result.trendDeltas, isEmpty);
    });

    test('today\'s cheek and cast mismatches lock with no percent', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'improved'},
        trendDeltas: const {'localized_redness': 84.0},
        trendLockReasons: const {'localized_redness': 'path_mismatch'},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [13.382, 13.202, 11.368],
          p10: 2.52,
          p95: 13.382,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [20.89, 20.391, 20.70],
          p10: 10.396,
          p95: 20.89,
        ),
      );

      expect(
        result.rednessLockReasons,
        containsAll(<String>[
          'path_mismatch',
          'cheek_mismatch',
          'cast_mismatch',
        ]),
      );
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('same cheek and deltas inside the larger p95 range may trend', () {
      expect(preservedAiExtractionPath('cheek_primary'), 'cheek_primary');
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {
          'localized_redness': 'improved',
          'texture_smoothness': 'stable',
        },
        trendDeltas: const {
          'localized_redness': 12.0,
          'texture_smoothness': 0.0,
        },
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus['localized_redness'], 'improved');
      expect(result.trendStatus['texture_smoothness'], 'stable');
      expect(result.trendDeltas['localized_redness'], 12.0);
      expect(result.trendLockReasons, isEmpty);
    });

    test('new scan and legacy baseline of the same physical cheek compare', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'improved'},
        trendDeltas: const {'localized_redness': 12.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          cheekSideConvention: null,
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendStatus['localized_redness'], 'improved');
    });

    test('different physical cheeks lock redness only', () {
      const otherMetrics = [
        'texture_smoothness',
        'pigment_load',
        'pore_visibility',
        'skin_tone_radiance_evenness',
        'structural_firmness_elasticity',
      ];
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: <String, String>{
          'localized_redness': 'improved',
          for (final metric in otherMetrics) metric: 'improved',
        },
        trendDeltas: <String, double>{
          'localized_redness': 12.0,
          for (final metric in otherMetrics) metric: 12.0,
        },
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 12.0, 11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0, 13.0, 12.0],
          p10: 5.0,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
      for (final metric in otherMetrics) {
        expect(result.trendStatus[metric], 'improved');
        expect(result.trendDeltas[metric], 12.0);
        expect(result.trendLockReasons.containsKey(metric), isFalse);
      }
    });

    test('side-independent redness skips cheek mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          bothCheeksInDeadZone: true,
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          bothCheeksInDeadZone: true,
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
      );

      expect(result.rednessLockReasons, isEmpty);
      expect(result.trendLockReasons, isEmpty);
    });

    test('missing side-independent flag keeps cheek mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [10.0, 10.2, 10.1],
          p10: 4.0,
          p95: 10.1,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('different cheeks with real redness still lock', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'worsened'},
        trendDeltas: const {'localized_redness': -20.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'right',
          bothCheeksInDeadZone: false,
          frameP95: const [18.0, 18.2, 18.1],
          p10: 6.0,
          p95: 18.1,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          bothCheeksInDeadZone: false,
          frameP95: const [18.0, 18.2, 18.1],
          p10: 6.0,
          p95: 18.1,
        ),
      );

      expect(result.rednessLockReasons, contains('cheek_mismatch'));
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
    });

    test('path mismatch alone leaves redness status and delta empty', () {
      final payload = rednessPayload(
        cheekSide: 'left',
        frameP95: const [10.0, 12.0, 11.0],
        p10: 4.0,
        p95: 11.0,
      );
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'stable'},
        trendDeltas: const {'localized_redness': 0.0},
        trendLockReasons: const {'localized_redness': 'path_mismatch'},
        baselinePayload: payload,
        currentPayload: payload,
      );

      expect(result.rednessLockReasons, {'path_mismatch'});
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'path_mismatch');
    });

    test('fewer than two frame p95 values locks as cast mismatch', () {
      final result = downgradeRednessTrendForCaptureMismatch(
        trendStatus: const {'localized_redness': 'worsened'},
        trendDeltas: const {'localized_redness': -15.0},
        trendLockReasons: const {},
        baselinePayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [11.0],
          p10: 4.0,
          p95: 11.0,
        ),
        currentPayload: rednessPayload(
          cheekSide: 'left',
          frameP95: const [12.0, 12.5, 12.2],
          p10: 4.5,
          p95: 12.0,
        ),
      );

      expect(result.rednessLockReasons, {'cast_mismatch'});
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
      expect(result.trendDeltas.containsKey('localized_redness'), isFalse);
      expect(result.trendLockReasons['localized_redness'], 'cast_mismatch');
    });
  });

  test('averages each metric over only frames with a finite value', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'status': 'success',
        'metric_confidence': {
          'localized_redness': 'high',
          'pigment_load': 'medium',
        },
        'metric_matrix': {'localized_redness': 10.0, 'pigment_load': 20.0},
      },
      {
        'status': 'success',
        'metrics': {
          'metric_confidence': {
            'localized_redness': 'medium',
            'texture_smoothness': 'low',
          },
          'metric_matrix': {
            'localized_redness': 20.0,
            'pigment_load': null,
            'texture_smoothness': 60.0,
          },
        },
      },
      {
        'status': 'success',
        'metric_confidence': {'localized_redness': 'high'},
        'metric_matrix': {'localized_redness': 30.0, 'pigment_load': 'invalid'},
      },
      {'status': 'error', 'metric_matrix': <String, dynamic>{}},
    ], requestedFrames: 4);

    final matrix = aggregate.response['metric_matrix'] as Map<String, double>;
    expect(matrix['localized_redness'], 20.0);
    expect(matrix['pigment_load'], 20.0);
    expect(matrix['texture_smoothness'], 60.0);
    expect(aggregate.metricContributorCounts['localized_redness'], 3);
    expect(aggregate.metricContributorCounts['pigment_load'], 1);
    expect(aggregate.metricContributorCounts['texture_smoothness'], 1);
    expect(aggregate.successfulFrames, 3);
    expect(aggregate.requestedFrames, 4);
    final nestedMetrics = aggregate.response['metrics'] as Map<String, dynamic>;
    expect(nestedMetrics['metric_matrix'], matrix);
    expect(nestedMetrics['localized_redness'], 20.0);
    expect(aggregate.response['multi_frame_analysis'], {
      'requested_frames': 4,
      'successful_frames': 3,
      'metric_contributor_counts': {
        'localized_redness': 3,
        'pigment_load': 1,
        'texture_smoothness': 1,
      },
      'metric_frame_values': {
        'localized_redness': [10.0, 20.0, 30.0],
        'pigment_load': [20.0],
        'texture_smoothness': [60.0],
      },
      'metric_ranges': {
        'localized_redness': {'min': 10.0, 'max': 30.0, 'count': 3},
        'pigment_load': {'min': 20.0, 'max': 20.0, 'count': 1},
        'texture_smoothness': {'min': 60.0, 'max': 60.0, 'count': 1},
      },
    });
    expect(aggregate.response['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'medium',
      'texture_smoothness': 'low',
    });
    expect(nestedMetrics['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'medium',
      'texture_smoothness': 'low',
    });
  });

  test('confidence is taken only from a frame that contributed the metric', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'metric_matrix': {'localized_redness': 10.0},
        'metric_confidence': {
          'localized_redness': 'high',
          'pigment_load': 'low',
        },
      },
      {
        'metric_matrix': {'pigment_load': 24.0},
        'metric_confidence': {'pigment_load': 'high'},
      },
    ], requestedFrames: 2);

    expect(aggregate.response['metric_confidence'], {
      'localized_redness': 'high',
      'pigment_load': 'high',
    });
  });

  test('frames that disagree on trend status show no verdict, while paths '
      'still come from the frame closest to the displayed average', () {
    // texture_smoothness values 28.7, 39.5, 50.2 average to 39.466..., so
    // frame 2 (39.5) is the nearest contributor -- its own backend-computed
    // trend fields for texture_smoothness must be the ones surfaced,
    // reproducing the bug where frame 1's "improved" was shown next to the
    // averaged value even though frame 1's own raw value never justified it.
    final aggregate = averageBackendAnalysisFrames([
      {
        'metric_matrix': {'texture_smoothness': 28.7},
        'metric_extraction_paths': {'texture_smoothness': 'primary_roi'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'improved'},
        'trend_deltas': {'texture_smoothness': 100.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
      {
        'metric_matrix': {'texture_smoothness': 39.5},
        'metric_extraction_paths': {'texture_smoothness': 'laplacian_fallback'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'stable'},
        'trend_deltas': {'texture_smoothness': 5.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
      {
        'metric_matrix': {'texture_smoothness': 50.2},
        'metric_extraction_paths': {'texture_smoothness': 'large_roi_fallback'},
        'baseline_metric_extraction_paths': {
          'texture_smoothness': 'primary_roi',
        },
        'trend_status': {'texture_smoothness': 'improved'},
        'trend_deltas': {'texture_smoothness': 158.0},
        'trend_lock_reasons': <String, dynamic>{},
      },
    ], requestedFrames: 3);

    // improved / stable / improved: the frames disagree, so neither the
    // nearest frame's "stable" nor anyone's delta is surfaced.
    expect(aggregate.response['trend_status'], isEmpty);
    expect(aggregate.response['trend_deltas'], isEmpty);
    expect(aggregate.response['metric_extraction_paths'], {
      'texture_smoothness': 'laplacian_fallback',
      'pore_visibility': 'skipped',
    });
    expect(aggregate.response['baseline_metric_extraction_paths'], {
      'texture_smoothness': 'primary_roi',
    });
    final nestedMetrics = aggregate.response['metrics'] as Map<String, dynamic>;
    expect(nestedMetrics['trend_status'], isEmpty);
    expect(nestedMetrics['trend_deltas'], isEmpty);
    expect(nestedMetrics['metric_extraction_paths'], {
      'texture_smoothness': 'laplacian_fallback',
      'pore_visibility': 'skipped',
    });
  });

  test(
    'pore visibility omissions retain their path without a metric value',
    () {
      for (final reason in ['pose', 'dog_spread', 'crop', 'skipped']) {
        final aggregate = averageBackendAnalysisFrames([
          {
            'metric_matrix': {'localized_redness': 20.0},
            'metric_extraction_paths': {'pore_visibility': reason},
          },
        ], requestedFrames: 1);

        expect(
          aggregate.response['metric_matrix'],
          isNot(contains('pore_visibility')),
          reason: reason,
        );
        expect(
          (aggregate.response['metric_extraction_paths']
              as Map)['pore_visibility'],
          reason,
          reason: reason,
        );
        final metrics = aggregate.response['metrics'] as Map<String, dynamic>;
        expect(
          (metrics['metric_extraction_paths'] as Map)['pore_visibility'],
          reason,
          reason: reason,
        );
      }
    },
  );

  test('averages raw LAB a_p95 without applying the 0-100 score clamp', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'status': 'success',
        'metric_matrix': {'localized_redness': 20.0, 'a_p95': 128.25},
      },
      {
        'status': 'success',
        'metric_matrix': {'localized_redness': 22.0, 'a_p95': 130.25},
      },
    ], requestedFrames: 2);

    final matrix = aggregate.response['metric_matrix'] as Map<String, double>;
    expect(matrix['a_p95'], 129.25);
    expect(aggregate.metricContributorCounts['a_p95'], 2);
  });

  test('scored pore visibility remains primary_roi through aggregation', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'metric_matrix': {'pore_visibility': 79.6},
        'metric_extraction_paths': {'pore_visibility': 'primary_roi'},
      },
    ], requestedFrames: 1);

    expect(aggregate.response['metric_matrix'], {'pore_visibility': 79.6});
    expect(
      (aggregate.response['metric_extraction_paths'] as Map)['pore_visibility'],
      'primary_roi',
    );
  });

  test('an omitted under-eye metric keeps the backend skipped path and exports '
      'skipped, not unknown', () {
    Map<String, dynamic> frame() => {
      'metric_matrix': {'pigment_load': 12.0},
      'metric_extraction_paths': {
        'pigment_load': 'cheek_primary',
        'under_eye_texture_density': 'skipped',
        'under_eye_dark_circle_density': 'skipped',
      },
    };
    final aggregate = averageBackendAnalysisFrames([
      frame(),
      frame(),
      frame(),
    ], requestedFrames: 3);

    final paths = aggregate.response['metric_extraction_paths'] as Map;
    expect(paths['under_eye_texture_density'], 'skipped');
    expect(paths['under_eye_dark_circle_density'], 'skipped');
    expect(paths['pigment_load'], 'cheek_primary');
    expect(
      (aggregate.response['metrics'] as Map)['metric_extraction_paths'],
      paths,
    );

    final saved = ScanHistoryEntry.fromJson(
      ScanHistoryEntry(
        id: 'omitted-under-eye-scan',
        timestamp: DateTime.parse('2026-10-05T16:32:04Z'),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: aggregate.response,
      ).toJson(),
    );
    final csv = AiScanDataCsvExporter.format([
      saved,
    ], registryBaselineScanIds: const {});
    final lines = csv.split('\r\n');
    final header = lines.first.split(',');
    final row = lines[1].split(',');
    String cell(String column) => row[header.indexOf(column)];
    expect(cell('under_eye_texture_density_extraction_path'), 'skipped');
    expect(cell('under_eye_dark_circle_density_extraction_path'), 'skipped');
    expect(cell('under_eye_texture_density_value'), isEmpty);
  });

  test(
    'a metric with a value never takes a skipped path from another frame',
    () {
      final aggregate = averageBackendAnalysisFrames([
        {
          'metric_matrix': {'chin_pore_visibility': 20.0},
          'metric_extraction_paths': {'chin_pore_visibility': 'primary_roi'},
        },
        {
          'metric_matrix': {'pigment_load': 12.0},
          'metric_extraction_paths': {'chin_pore_visibility': 'skipped'},
        },
      ], requestedFrames: 2);

      expect(
        (aggregate.response['metric_extraction_paths']
            as Map)['chin_pore_visibility'],
        'primary_roi',
      );
    },
  );

  group('aiBaselineExtractionPathsForRequest', () {
    test('sends the baseline scan\'s stored under-eye paths', () {
      final paths = aiBaselineExtractionPathsForRequest({
        'metric_extraction_paths': {
          'pigment_load': 'cheek_primary',
          'under_eye_texture_density': 'primary_roi',
          'under_eye_dark_circle_density': 'primary_roi',
        },
      });
      expect(paths['under_eye_texture_density'], 'primary_roi');
      expect(paths['under_eye_dark_circle_density'], 'primary_roi');
      expect(paths['pigment_load'], 'cheek_primary');
    });

    test('a missing stored under-eye path stays missing', () {
      final paths = aiBaselineExtractionPathsForRequest({
        'metric_extraction_paths': {
          'pigment_load': 'cheek_primary',
          'under_eye_texture_density': '',
        },
      });
      expect(paths.containsKey('under_eye_texture_density'), isFalse);
      expect(paths.containsKey('under_eye_dark_circle_density'), isFalse);
      expect(
        aiBaselineExtractionPathsForRequest(null).keys,
        isNot(contains('under_eye_texture_density')),
      );
      // Older metrics keep their existing 'unknown' default.
      expect(paths['localized_redness'], 'unknown');
    });
  });

  test(
    'the lash-free under-eye band kind and pixel counts reach the export',
    () {
      final aggregate = averageBackendAnalysisFrames([
        {
          'metric_matrix': {'under_eye_dark_circle_density': 16.8},
          'image_quality': {
            'under_eye_dark_circle_density_mask_kind':
                'under_eye_lash_free_band',
            'under_eye_dark_circle_density_mask_pixels': 2474,
            'under_eye_texture_density_mask_kind': 'under_eye_lash_free_band',
            'under_eye_texture_density_mask_pixels': 2474,
            'under_eye_reference_mask_pixels': 2569,
          },
        },
      ], requestedFrames: 1);
      final scan = ScanHistoryEntry(
        id: 'lash-free-band',
        timestamp: DateTime.utc(2026, 10, 11),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: {
          ...aggregate.response,
          aiScanPerFrameDiagnosticsKey: buildAiScanPerFrameDiagnostics(
            frameResponses: [aggregate.response],
            frameExposureMetadata: const <AiScanFrameExposure>[],
            frameCount: 1,
          ),
        },
      );
      final rows = AiScanDataCsvExporter.format([
        scan,
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final values = rows[1].split(',');
      String cell(String column) => values[header.indexOf(column)];
      expect(
        cell('image_quality.under_eye_dark_circle_density_mask_kind'),
        'under_eye_lash_free_band',
      );
      expect(cell('image_quality.under_eye_reference_mask_pixels'), '2569');
      expect(
        cell('frame1_under_eye_dark_circle_density_mask_kind'),
        'under_eye_lash_free_band',
      );
      expect(cell('frame1_under_eye_dark_circle_density_mask_pixels'), '2474');
    },
  );

  group('untrusted metrics never keep a verdict', () {
    test(
      'agreeing improved pore_contraction_index frames export no status',
      () {
        Map<String, dynamic> frame(double value) => {
          'metric_matrix': {
            'pore_contraction_index': value,
            'pigment_load': 9.0,
          },
          'trend_status': {
            'pore_contraction_index': 'improved',
            'pigment_load': 'stable',
          },
          'trend_deltas': {'pore_contraction_index': 9.0, 'pigment_load': 0.0},
        };
        final aggregate = averageBackendAnalysisFrames([
          frame(59.7),
          frame(65.1),
          frame(62.0),
          frame(60.5),
          frame(63.3),
        ], requestedFrames: 5);

        final status = aggregate.response['trend_status'] as Map;
        final deltas = aggregate.response['trend_deltas'] as Map;
        expect(status.containsKey('pore_contraction_index'), isFalse);
        expect(deltas.containsKey('pore_contraction_index'), isFalse);
        // A trusted metric with agreeing frames is untouched.
        expect(status['pigment_load'], 'stable');
        expect(
          aggregate.response['metric_matrix']['pore_contraction_index'],
          62.0, // median of five
        );

        final scan = ScanHistoryEntry(
          id: 'untrusted-verdicts',
          timestamp: DateTime.utc(2026, 10, 9, 13),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: aggregate.response,
        );
        final rows = AiScanDataCsvExporter.format([
          scan,
        ], registryBaselineScanIds: const {}).split('\r\n');
        final header = rows.first.split(',');
        final values = rows[1].split(',');
        String cell(String column) => values[header.indexOf(column)];
        expect(cell('pore_contraction_index_trend_status'), isEmpty);
        expect(cell('pore_contraction_index_value'), '62.0');
        expect(cell('pigment_load_trend_status'), 'stable');
      },
    );

    test('every untrusted metric drops status and delta but keeps a lock', () {
      for (final key in untrustedTrendVerdictMetricKeys) {
        // Median-of-five metrics need all five frames to be emitted.
        final frames = fiveFrameMedianMetricKeys.contains(key) ? 5 : 1;
        final aggregate = averageBackendAnalysisFrames([
          for (var i = 0; i < frames; i++)
            {
              'metric_matrix': {key: 40.0},
              'trend_status': {key: 'worsened'},
              'trend_deltas': {key: -12.0},
              'trend_lock_reasons': {key: 'capture_quality_mismatch'},
            },
        ], requestedFrames: frames);
        expect(aggregate.response['trend_status'], isEmpty, reason: key);
        expect(aggregate.response['trend_deltas'], isEmpty, reason: key);
        expect(aggregate.response['trend_lock_reasons'], {
          key: 'capture_quality_mismatch',
        }, reason: key);
      }
      expect(untrustedTrendVerdictMetricKeys, {
        'pore_contraction_index',
        'under_eye_dark_circle_density',
        'under_eye_texture_density',
        'wrinkle_load',
        'rosacea_severity',
        'diffuse_flushing_erythema',
      });
    });

    testWidgets('a locked untrusted metric keeps its lock in the export and '
        'shows only its number on the card', (tester) async {
      final aggregate = averageBackendAnalysisFrames([
        for (var i = 0; i < 5; i++)
          {
            'metric_matrix': {'wrinkle_load': 46.2},
            'trend_status': {'wrinkle_load': 'stable'},
            'trend_deltas': {'wrinkle_load': 0.0},
            'trend_lock_reasons': {'wrinkle_load': 'capture_quality_mismatch'},
          },
      ], requestedFrames: 5);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LuxeReportLayout(
                rawPayload: {
                  ...aggregate.response,
                  'is_follow_up': true,
                  'local_history_count': 2,
                  'baseline_metric_matrix': {'wrinkle_load': 44.0},
                  'metric_extraction_paths': {'wrinkle_load': 'primary_roi'},
                  'baseline_metric_extraction_paths': {
                    'wrinkle_load': 'primary_roi',
                  },
                },
                requireBackendVerdict: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const ValueKey('result_metric_wrinkle_load'));
      expect(
        find.descendant(of: card, matching: find.textContaining('46.2')),
        findsWidgets,
      );
      for (final label in const ['Improved', 'Worsened']) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsNothing,
        );
      }
      expect(
        find.descendant(of: card, matching: find.textContaining('Stable')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('%')),
        findsNothing,
      );

      final scan = ScanHistoryEntry(
        id: 'locked-untrusted',
        timestamp: DateTime.utc(2026, 10, 9, 13, 5),
        scanType: ScanHistoryEntry.scanTypeAiAnalysis,
        estimatedSkinAge: 0,
        metrics: const <String, double>{},
        rawPayload: aggregate.response,
      );
      final rows = AiScanDataCsvExporter.format([
        scan,
      ], registryBaselineScanIds: const {}).split('\r\n');
      final header = rows.first.split(',');
      final values = rows[1].split(',');
      expect(values[header.indexOf('wrinkle_load_trend_status')], isEmpty);
      expect(
        values[header.indexOf('wrinkle_load_trend_lock_reason')],
        'capture_quality_mismatch',
      );
    });
  });

  group('verdict only when every contributing frame agrees', () {
    Map<String, dynamic> frame(
      String key,
      double value,
      String status,
      double delta, {
      String? lockReason,
    }) => {
      'metric_matrix': {key: value},
      'metric_extraction_paths': {key: 'cheek_primary'},
      'trend_status': {key: status},
      'trend_deltas': {key: delta},
      'trend_lock_reasons': {if (lockReason != null) key: lockReason},
    };

    test('three agreeing frames keep that status and the nearest delta', () {
      final aggregate = averageBackendAnalysisFrames([
        frame('pigment_load', 10.4, 'worsened', 35.6),
        frame('pigment_load', 10.4, 'worsened', 35.6),
        frame('pigment_load', 10.5, 'worsened', 37.0),
      ], requestedFrames: 3);

      expect(aggregate.response['trend_status'], {'pigment_load': 'worsened'});
      expect(aggregate.response['trend_deltas'], {'pigment_load': 35.6});
    });

    test('8.5 / 9.9 / 10.3 with mixed statuses does not get worsened', () {
      // The 12:49:15 scan: frame 9.9 is nearest the 9.57 mean and cleared
      // the 2.0 floor, but frame 8.5 did not.
      final aggregate = averageBackendAnalysisFrames([
        frame('pigment_load', 8.5, 'stable', 0.0),
        frame('pigment_load', 9.9, 'worsened', -29.1),
        frame('pigment_load', 10.3, 'worsened', -34.3),
      ], requestedFrames: 3);

      expect(
        aggregate.response['metric_matrix']['pigment_load'],
        closeTo(9.567, 0.001),
      );
      expect(aggregate.response['trend_status'], isEmpty);
      expect(aggregate.response['trend_deltas'], isEmpty);
      final nested = aggregate.response['metrics'] as Map<String, dynamic>;
      expect(nested['trend_status'], isEmpty);
      expect(nested['trend_deltas'], isEmpty);
    });

    testWidgets(
      'disagreeing frames show the number with no verdict or percent',
      (tester) async {
        final aggregate = averageBackendAnalysisFrames([
          frame('pigment_load', 8.5, 'stable', 0.0),
          frame('pigment_load', 9.9, 'worsened', -29.1),
          frame('pigment_load', 10.3, 'worsened', -34.3),
        ], requestedFrames: 3);
        final payload = <String, dynamic>{
          ...aggregate.response,
          'is_follow_up': true,
          'local_history_count': 2,
          'baseline_metric_matrix': {'pigment_load': 7.67},
          'baseline_metric_extraction_paths': {'pigment_load': 'cheek_primary'},
        };

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LuxeReportLayout(
                  rawPayload: payload,
                  requireBackendVerdict: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final card = find.byKey(const ValueKey('result_metric_pigment_load'));
        expect(
          find.descendant(of: card, matching: find.textContaining('9.6')),
          findsWidgets,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('No verdict for this metric'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('Worsened')),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('%')),
          findsNothing,
        );

        final scan = ScanHistoryEntry(
          id: 'disagreeing-frames',
          timestamp: DateTime.utc(2026, 10, 9, 12, 49, 15),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: payload,
        );
        final rows = AiScanDataCsvExporter.format([
          scan,
        ], registryBaselineScanIds: const {}).split('\r\n');
        final header = rows.first.split(',');
        final values = rows[1].split(',');
        expect(values[header.indexOf('pigment_load_trend_status')], isEmpty);
        expect(values[header.indexOf('pigment_load_value')], startsWith('9.5'));
      },
    );

    test('a metric locked on every frame stays locked', () {
      final aggregate = averageBackendAnalysisFrames([
        frame(
          'texture_smoothness',
          56.0,
          'stable',
          0.0,
          lockReason: 'capture_quality_mismatch',
        ),
        frame(
          'texture_smoothness',
          57.0,
          'stable',
          0.0,
          lockReason: 'capture_quality_mismatch',
        ),
        frame(
          'texture_smoothness',
          58.0,
          'stable',
          0.0,
          lockReason: 'capture_quality_mismatch',
        ),
      ], requestedFrames: 3);

      expect(aggregate.response['trend_status'], {
        'texture_smoothness': 'stable',
      });
      expect(aggregate.response['trend_lock_reasons'], {
        'texture_smoothness': 'capture_quality_mismatch',
      });
    });

    test('a locked metric whose frames disagree keeps its lock', () {
      final aggregate = averageBackendAnalysisFrames([
        frame('texture_smoothness', 56.0, 'improved', 9.0),
        frame(
          'texture_smoothness',
          57.0,
          'stable',
          0.0,
          lockReason: 'path_mismatch',
        ),
        frame('texture_smoothness', 58.0, 'improved', 11.0),
      ], requestedFrames: 3);

      expect(aggregate.response['trend_status'], isEmpty);
      expect(aggregate.response['trend_lock_reasons'], {
        'texture_smoothness': 'path_mismatch',
      });
    });
  });

  test('trend fields read from a nested metrics node are honored the same as '
      'top-level ones when picking the nearest frame', () {
    final aggregate = averageBackendAnalysisFrames([
      {
        'metrics': {
          'metric_matrix': {'localized_redness': 10.0},
          'trend_status': {'localized_redness': 'worsened'},
          'trend_deltas': {'localized_redness': -40.0},
          'trend_lock_reasons': {'localized_redness': 'some_reason'},
        },
      },
      {
        'metrics': {
          'metric_matrix': {'localized_redness': 30.0},
          'trend_status': {'localized_redness': 'worsened'},
          'trend_deltas': {'localized_redness': -2.0},
        },
      },
    ], requestedFrames: 2);

    // Average is 20.0, exactly between the two frames' own values (10.0
    // and 30.0) -- both are equally close, so the tie-break (first
    // strictly-smaller distance wins) keeps frame 1's worsened verdict and
    // delta. Both frames agree on "worsened", so the verdict is kept.
    expect(aggregate.response['metric_matrix'], {'localized_redness': 20.0});
    expect(aggregate.response['trend_status'], {
      'localized_redness': 'worsened',
    });
    expect(aggregate.response['trend_deltas'], {'localized_redness': -40.0});
    expect(aggregate.response['trend_lock_reasons'], {
      'localized_redness': 'some_reason',
    });
  });

  test('throws when no frame contributes a finite metric', () {
    expect(
      () => averageBackendAnalysisFrames([
        {
          'metric_matrix': {'localized_redness': null},
        },
      ], requestedFrames: 1),
      throwsStateError,
    );
  });

  test(
    'missing upload acknowledgment never calls the frame uploader',
    () async {
      var uploadCalls = 0;
      await expectLater(
        analyzeBackendFrames(
          [
            Uint8List.fromList([1]),
          ],
          photoUploadAccepted: false,
          uploadFrame: (frame, frameNumber) async {
            uploadCalls++;
            return {
              'metric_matrix': {'localized_redness': 20.0},
            };
          },
        ),
        throwsStateError,
      );
      expect(uploadCalls, 0);
    },
  );

  test(
    'uploads all three frames after acceptance and excludes a failed frame from averages',
    () async {
      final requestedFrameNumbers = <int>[];
      final aggregate = await analyzeBackendFrames(
        [
          Uint8List.fromList([1]),
          Uint8List.fromList([2]),
          Uint8List.fromList([3]),
        ],
        photoUploadAccepted: true,
        frameExposureMetadata: const [
          AiScanFrameExposure(
            iso: 100,
            exposureBias: -0.3,
            shutterSeconds: 1 / 120,
            brightnessValue: 4.5,
            flashFired: false,
          ),
          AiScanFrameExposure(iso: 125),
          AiScanFrameExposure(
            iso: 160,
            exposureBias: 0.0,
            shutterSeconds: 1 / 60,
          ),
        ],
        uploadFrame: (frame, frameNumber) async {
          requestedFrameNumbers.add(frameNumber);
          if (frameNumber == 2) throw Exception('no face detected');
          return {
            'status': 'success',
            'image_quality': {
              'redness_cheek_side': frameNumber == 1 ? 'left' : 'right',
              'cheek_side_convention': cheekSideConventionSubjectAnatomical,
              'redness_both_cheeks_in_dead_zone': false,
              'redness_cheek_roi_pixels': frameNumber == 1 ? 2100 : 2300,
              'redness_cheek_p95_a_after_wb': frameNumber == 1 ? 31.5 : 33.5,
              'redness_cheek_p10_a_after_wb': frameNumber == 1 ? 20.5 : 21.5,
              'redness_cheek_p10_a_before_wb': frameNumber == 1 ? 19.5 : 20.5,
              'face_skin_pixels': 18000,
              'pore_roi_pixels': 6200,
              'u_zone_pixels': 9500,
              'localized_redness_mask_kind': 'cheek_primary',
              'localized_redness_mask_pixels': 9500,
              'texture_smoothness_mask_kind': 'face_skin',
              'texture_smoothness_mask_pixels': 18000,
              'pigment_load_mask_kind': 'cheek_primary',
              'pigment_load_mask_pixels': 9500,
              'pore_visibility_mask_kind': 'tzone_pore',
              'pore_visibility_mask_pixels': 6200,
              'diffuse_flushing_erythema_mask_kind': 'face_skin',
              'diffuse_flushing_erythema_mask_pixels': 10200,
              'under_eye_dark_circle_density_mask_kind': 'under_eye',
              'under_eye_dark_circle_density_mask_pixels': frameNumber == 1
                  ? 991
                  : 1606,
              'under_eye_dark_circle_density_omit_reason': frameNumber == 1
                  ? 'under_eye_roi_too_small'
                  : null,
              'under_eye_texture_density_mask_kind': 'under_eye',
              'under_eye_texture_density_mask_pixels': frameNumber == 1
                  ? 991
                  : 1606,
              'under_eye_texture_density_omit_reason': frameNumber == 1
                  ? 'under_eye_roi_too_small'
                  : null,
            },
            'metric_extraction_paths': {
              'pore_visibility': frameNumber == 1 ? 'pose' : 'dog_spread',
            },
            'metric_matrix': {
              'localized_redness': frameNumber == 1 ? 20.0 : 40.0,
              if (frameNumber == 1) 'pigment_load': 12.0,
            },
          };
        },
      );

      expect(requestedFrameNumbers, [1, 2, 3]);
      expect(aggregate.requestedFrames, 3);
      expect(aggregate.successfulFrames, 2);
      expect(aggregate.response['metric_matrix'], {
        'localized_redness': 30.0,
        'pigment_load': 12.0,
      });
      expect(aggregate.metricContributorCounts, {
        'localized_redness': 2,
        'pigment_load': 1,
      });
      final diagnostics =
          aggregate.response[aiScanPerFrameDiagnosticsKey] as List<dynamic>;
      expect(diagnostics, hasLength(3));
      expect(diagnostics[0], containsPair('cheek_side', 'left'));
      expect(
        diagnostics[0],
        containsPair(
          'cheek_side_convention',
          cheekSideConventionSubjectAnatomical,
        ),
      );
      expect(
        diagnostics[0],
        containsPair('redness_both_cheeks_in_dead_zone', isFalse),
      );
      expect(diagnostics[0], containsPair('localized_redness', 20.0));
      expect(diagnostics[0], containsPair('cheek_p10_a_after_wb', 20.5));
      expect(diagnostics[0], containsPair('shutter_seconds', 1 / 120));
      expect(diagnostics[0], containsPair('flash_fired', isFalse));
      expect(diagnostics[0], containsPair('face_skin_pixels', 18000));
      expect(
        diagnostics[0],
        containsPair('localized_redness_mask_kind', 'cheek_primary'),
      );
      expect(
        diagnostics[0],
        containsPair('pore_visibility_mask_kind', 'tzone_pore'),
      );
      expect(
        diagnostics[0],
        containsPair('pore_visibility_extraction_path', 'pose'),
      );
      for (final metric in const [
        'under_eye_dark_circle_density',
        'under_eye_texture_density',
      ]) {
        // Omitted on frame 1, emitted on frame 3: the count is kept either way.
        expect(
          diagnostics[0],
          containsPair('${metric}_mask_kind', 'under_eye'),
        );
        expect(diagnostics[0], containsPair('${metric}_mask_pixels', 991));
        expect(
          diagnostics[0],
          containsPair('${metric}_omit_reason', 'under_eye_roi_too_small'),
        );
        expect(diagnostics[2], containsPair('${metric}_mask_pixels', 1606));
        expect(diagnostics[2], containsPair('${metric}_omit_reason', isNull));
      }
      expect(diagnostics[1], containsPair('cheek_side', isNull));
      expect(diagnostics[1], containsPair('localized_redness', isNull));
      expect(diagnostics[1], containsPair('iso', 125));
      expect(diagnostics[1], containsPair('brightness_value', isNull));
      expect(diagnostics[2], containsPair('cheek_side', 'right'));
      expect(diagnostics[2], containsPair('localized_redness', 40.0));
      expect(diagnostics[2], containsPair('brightness_value', isNull));

      final saved = ScanHistoryEntry.fromJson(
        ScanHistoryEntry(
          id: 'three-frame-scan',
          timestamp: DateTime.parse('2026-09-26T06:13:00Z'),
          scanType: ScanHistoryEntry.scanTypeAiAnalysis,
          estimatedSkinAge: 0,
          metrics: const <String, double>{},
          rawPayload: aggregate.response,
        ).toJson(),
      );
      final storedDiagnostics =
          saved.rawPayload![aiScanPerFrameDiagnosticsKey] as List<dynamic>;
      expect(storedDiagnostics, hasLength(3));
      expect(storedDiagnostics[1], containsPair('localized_redness', isNull));
      expect(storedDiagnostics[1], containsPair('brightness_value', isNull));
    },
  );

  test(
    'AI multi-frame mode is opt-in and Track Procedure remains single-path',
    () {
      const trackProcedure = CameraScreen();
      const aiAnalysis = CameraScreen(
        isSkincareScan: true,
        aiMultiFrameCapture: true,
        capturePurpose: CameraCapturePurpose.aiSkinAnalysis,
      );

      expect(trackProcedure.aiMultiFrameCapture, isFalse);
      expect(aiAnalysis.aiMultiFrameCapture, isTrue);

      final source = File(
        'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
      ).readAsStringSync();
      expect(source, contains('Future<XFile?> _captureFromLiveCamera()'));
      expect(source, contains('navigator.pop(imagePathToSave);'));
      expect(source, contains('Future<void> _captureAiSkinAnalysisFrames()'));
      expect(
        source,
        contains(
          'final burstFrameCount = widget.aiQuickScan ? 1 : aiScanCaptureFrameCount;',
        ),
      );
      expect(
        source,
        contains('for (var index = 0; index < burstFrameCount; index++)'),
      );
      expect(source, contains('AiSkinAnalysisCaptureResult('));
    },
  );

  test(
    'AI backend fields carry distinct current and previous capture quality tags',
    () {
      final fields = buildAiSkinAnalysisBackendFields(
        focusArea: 'Full Face',
        currentCaptureQuality: 'normal',
        baselineCaptureQuality: 'normal',
      );

      expect(fields['capture_quality'], 'normal');
      expect(fields['baseline_capture_quality'], 'normal');
      expect(fields['capture_quality'], fields['baseline_capture_quality']);

      final mismatched = buildAiSkinAnalysisBackendFields(
        focusArea: 'Full Face',
        currentCaptureQuality: 'normal',
        baselineCaptureQuality: 'low_light',
      );
      expect(mismatched['capture_quality'], 'normal');
      expect(mismatched['baseline_capture_quality'], 'low_light');
    },
  );

  test(
    'AI backend fields carry pose template and guide type for both scans',
    () {
      final fields = buildAiSkinAnalysisBackendFields(
        focusArea: 'Full Face',
        poseTemplate: 'Front',
        baselinePoseTemplate: 'Front',
        guideType: 'facial',
        baselineGuideType: 'facial',
      );

      expect(fields['pose_template'], 'Front');
      expect(fields['baseline_pose_template'], 'Front');
      expect(fields['guide_type'], 'facial');
      expect(fields['baseline_guide_type'], 'facial');
    },
  );

  test('AI backend fields omit pose/guide keys entirely when unknown', () {
    final fields = buildAiSkinAnalysisBackendFields(focusArea: 'Full Face');

    expect(fields.containsKey('pose_template'), isFalse);
    expect(fields.containsKey('baseline_pose_template'), isFalse);
    expect(fields.containsKey('guide_type'), isFalse);
    expect(fields.containsKey('baseline_guide_type'), isFalse);
  });

  group('cheek lock only when both scans used within_cheek_spread', () {
    Map<String, dynamic> scan({
      required String branch,
      required String side,
      required double redness,
    }) => rednessPayload(
      branch: branch,
      cheekSide: side,
      redness: redness,
      region: side == 'both' ? 'u_zone' : '${side}_cheek',
      frameP95: const [10.0, 10.5, 10.2],
      p10: 4.0,
      p95: 10.0,
    );

    ({
      Map<String, String> trendStatus,
      Map<String, double> trendDeltas,
      Map<String, String> trendLockReasons,
      Set<String> rednessLockReasons,
      bool cheekLockSkippedLowValues,
      bool regionLockSkippedLowValues,
    })
    run(Map<String, dynamic> baseline, Map<String, dynamic> current) =>
        downgradeRednessTrendForCaptureMismatch(
          trendStatus: const {'localized_redness': 'stable'},
          trendDeltas: const {'localized_redness': 0.0},
          trendLockReasons: const {},
          baselinePayload: baseline,
          currentPayload: current,
        );

    test('within_cheek_spread "left" baseline vs baseline_p95_anchor "both" '
        '(the 18/21 Oct scans): no cheek_mismatch', () {
      for (final current in const [0.83, 4.33, 9.3, 14.0]) {
        final result = run(
          scan(branch: 'within_cheek_spread', side: 'left', redness: 9.3),
          scan(branch: 'baseline_p95_anchor', side: 'both', redness: current),
        );
        expect(
          result.rednessLockReasons,
          isNot(contains('cheek_mismatch')),
          reason: '$current',
        );
        expect(
          result.trendLockReasons['localized_redness'],
          isNot('cheek_mismatch'),
          reason: '$current',
        );
      }
    });

    test('anchored by redness_branch even if a side label is single', () {
      final result = run(
        scan(branch: 'within_cheek_spread', side: 'left', redness: 9.3),
        scan(branch: 'baseline_p95_anchor', side: 'right', redness: 14.0),
      );
      expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
    });

    test('both within_cheek_spread with different sides still locks', () {
      final result = run(
        scan(branch: 'within_cheek_spread', side: 'left', redness: 9.3),
        scan(branch: 'within_cheek_spread', side: 'right', redness: 9.3),
      );
      expect(result.trendLockReasons['localized_redness'], 'cheek_mismatch');
      expect(result.trendStatus.containsKey('localized_redness'), isFalse);
    });

    test('the low-value skip still sets its flag', () {
      final result = run(
        scan(branch: 'within_cheek_spread', side: 'left', redness: 1.43),
        scan(branch: 'baseline_p95_anchor', side: 'both', redness: 3.13),
      );
      expect(result.rednessLockReasons, isNot(contains('cheek_mismatch')));
      expect(result.cheekLockSkippedLowValues, isTrue);
    });
  });
}
