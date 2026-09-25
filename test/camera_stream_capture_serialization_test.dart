import 'dart:async';

import 'package:aesthetic_skin_tracker/features/skin_tracker/presentation/screens/camera_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Covers the two pure pieces behind the CameraException(-11803, "Cannot
/// Record") fix on iOS:
///
/// - AsyncTransitionGate: serializes a capture against a stream restart's
///   native startImageStream() call so stopImageStream()/takePicture()
///   never race a stream that hasn't finished starting back up yet.
/// - isRecordingSessionConflictError: the pure classification behind the
///   "retry once" behavior in _takePictureWithRetry.
///
/// Neither of these touches CameraController -- they're the
/// controller-agnostic seams the real capture flow is built on, extracted
/// specifically so this ordering/classification logic is testable without
/// a camera.
void main() {
  group('AsyncTransitionGate', () {
    test('awaitPending completes immediately when nothing is tracked', () async {
      final gate = AsyncTransitionGate();
      expect(gate.pending, isNull);
      // Should not hang.
      await gate.awaitPending();
    });

    test(
      'awaitPending does not resolve until the tracked operation completes',
      () async {
        final gate = AsyncTransitionGate();
        final completer = Completer<void>();
        gate.track(completer.future);

        var resolved = false;
        final waiter = gate.awaitPending().then((_) => resolved = true);

        // Give the event loop a couple of turns -- still must not resolve.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(resolved, isFalse);

        completer.complete();
        await waiter;
        expect(resolved, isTrue);
      },
    );

    test(
      'a capture starting right after a restart is serialized behind it -- '
      'this is the exact race that threw -11803 on iOS',
      () async {
        final gate = AsyncTransitionGate();
        final restartCompleter = Completer<void>();
        gate.track(restartCompleter.future);

        final events = <String>[];

        // Simulates _startLightingStream's fire-and-forget restart still
        // being in flight when the shutter is tapped again.
        final capture = () async {
          await gate.awaitPending();
          events.add('stopImageStream');
          events.add('takePicture');
        }();

        await Future<void>.delayed(Duration.zero);
        // The capture must not have touched the session yet.
        expect(events, isEmpty);

        events.add('nativeStartImageStreamFinished');
        restartCompleter.complete();
        await capture;

        expect(events, [
          'nativeStartImageStreamFinished',
          'stopImageStream',
          'takePicture',
        ]);
      },
    );

    test('pending clears once the tracked operation completes', () async {
      final gate = AsyncTransitionGate();
      final completer = Completer<void>();
      gate.track(completer.future);
      expect(gate.pending, isNotNull);

      completer.complete();
      await Future<void>.delayed(Duration.zero);
      expect(gate.pending, isNull);
    });

    test(
      'tracking a newer operation before the older one settles is not '
      'clobbered by the older one completing late',
      () async {
        final gate = AsyncTransitionGate();
        final first = Completer<void>();
        final second = Completer<void>();

        gate.track(first.future);
        gate.track(second.future);
        expect(gate.pending, same(second.future));

        // The stale first transition finishing late must not clear the
        // newer pending one.
        first.complete();
        await Future<void>.delayed(Duration.zero);
        expect(gate.pending, same(second.future));

        second.complete();
        await Future<void>.delayed(Duration.zero);
        expect(gate.pending, isNull);
      },
    );
  });

  group('isRecordingSessionConflictError', () {
    test('matches a code containing 11803', () {
      final result = isRecordingSessionConflictError(
        code: 'Error -11803',
        description: 'Something else',
      );
      expect(result, isTrue);
    });

    test('matches a description containing 11803', () {
      final result = isRecordingSessionConflictError(
        code: 'unknown',
        description: 'Video capture failed with -11803',
      );
      expect(result, isTrue);
    });

    test('matches a description containing "Cannot Record" case-insensitively', () {
      final result = isRecordingSessionConflictError(
        code: 'unknown',
        description: 'Cannot Record',
      );
      expect(result, isTrue);
    });

    test('does not match an unrelated camera error', () {
      final result = isRecordingSessionConflictError(
        code: 'CameraAccessDenied',
        description: 'The user denied camera permission.',
      );
      expect(result, isFalse);
    });

    test('does not match when description is null and code is unrelated', () {
      final result = isRecordingSessionConflictError(
        code: 'takePictureFailed',
        description: null,
      );
      expect(result, isFalse);
    });
  });
}
