// lib/models/acne_rosacea_log.dart
//
// A single severity log entry for the dedicated Acne & Rosacea Tracker.
// Stored as a JSON list under SharedPreferences key `acne_rosacea_logs`
// (a Map<metricKey, List<entry>>). See AppPrefs.{get,add,remove}AcneRosaceaLog.

class AcneRosaceaLog {
  final DateTime timestamp;
  final String metricKey; // SkinMetricRegistry key (e.g. 'acneSeverity')
  final int value; // 0–10 severity / frequency
  final String note;
  final String
  imagePath; // Absolute file path (native) or data: URI / blob: URL (web). Empty if none.

  const AcneRosaceaLog({
    required this.timestamp,
    required this.metricKey,
    required this.value,
    this.note = '',
    this.imagePath = '',
  });

  bool get hasPhoto => imagePath.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'metricKey': metricKey,
    'value': value,
    'note': note,
    if (imagePath.isNotEmpty) 'imagePath': imagePath,
  };

  factory AcneRosaceaLog.fromJson(Map<String, dynamic> json) => AcneRosaceaLog(
    timestamp: DateTime.parse(json['timestamp'] as String),
    metricKey: json['metricKey'] as String? ?? '',
    value: ((json['value'] as num?) ?? 0).toInt().clamp(0, 10),
    note: json['note'] as String? ?? '',
    imagePath: json['imagePath'] as String? ?? '',
  );
}
