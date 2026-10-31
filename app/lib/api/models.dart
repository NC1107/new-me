import 'dart:convert';

import '../util/units.dart';

import 'habit_models.dart';

import 'together_models.dart';
import 'v6_models.dart';
import 'v7_models.dart';
import 'v8_models.dart';

export '../util/units.dart';
export 'food_models.dart';
export 'together_models.dart';
export 'v6_models.dart';
export 'v7_models.dart';
export 'training_history_models.dart';
export 'training_models.dart';
export 'yoga_models.dart';
export 'v8_models.dart';
export 'v18_models.dart';

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
    this.birthYear,
    this.heightCm,
    this.sex,
    this.goal,
    this.units,
  });

  factory AccountUser.fromJson(Json j) => AccountUser(
    id: _int(j['id']),
    name: _str(j['name']),
    color: _str(j['color']),
    timezone: _str(j['timezone']),
    isAdmin: j['isAdmin'] as bool? ?? false,
    birthYear: _intOrNull(j['birthYear']),
    heightCm: (j['heightCm'] as num?)?.toDouble(),
    sex: j['sex'] is String ? j['sex'] as String : null,
    goal: j['goal'] is Map ? GoalSetting.parse(j['goal']) : null,
    units: j['units'] is String ? Units.parse(j['units']) : null,
  );

  final int id;
  final String name;
  final String color;
  final String timezone;
  final bool isAdmin;

  /// Null until the person shares it, and on servers older than v4.
  final int? birthYear;

  /// Optional, in cm; null until entered, and on servers older than v8.
  final double? heightCm;

  /// `male` or `female`, or null until asked.
  final String? sex;

  /// Null on servers older than v8; read it through [goalSetting].
  final GoalSetting? goal;

  GoalSetting get goalSetting => goal ?? const GoalSetting();

  /// What the person reads; null before it was chosen, and on servers older than v10.
  final Units? units;

  Json toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'timezone': timezone,
    'isAdmin': isAdmin,
    'birthYear': ?birthYear,
    'heightCm': ?heightCm,
    'sex': ?sex,
    'goal': ?goal?.toJson(),
    'units': ?units?.name,
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

/// The caller's Audiobookshelf link as GET /me reports it. The server leaves it null while the
/// feature is off, and older servers omit it, so [Me.audiobookshelf] is null for both.
class AudiobookshelfLink {
  const AudiobookshelfLink({this.linked = false, this.username, this.syncedAt, this.lastError});

  factory AudiobookshelfLink.fromJson(Json j) => AudiobookshelfLink(
    linked: j['linked'] as bool? ?? false,
    username: j['username'] as String?,
    syncedAt: _time(j['syncedAt']),
    lastError: j['lastError'] as String?,
  );

  final bool linked;
  final String? username;
  final DateTime? syncedAt;

  /// `auth_failed` when the person has to sign in again, `unreachable` when the last poll could
  /// not reach Audiobookshelf, null while polls work.
  final String? lastError;

  /// The stored session was rejected, so only a fresh sign-in brings listening back.
  bool get needsSignIn => linked && lastError == 'auth_failed';

  Json toJson() => {
    'linked': linked,
    'username': username,
    'syncedAt': _timeJson(syncedAt),
    'lastError': lastError,
  };
}

class Me {
  const Me({
    required this.user,
    required this.targets,
    required this.questTemplates,
    required this.localToday,
    required this.serverNow,
    this.backdateUntil,
    this.audiobookshelf,
    this.notifications = const NotificationPrefs(),
    this.features = const Features(),
    this.schedule = const Schedule(),
    this.protein = const ProteinInfo(),
  });

  factory Me.fromJson(Json j) => Me(
    user: AccountUser.fromJson(j['user'] as Json),
    targets: Targets.fromJson(j['targets'] as Json),
    questTemplates: _list(j['questTemplates'], QuestTemplate.fromJson),
    localToday: _str(j['localToday']),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    backdateUntil: _time(j['backdateUntil']),
    audiobookshelf: j['audiobookshelf'] is Map
        ? AudiobookshelfLink.fromJson((j['audiobookshelf'] as Map).cast<String, dynamic>())
        : null,
    notifications: NotificationPrefs.fromJson(j['notifications']),
    features: Features.fromJson(j['features']),
    schedule: Schedule.parse(j['schedule']),
    protein: ProteinInfo.parse(j['protein']),
  );

  final AccountUser user;
  final Targets targets;
  final List<QuestTemplate> questTemplates;
  final String localToday;
  final DateTime serverNow;

  /// Null once yesterday is closed for entries.
  final DateTime? backdateUntil;

  /// Null while the server has no Audiobookshelf set up, which hides the Me row.
  final AudiobookshelfLink? audiobookshelf;

  /// Push switches; everything on for servers that predate them.
  final NotificationPrefs notifications;

  /// Optional server features; all off for servers that predate v6.
  final Features features;

  /// Wake and bed times, workdays and the first-notification offset.
  final Schedule schedule;

  /// The protein target explained; empty before v7 servers.
  final ProteinInfo protein;

  Me copyWith({NotificationPrefs? notifications}) => Me(
    user: user,
    targets: targets,
    questTemplates: questTemplates,
    localToday: localToday,
    serverNow: serverNow,
    backdateUntil: backdateUntil,
    audiobookshelf: audiobookshelf,
    notifications: notifications ?? this.notifications,
    features: features,
    schedule: schedule,
    protein: protein,
  );

  Json toJson() => {
    'user': user.toJson(),
    'targets': targets.toJson(),
    'questTemplates': [for (final q in questTemplates) q.toJson()],
    'localToday': localToday,
    'serverNow': _timeJson(serverNow),
    'backdateUntil': _timeJson(backdateUntil),
    if (audiobookshelf != null) 'audiobookshelf': audiobookshelf!.toJson(),
    'notifications': notifications.toJson(),
    'features': features.toJson(),
    // Left out while default, so a response from an older server re-encodes to what it sent.
    if (schedule != const Schedule()) 'schedule': schedule.toJson(),
    if (!protein.isEmpty) 'protein': protein.toJson(),
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
    this.birthYear,
    this.clearBirthYear = false,
    this.notifications,
    this.schedule,
    this.heightCm,
    this.clearHeight = false,
    this.sex,
    this.clearSex = false,
    this.goal,
    this.units,
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

  /// 1900..current year.
  final int? birthYear;

  /// Sends `birthYear: null` so the server forgets it.
  final bool clearBirthYear;

  final NotificationPatch? notifications;

  /// The whole schedule; the server validates it as one.
  final Schedule? schedule;

  /// 100..250 cm.
  final double? heightCm;

  /// Sends `heightCm: null` so the server forgets it.
  final bool clearHeight;

  /// `male` or `female`.
  final String? sex;

  /// Sends `sex: null` so the server forgets it.
  final bool clearSex;

  /// Replaces the goal as a whole; the server validates the pace for the kind.
  final GoalSetting? goal;

  final Units? units;

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
      if (clearBirthYear) 'birthYear': null else 'birthYear': ?birthYear,
      if (questTemplates != null) 'questTemplates': [for (final q in questTemplates!) q.toJson()],
      if (notifications != null) 'notifications': notifications!.toJson(),
      if (schedule != null) 'schedule': schedule!.toJson(),
      if (clearHeight) 'heightCm': null else 'heightCm': ?heightCm,
      if (clearSex) 'sex': null else 'sex': ?sex,
      'goal': ?goal?.toJson(),
      'units': ?units?.name,
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
    this.doneBy,
    this.detail,
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
    doneBy: DoneBy.tryParse(j['doneBy']),
    detail: j['detail'] is Map ? (j['detail'] as Map).cast<String, dynamic>() : null,
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

  /// The Health workout that completed the quest, when logged entries alone did not.
  final DoneBy? doneBy;

  /// Quest-specific facts from the server. The steady bedtime sends the night against the
  /// person's usual bed and wake times here.
  final Json? detail;

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
    if (doneBy != null) 'doneBy': doneBy!.toJson(),
    if (detail != null) 'detail': detail,
  };
}

int _goalPointsOf(int maxBase, int line) => (maxBase * line / 100).ceil();

int _goalPercentOf(int base, int maxBase, int line) {
  final goal = _goalPointsOf(maxBase, line);
  return goal <= 0 || base <= 0 ? 0 : base * 100 ~/ goal;
}

/// What the partner has done on their own local today, from GET /api/partner/today: their
/// quests, day and habits, without their food, health or plan.
class PartnerToday {
  const PartnerToday({
    required this.id,
    required this.name,
    required this.date,
    required this.day,
    required this.quests,
    required this.streak,
    required this.habits,
  });

  factory PartnerToday.fromJson(Json j) => PartnerToday(
    id: _int(j['id']),
    name: _str(j['name']),
    date: _str(j['date']),
    day: DayScore.fromJson(j['day'] as Json),
    quests: _list(j['quests'], Quest.fromJson),
    streak: Streak.fromJson(j['streak'] as Json),
    habits: parseHabitStates(j['habits']),
  );

  final int id;
  final String name;
  final String date;
  final DayScore day;
  final List<Quest> quests;
  final Streak streak;
  final List<HabitState> habits;
}

class DayScore {
  DayScore({
    required this.basePoints,
    required this.bonusPoints,
    required this.points,
    required this.maxBase,
    required this.percent,
    int? goalPercent,
    required this.counted,
    required this.streakLine,
  }) : goalPercent = goalPercent ?? _goalPercentOf(basePoints, maxBase, streakLine);

  factory DayScore.fromJson(Json j) => DayScore(
    basePoints: _int(j['basePoints']),
    bonusPoints: _int(j['bonusPoints']),
    points: _int(j['points']),
    maxBase: _int(j['maxBase']),
    percent: _int(j['percent']),
    goalPercent: j['goalPercent'] == null ? null : _int(j['goalPercent']),
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

  /// The share of the day's goal reached: 100 or more means the day counts, and it goes above
  /// 100 when more than the goal is earned. Older data without it is computed from the points.
  final int goalPercent;

  /// The points that make the day count: 100% of the goal.
  int get goalPoints => _goalPointsOf(maxBase, streakLine);
  final bool counted;

  /// The percent of the possible points that makes the goal.
  final int streakLine;

  Json toJson() => {
    'basePoints': basePoints,
    'bonusPoints': bonusPoints,
    'points': points,
    'maxBase': maxBase,
    'percent': percent,
    'goalPercent': goalPercent,
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
    this.listening,
    this.listeningSyncedAt,
    this.cheers = const [],
    this.habits = const [],
    this.readiness,
    this.plan,
    this.freezes = const Freezes(),
    this.repair,
    this.away = const AwayState(),
    this.newMilestones = const [],
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
    listening: j['listening'] is Map ? _int((j['listening'] as Map)['minutes']) : null,
    listeningSyncedAt: j['listening'] is Map ? _time((j['listening'] as Map)['syncedAt']) : null,
    cheers: parseCheers(j['cheers']),
    habits: parseHabitStates(j['habits']),
    readiness: Readiness.tryParse(j['readiness']),
    plan: Plan.tryParse(j['plan']),
    freezes: Freezes.parse(j['freezes']),
    repair: Repair.tryParse(j['repair']),
    away: AwayState.parse(j['away']),
    newMilestones: parseMilestones(j['newMilestones']),
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

  /// Audiobook minutes already counted in the reading quest; null from servers without the
  /// feature.
  final int? listening;

  /// When Audiobookshelf was last read; null while the person is not linked.
  final DateTime? listeningSyncedAt;

  /// Cheers the partner sent on this local day, oldest first.
  final List<Cheer> cheers;

  /// The habits due today with what is done, in the person's order.
  final List<HabitState> habits;

  /// How ready the day looks; null without enough data or on any day but today.
  final Readiness? readiness;

  /// The day's plan; null on any day but today.
  final Plan? plan;

  /// Streak freezes held and how far the next one is.
  final Freezes freezes;

  /// The open window to repair a missed yesterday; null when there is none.
  final Repair? repair;

  /// Whether today is an away day, and the spans around it.
  final AwayState away;

  /// Milestones reached yesterday or today, for a one-off celebration.
  final List<Milestone> newMilestones;

  int get listeningMinutes => listening ?? 0;

  Today copyWith({
    DayScore? day,
    List<Quest>? quests,
    Food? food,
    HealthStatus? health,
    List<HabitState>? habits,
  }) => Today(
    date: date,
    localToday: localToday,
    serverNow: serverNow,
    backdateUntil: backdateUntil,
    day: day ?? this.day,
    quests: quests ?? this.quests,
    streak: streak,
    food: food ?? this.food,
    health: health ?? this.health,
    listening: listening,
    listeningSyncedAt: listeningSyncedAt,
    cheers: cheers,
    habits: habits ?? this.habits,
    readiness: readiness,
    plan: plan,
    freezes: freezes,
    repair: repair,
    away: away,
    newMilestones: newMilestones,
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
    if (listening != null)
      'listening': {
        'minutes': listening,
        if (listeningSyncedAt != null) 'syncedAt': _timeJson(listeningSyncedAt),
      },
    'cheers': [for (final c in cheers) c.toJson()],
    'habits': [for (final h in habits) h.toJson()],
    if (readiness != null) 'readiness': readiness!.toJson(),
    if (plan != null) 'plan': plan!.toJson(),
    if (!freezes.isEmpty) 'freezes': freezes.toJson(),
    if (repair != null) 'repair': repair!.toJson(),
    if (!away.isEmpty) 'away': away.toJson(),
    if (newMilestones.isNotEmpty) 'newMilestones': [for (final m in newMilestones) m.toJson()],
  };
}

class DayMark {
  const DayMark({
    required this.date,
    required this.percent,
    int? goalPercent,
    required this.counted,
    required this.rest,
    this.frozen = false,
    this.away = false,
    this.repaired = false,
  }) : goalPercent = goalPercent ?? percent * 100 ~/ 70;

  factory DayMark.fromJson(Json j) => DayMark(
    date: _str(j['date']),
    percent: _int(j['percent']),
    goalPercent: j['goalPercent'] == null ? null : _int(j['goalPercent']),
    counted: j['counted'] as bool? ?? false,
    rest: j['rest'] as bool? ?? false,
    frozen: j['frozen'] as bool? ?? false,
    away: j['away'] as bool? ?? false,
    repaired: j['repaired'] as bool? ?? false,
  );

  final String date;
  final int percent;

  /// Share of the day's goal; see [DayScore.goalPercent].
  final int goalPercent;
  final bool counted;
  final bool rest;

  /// Covered by a freeze: the streak holds but gains no day.
  final bool frozen;

  /// An away day, which neither breaks nor extends the streak.
  final bool away;

  /// A missed day that was repaired afterwards; it counts as a frozen day.
  final bool repaired;

  Json toJson() => {
    'date': date,
    'percent': percent,
    'goalPercent': goalPercent,
    'counted': counted,
    'rest': rest,
    if (frozen) 'frozen': true,
    if (away) 'away': true,
    if (repaired) 'repaired': true,
  };
}

class BoardDay {
  const BoardDay({
    required this.points,
    required this.percent,
    int? goalPercent,
    required this.counted,
  }) : goalPercent = goalPercent ?? percent * 100 ~/ 70;

  factory BoardDay.fromJson(Json j) => BoardDay(
    points: _int(j['points']),
    percent: _int(j['percent']),
    goalPercent: j['goalPercent'] == null ? null : _int(j['goalPercent']),
    counted: j['counted'] as bool? ?? false,
  );

  final int points;
  final int percent;

  /// Share of the day's goal; see [DayScore.goalPercent].
  final int goalPercent;
  final bool counted;

  Json toJson() => {
    'points': points,
    'percent': percent,
    'goalPercent': goalPercent,
    'counted': counted,
  };
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
    this.workoutsThisWeek,
    this.freezes = const Freezes(),
    this.away = const AwayState(),
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
    workoutsThisWeek: _intOrNull(j['workoutsThisWeek']),
    freezes: Freezes.parse(j['freezes']),
    away: AwayState.parse(j['away']),
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

  /// Workouts in the current week; null on servers older than v4.
  final int? workoutsThisWeek;

  /// Streak freezes held; none before v7 servers.
  final Freezes freezes;

  /// Whether the person is away today, and the spans.
  final AwayState away;

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
    'workoutsThisWeek': ?workoutsThisWeek,
    if (!freezes.isEmpty) 'freezes': freezes.toJson(),
    if (!away.isEmpty) 'away': away.toJson(),
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
  const Board({
    required this.season,
    required this.serverNow,
    required this.users,
    this.challenge,
    this.lastChallenge,
    this.reward,
    this.sharedStreak = const SharedStreak(),
  });

  factory Board.fromJson(Json j) => Board(
    season: SeasonInfo.fromJson(j['season'] as Json),
    serverNow: _time(j['serverNow']) ?? DateTime.now().toUtc(),
    users: _list(j['users'], BoardUser.fromJson),
    challenge: Challenge.tryParse(j['challenge']),
    lastChallenge: Challenge.tryParse(j['lastChallenge']),
    reward: Reward.tryParse(j['reward']),
    sharedStreak: SharedStreak.parse(j['sharedStreak']),
  );

  final SeasonInfo season;
  final DateTime serverNow;

  /// The signed-in person first.
  final List<BoardUser> users;

  /// This week's shared challenge; null from servers older than v5.
  final Challenge? challenge;

  /// Last week's challenge when it ended unfinished; null otherwise and before v13.
  final Challenge? lastChallenge;

  /// The reward being earned, or the newest reached one not yet enjoyed.
  final Reward? reward;

  /// The couple's streak; zero before v7 servers.
  final SharedStreak sharedStreak;

  Board copyWith({Reward? reward, bool clearReward = false}) => Board(
    season: season,
    serverNow: serverNow,
    users: users,
    challenge: challenge,
    lastChallenge: lastChallenge,
    reward: clearReward ? null : (reward ?? this.reward),
    sharedStreak: sharedStreak,
  );

  Json toJson() => {
    'season': season.toJson(),
    'serverNow': _timeJson(serverNow),
    'users': [for (final u in users) u.toJson()],
    'challenge': challenge?.toJson(),
    if (lastChallenge != null) 'lastChallenge': lastChallenge!.toJson(),
    'reward': reward?.toJson(),
    if (!sharedStreak.isEmpty) 'sharedStreak': sharedStreak.toJson(),
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
    this.name = '',
    this.intensity,
  });

  factory ActivityLog.fromJson(Json j) => ActivityLog(
    id: _int(j['id']),
    localDate: _str(j['localDate']),
    loggedAt: _time(j['loggedAt']) ?? DateTime.now().toUtc(),
    type: _str(j['type']),
    quantity: _int(j['quantity']),
    unit: _str(j['unit']),
    name: _str(j['name']),
    intensity: j['intensity'] as String?,
  );

  /// `pushups`, `reading`, `yoga` or `other`.
  final String type;
  final int quantity;
  final String unit;

  /// The free name of an `other` activity.
  final String name;

  /// easy, moderate or hard, for an `other` activity.
  final String? intensity;

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
    if (name.isNotEmpty) 'name': name,
    'intensity': ?intensity,
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

/// The body of PATCH /logs/{id} for a meal: only the fields that changed.
class MealEdit {
  const MealEdit({
    this.name,
    this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.fiber,
    this.loggedAt,
  });

  final String? name;
  final int? kcal;
  final num? protein;
  final num? carbs;
  final num? fat;
  final num? fiber;

  /// Moves the meal to another moment, which may be another day.
  final DateTime? loggedAt;

  bool get isEmpty =>
      loggedAt == null &&
      name == null &&
      kcal == null &&
      protein == null &&
      carbs == null &&
      fat == null &&
      fiber == null;

  Json toJson() => {
    'name': ?name,
    'kcal': ?kcal,
    'protein': ?protein,
    'carbs': ?carbs,
    'fat': ?fat,
    'fiber': ?fiber,
    'loggedAt': ?_timeJson(loggedAt),
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
    this.name,
    this.intensity,
  });

  /// A free-named activity that counts toward exercise minutes.
  const ActivityDraft.other({
    required super.clientOpId,
    required String this.name,
    required int minutes,
    required String this.intensity,
    super.date,
  }) : type = 'other',
       quantity = minutes,
       unit = 'minutes';

  final String type;
  final int quantity;
  final String unit;

  /// Only for type `other`.
  final String? name;
  final String? intensity;

  @override
  String get kind => 'activity';

  @override
  Json toJson() => {
    ...super.toJson(),
    'type': type,
    'quantity': quantity,
    'unit': unit,
    'name': ?name,
    'intensity': ?intensity,
  };
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
      name: a.type == 'other' ? a.name : null,
      intensity: a.type == 'other' ? a.intensity : null,
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

/// How GET /health/cardio reads: why the page can or cannot compare the latest VO2 max.
enum CardioStatus {
  ready,
  noReading,
  needsProfile,
  ageOutOfRange;

  static CardioStatus parse(String? v) => switch (v) {
    'ready' => ready,
    'needs_profile' => needsProfile,
    'age_out_of_range' => ageOutOfRange,
    _ => noReading,
  };
}

/// GET /health/cardio: the newest VO2 max and where it falls among people of the same sex and
/// age decade, or what the comparison still needs.
class CardioFitness {
  const CardioFitness({
    required this.status,
    this.latestDate,
    this.latestValue,
    this.needs = const [],
    this.ageGroup,
    this.sex,
    this.percentileLow,
    this.percentileHigh,
    this.median,
    this.source,
  });

  factory CardioFitness.fromJson(Json j) {
    final latest = j['latest'] as Json?;
    final norm = j['norm'] as Json?;
    return CardioFitness(
      status: CardioStatus.parse(j['status'] as String?),
      latestDate: latest == null ? null : _str(latest['date']),
      latestValue: latest == null ? null : _num(latest['value']),
      needs: [for (final n in j['needs'] as List? ?? const []) n as String],
      ageGroup: norm == null ? null : _str(norm['ageGroup']),
      sex: norm == null ? null : _str(norm['sex']),
      percentileLow: norm == null ? null : _intOrNull(norm['percentileLow']),
      percentileHigh: norm == null ? null : _intOrNull(norm['percentileHigh']),
      median: norm == null ? null : _num(norm['median']),
      source: norm == null ? null : _str(norm['source']),
    );
  }

  final CardioStatus status;
  final String? latestDate;
  final num? latestValue;

  /// Profile fields the comparison is waiting for: `birthYear` and `sex`.
  final List<String> needs;
  final String? ageGroup;
  final String? sex;

  /// The percentile band: 0 means below the 10th, and a high of 100 means above the 90th.
  final int? percentileLow;
  final int? percentileHigh;
  final num? median;
  final String? source;
}

/// One workout of PUT /health/workouts. [type] is one of `WorkoutType.all`.
class WorkoutUpload {
  const WorkoutUpload({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.durationMin,
    required this.source,
    this.kcal,
    this.distanceM,
    this.avgHr,
  });

  /// The HealthKit sample UUID; the server upserts on it.
  final String id;
  final String type;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMin;
  final int? kcal;
  final int? distanceM;
  final int? avgHr;
  final String source;

  Json toJson() => {
    'id': id,
    'type': type,
    'startedAt': _timeJson(startedAt),
    'endedAt': _timeJson(endedAt),
    'durationMin': durationMin,
    'kcal': kcal,
    'distanceM': distanceM,
    'avgHr': avgHr,
    'source': source,
  };

  @override
  bool operator ==(Object other) =>
      other is WorkoutUpload && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// The workout types the server accepts.
abstract final class WorkoutType {
  static const walking = 'walking';
  static const running = 'running';
  static const cycling = 'cycling';
  static const strength = 'strength';
  static const hiit = 'hiit';
  static const yoga = 'yoga';
  static const swimming = 'swimming';
  static const hiking = 'hiking';
  static const dance = 'dance';
  static const climbing = 'climbing';
  static const other = 'other';

  static const all = [
    walking,
    running,
    cycling,
    strength,
    hiit,
    yoga,
    swimming,
    hiking,
    dance,
    climbing,
    other,
  ];
}

/// One night of PUT /health/sleep.
class SleepNightUpload {
  const SleepNightUpload({
    required this.date,
    required this.bedAt,
    required this.wakeAt,
    required this.asleepMin,
    required this.source,
    this.deepMin = 0,
    this.remMin = 0,
    this.coreMin = 0,
    this.awakeMin = 0,
  });

  /// The morning the night ends, as a local date.
  final String date;
  final DateTime bedAt;
  final DateTime wakeAt;
  final int asleepMin;
  final int deepMin;
  final int remMin;
  final int coreMin;
  final int awakeMin;
  final String source;

  Json toJson() => {
    'date': date,
    'bedAt': _timeJson(bedAt),
    'wakeAt': _timeJson(wakeAt),
    'asleepMin': asleepMin,
    'deepMin': deepMin,
    'remMin': remMin,
    'coreMin': coreMin,
    'awakeMin': awakeMin,
    'source': source,
  };

  @override
  bool operator ==(Object other) =>
      other is SleepNightUpload && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// A workout of GET /workouts.
class Workout {
  const Workout({
    required this.id,
    required this.type,
    required this.date,
    required this.startedAt,
    required this.endedAt,
    required this.durationMin,
    this.kcal,
    this.distanceM,
    this.avgHr,
  });

  factory Workout.fromJson(Json j) => Workout(
    id: _str(j['id']),
    type: _str(j['type'], WorkoutType.other),
    date: _str(j['date']),
    startedAt: _time(j['startedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    endedAt: _time(j['endedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    // The server keeps one decimal; truncating would show 34.9 minutes as 34.
    durationMin: ((j['durationMin'] as num?) ?? 0).round(),
    kcal: _intOrNull(j['kcal']),
    distanceM: _intOrNull(j['distanceM']),
    avgHr: _intOrNull(j['avgHr']),
  );

  final String id;
  final String type;

  /// The local date of [startedAt] in the person's zone.
  final String date;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationMin;
  final int? kcal;
  final int? distanceM;
  final int? avgHr;

  Json toJson() => {
    'id': id,
    'type': type,
    'date': date,
    'startedAt': _timeJson(startedAt),
    'endedAt': _timeJson(endedAt),
    'durationMin': durationMin,
    'kcal': kcal,
    'distanceM': distanceM,
    'avgHr': avgHr,
  };
}

/// A count and total minutes of workouts.
class WorkoutTotals {
  const WorkoutTotals({this.count = 0, this.minutes = 0});

  factory WorkoutTotals.fromJson(Object? j) => j is Map
      ? WorkoutTotals(count: _int(j['count']), minutes: _int(j['minutes']))
      : const WorkoutTotals();

  final int count;
  final int minutes;

  Json toJson() => {'count': count, 'minutes': minutes};
}

/// GET /workouts: newest first, plus this week's totals.
class WorkoutList {
  const WorkoutList({required this.workouts, this.week = const WorkoutTotals()});

  factory WorkoutList.fromJson(Json j) => WorkoutList(
    workouts: _list(j['workouts'], Workout.fromJson),
    week: WorkoutTotals.fromJson(j['week']),
  );

  final List<Workout> workouts;
  final WorkoutTotals week;

  Json toJson() => {
    'workouts': [for (final w in workouts) w.toJson()],
    'week': week.toJson(),
  };
}

class StepBest {
  const StepBest({required this.date, required this.value});

  factory StepBest.fromJson(Json j) => StepBest(date: _str(j['date']), value: _num(j['value']));

  final String date;
  final num value;

  Json toJson() => {'date': date, 'value': value};
}

class StepSuggestion {
  const StepSuggestion({
    required this.target,
    required this.median14,
    required this.bandLow,
    required this.bandHigh,
    required this.ageKnown,
  });

  factory StepSuggestion.fromJson(Json j) => StepSuggestion(
    target: _int(j['target']),
    median14: _num(j['median14']),
    bandLow: _int(j['bandLow']),
    bandHigh: _int(j['bandHigh']),
    ageKnown: j['ageKnown'] as bool? ?? false,
  );

  final int target;
  final num median14;
  final int bandLow;
  final int bandHigh;
  final bool ageKnown;

  Json toJson() => {
    'target': target,
    'median14': median14,
    'bandLow': bandLow,
    'bandHigh': bandHigh,
    'ageKnown': ageKnown,
  };
}

class StepInsights {
  const StepInsights({
    this.avg7,
    this.avg30,
    this.median14,
    this.trend = 'flat',
    this.best,
    this.daysAtGoal30 = 0,
    this.goal = 0,
    this.suggestion,
  });

  factory StepInsights.fromJson(Object? raw) {
    if (raw is! Map) return const StepInsights();
    final j = raw.cast<String, dynamic>();
    return StepInsights(
      avg7: j['avg7'] as num?,
      avg30: j['avg30'] as num?,
      median14: j['median14'] as num?,
      trend: _str(j['trend'], 'flat'),
      best: j['best'] is Map ? StepBest.fromJson((j['best'] as Map).cast<String, dynamic>()) : null,
      daysAtGoal30: _int(j['daysAtGoal30']),
      goal: _int(j['goal']),
      suggestion: j['suggestion'] is Map
          ? StepSuggestion.fromJson((j['suggestion'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  final num? avg7;
  final num? avg30;
  final num? median14;

  /// `up`, `flat` or `down`.
  final String trend;
  final StepBest? best;
  final int daysAtGoal30;
  final int goal;

  /// Null when fewer than five of the last 14 days have steps.
  final StepSuggestion? suggestion;

  Json toJson() => {
    'avg7': avg7,
    'avg30': avg30,
    'median14': median14,
    'trend': trend,
    'best': best?.toJson(),
    'daysAtGoal30': daysAtGoal30,
    'goal': goal,
    'suggestion': suggestion?.toJson(),
  };
}

class SleepStages {
  const SleepStages({this.deepMin = 0, this.remMin = 0, this.coreMin = 0, this.awakeMin = 0});

  factory SleepStages.fromJson(Json j) => SleepStages(
    deepMin: _int(j['deepMin']),
    remMin: _int(j['remMin']),
    coreMin: _int(j['coreMin']),
    awakeMin: _int(j['awakeMin']),
  );

  final int deepMin;
  final int remMin;
  final int coreMin;
  final int awakeMin;

  Json toJson() => {'deepMin': deepMin, 'remMin': remMin, 'coreMin': coreMin, 'awakeMin': awakeMin};
}

class SleepNight {
  const SleepNight({
    required this.date,
    required this.bedAt,
    required this.wakeAt,
    required this.asleepMin,
    this.stages = const SleepStages(),
  });

  factory SleepNight.fromJson(Json j) => SleepNight(
    date: _str(j['date']),
    bedAt: _time(j['bedAt']),
    wakeAt: _time(j['wakeAt']),
    asleepMin: _int(j['asleepMin']),
    stages: SleepStages.fromJson(j),
  );

  final String date;
  final DateTime? bedAt;
  final DateTime? wakeAt;
  final int asleepMin;
  final SleepStages stages;

  Json toJson() => {
    'date': date,
    'bedAt': _timeJson(bedAt),
    'wakeAt': _timeJson(wakeAt),
    'asleepMin': asleepMin,
    ...stages.toJson(),
  };
}

class SleepNightPoint {
  const SleepNightPoint({required this.date, required this.asleepMin});

  factory SleepNightPoint.fromJson(Json j) =>
      SleepNightPoint(date: _str(j['date']), asleepMin: _int(j['asleepMin']));

  final String date;
  final int asleepMin;

  Json toJson() => {'date': date, 'asleepMin': asleepMin};
}

class SleepInsights {
  const SleepInsights({
    this.avg7Min,
    this.avg30Min,
    this.targetMin = 420,
    this.avgBedtime,
    this.avgWake,
    this.bedtimeSpreadMin,
    this.stages7,
    this.lastNight,
    this.nights = const [],
    this.regularity = const SleepRegularity(),
  });

  factory SleepInsights.fromJson(Object? raw) {
    if (raw is! Map) return const SleepInsights();
    final j = raw.cast<String, dynamic>();
    return SleepInsights(
      avg7Min: j['avg7Min'] as num?,
      avg30Min: j['avg30Min'] as num?,
      targetMin: _int(j['targetMin'], 420),
      avgBedtime: j['avgBedtime'] as String?,
      avgWake: j['avgWake'] as String?,
      bedtimeSpreadMin: j['bedtimeSpreadMin'] as num?,
      stages7: j['stages7'] is Map
          ? SleepStages.fromJson((j['stages7'] as Map).cast<String, dynamic>())
          : null,
      lastNight: j['lastNight'] is Map
          ? SleepNight.fromJson((j['lastNight'] as Map).cast<String, dynamic>())
          : null,
      nights: _list(j['nights'], SleepNightPoint.fromJson),
      regularity: SleepRegularity.fromJson(j['regularity']),
    );
  }

  final num? avg7Min;
  final num? avg30Min;
  final int targetMin;

  /// Local clock times as `HH:mm`.
  final String? avgBedtime;
  final String? avgWake;
  final num? bedtimeSpreadMin;
  final SleepStages? stages7;
  final SleepNight? lastNight;

  /// The last 14 nights with data, oldest first.
  final List<SleepNightPoint> nights;

  /// The Sleep Regularity Index over the last 14 days.
  final SleepRegularity regularity;

  Json toJson() => {
    'avg7Min': avg7Min,
    'avg30Min': avg30Min,
    'targetMin': targetMin,
    'avgBedtime': avgBedtime,
    'avgWake': avgWake,
    'bedtimeSpreadMin': bedtimeSpreadMin,
    'stages7': stages7?.toJson(),
    'lastNight': lastNight?.toJson(),
    'nights': [for (final n in nights) n.toJson()],
    if (regularity.nights > 0 || regularity.score != null) 'regularity': regularity.toJson(),
  };
}

/// The Sleep Regularity Index (Phillips et al., Sci Rep 2017): 100 is a perfectly regular
/// schedule. [score] is null until there are enough nights.
class SleepRegularity {
  const SleepRegularity({
    this.score,
    this.nights = 0,
    this.pairs = 0,
    this.windowDays = 14,
    this.minNights = 5,
  });

  factory SleepRegularity.fromJson(Object? raw) {
    if (raw is! Map) return const SleepRegularity();
    final j = raw.cast<String, dynamic>();
    return SleepRegularity(
      score: j['score'] as num?,
      nights: _int(j['nights']),
      pairs: _int(j['pairs']),
      windowDays: _int(j['windowDays'], 14),
      minNights: _int(j['minNights'], 5),
    );
  }

  final num? score;
  final int nights;
  final int pairs;
  final int windowDays;
  final int minNights;

  Json toJson() => {
    'score': score,
    'nights': nights,
    'pairs': pairs,
    'windowDays': windowDays,
    'minNights': minNights,
  };
}

class WorkoutTypeTotals {
  const WorkoutTypeTotals({required this.type, required this.count, required this.minutes});

  factory WorkoutTypeTotals.fromJson(Json j) => WorkoutTypeTotals(
    type: _str(j['type'], WorkoutType.other),
    count: _int(j['count']),
    minutes: _int(j['minutes']),
  );

  final String type;
  final int count;
  final int minutes;

  Json toJson() => {'type': type, 'count': count, 'minutes': minutes};
}

class WorkoutInsights {
  const WorkoutInsights({
    this.week = const WorkoutTotals(),
    this.last30 = const WorkoutTotals(),
    this.byType = const [],
  });

  factory WorkoutInsights.fromJson(Object? raw) {
    if (raw is! Map) return const WorkoutInsights();
    final j = raw.cast<String, dynamic>();
    final last30 = j['last30'] is Map ? (j['last30'] as Map).cast<String, dynamic>() : null;
    return WorkoutInsights(
      week: WorkoutTotals.fromJson(j['week']),
      last30: WorkoutTotals.fromJson(last30),
      byType: _list(last30?['byType'], WorkoutTypeTotals.fromJson),
    );
  }

  final WorkoutTotals week;
  final WorkoutTotals last30;

  /// The 30 day breakdown, flattened from `last30.byType`.
  final List<WorkoutTypeTotals> byType;

  Json toJson() => {
    'week': week.toJson(),
    'last30': {
      ...last30.toJson(),
      'byType': [for (final t in byType) t.toJson()],
    },
  };
}

/// GET /insights; every part tolerates being absent so an older server still parses.
class Insights {
  const Insights({
    this.steps = const StepInsights(),
    this.sleep = const SleepInsights(),
    this.workouts = const WorkoutInsights(),
    this.weight = const WeightInsights(),
    this.activity = const ActivitySummary(),
    this.protein = const ProteinHitRate(),
  });

  factory Insights.fromJson(Json j) => Insights(
    steps: StepInsights.fromJson(j['steps']),
    sleep: SleepInsights.fromJson(j['sleep']),
    workouts: WorkoutInsights.fromJson(j['workouts']),
    weight: WeightInsights.parse(j['weight']),
    activity: ActivitySummary.parse(j['activity']),
    protein: ProteinHitRate.parse(j['protein']),
  );

  final StepInsights steps;
  final SleepInsights sleep;
  final WorkoutInsights workouts;

  /// Smoothed weight with the weekly rate.
  final WeightInsights weight;

  /// The last seven days against the WHO 2020 guideline.
  final ActivitySummary activity;

  /// The 7-day protein hit rate.
  final ProteinHitRate protein;

  Json toJson() => {
    'steps': steps.toJson(),
    'sleep': sleep.toJson(),
    'workouts': workouts.toJson(),
    if (weight.hasData || weight.points.isNotEmpty) 'weight': weight.toJson(),
    if (activity.available) 'activity': activity.toJson(),
    if (protein.available) 'protein': protein.toJson(),
  };
}
