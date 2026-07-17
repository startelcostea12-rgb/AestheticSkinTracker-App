import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/procedure_log.dart';

const String procedureLogsBoxName = 'procedureLogs';

final procedureLogsProvider =
    AsyncNotifierProvider<ProcedureLogsNotifier, List<ProcedureLog>>(
      ProcedureLogsNotifier.new,
    );

class ProcedureLogsNotifier extends AsyncNotifier<List<ProcedureLog>> {
  @override
  Future<List<ProcedureLog>> build() {
    return fetchLogs();
  }

  Future<List<ProcedureLog>> fetchLogs() async {
    final box = await _openBox();
    final logs = _sortedLogs(box.values);
    state = AsyncData(logs);
    return logs;
  }

  Future<void> addLog(ProcedureLog log) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final box = await _openBox();
      await box.put(log.id, log);
      return _sortedLogs(box.values);
    });
  }

  Future<void> updateLog(ProcedureLog log) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final box = await _openBox();
      await box.put(log.id, log);
      return _sortedLogs(box.values);
    });
  }

  /// Deletes a single procedure log by id.
  Future<void> deleteLog(String id) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final box = await _openBox();
      await box.delete(id);
      return _sortedLogs(box.values);
    });
  }

  /// Clears every procedure log from the box and refreshes state to empty.
  /// Use after a data reset so the UI immediately reflects the cleared box.
  Future<void> clearAll() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final box = await _openBox();
      await box.clear();
      return _sortedLogs(box.values);
    });
  }

  Future<Box<ProcedureLog>> _openBox() {
    if (Hive.isBoxOpen(procedureLogsBoxName)) {
      return Future.value(Hive.box<ProcedureLog>(procedureLogsBoxName));
    }
    return Hive.openBox<ProcedureLog>(procedureLogsBoxName);
  }

  List<ProcedureLog> _sortedLogs(Iterable<ProcedureLog> logs) {
    final sortedLogs = logs.toList();
    sortedLogs.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return sortedLogs;
  }
}
