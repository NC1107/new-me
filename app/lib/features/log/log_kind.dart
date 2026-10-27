enum LogKind {
  pushups,
  reading,
  meal,
  yoga;

  String get label => switch (this) {
    LogKind.pushups => 'Pushups',
    LogKind.reading => 'Reading',
    LogKind.meal => 'Meal',
    LogKind.yoga => 'Yoga',
  };

  static LogKind fromName(String? name) =>
      LogKind.values.firstWhere((k) => k.name == name, orElse: () => LogKind.pushups);

  /// The log form that feeds a quest, or null for quests the app cannot log by hand.
  static LogKind? forQuest(String key) => switch (key) {
    'pushups' => LogKind.pushups,
    'reading' => LogKind.reading,
    'meals_logged' || 'protein' => LogKind.meal,
    'yoga' => LogKind.yoga,
    _ => null,
  };
}
