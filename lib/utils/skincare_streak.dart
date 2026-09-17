class SkincareStreakCalculator {
  static const int _graceHour = 12;

  static int computeCurrentStreak(
    Iterable<DateTime> loggedDates, {
    DateTime? now,
  }) {
    final baseNow = now ?? DateTime.now();
    final uniqueDates = loggedDates
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet()
        .toList()
      ..sort();

    if (uniqueDates.isEmpty) return 0;

    final today = DateTime(baseNow.year, baseNow.month, baseNow.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final candidate = uniqueDates.lastWhere(
      (date) => date == today || date == yesterday,
      orElse: () => uniqueDates.last,
    );

    if (!uniqueDates.contains(today) &&
        baseNow.hour < _graceHour &&
        uniqueDates.contains(yesterday)) {
      return _countBackwardsFrom(uniqueDates, yesterday);
    }

    if (!uniqueDates.contains(today) &&
        !uniqueDates.contains(yesterday) &&
        uniqueDates.last.isBefore(yesterday)) {
      return 0;
    }

    if (!uniqueDates.contains(today) &&
        uniqueDates.last == yesterday &&
        baseNow.hour >= _graceHour) {
      return 0;
    }

    return _countBackwardsFrom(uniqueDates, candidate);
  }

  static int _countBackwardsFrom(
    List<DateTime> uniqueDates,
    DateTime anchor,
  ) {
    var streak = 0;
    var cursor = anchor;
    final set = uniqueDates.toSet();

    while (set.contains(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }
}
