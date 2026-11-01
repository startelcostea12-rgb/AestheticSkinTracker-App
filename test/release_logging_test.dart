import 'dart:io';

import 'package:aesthetic_skin_tracker/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalDebugPrint = debugPrint;
  final messages = <String?>[];
  setUp(() {
    messages.clear();
    AppLogger.setVerboseEnabled(false);
    debugPrint = (String? message, {int? wrapWidth}) => messages.add(message);
  });
  tearDown(() {
    debugPrint = originalDebugPrint;
    AppLogger.setVerboseEnabled(false);
  });

  test('debug diagnostics remain available in debug builds', () {
    AppLogger.debug('diagnostic');
    expect(messages, ['diagnostic']);
  });

  test('verbose logging remains opt-in', () {
    AppLogger.verbose('hidden');
    expect(messages, isEmpty);
    AppLogger.setVerboseEnabled(true);
    AppLogger.verbose('visible');
    expect(messages, ['visible']);
  });

  test('both logger entry points return before output outside debug mode', () {
    final source = File('lib/utils/app_logger.dart').readAsStringSync();
    expect(source, contains('if (!kDebugMode) return;'));
    expect(source, contains('if (!kDebugMode || !_verboseEnabled) return;'));
  });
}
