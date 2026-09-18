class RecoveryPlanReminder {
  const RecoveryPlanReminder({
    required this.kind,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
  });

  final String kind;
  final int hour;
  final int minute;
  final String title;
  final String body;

  factory RecoveryPlanReminder.fromJson(Map<String, dynamic> json) {
    return RecoveryPlanReminder(
      kind: json['kind']?.toString() ?? 'note',
      hour: (json['hour'] as num?)?.toInt() ?? 19,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? 'Recovery check-in',
      body: json['body']?.toString() ?? 'Consider adding a recovery note.',
    );
  }
}

class RecoveryPlanDay {
  const RecoveryPlanDay({
    required this.day,
    required this.whatsCommon,
    required this.watchFor,
    required this.suggestedAction,
    required this.reminder,
  });

  final int day;
  final String whatsCommon;
  final String watchFor;
  final String suggestedAction;
  final RecoveryPlanReminder reminder;

  factory RecoveryPlanDay.fromJson(Map<String, dynamic> json) {
    return RecoveryPlanDay(
      day: (json['day'] as num?)?.toInt() ?? 1,
      whatsCommon: json['whats_common']?.toString() ?? '',
      watchFor: json['watch_for']?.toString() ?? '',
      suggestedAction: json['suggested_action']?.toString() ?? '',
      reminder: RecoveryPlanReminder.fromJson(
        Map<String, dynamic>.from(json['reminder'] as Map? ?? const {}),
      ),
    );
  }
}

class RecoveryPlan {
  const RecoveryPlan({
    required this.id,
    required this.procedureType,
    required this.title,
    required this.reviewStatus,
    required this.disclaimer,
    required this.days,
  });

  final String id;
  final String procedureType;
  final String title;
  final String reviewStatus;
  final String disclaimer;
  final List<RecoveryPlanDay> days;

  factory RecoveryPlan.fromJson(Map<String, dynamic> json) {
    return RecoveryPlan(
      id: json['id']?.toString() ?? '',
      procedureType: json['procedure_type']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Recovery plan',
      reviewStatus: json['review_status']?.toString() ?? '',
      disclaimer: json['disclaimer']?.toString() ?? '',
      days: (json['days'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => RecoveryPlanDay.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
    );
  }

  RecoveryPlanDay? dayFor(DateTime startDate, DateTime now) {
    final dayNumber = now.difference(startDate).inDays + 1;
    if (dayNumber < 1 || dayNumber > 7) return null;
    for (final day in days) {
      if (day.day == dayNumber) return day;
    }
    return null;
  }
}
