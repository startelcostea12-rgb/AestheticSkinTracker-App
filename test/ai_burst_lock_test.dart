import 'dart:io';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:aesthetic_skin_tracker/models/ai_scan_frame_exposure.dart';
import 'package:aesthetic_skin_tracker/utils/ai_scan_data_csv_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

const _locked = AiScanFrameExposure(
  iso: 125,
  shutterSeconds: 1 / 60,
  brightnessValue: 3.11,
  exposureLockSucceeded: true,
  focusLockSucceeded: true,
);

void main() {
  group('focus lock request', () {
    test('success is reported once', () async {
      var requests = 0;
      expect(await requestAiBurstFocusLock(() async => requests++), isTrue);
      expect(requests, 1);
    });

    test('unsupported focus lock does not stop the burst', () async {
      final ok = await requestAiBurstFocusLock(
        () async => throw StateError('focus lock unsupported'),
      );
      expect(ok, isFalse);
      expect(
        const AiScanFrameExposure(
          focusLockSucceeded: false,
        ).toJson()['focus_lock_succeeded'],
        isFalse,
      );
    });
  });

  group('burst exposure summary', () {
    test('all frames share the locked ISO and exposure time', () {
      final summary = summarizeAiBurstExposure(List.filled(5, _locked));
      expect(summary.iso, 125);
      expect(summary.shutterSeconds, closeTo(1 / 60, 1e-12));
      expect(summary.shared, isTrue);
    });

    test('Bv alone may move; settings are still shared', () {
      final summary = summarizeAiBurstExposure([
        _locked,
        const AiScanFrameExposure(
          iso: 125,
          shutterSeconds: 1 / 60,
          brightnessValue: 3.09,
        ),
      ]);
      expect(summary.shared, isTrue);
    });

    test('a frame that re-exposed is reported', () {
      expect(
        summarizeAiBurstExposure([
          _locked,
          const AiScanFrameExposure(iso: 160, shutterSeconds: 1 / 60),
        ]).shared,
        isFalse,
      );
      expect(
        summarizeAiBurstExposure([
          _locked,
          const AiScanFrameExposure(iso: 125, shutterSeconds: 1 / 30),
        ]).shared,
        isFalse,
      );
    });

    test('missing EXIF: nothing to confirm', () {
      expect(
        summarizeAiBurstExposure([_locked, const AiScanFrameExposure()]).shared,
        isNull,
      );
      expect(summarizeAiBurstExposure(const []).shared, isNull);
    });

    test('log line names the locked ISO and exposure time', () {
      final line = aiBurstLockLogLine(
        exposureLockSucceeded: true,
        focusLockSucceeded: true,
        frames: List.filled(3, _locked),
      );
      expect(line, startsWith('[AI_BURST_LOCK] frames=3 '));
      expect(line, contains('exposure_lock=true focus_lock=true'));
      expect(line, contains('locked_iso=125'));
      expect(line, contains('locked_exposure_time=0.01667s (1/60)'));
      expect(line, contains('frames_share_settings=true'));
      expect(line, contains('isos=[125, 125, 125]'));
    });
  });

  test('CSV exports focus_lock_succeeded per frame', () {
    expect(
      AiScanDataCsvExporter.perFrameFields,
      contains('focus_lock_succeeded'),
    );
    final header = AiScanDataCsvExporter.format(
      const [],
      registryBaselineScanIds: const {},
    ).split('\r\n').first.split(',');
    expect(header, contains('frame1_focus_lock_succeeded'));
    expect(header, contains('frame5_focus_lock_succeeded'));
  });

  test('wiring: exposure and focus locked before frame 1, released after', () {
    final source = File(
      'lib/features/skin_tracker/presentation/screens/camera_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _captureAiSkinAnalysisFrames()');
    expect(start, isNonNegative);
    final body = source.substring(start);
    final exposureLock = body.indexOf('setExposureMode(ExposureMode.locked)');
    final focusLock = body.indexOf('setFocusMode(FocusMode.locked)');
    final firstFrame = body.indexOf(
      'for (var index = 0; index < burstFrameCount; index++)',
    );
    final logLine = body.indexOf('aiBurstLockLogLine(');
    final release = body.indexOf('} finally {');
    expect(exposureLock, isNonNegative);
    expect(focusLock, greaterThan(exposureLock));
    expect(firstFrame, greaterThan(focusLock));
    expect(logLine, greaterThan(firstFrame));
    // No re-lock or unlock inside the burst loop.
    final loop = body.substring(firstFrame, logLine);
    expect(loop, isNot(contains('setExposureMode')));
    expect(loop, isNot(contains('setFocusMode')));
    final cleanup = body.substring(release, release + 600);
    expect(cleanup, contains('setExposureMode(ExposureMode.auto)'));
    expect(cleanup, contains('setFocusMode(FocusMode.auto)'));
  });
}
