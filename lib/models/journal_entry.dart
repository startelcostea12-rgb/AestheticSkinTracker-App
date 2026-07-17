// lib/models/journal_entry.dart
class JournalEntry {
  final DateTime date;
  final String title;
  final String content;
  final int moodRating; // 1–5
  final String? attachedImagePath;
  final int? swellingLevel; // 1-10, used for facial cosmetic recovery tracking

  JournalEntry({
    required this.date,
    required this.title,
    required this.content,
    this.moodRating = 3,
    this.attachedImagePath,
    this.swellingLevel,
  });

  static String swellingLabelFor(int level) {
    if (level <= 1) return 'None';
    if (level <= 4) return 'Mild';
    if (level <= 7) return 'Moderate';
    return 'Severe';
  }

  String? get swellingLabel =>
      swellingLevel == null ? null : swellingLabelFor(swellingLevel!);

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final rawSwelling = json['swellingLevel'];
    return JournalEntry(
      date: DateTime.parse(json['date'] as String),
      title: json['title'] as String,
      content: json['content'] as String,
      moodRating: json['moodRating'] as int? ?? 3,
      attachedImagePath: json['attachedImagePath'] as String?,
      swellingLevel: rawSwelling is int
          ? rawSwelling
          : (rawSwelling as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'title': title,
      'content': content,
      'moodRating': moodRating,
      'attachedImagePath': attachedImagePath,
      'swellingLevel': swellingLevel,
    };
  }

  JournalEntry copyWith({
    DateTime? date,
    String? title,
    String? content,
    int? moodRating,
    String? attachedImagePath,
    int? swellingLevel,
    bool clearAttachedImagePath = false,
    bool clearSwellingLevel = false,
  }) {
    return JournalEntry(
      date: date ?? this.date,
      title: title ?? this.title,
      content: content ?? this.content,
      moodRating: moodRating ?? this.moodRating,
      attachedImagePath: clearAttachedImagePath
          ? null
          : (attachedImagePath ?? this.attachedImagePath),
      swellingLevel: clearSwellingLevel
          ? null
          : (swellingLevel ?? this.swellingLevel),
    );
  }
}
