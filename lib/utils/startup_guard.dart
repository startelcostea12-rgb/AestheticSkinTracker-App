import 'dart:async';

import 'package:flutter/foundation.dart';

/// How long one startup step may take before the app gives up on it and
/// continues to its first screen. Startup timing only -- unrelated to any
/// metric.
const Duration defaultStartupStepTimeout = Duration(seconds: 8);

/// Runs one optional startup step so it can never keep the app on the
/// launch screen: it either finishes, throws (logged and skipped), or
/// exceeds [timeout] (logged and left running in the background). Returns
/// true only when the step completed normally.
Future<bool> runStartupStep(
  String name,
  Future<void> Function() step, {
  Duration timeout = defaultStartupStepTimeout,
}) async {
  try {
    await step().timeout(timeout);
    return true;
  } on TimeoutException {
    debugPrint(
      '[Startup] $name did not finish within ${timeout.inSeconds}s; '
      'continuing to the first screen.',
    );
  } catch (error) {
    debugPrint('[Startup] $name failed: $error; continuing.');
  }
  return false;
}
