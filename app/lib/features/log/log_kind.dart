enum LogKind {
  pushups,
  reading,
  meal,
  yoga,
  water,
  produce,
  breathing,
  activity;

  String get label => switch (this) {
    LogKind.pushups => 'Push-ups',
    LogKind.reading => 'Reading',
    LogKind.meal => 'Meal',
    LogKind.yoga => 'Yoga',
    LogKind.water => 'Water',
    LogKind.produce => 'Fruit and vegetables',
    LogKind.breathing => 'Breathing',
    LogKind.activity => 'Activity',
  };

  String get title => switch (this) {
    LogKind.pushups => 'Log push-ups',
    LogKind.reading => 'Log reading',
    LogKind.meal => 'Log a meal',
    LogKind.yoga => 'Log yoga',
    LogKind.water => 'Log water',
    LogKind.produce => 'Log fruit and vegetables',
    LogKind.breathing => 'Breathe',
    LogKind.activity => 'Log activity',
  };

  /// The quest whose colour and icon this form borrows.
  String get questKey => switch (this) {
    LogKind.pushups => 'pushups',
    LogKind.reading => 'reading',
    LogKind.meal => 'meals_logged',
    LogKind.yoga => 'yoga',
    LogKind.water => 'water',
    LogKind.produce => 'produce',
    LogKind.breathing => 'breathing',
    LogKind.activity => 'exercise',
  };

  /// The log form that feeds a quest, or null for quests the app cannot log by hand.
  static LogKind? forQuest(String key) => switch (key) {
    'pushups' => LogKind.pushups,
    'reading' => LogKind.reading,
    'meals_logged' || 'protein' => LogKind.meal,
    'yoga' => LogKind.yoga,
    'water' => LogKind.water,
    'produce' => LogKind.produce,
    'breathing' => LogKind.breathing,
    'exercise' => LogKind.activity,
    _ => null,
  };
}
