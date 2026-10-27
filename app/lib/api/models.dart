typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

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
      JoinResult(user: UserSummary.fromJson(j['user'] as Json), token: _str(j['token']));

  final UserSummary user;
  final String token;

  Json toJson() => {'user': user.toJson(), 'token': token};
}

/// The three ways to call POST /join. Only the fields a case needs are sent.
class JoinRequest {
  const JoinRequest.first({required String name, required String color, String? timezone})
    : this._(name: name, color: color, timezone: timezone);

  const JoinRequest.member({
    required String code,
    required String name,
    required String color,
    String? timezone,
  }) : this._(code: code, name: name, color: color, timezone: timezone);

  const JoinRequest.repair({required String code, required int userId, String? timezone})
    : this._(code: code, userId: userId, timezone: timezone);

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

/// The answer to POST /invites/check: who can be re-paired with a valid code.
class InviteCheck {
  const InviteCheck({required this.users});

  factory InviteCheck.fromJson(Json j) =>
      InviteCheck(users: _list(j['users'], UserSummary.fromJson));

  final List<UserSummary> users;

  Json toJson() => {
    'users': [for (final u in users) u.toJson()],
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
    targetAlt: j['targetAlt'] as num?,
    unitAlt: j['unitAlt'] as String?,
  );

  final String key;
  final String title;
  final bool enabled;
  final num target;
  final String unit;
  final int points;
  final num? targetAlt;
  final String? unitAlt;

  Json toJson() => {
    'key': key,
    'title': title,
    'enabled': enabled,
    'target': target,
    'unit': unit,
    'points': points,
    'targetAlt': ?targetAlt,
    'unitAlt': ?unitAlt,
  };
}

class Me {
  const Me({
    required this.user,
    required this.timezone,
    required this.isAdmin,
    required this.quests,
    required this.localToday,
    required this.serverNow,
    this.backdateUntil,
    this.kcalTarget,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
  });

  factory Me.fromJson(Json j) => Me(
    user: UserSummary.fromJson(j),
    timezone: _str(j['timezone']),
    isAdmin: j['isAdmin'] as bool? ?? false,
    quests: _list(j['quests'], QuestTemplate.fromJson),
    localToday: _str(j['localToday']),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    backdateUntil: _time(j['backdateUntil']),
    kcalTarget: j['kcalTarget'] as num?,
    proteinTarget: j['proteinTarget'] as num?,
    carbsTarget: j['carbsTarget'] as num?,
    fatTarget: j['fatTarget'] as num?,
  );

  final UserSummary user;
  final String timezone;
  final bool isAdmin;
  final List<QuestTemplate> quests;
  final String localToday;
  final DateTime serverNow;

  /// Null once yesterday is closed for entries.
  final DateTime? backdateUntil;
  final num? kcalTarget;
  final num? proteinTarget;
  final num? carbsTarget;
  final num? fatTarget;

  Json toJson() => {
    ...user.toJson(),
    'timezone': timezone,
    'isAdmin': isAdmin,
    'quests': [for (final q in quests) q.toJson()],
    'localToday': localToday,
    'serverNow': _timeJson(serverNow),
    'backdateUntil': _timeJson(backdateUntil),
    'kcalTarget': kcalTarget,
    'proteinTarget': proteinTarget,
    'carbsTarget': carbsTarget,
    'fatTarget': fatTarget,
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
    this.quests,
  });

  final String? name;
  final String? color;
  final String? timezone;
  final num? kcalTarget;
  final num? proteinTarget;
  final num? carbsTarget;
  final num? fatTarget;
  final List<QuestEdit>? quests;

  Json toJson() => {
    'name': ?name,
    'color': ?color,
    'timezone': ?timezone,
    'kcalTarget': ?kcalTarget,
    'proteinTarget': ?proteinTarget,
    'carbsTarget': ?carbsTarget,
    'fatTarget': ?fatTarget,
    if (quests != null) 'quests': [for (final q in quests!) q.toJson()],
  };
}

class QuestEdit {
  const QuestEdit({required this.key, this.enabled, this.target, this.targetAlt});

  final String key;
  final bool? enabled;
  final num? target;
  final num? targetAlt;

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
    required this.earned,
    required this.bonus,
    required this.completed,
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
    earned: _int(j['earned']),
    bonus: _int(j['bonus']),
    completed: j['completed'] as bool? ?? false,
    unitAlt: j['unitAlt'] as String?,
    targetAlt: j['targetAlt'] as num?,
    actualAlt: j['actualAlt'] as num?,
  );

  final String key;
  final String title;
  final String unit;
  final num target;
  final num actual;

  /// Base points this quest is worth, before the completion bonus.
  final int points;

  /// Points earned so far, excluding the bonus.
  final int earned;

  /// The completion bonus; zero until the quest is complete.
  final int bonus;
  final bool completed;
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
    'earned': earned,
    'bonus': bonus,
    'completed': completed,
    'unitAlt': ?unitAlt,
    'targetAlt': ?targetAlt,
    'actualAlt': ?actualAlt,
  };
}

class DayScore {
  const DayScore({
    required this.points,
    required this.maxPoints,
    required this.percent,
    required this.counted,
    this.threshold = 70,
  });

  factory DayScore.fromJson(Json j) => DayScore(
    points: _int(j['points']),
    maxPoints: _int(j['maxPoints']),
    percent: _int(j['percent']),
    counted: j['counted'] as bool? ?? false,
    threshold: _int(j['threshold'], 70),
  );

  final int points;
  final int maxPoints;

  /// Computed by the server on base points; the app never recomputes it.
  final int percent;
  final bool counted;

  /// The percent a day needs to count toward the streak.
  final int threshold;

  Json toJson() => {
    'points': points,
    'maxPoints': maxPoints,
    'percent': percent,
    'counted': counted,
    'threshold': threshold,
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

  Json toJson() => {'current': current, 'restAvailable': restAvailable, 'restUsedOn': ?restUsedOn};
}

class Food {
  const Food({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.burned,
    this.kcalTarget,
    this.proteinTarget,
    this.carbsTarget,
    this.fatTarget,
  });

  factory Food.fromJson(Json j) => Food(
    kcal: _num(j['kcal']),
    protein: _num(j['protein']),
    carbs: _num(j['carbs']),
    fat: _num(j['fat']),
    burned: _num(j['burned']),
    kcalTarget: j['kcalTarget'] as num?,
    proteinTarget: j['proteinTarget'] as num?,
    carbsTarget: j['carbsTarget'] as num?,
    fatTarget: j['fatTarget'] as num?,
  );

  final num kcal;
  final num protein;
  final num carbs;
  final num fat;

  Food plusMeal(MealLog meal) => Food(
    kcal: kcal + meal.kcal,
    protein: protein + meal.proteinG,
    carbs: carbs + meal.carbsG,
    fat: fat + meal.fatG,
    burned: burned,
    kcalTarget: kcalTarget,
    proteinTarget: proteinTarget,
    carbsTarget: carbsTarget,
    fatTarget: fatTarget,
  );

  /// Active energy from Health; shown, never scored.
  final num burned;
  final num? kcalTarget;
  final num? proteinTarget;
  final num? carbsTarget;
  final num? fatTarget;

  Json toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'burned': burned,
    'kcalTarget': ?kcalTarget,
    'proteinTarget': ?proteinTarget,
    'carbsTarget': ?carbsTarget,
    'fatTarget': ?fatTarget,
  };
}

class HealthStatus {
  const HealthStatus({required this.hasSteps, this.syncedAt});

  factory HealthStatus.fromJson(Json j) =>
      HealthStatus(hasSteps: j['hasSteps'] as bool? ?? false, syncedAt: _time(j['syncedAt']));

  /// False until a steps row has ever arrived.
  final bool hasSteps;
  final DateTime? syncedAt;

  Json toJson() => {'hasSteps': hasSteps, 'syncedAt': _timeJson(syncedAt)};
}

class Today {
  const Today({
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
    localToday: _str(j['localToday']),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    backdateUntil: _time(j['backdateUntil']),
    day: DayScore.fromJson(j['day'] as Json),
    quests: _list(j['quests'], Quest.fromJson),
    streak: Streak.fromJson(j['streak'] as Json),
    food: Food.fromJson(j['food'] as Json),
    health: HealthStatus.fromJson(j['health'] as Json),
  );

  final String localToday;
  final DateTime serverNow;
  final DateTime? backdateUntil;
  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final Food food;
  final HealthStatus health;

  Today copyWith({DayScore? day, List<Quest>? quests, Food? food, HealthStatus? health}) => Today(
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
  const DayMark({required this.date, required this.percent, required this.rest});

  factory DayMark.fromJson(Json j) => DayMark(
    date: _str(j['date']),
    percent: _int(j['percent']),
    rest: j['rest'] as bool? ?? false,
  );

  final String date;
  final int percent;
  final bool rest;

  Json toJson() => {'date': date, 'percent': percent, 'rest': rest};
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
  });

  factory BoardUser.fromJson(Json j) => BoardUser(
    id: _int(j['id']),
    name: _str(j['name']),
    color: _str(j['color']),
    today: BoardDay.fromJson(j['today'] as Json),
    week: _int(j['week']),
    season: _int(j['season']),
    streak: _int(j['streak']),
    last7: _list(j['last7'], DayMark.fromJson),
    syncedAt: _time(j['syncedAt']),
  );

  final int id;
  final String name;
  final String color;
  final BoardDay today;
  final int week;
  final int season;
  final int streak;
  final List<DayMark> last7;
  final DateTime? syncedAt;

  Json toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'today': today.toJson(),
    'week': week,
    'season': season,
    'streak': streak,
    'last7': [for (final d in last7) d.toJson()],
    'syncedAt': _timeJson(syncedAt),
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
  const Board({required this.season, required this.users});

  factory Board.fromJson(Json j) => Board(
    season: SeasonInfo.fromJson(j['season'] as Json),
    users: _list(j['users'], BoardUser.fromJson),
  );

  final SeasonInfo season;
  final List<BoardUser> users;

  Json toJson() => {
    'season': season.toJson(),
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
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  factory MealLog.fromJson(Json j) => MealLog(
    id: _int(j['id']),
    localDate: _str(j['localDate']),
    loggedAt: _time(j['loggedAt']) ?? DateTime.now().toUtc(),
    name: _str(j['name']),
    kcal: _int(j['kcal']),
    proteinG: _num(j['proteinG']),
    carbsG: _num(j['carbsG']),
    fatG: _num(j['fatG']),
    fiberG: _num(j['fiberG']),
  );

  final String name;
  final int kcal;
  final num proteinG;
  final num carbsG;
  final num fatG;
  final num fiberG;

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
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'fiberG': fiberG,
  };
}

/// The body of POST /logs. The date is omitted for today: the server decides it.
sealed class LogDraft {
  const LogDraft({required this.clientOpId, this.localDate});

  final String clientOpId;

  /// Only set to backdate an entry to yesterday.
  final String? localDate;

  String get kind;

  Json toJson() => {'kind': kind, 'clientOpId': clientOpId, 'localDate': ?localDate};
}

class ActivityDraft extends LogDraft {
  const ActivityDraft({
    required super.clientOpId,
    required this.type,
    required this.quantity,
    required this.unit,
    super.localDate,
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
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
    this.fiberG = 0,
    super.localDate,
  });

  final String name;
  final int kcal;
  final num proteinG;
  final num carbsG;
  final num fatG;
  final num fiberG;

  @override
  String get kind => 'meal';

  @override
  Json toJson() => {
    ...super.toJson(),
    'name': name,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'fiberG': fiberG,
  };
}

extension LogEntryDraft on LogEntry {
  /// The same entry as a new write, for undoing a delete. [clientOpId] must be fresh.
  LogDraft toDraft(String clientOpId, {String? localDate}) => switch (this) {
    final ActivityLog a => ActivityDraft(
      clientOpId: clientOpId,
      type: a.type,
      quantity: a.quantity,
      unit: a.unit,
      localDate: localDate,
    ),
    final MealLog m => MealDraft(
      clientOpId: clientOpId,
      name: m.name,
      kcal: m.kcal,
      proteinG: m.proteinG,
      carbsG: m.carbsG,
      fatG: m.fatG,
      fiberG: m.fiberG,
      localDate: localDate,
    ),
  };
}

/// The answer to POST /logs: the stored entry and the recomputed day.
class LogResult {
  const LogResult({required this.log, required this.day, required this.quests});

  factory LogResult.fromJson(Json j) => LogResult(
    log: LogEntry.fromJson(j['log'] as Json),
    day: DayScore.fromJson(j['day'] as Json),
    quests: _list(j['quests'], Quest.fromJson),
  );

  final LogEntry log;
  final DayScore day;
  final List<Quest> quests;

  Json toJson() => {
    'log': log.toJson(),
    'day': day.toJson(),
    'quests': [for (final q in quests) q.toJson()],
  };
}

class RecentMeal {
  const RecentMeal({
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
  });

  factory RecentMeal.fromJson(Json j) => RecentMeal(
    name: _str(j['name']),
    kcal: _int(j['kcal']),
    proteinG: _num(j['proteinG']),
    carbsG: _num(j['carbsG']),
    fatG: _num(j['fatG']),
    fiberG: _num(j['fiberG']),
  );

  final String name;
  final int kcal;
  final num proteinG;
  final num carbsG;
  final num fatG;
  final num fiberG;

  Json toJson() => {
    'name': name,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'fiberG': fiberG,
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

  /// `steps` or `active_energy`.
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

/// A day the server rescored because of a health push.
class RescoredDay {
  const RescoredDay({required this.date, required this.day, required this.quests});

  factory RescoredDay.fromJson(Json j) => RescoredDay(
    date: _str(j['date']),
    day: DayScore.fromJson(j['day'] as Json),
    quests: _list(j['quests'], Quest.fromJson),
  );

  final String date;
  final DayScore day;
  final List<Quest> quests;

  Json toJson() => {
    'date': date,
    'day': day.toJson(),
    'quests': [for (final q in quests) q.toJson()],
  };
}

class HealthDailyResult {
  const HealthDailyResult({required this.days});

  factory HealthDailyResult.fromJson(Json j) =>
      HealthDailyResult(days: _list(j['days'], RescoredDay.fromJson));

  final List<RescoredDay> days;

  Json toJson() => {
    'days': [for (final d in days) d.toJson()],
  };
}
