// Models for the v18 quest sheet: one quest's last days (docs/design-v18-quests.md).

/// One day of a quest's history. [tracked] is false when the quest was not part of that day.
class QuestDay {
  const QuestDay({
    required this.date,
    required this.tracked,
    required this.actual,
    required this.target,
    required this.unit,
    required this.done,
  });

  factory QuestDay.fromJson(Map<String, dynamic> j) => QuestDay(
    date: j['date'] as String? ?? '',
    tracked: j['tracked'] as bool? ?? false,
    actual: (j['actual'] as num?) ?? 0,
    target: (j['target'] as num?) ?? 0,
    unit: j['unit'] as String? ?? '',
    done: j['done'] as bool? ?? false,
  );

  /// `YYYY-MM-DD` in the person's zone.
  final String date;
  final bool tracked;
  final num actual;
  final num target;
  final String unit;
  final bool done;

  double get fraction => target <= 0 ? 0 : (actual / target).clamp(0, 1).toDouble();
}

/// GET /api/quests/{key}/history, oldest day first.
List<QuestDay> parseQuestHistory(Object? data) => [
  if (data is Map && data['days'] is List)
    for (final d in data['days'] as List)
      if (d is Map) QuestDay.fromJson(d.cast<String, dynamic>()),
];
