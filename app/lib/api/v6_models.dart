/// Wire models for the v6 autopilot features: readiness, the plan, what completed a quest, the
/// weekly recap, goal proposals and meal estimates. Parsing is tolerant: a piece the server
/// leaves out or this build does not know degrades to "nothing to show".
library;

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

num _num(Object? v, [num fallback = 0]) => (v as num?) ?? fallback;

String _str(Object? v, [String fallback = '']) => v as String? ?? fallback;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _timeJson(DateTime? v) => v?.toUtc().toIso8601String();

Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<T> _items<T>(Object? v, T? Function(Object?) parse) => [
  if (v is List)
    for (final item in v) ?parse(item),
];

/// Which Health workout completed a quest, as `doneBy` on a quest reports it.
class DoneBy {
  const DoneBy({required this.kind, required this.type, required this.minutes});

  static DoneBy? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return DoneBy(kind: _str(j['kind']), type: _str(j['type']), minutes: _int(j['minutes']));
  }

  /// Always `workout` today.
  final String kind;

  /// strength, hiit or yoga.
  final String type;
  final int minutes;

  Map<String, dynamic> toJson() => {'kind': kind, 'type': type, 'minutes': minutes};
}

enum ReadinessLevel {
  ready,
  normal,
  easy;

  static ReadinessLevel? parse(Object? v) {
    for (final l in values) {
      if (l.name == v) return l;
    }
    return null;
  }
}

class ReadinessReason {
  const ReadinessReason({required this.kind, required this.text});

  final String kind;
  final String text;

  Map<String, dynamic> toJson() => {'kind': kind, 'text': text};
}

/// How ready the day looks, from last night's sleep and the body's own baselines.
class Readiness {
  const Readiness({required this.level, this.reasons = const [], this.basis = 'full'});

  /// Null when the level is one this build does not know, so the card stays hidden.
  static Readiness? tryParse(Object? v) {
    final j = _map(v);
    final level = ReadinessLevel.parse(j?['level']);
    if (j == null || level == null) return null;
    return Readiness(
      level: level,
      reasons: _items(j['reasons'], (r) {
        final m = _map(r);
        if (m == null || _str(m['text']).isEmpty) return null;
        return ReadinessReason(kind: _str(m['kind']), text: _str(m['text']));
      }),
      basis: _str(j['basis'], 'full'),
    );
  }

  final ReadinessLevel level;
  final List<ReadinessReason> reasons;

  /// `full`, or `sleep_only` while HRV and resting heart rate lack seven days of history.
  final String basis;

  bool get sleepOnly => basis == 'sleep_only';

  /// The reasons about the person's numbers, without the server's note on what the level is
  /// based on.
  List<ReadinessReason> get findings => [
    for (final r in reasons)
      if (r.kind != 'basis') r,
  ];

  /// What the level is based on when that is less than everything, in the server's words; null
  /// when it is based on sleep and heart data both.
  String? get basisNote {
    for (final r in reasons) {
      if (r.kind == 'basis') return r.text;
    }
    return sleepOnly ? 'Based on sleep only until there are 7 days of heart data' : null;
  }

  Map<String, dynamic> toJson() => {
    'level': level.name,
    'reasons': [for (final r in reasons) r.toJson()],
    'basis': basis,
  };
}

enum PlanItemKind {
  done,
  todo,
  habit;

  static PlanItemKind? parse(Object? v) {
    for (final k in values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

class PlanItem {
  const PlanItem({required this.kind, required this.key, required this.text});

  static PlanItem? tryParse(Object? v) {
    final j = _map(v);
    final kind = PlanItemKind.parse(j?['kind']);
    if (j == null || kind == null || _str(j['text']).isEmpty) return null;
    return PlanItem(kind: kind, key: _str(j['key']), text: _str(j['text']));
  }

  final PlanItemKind kind;

  /// The quest key, or `habit:<id>`.
  final String key;
  final String text;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'key': key, 'text': text};
}

/// The day's plan: what data already did, what is left and the habits by time.
class Plan {
  const Plan({this.items = const [], this.summary = ''});

  static Plan? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return Plan(items: _items(j['items'], PlanItem.tryParse), summary: _str(j['summary']));
  }

  final List<PlanItem> items;
  final String summary;

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
    'summary': summary,
  };
}

/// Optional server features, so the app hides what is switched off.
class Features {
  const Features({this.mealEstimate = false, this.planPolish = false});

  factory Features.fromJson(Object? v) {
    final j = _map(v);
    return Features(
      mealEstimate: j?['mealEstimate'] as bool? ?? false,
      planPolish: j?['planPolish'] as bool? ?? false,
    );
  }

  final bool mealEstimate;
  final bool planPolish;

  Map<String, dynamic> toJson() => {'mealEstimate': mealEstimate, 'planPolish': planPolish};
}

/// What POST /me/audiobookshelf/sync answers.
class ListeningSync {
  const ListeningSync({
    required this.linked,
    this.username,
    this.syncedAt,
    this.lastError,
    this.minutesToday = 0,
  });

  factory ListeningSync.fromJson(Map<String, dynamic> j) => ListeningSync(
    linked: j['linked'] as bool? ?? false,
    username: j['username'] as String?,
    syncedAt: _time(j['syncedAt']),
    lastError: j['lastError'] as String?,
    minutesToday: _int(j['minutesToday']),
  );

  final bool linked;
  final String? username;
  final DateTime? syncedAt;
  final String? lastError;
  final int minutesToday;

  Map<String, dynamic> toJson() => {
    'linked': linked,
    'username': username,
    'syncedAt': _timeJson(syncedAt),
    'lastError': lastError,
    'minutesToday': minutesToday,
  };
}

enum EstimateConfidence {
  low,
  medium,
  high;

  /// An unknown word reads as the least certain, the way the server treats it.
  static EstimateConfidence parse(Object? v) {
    for (final c in values) {
      if (c.name == v) return c;
    }
    return low;
  }
}

/// A meal worked out from a photo or a sentence. Nothing is logged until the person saves.
class MealEstimate {
  const MealEstimate({
    required this.name,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.confidence,
    required this.notes,
  });

  factory MealEstimate.fromJson(Map<String, dynamic> j) => MealEstimate(
    name: _str(j['name']),
    kcal: _int(j['kcal']),
    protein: _num(j['protein']),
    carbs: _num(j['carbs']),
    fat: _num(j['fat']),
    fiber: _num(j['fiber']),
    confidence: EstimateConfidence.parse(j['confidence']),
    notes: _str(j['notes']),
  );

  final String name;
  final int kcal;
  final num protein;
  final num carbs;
  final num fat;
  final num fiber;
  final EstimateConfidence confidence;
  final String notes;

  Map<String, dynamic> toJson() => {
    'name': name,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'confidence': confidence.name,
    'notes': notes,
  };
}

/// One person's or the pair's totals for a week.
class RecapStats {
  const RecapStats({
    this.points = 0,
    this.countedDays = 0,
    this.steps = 0,
    this.sleepAvgMin = 0,
    this.sleepNights = 0,
    this.workouts = 0,
    this.readingMinutes = 0,
  });

  factory RecapStats.fromJson(Object? v) {
    final j = _map(v);
    if (j == null) return const RecapStats();
    return RecapStats(
      points: _int(j['points']),
      countedDays: _int(j['countedDays']),
      steps: _int(j['steps']),
      sleepAvgMin: _int(j['sleepAvgMin']),
      sleepNights: _int(j['sleepNights']),
      workouts: _int(j['workouts']),
      readingMinutes: _int(j['readingMinutes']),
    );
  }

  final int points;
  final int countedDays;
  final int steps;
  final int sleepAvgMin;
  final int sleepNights;
  final int workouts;
  final int readingMinutes;

  Map<String, dynamic> toJson() => {
    'points': points,
    'countedDays': countedDays,
    'steps': steps,
    'sleepAvgMin': sleepAvgMin,
    'sleepNights': sleepNights,
    'workouts': workouts,
    'readingMinutes': readingMinutes,
  };
}

class RecapBestDay {
  const RecapBestDay({required this.date, required this.points});

  static RecapBestDay? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['date']).isEmpty) return null;
    return RecapBestDay(date: _str(j['date']), points: _int(j['points']));
  }

  final String date;
  final int points;

  Map<String, dynamic> toJson() => {'date': date, 'points': points};
}

class RecapPerson {
  const RecapPerson({
    required this.userId,
    required this.name,
    required this.color,
    required this.thisWeek,
    required this.previous,
    this.bestDay,
    this.suggestion = '',
  });

  factory RecapPerson.fromJson(Map<String, dynamic> j) => RecapPerson(
    userId: _int(j['userId']),
    name: _str(j['name']),
    color: _str(j['color']),
    thisWeek: RecapStats.fromJson(j['this']),
    previous: RecapStats.fromJson(j['previous']),
    bestDay: RecapBestDay.tryParse(j['bestDay']),
    suggestion: _str(j['suggestion']),
  );

  final int userId;
  final String name;
  final String color;
  final RecapStats thisWeek;
  final RecapStats previous;
  final RecapBestDay? bestDay;
  final String suggestion;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'color': color,
    'this': thisWeek.toJson(),
    'previous': previous.toJson(),
    'bestDay': bestDay?.toJson(),
    'suggestion': suggestion,
  };
}

class RecapPair {
  const RecapPair({
    this.thisWeek = const RecapStats(),
    this.previous = const RecapStats(),
    this.bestDay,
  });

  factory RecapPair.fromJson(Object? v) {
    final j = _map(v);
    return RecapPair(
      thisWeek: RecapStats.fromJson(j?['this']),
      previous: RecapStats.fromJson(j?['previous']),
      bestDay: RecapBestDay.tryParse(j?['bestDay']),
    );
  }

  final RecapStats thisWeek;
  final RecapStats previous;
  final RecapBestDay? bestDay;

  Map<String, dynamic> toJson() => {
    'this': thisWeek.toJson(),
    'previous': previous.toJson(),
    'bestDay': bestDay?.toJson(),
  };
}

class RecapChallenge {
  const RecapChallenge({
    required this.kind,
    required this.title,
    required this.target,
    required this.progress,
    required this.completed,
  });

  static RecapChallenge? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _int(j['target']) < 1) return null;
    return RecapChallenge(
      kind: _str(j['kind']),
      title: _str(j['title']),
      target: _int(j['target']),
      progress: _int(j['progress']),
      completed: j['completed'] as bool? ?? false,
    );
  }

  final String kind;
  final String title;
  final int target;
  final int progress;
  final bool completed;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'title': title,
    'target': target,
    'progress': progress,
    'completed': completed,
  };
}

/// GET /recap: both people for one ISO week against the week before.
class Recap {
  const Recap({
    required this.week,
    required this.from,
    required this.to,
    required this.complete,
    required this.people,
    required this.pair,
    this.challenge,
  });

  factory Recap.fromJson(Map<String, dynamic> j) => Recap(
    week: _str(j['week']),
    from: _str(j['from']),
    to: _str(j['to']),
    complete: j['complete'] as bool? ?? false,
    people: [
      for (final p in j['people'] as List? ?? const [])
        if (p is Map) RecapPerson.fromJson(p.cast<String, dynamic>()),
    ],
    pair: RecapPair.fromJson(j['pair']),
    challenge: RecapChallenge.tryParse(j['challenge']),
  );

  /// `2026-W44`.
  final String week;
  final String from;
  final String to;

  /// False while the week is still running.
  final bool complete;
  final List<RecapPerson> people;
  final RecapPair pair;
  final RecapChallenge? challenge;

  Map<String, dynamic> toJson() => {
    'week': week,
    'from': from,
    'to': to,
    'complete': complete,
    'people': [for (final p in people) p.toJson()],
    'pair': pair.toJson(),
    'challenge': challenge?.toJson(),
  };
}

/// One suggested change to a quest target, from this week's data.
class GoalProposal {
  const GoalProposal({
    required this.key,
    required this.title,
    required this.unit,
    required this.current,
    required this.proposed,
    required this.reason,
  });

  static GoalProposal? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['key']).isEmpty) return null;
    return GoalProposal(
      key: _str(j['key']),
      title: _str(j['title']),
      unit: _str(j['unit']),
      current: _int(j['current']),
      proposed: _int(j['proposed']),
      reason: _str(j['reason']),
    );
  }

  /// steps or sleep.
  final String key;
  final String title;
  final String unit;
  final int current;
  final int proposed;
  final String reason;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'unit': unit,
    'current': current,
    'proposed': proposed,
    'reason': reason,
  };
}

class GoalProposals {
  const GoalProposals({this.week = '', this.weekStart = '', this.proposals = const []});

  factory GoalProposals.fromJson(Map<String, dynamic> j) => GoalProposals(
    week: _str(j['week']),
    weekStart: _str(j['weekStart']),
    proposals: _items(j['proposals'], GoalProposal.tryParse),
  );

  final String week;
  final String weekStart;
  final List<GoalProposal> proposals;

  GoalProposals without(String key) => GoalProposals(
    week: week,
    weekStart: weekStart,
    proposals: [
      for (final p in proposals)
        if (p.key != key) p,
    ],
  );

  Map<String, dynamic> toJson() => {
    'week': week,
    'weekStart': weekStart,
    'proposals': [for (final p in proposals) p.toJson()],
  };
}
