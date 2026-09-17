import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConversionEventRecord {
  const ConversionEventRecord({
    required this.event,
    required this.timestamp,
    required this.properties,
  });

  final String event;
  final DateTime timestamp;
  final Map<String, dynamic> properties;

  factory ConversionEventRecord.fromMap(Map<String, dynamic> map) {
    final rawEvent = map['event']?.toString().trim();
    final rawTimestamp = map['timestamp']?.toString().trim();

    final event = (rawEvent == null || rawEvent.isEmpty) ? 'unknown' : rawEvent;
    final timestamp = DateTime.tryParse(rawTimestamp ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final rawProps = map['properties'];
    final properties = rawProps is Map
        ? Map<String, dynamic>.from(rawProps)
        : <String, dynamic>{};

    return ConversionEventRecord(
      event: event,
      timestamp: timestamp,
      properties: properties,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event': event,
      'timestamp': timestamp.toIso8601String(),
      'properties': properties,
    };
  }
}

class ConversionFunnelSummary {
  const ConversionFunnelSummary({
    required this.paywallViews,
    required this.trialStarts,
    required this.subscribes,
    required this.churns,
    required this.immediateChurns,
    required this.viewToTrialRate,
    required this.trialToSubscribeRate,
    required this.viewToSubscribeRate,
    required this.immediateChurnRate,
    required this.overallChurnPerSubscribeRate,
  });

  final int paywallViews;
  final int trialStarts;
  final int subscribes;
  final int churns;
  final int immediateChurns;
  final double viewToTrialRate;
  final double trialToSubscribeRate;
  final double viewToSubscribeRate;
  final double immediateChurnRate;
  final double overallChurnPerSubscribeRate;
}

class ConversionEvent {
  static const String paywallView = 'paywall_view';
  static const String trialStart = 'trial_start';
  static const String subscribe = 'subscribe';
  static const String churn = 'churn';
}

class ConversionAnalytics {
  ConversionAnalytics._();

  static const String _storageKey = 'conversion_event_log_v1';
  static const int _maxStoredEvents = 200;

  static Future<void> track(
    String eventName, {
    Map<String, dynamic> properties = const <String, dynamic>{},
  }) async {
    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'event': eventName,
      'timestamp': now,
      'properties': properties,
    };

    debugPrint('[CONVERSION] ${jsonEncode(payload)}');

    final prefs = await SharedPreferences.getInstance();
    final existingRaw = prefs.getString(_storageKey);
    final events = <Map<String, dynamic>>[];

    if (existingRaw != null && existingRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              events.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {
        // If historical data is malformed, start fresh instead of throwing.
      }
    }

    events.add(payload);
    final trimmed = events.length > _maxStoredEvents
        ? events.sublist(events.length - _maxStoredEvents)
        : events;

    await prefs.setString(_storageKey, jsonEncode(trimmed));
  }

  static Future<List<ConversionEventRecord>> readEventLog() async {
    final prefs = await SharedPreferences.getInstance();
    final existingRaw = prefs.getString(_storageKey);
    final out = <ConversionEventRecord>[];

    if (existingRaw == null || existingRaw.trim().isEmpty) {
      return out;
    }

    try {
      final decoded = jsonDecode(existingRaw);
      if (decoded is! List) return out;
      for (final item in decoded) {
        if (item is Map) {
          out.add(
            ConversionEventRecord.fromMap(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
      out.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return out;
    } catch (_) {
      return out;
    }
  }

  static ConversionFunnelSummary summarizeFunnel(
    List<ConversionEventRecord> records,
  ) {
    var paywallViews = 0;
    var trialStarts = 0;
    var subscribes = 0;
    var churns = 0;

    for (final record in records) {
      switch (record.event) {
        case ConversionEvent.paywallView:
          paywallViews++;
          break;
        case ConversionEvent.trialStart:
          trialStarts++;
          break;
        case ConversionEvent.subscribe:
          subscribes++;
          break;
        case ConversionEvent.churn:
          churns++;
          break;
      }
    }

    var immediateChurns = 0;
    for (var i = 0; i < records.length; i++) {
      if (records[i].event != ConversionEvent.subscribe) continue;
      for (var j = i + 1; j < records.length; j++) {
        final nextEvent = records[j].event;
        if (nextEvent == ConversionEvent.churn) {
          immediateChurns++;
          break;
        }
        if (nextEvent == ConversionEvent.subscribe ||
            nextEvent == ConversionEvent.paywallView ||
            nextEvent == ConversionEvent.trialStart) {
          break;
        }
      }
    }

    double ratio(int num, int den) {
      if (den <= 0) return 0.0;
      return num / den;
    }

    return ConversionFunnelSummary(
      paywallViews: paywallViews,
      trialStarts: trialStarts,
      subscribes: subscribes,
      churns: churns,
      immediateChurns: immediateChurns,
      viewToTrialRate: ratio(trialStarts, paywallViews),
      trialToSubscribeRate: ratio(subscribes, trialStarts),
      viewToSubscribeRate: ratio(subscribes, paywallViews),
      immediateChurnRate: ratio(immediateChurns, subscribes),
      overallChurnPerSubscribeRate: ratio(churns, subscribes),
    );
  }

  static Future<void> clearEventLog() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
