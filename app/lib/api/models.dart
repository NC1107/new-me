typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

int? _intOrNull(Object? v) => (v as num?)?.toInt();

num _num(Object? v, [num fallback = 0]) => (v as num?) ?? fallback;

String _str(Object? v, [String fallback = '']) => v as String? ?? fallback;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _timeJson(DateTime? v) => v?.toUtc().toIso8601String();

List<T> _list<T>(Object? v, T Function(Json) parse) => [
  for (final item in v as List? ?? const []) parse(item as Json),
];

class UserSummary {
  const UserSummary({required this.id, required this.name, required this.color});

  factory UserSummary.fromJson(Json j) =>
      UserSummary(id: _int(j['id']), name: _str(j['name']), color: _str(j['color']));

  final int id;
  final String name;
  final String color;

  Json toJson() => {'id': id, 'name': name, 'color': color};
}

/// The signed-in person as the server reports them after pairing and in GET /me.
class AccountUser {
  const AccountUser({
    required this.id,
    required this.name,
    required this.color,
    required this.timezone,
    required this.isAdmin,
  });

  factory AccountUser.fromJson(Json j) => AccountUser(
    id: _int(j['id']),
    name: _str(j['name']),
    color: _str(j['color']),
    timezone: _str(j['timezone']),
    isAdmin: j['isAdmin'] as bool? ?? false,
  );

  final int id;
  final String name;
  final String color;
  final String timezone;
  final bool isAdmin;

  Json toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'timezone': timezone,
    'isAdmin': isAdmin,
  };
}

class ServerInfo {
  const ServerInfo({
    required this.name,
    required this.initialized,
    required this.joinOpen,
    required this.minClientVersion,
  });

  factory ServerInfo.fromJson(Json j) => ServerInfo(
    name: _str(j['name']),
    initialized: j['initialized'] as bool? ?? false,
    joinOpen: j['joinOpen'] as bool? ?? false,
    minClientVersion: _str(j['minClientVersion']),
  );

  final String name;
  final bool initialized;
  final bool joinOpen;
  final String minClientVersion;

  Json toJson() => {
    'name': name,
    'initialized': initialized,
    'joinOpen': joinOpen,
    'minClientVersion': minClientVersion,
  };
}

class JoinResult {
  const JoinResult({required this.user, required this.token});

  factory JoinResult.fromJson(Json j) =>
      JoinResult(user: AccountUser.fromJson(j['user'] as Json), token: _str(j['token']));

  final AccountUser user;
  final String token;

  Json toJson() => {'user': user.toJson(), 'token': token};
}

/// The three ways to call POST /join. The server rejects any field a case does not use.
class JoinRequest {
  const JoinRequest.first({required String name, required String color, required String timezone})
    : this._(name: name, color: color, timezone: timezone);

  const JoinRequest.member({
    required String code,
    required String name,
    required String color,
    required String timezone,
  }) : this._(code: code, name: name, color: color, timezone: timezone);

  const JoinRequest.repair({required String code, required int userId})
    : this._(code: code, userId: userId);

  const JoinRequest._({this.code, this.name, this.color, this.userId, this.timezone});

  final String? code;
  final String? name;
  final String? color;
  final int? userId;
  final String? timezone;

  Json toJson() => {
    'code': ?code,
    'name': ?name,
    'color': ?color,
    'userId': ?userId,
    'timezone': ?timezone,
  };
}

/// The answer to POST /invites/check. An unusable code is a 200 with [valid] false.
class InviteCheck {
  const InviteCheck({required this.valid, required this.users, required this.canJoinNew});

  factory InviteCheck.fromJson(Json j) => InviteCheck(
    valid: j['valid'] as bool? ?? false,
    users: _list(j['users'], UserSummary.fromJson),
    canJoinNew: j['canJoinNew'] as bool? ?? false,
  );

  final bool valid;

  /// Who can be re-paired; empty unless the code is valid.
  final List<UserSummary> users;
  final bool canJoinNew;

  Json toJson() => {
    'valid': valid,
    'users': [for (final u in users) u.toJson()],
    'canJoinNew': canJoinNew,
  };
}

class Invite {
  const Invite({required this.code, required this.expiresAt});

  factory Invite.fromJson(Json j) =>
      Invite(code: _str(j['code']), expiresAt: _time(j['expiresAt']) ?? DateTime.now().toUtc());

  final String code;
  final DateTime expiresAt;

  Json toJson() => {'code': code, 'expiresAt': _timeJson(expiresAt)};
}

class QuestTemplate {
  const QuestTemplate({
    required this.key,
    required this.title,
    required this.enabled,
    required this.target,
    required this.unit,
    required this.points,
    required this.position,
    this.targetAlt,
    this.unitAlt,
  });

  factory QuestTemplate.fromJson(Json j) => QuestTemplate(
    key: _str(j['key']),
    title: _str(j['title']),
    enabled: j['enabled'] as bool? ?? true,
    target: _num(j['target']),
    unit: _str(j['unit']),
    points: _int(j['points']),
    position: _int(j['position']),
    targetAlt: j['targetAlt'] as num?,
    unitAlt: j['unitAlt'] as String?,
  );

  final String key;
  final String title;
  final bool enabled;
  final num target;
  final String unit;
  final int points;
  final int position;
  final num? targetAlt;
  final String? unitAlt;

  Json toJson() => {
    'key': key,
    'title': title,
    'enabled': enabled,
    'target': target,
    'unit': unit,
    'points': points,
    'position': position,
    'targetAlt': targetAlt,
    'unitAlt': unitAlt,
  };
}

/// The profile goals; a null target is one the person has not set.
class Targets {
  const Targets({this.kcal, this.protein, this.carbs, this.fat});

  factory Targets.fromJson(Json j) => Targets(
    kcal: _intOrNull(j['kcal']),
    protein: _intOrNull(j['protein']),
    carbs: _intOrNull(j['carbs']),
    fat: _intOrNull(j['fat']),
  );

  final int? kcal;
  final int? protein;
  final int? carbs;
  final int? fat;

  bool get complete => kcal != null && protein != null && carbs != null && fat != null;

  Json toJson() => {'kcal': kcal, 'protein': protein, 'carbs': carbs, 'fat': fat};
}

class Me {
  const Me({
    required this.user,
    required this.targets,
    required this.questTemplates,
    required this.localToday,
    required this.serverNow,
    this.backdateUntil,
  });

  factory Me.fromJson(Json j) => Me(
    user: AccountUser.fromJson(j['user'] as Json),
    targets: Targets.fromJson(j['targets'] as Json),
    questTemplates: _list(j['questTemplates'], QuestTemplate.fromJson),
    localToday: _str(j['localToday']),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    backdateUntil: _time(j['backdateUntil']),
  );

  final AccountUser user;
  final Targets targets;
  final List<QuestTemplate> questTemplates;
  final String localToday;
  final DateTime serverNow;

  /// Null once yesterday is closed for entries.
  final DateTime? backdateUntil;

  Json toJson() => {
    'user': user.toJson(),
    'targets': targets.toJson(),
    'questTemplates': [for (final q in questTemplates) q.toJson()],
    'localToday': localToday,
    'serverNow': _timeJson(serverNow),
    'backdateUntil': _timeJson(backdateUntil),
  };
}

/// A partial PATCH /me. Null fields are left out of the body.
class MePatch {
  const MePatch({
    this.name,
    this.color,
    this.timezone,
    this.kcalTarget,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
    this.questTemplates,
    this.clearTargets = const {},
  });

  /// Builds a targets-only patch where a null value clears that target on the server.
  factory MePatch.targets(Map<String, int?> targets) => MePatch(
    kcalTarget: targets['kcal'],
    proteinTarget: targets['protein'],
    carbsTarget: targets['carbs'],
    fatTarget: targets['fat'],
    clearTargets: {
      for (final e in targets.entries)
        if (e.value == null) e.key,
    },
  );

  final String? name;
  final String? color;
  final String? timezone;
  final int? kcalTarget;
  final int? proteinTarget;
  final int? carbsTarget;
  final int? fatTarget;
  final List<QuestEdit>? questTemplates;

  /// Target keys (kcal, protein, carbs, fat) sent as null so the server clears them.
  final Set<String> clearTargets;

  Json toJson() {
    final targets = <String, int?>{
      for (final key in clearTargets) key: null,
      'kcal': ?kcalTarget,
      'protein': ?proteinTarget,
      'carbs': ?carbsTarget,
      'fat': ?fatTarget,
    };
    return {
      'name': ?name,
      'color': ?color,
      'timezone': ?timezone,
      if (targets.isNotEmpty) 'targets': targets,
      if (questTemplates != null) 'questTemplates': [for (final q in questTemplates!) q.toJson()],
    };
  }
}

class QuestEdit {
  const QuestEdit({required this.key, this.enabled, this.target, this.targetAlt});

  final String key;
  final bool? enabled;
  final int? target;
  final int? targetAlt;

  Json toJson() => {'key': key, 'enabled': ?enabled, 'target': ?target, 'targetAlt': ?targetAlt};
}

class Quest {
  const Quest({
    required this.key,
    required this.title,
    required this.unit,
    required this.target,
    required this.actual,
    required this.points,
    required this.basePoints,
    required this.bonusPoints,
    required this.done,
    this.unitAlt,
    this.targetAlt,
    this.actualAlt,
  });

  factory Quest.fromJson(Json j) => Quest(
    key: _str(j['key']),
    title: _str(j['title']),
    unit: _str(j['unit']),
    target: _num(j['target']),
    actual: _num(j['actual']),
    points: _int(j['points']),
    basePoints: _int(j['basePoints']),
    bonusPoints: _int(j['bonusPoints']),
    done: j['done'] as bool? ?? false,
    unitAlt: j['unitAlt'] as String?,
    targetAlt: j['targetAlt'] as num?,
    actualAlt: j['actualAlt'] as num?,
  );

  final String key;
  final String title;
  final String unit;
  final num target;
  final num actual;

  /// Base points this quest is worth in full, before the completion bonus.
  final int points;

  /// Base points earned so far.
  final int basePoints;

  /// The completion bonus earned; zero until the quest is done.
  final int bonusPoints;
  final bool done;
  final String? unitAlt;
  final num? targetAlt;
  final num? actualAlt;

  Json toJson() => {
    'key': key,
    'title': title,
    'unit': unit,
    'target': target,
    'actual': actual,
    'points': points,
    'basePoints': basePoints,
    'bonusPoints': bonusPoints,
    'done': done,
    'unitAlt': unitAlt,
    'targetAlt': targetAlt,
    'actualAlt': actualAlt,
  };
}

class DayScore {
  const DayScore({
    required this.basePoints,
    required this.bonusPoints,
    required this.points,
    required this.maxBase,
    required this.percent,
    required this.counted,
    required this.streakLine,
  });

  factory DayScore.fromJson(Json j) => DayScore(
    basePoints: _int(j['basePoints']),
    bonusPoints: _int(j['bonusPoints']),
    points: _int(j['points']),
    maxBase: _int(j['maxBase']),
    percent: _int(j['percent']),
    counted: j['counted'] as bool? ?? false,
    streakLine: _int(j['streakLine'], 70),
  );

  final int basePoints;
  final int bonusPoints;

  /// Base plus bonus.
  final int points;
  final int maxBase;

  /// Computed by the server on base points; the app never recomputes it.
  final int percent;
  final bool counted;

  /// The percent a day needs to count toward the streak.
  final int streakLine;

  Json toJson() => {
    'basePoints': basePoints,
    'bonusPoints': bonusPoints,
    'points': points,
    'maxBase': maxBase,
    'percent': percent,
    'counted': counted,
    'streakLine': streakLine,
  };
}

/// A scored day with its quests, what every write endpoint returns. The score fields sit next
/// to `date` and `quests` on the wire.
class DayDetail {
  const DayDetail({required this.date, required this.score, required this.quests});

  factory DayDetail.fromJson(Json j) => DayDetail(
    date: _str(j['date']),
    score: DayScore.fromJson(j),
    quests: _list(j['quests'], Quest.fromJson),
  );

  final String date;
  final DayScore score;
  final List<Quest> quests;

  Json toJson() => {
    'date': date,
    ...score.toJson(),
    'quests': [for (final q in quests) q.toJson()],
  };
}

class Streak {
  const Streak({required this.current, required this.restAvailable, this.restUsedOn});

  factory Streak.fromJson(Json j) => Streak(
    current: _int(j['current']),
    restAvailable: j['restAvailable'] as bool? ?? false,
    restUsedOn: j['restUsedOn'] as String?,
  );

  final int current;
  final bool restAvailable;

  /// Local date of this week's rest day, when it has been used.
  final String? restUsedOn;

  Json toJson() => {'current': current, 'restAvailable': restAvailable, 'restUsedOn': restUsedOn};
}

class Food {
  const Food({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.burned,
    required this.targets,
  });

  factory Food.fromJson(Json j) => Food(
    kcal: _num(j['kcal']),
    protein: _num(j['protein']),
    carbs: _num(j['carbs']),
    fat: _num(j['fat']),
    fiber: _num(j['fiber']),
    burned: _num(j['burned']),
    targets: Targets.fromJson(j['targets'] as Json),
  );

  final num kcal;
  final num protein;
  final num carbs;
  final num fat;
  final num fiber;

  /// Active energy from Health; shown, never scored.
  final num burned;
  final Targets targets;

  Food plusMeal(MealLog meal) => Food(
    kcal: kcal + meal.kcal,
    protein: protein + meal.protein,
    carbs: carbs + meal.carbs,
    fat: fat + meal.fat,
    fiber: fiber + meal.fiber,
    burned: burned,
    targets: targets,
  );

  Food withBurned(num value) => Food(
    kcal: kcal,
    protein: protein,
    carbs: carbs,
    fat: fat,
    fiber: fiber,
    burned: value,
    targets: targets,
  );

  Json toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'burned': burned,
    'targets': targets.toJson(),
  };
}

/// The newest reading of a slow-moving metric on or before the day shown.
class HealthLatest {
  const HealthLatest({required this.value, required this.date});

  factory HealthLatest.fromJson(Json j) =>
      HealthLatest(value: _num(j['value']), date: _str(j['date']));

  final num value;
  final String date;

  Json toJson() => {'value': value, 'date': date};
}

Map<String, T> _keyed<T>(Object? v, T Function(Object? value) parse) {
  if (v is! Map) return const {};
  return {for (final e in v.entries) e.key as String: parse(e.value)};
}

class HealthStatus {
  const HealthStatus({
    required this.stepsEverSynced,
    this.syncedAt,
    this.metrics = const {},
    this.latest = const {},
  });

  /// `metrics` and `latest` are absent from servers older than v2.
  factory HealthStatus.fromJson(Json j) => HealthStatus(
    stepsEverSynced: j['stepsEverSynced'] as bool? ?? false,
    syncedAt: _time(j['syncedAt']),
    metrics: _keyed(j['metrics'], (v) => _num(v)),
    latest: {
      for (final e in _keyed<Object?>(j['latest'], (v) => v).entries)
        if (e.value is Map) e.key: HealthLatest.fromJson((e.value as Map).cast<String, dynamic>()),
    },
  );

  /// False until a steps row has ever arrived.
  final bool stepsEverSynced;
  final DateTime? syncedAt;

  /// The day's value for each metric that has data.
  final Map<String, num> metrics;

  /// Weight, body fat, lean mass and VO2 max: the newest value on or before the day.
  final Map<String, HealthLatest> latest;

  /// After a push: [metrics] overwrite the day's values and the newest weight-like readings follow.
  HealthStatus synced(DateTime at, {Map<String, num> metrics = const {}}) => HealthStatus(
    stepsEverSynced: true,
    syncedAt: at,
    metrics: {...this.metrics, ...metrics},
    latest: latest,
  );

  Json toJson() => {
    'stepsEverSynced': stepsEverSynced,
    'syncedAt': _timeJson(syncedAt),
    'metrics': metrics,
    'latest': {for (final e in latest.entries) e.key: e.value.toJson()},
  };
}

class Today {
  const Today({
    required this.date,
    required this.localToday,
    required this.serverNow,
    required this.day,
    required this.quests,
    required this.streak,
    required this.food,
    required this.health,
    this.backdateUntil,
  });

  factory Today.fromJson(Json j) => Today(
    date: _str(j['date']),
    localToday: _str(j['localToday']),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    backdateUntil: _time(j['backdateUntil']),
    day: DayScore.fromJson(j['day'] as Json),
    quests: _list(j['quests'], Quest.fromJson),
    streak: Streak.fromJson(j['streak'] as Json),
    food: Food.fromJson(j['food'] as Json),
    health: HealthStatus.fromJson(j['health'] as Json),
  );

  /// The day shown; always [localToday] unless the request named an earlier one.
  final String date;
  final String localToday;
  final DateTime serverNow;
  final DateTime? backdateUntil;
  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final Food food;
  final HealthStatus health;

  Today copyWith({DayScore? day, List<Quest>? quests, Food? food, HealthStatus? health}) => Today(
    date: date,
    localToday: localToday,
    serverNow: serverNow,
    backdateUntil: backdateUntil,
    day: day ?? this.day,
    quests: quests ?? this.quests,
    streak: streak,
    food: food ?? this.food,
    health: health ?? this.health,
  );

  Json toJson() => {
    'date': date,
    'localToday': localToday,
    'serverNow': _timeJson(serverNow),
    'backdateUntil': _timeJson(backdateUntil),
    'day': day.toJson(),
    'quests': [for (final q in quests) q.toJson()],
    'streak': streak.toJson(),
    'food': food.toJson(),
    'health': health.toJson(),
  };
}

class DayMark {
  const DayMark({
    required this.date,
    required this.percent,
    required this.counted,
    required this.rest,
  });

  factory DayMark.fromJson(Json j) => DayMark(
    date: _str(j['date']),
    percent: _int(j['percent']),
    counted: j['counted'] as bool? ?? false,
    rest: j['rest'] as bool? ?? false,
  );

  final String date;
  final int percent;
  final bool counted;
  final bool rest;

  Json toJson() => {'date': date, 'percent': percent, 'counted': counted, 'rest': rest};
}

class BoardDay {
  const BoardDay({required this.points, required this.percent, required this.counted});

  factory BoardDay.fromJson(Json j) => BoardDay(
    points: _int(j['points']),
    percent: _int(j['percent']),
    counted: j['counted'] as bool? ?? false,
  );

  final int points;
  final int percent;
  final bool counted;

  Json toJson() => {'points': points, 'percent': percent, 'counted': counted};
}

class BoardHighlights {
  const BoardHighlights({this.steps, this.exerciseMinutes, this.sleepMinutes});

  factory BoardHighlights.fromJson(Json j) => BoardHighlights(
    steps: j['steps'] as num?,
    exerciseMinutes: j['exercise_minutes'] as num?,
    sleepMinutes: j['sleep_minutes'] as num?,
  );

  final num? steps;
  final num? exerciseMinutes;
  final num? sleepMinutes;

  Json toJson() => {
    'steps': ?steps,
    'exercise_minutes': ?exerciseMinutes,
    'sleep_minutes': ?sleepMinutes,
  };
}

class BoardUser {
  const BoardUser({
    required this.id,
    required this.name,
    required this.color,
    required this.today,
    required this.week,
    required this.season,
    required this.streak,
    required this.last7,
    this.syncedAt,
    this.highlights = const BoardHighlights(),
  });

  factory BoardUser.fromJson(Json j) => BoardUser(
    id: _int(j['id']),
    name: _str(j['name']),
    color: _str(j['color']),
    today: BoardDay.fromJson(j['today'] as Json),
    week: _int((j['week'] as Json)['points']),
    season: _int((j['season'] as Json)['points']),
    streak: _int((j['streak'] as Json)['current']),
    last7: _list(j['last7'], DayMark.fromJson),
    syncedAt: _time(j['syncedAt']),
    highlights: j['highlights'] is Map
        ? BoardHighlights.fromJson((j['highlights'] as Map).cast<String, dynamic>())
        : const BoardHighlights(),
  );

  final int id;
  final String name;
  final String color;
  final BoardDay today;

  /// Points this season week, flattened from `week.points`.
  final int week;

  /// Points this season, flattened from `season.points`.
  final int season;

  /// The running streak, flattened from `streak.current`.
  final int streak;
  final List<DayMark> last7;
  final DateTime? syncedAt;

  /// Today's health numbers worth showing next to a member; empty before v2 servers.
  final BoardHighlights highlights;

  Json toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'today': today.toJson(),
    'week': {'points': week},
    'season': {'points': season},
    'streak': {'current': streak},
    'last7': [for (final d in last7) d.toJson()],
    'syncedAt': _timeJson(syncedAt),
    'highlights': highlights.toJson(),
  };
}

class SeasonInfo {
  const SeasonInfo({required this.name, required this.startsOn, this.endsOn});

  factory SeasonInfo.fromJson(Json j) => SeasonInfo(
    name: _str(j['name']),
    startsOn: _str(j['startsOn']),
    endsOn: j['endsOn'] as String?,
  );

  final String name;
  final String startsOn;
  final String? endsOn;

  Json toJson() => {'name': name, 'startsOn': startsOn, 'endsOn': endsOn};
}

class Board {
  const Board({required this.season, required this.serverNow, required this.users});

  factory Board.fromJson(Json j) => Board(
    season: SeasonInfo.fromJson(j['season'] as Json),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    users: _list(j['users'], BoardUser.fromJson),
  );

  final SeasonInfo season;
  final DateTime serverNow;

  /// The signed-in person first.
  final List<BoardUser> users;

  Json toJson() => {
    'season': season.toJson(),
    'serverNow': _timeJson(serverNow),
    'users': [for (final u in users) u.toJson()],
  };
}

/// An entry of GET /logs, a tagged union on `kind`.
sealed class LogEntry {
  const LogEntry({required this.id, required this.localDate, required this.loggedAt});

  factory LogEntry.fromJson(Json j) => switch (j['kind']) {
    'activity' => ActivityLog.fromJson(j),
    'meal' => MealLog.fromJson(j),
    final other => throw FormatException('Unknown log kind: $other'),
  };

  final int id;
  final String localDate;
  final DateTime loggedAt;

  String get kind;

  Json toJson();
}

class ActivityLog extends LogEntry {
  const ActivityLog({
    required super.id,
    required super.localDate,
    required super.loggedAt,
    required this.type,
    required this.quantity,
    required this.unit,
  });

  factory ActivityLog.fromJson(Json j) => ActivityLog(
    id: _int(j['id']),
    localDate: _str(j['localDate']),
    loggedAt: _time(j['loggedAt']) ?? DateTime.now().toUtc(),
    type: _str(j['type']),
    quantity: _int(j['quantity']),
    unit: _str(j['unit']),
  );

  /// `pushups` or `reading`.
  final String type;
  final int quantity;
  final String unit;

  @override
  String get kind => 'activity';

  @override
  Json toJson() => {
    'id': id,
    'kind': kind,
    'localDate': localDate,
    'loggedAt': _timeJson(loggedAt),
    'type': type,
    'quantity': quantity,
    'unit': unit,
  };
}

class MealLog extends LogEntry {
  const MealLog({
    required super.id,
    required super.localDate,
    required super.loggedAt,
    required this.name,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  factory MealLog.fromJson(Json j) => MealLog(
    id: _int(j['id']),
    localDate: _str(j['localDate']),
    loggedAt: _time(j['loggedAt']) ?? DateTime.now().toUtc(),
    name: _str(j['name']),
    kcal: _int(j['kcal']),
    protein: _num(j['protein']),
    carbs: _num(j['carbs']),
    fat: _num(j['fat']),
    fiber: _num(j['fiber']),
  );

  final String name;
  final int kcal;
  final num protein;
  final num carbs;
  final num fat;
  final num fiber;

  @override
  String get kind => 'meal';

  @override
  Json toJson() => {
    'id': id,
    'kind': kind,
    'localDate': localDate,
    'loggedAt': _timeJson(loggedAt),
    'name': name,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
  };
}

/// The body of POST /logs. The date is omitted for today: the server decides it.
sealed class LogDraft {
  const LogDraft({required this.clientOpId, this.date});

  final String clientOpId;

  /// Only set to backdate an entry to yesterday.
  final String? date;

  String get kind;

  Json toJson() => {'kind': kind, 'clientOpId': clientOpId, 'date': ?date};
}

class ActivityDraft extends LogDraft {
  const ActivityDraft({
    required super.clientOpId,
    required this.type,
    required this.quantity,
    required this.unit,
    super.date,
  });

  final String type;
  final int quantity;
  final String unit;

  @override
  String get kind => 'activity';

  @override
  Json toJson() => {...super.toJson(), 'type': type, 'quantity': quantity, 'unit': unit};
}

class MealDraft extends LogDraft {
  const MealDraft({
    required super.clientOpId,
    required this.name,
    required this.kcal,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    super.date,
  });

  final String name;
  final int kcal;
  final num protein;
  final num carbs;
  final num fat;
  final num fiber;

  @override
  String get kind => 'meal';

  @override
  Json toJson() => {
    ...super.toJson(),
    'name': name,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
  };
}

extension LogEntryDraft on LogEntry {
  /// The same entry as a new write, for undoing a delete. [clientOpId] must be fresh.
  LogDraft toDraft(String clientOpId, {String? date}) => switch (this) {
    final ActivityLog a => ActivityDraft(
      clientOpId: clientOpId,
      type: a.type,
      quantity: a.quantity,
      unit: a.unit,
      date: date,
    ),
    final MealLog m => MealDraft(
      clientOpId: clientOpId,
      name: m.name,
      kcal: m.kcal,
      protein: m.protein,
      carbs: m.carbs,
      fat: m.fat,
      fiber: m.fiber,
      date: date,
    ),
  };
}

/// The answer to POST /logs: the stored entry and the recomputed day.
class LogResult {
  const LogResult({required this.log, required this.day});

  factory LogResult.fromJson(Json j) => LogResult(
    log: LogEntry.fromJson(j['log'] as Json),
    day: DayDetail.fromJson(j['day'] as Json),
  );

  final LogEntry log;
  final DayDetail day;

  Json toJson() => {'log': log.toJson(), 'day': day.toJson()};
}

/// The answer to DELETE /logs/{id}: the recomputed day.
class LogDeleteResult {
  const LogDeleteResult({required this.day});

  factory LogDeleteResult.fromJson(Json j) =>
      LogDeleteResult(day: DayDetail.fromJson(j['day'] as Json));

  final DayDetail day;

  Json toJson() => {'day': day.toJson()};
}

class RecentMeal {
  const RecentMeal({
    required this.name,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
  });

  factory RecentMeal.fromJson(Json j) => RecentMeal(
    name: _str(j['name']),
    kcal: _int(j['kcal']),
    protein: _num(j['protein']),
    carbs: _num(j['carbs']),
    fat: _num(j['fat']),
    fiber: _num(j['fiber']),
  );

  final String name;
  final int kcal;
  final num protein;
  final num carbs;
  final num fat;
  final num fiber;

  Json toJson() => {
    'name': name,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
  };
}

/// One row of PUT /health/daily.
class HealthItem {
  const HealthItem({
    required this.date,
    required this.metric,
    required this.value,
    required this.source,
    required this.measuredAt,
  });

  final String date;

  /// One of the metric keys in `HealthMetric`.
  final String metric;
  final double value;
  final String source;
  final DateTime measuredAt;

  Json toJson() => {
    'date': date,
    'metric': metric,
    'value': value,
    'source': source,
    'measuredAt': _timeJson(measuredAt),
  };
}

class HealthDailyResult {
  const HealthDailyResult({required this.days});

  factory HealthDailyResult.fromJson(Json j) =>
      HealthDailyResult(days: _list(j['days'], DayDetail.fromJson));

  /// One per affected date, oldest first.
  final List<DayDetail> days;

  Json toJson() => {
    'days': [for (final d in days) d.toJson()],
  };
}

class HealthTrendPoint {
  const HealthTrendPoint({required this.date, required this.value});

  factory HealthTrendPoint.fromJson(Json j) =>
      HealthTrendPoint(date: _str(j['date']), value: _num(j['value']));

  final String date;
  final num value;

  Json toJson() => {'date': date, 'value': value};
}

/// GET /health/trends: one metric's daily values, oldest first.
class HealthTrend {
  const HealthTrend({required this.metric, required this.points});

  factory HealthTrend.fromJson(Json j) =>
      HealthTrend(metric: _str(j['metric']), points: _list(j['points'], HealthTrendPoint.fromJson));

  final String metric;
  final List<HealthTrendPoint> points;

  Json toJson() => {
    'metric': metric,
    'points': [for (final p in points) p.toJson()],
  };
}
