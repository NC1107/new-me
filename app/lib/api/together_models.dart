/// Wire models for cheers, the weekly challenge, rewards and notification switches. Parsing is
/// tolerant: a missing or malformed piece degrades to "nothing to show" instead of failing the
/// screen that carries it.
library;

typedef _Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

String _str(Object? v, [String fallback = '']) => v as String? ?? fallback;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

String? _timeJson(DateTime? v) => v?.toUtc().toIso8601String();

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

/// The reactions one person can send the other, in display order.
enum CheerKind {
  clap,
  fire,
  flex,
  heart;

  static CheerKind? parse(Object? v) {
    for (final k in values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

class Cheer {
  const Cheer({required this.from, required this.fromName, required this.kind, this.at});

  /// Null when the kind is one this build does not know, so the caller can skip it.
  static Cheer? tryParse(Object? v) {
    final j = _map(v);
    final kind = CheerKind.parse(j?['kind']);
    if (j == null || kind == null) return null;
    return Cheer(
      from: _int(j['from']),
      fromName: _str(j['fromName']),
      kind: kind,
      at: _time(j['at']),
    );
  }

  final int from;
  final String fromName;
  final CheerKind kind;
  final DateTime? at;

  Map<String, dynamic> toJson() => {
    'from': from,
    'fromName': fromName,
    'kind': kind.name,
    'at': _timeJson(at),
  };
}

List<Cheer> parseCheers(Object? v) => [
  if (v is List)
    for (final item in v) ?Cheer.tryParse(item),
];

/// The shared goal of the week. The server sizes it and reports combined progress only.
class Challenge {
  const Challenge({
    required this.kind,
    required this.title,
    required this.target,
    required this.progress,
    required this.done,
    required this.endsOn,
  });

  static Challenge? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _int(j['target']) < 1) return null;
    return Challenge(
      kind: _str(j['kind']),
      title: _str(j['title']),
      target: _int(j['target']),
      progress: _int(j['progress']),
      done: j['done'] as bool? ?? false,
      endsOn: _str(j['endsOn']),
    );
  }

  /// steps, workouts, counted_days or reading; unknown kinds still render with generic copy.
  final String kind;
  final String title;
  final int target;
  final int progress;
  final bool done;

  /// Local date (yyyy-MM-dd) of the last day of the week.
  final String endsOn;

  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'title': title,
    'target': target,
    'progress': progress,
    'done': done,
    'endsOn': endsOn,
  };
}

class Reward {
  const Reward({
    required this.id,
    required this.name,
    required this.target,
    required this.progress,
    this.startedAt,
    this.reachedAt,
    this.claimedAt,
    this.createdBy,
  });

  static Reward? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _int(j['id']) < 1 || _int(j['target']) < 1) return null;
    return Reward(
      id: _int(j['id']),
      name: _str(j['name']),
      target: _int(j['target']),
      progress: _int(j['progress']),
      startedAt: _time(j['startedAt']),
      reachedAt: _time(j['reachedAt']),
      claimedAt: _time(j['claimedAt']),
      createdBy: (j['createdBy'] as num?)?.toInt(),
    );
  }

  final int id;
  final String name;
  final int target;
  final int progress;
  final DateTime? startedAt;
  final DateTime? reachedAt;
  final DateTime? claimedAt;
  final int? createdBy;

  bool get reached => reachedAt != null;
  bool get claimed => claimedAt != null;
  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'target': target,
    'progress': progress,
    'startedAt': _timeJson(startedAt),
    'reachedAt': _timeJson(reachedAt),
    'claimedAt': _timeJson(claimedAt),
    'createdBy': createdBy,
  };
}

/// GET /api/rewards: the reward being earned and the ones already reached, newest first.
class RewardList {
  const RewardList({this.active, this.history = const []});

  factory RewardList.fromJson(Map<String, dynamic> j) => RewardList(
    active: Reward.tryParse(j['reward']),
    history: [
      if (j['history'] is List)
        for (final item in j['history'] as List) ?Reward.tryParse(item),
    ],
  );

  final Reward? active;
  final List<Reward> history;
}

/// Which events may send this person a push notification.
class NotificationPrefs {
  const NotificationPrefs({
    this.partnerDone = true,
    this.cheers = true,
    this.challenge = true,
    this.reward = true,
    this.behindPace = false,
    this.closeToDone = true,
    this.windDown = false,
    this.morningPlan = true,
    this.weeklyRecap = true,
  });

  /// Servers older than v5 send nothing, which reads as everything on.
  factory NotificationPrefs.fromJson(Object? v) {
    final j = _map(v);
    if (j == null) return const NotificationPrefs();
    return NotificationPrefs(
      partnerDone: j['partnerDone'] as bool? ?? true,
      cheers: j['cheers'] as bool? ?? true,
      challenge: j['challenge'] as bool? ?? true,
      reward: j['reward'] as bool? ?? true,
      behindPace: j['behindPace'] as bool? ?? false,
      closeToDone: j['closeToDone'] as bool? ?? true,
      windDown: j['windDown'] as bool? ?? false,
      morningPlan: j['morningPlan'] as bool? ?? true,
      weeklyRecap: j['weeklyRecap'] as bool? ?? true,
    );
  }

  final bool partnerDone;
  final bool cheers;
  final bool challenge;
  final bool reward;

  /// The v6 nudges and the Sunday recap. The server defaults Steps to go and Wind down to off.
  final bool behindPace;
  final bool closeToDone;
  final bool windDown;
  final bool morningPlan;
  final bool weeklyRecap;

  Map<String, dynamic> toJson() => {
    'partnerDone': partnerDone,
    'cheers': cheers,
    'challenge': challenge,
    'reward': reward,
    'behindPace': behindPace,
    'closeToDone': closeToDone,
    'windDown': windDown,
    'morningPlan': morningPlan,
    'weeklyRecap': weeklyRecap,
  };
}

/// A partial change to [NotificationPrefs]; null switches are left out of the PATCH body.
class NotificationPatch {
  const NotificationPatch({
    this.partnerDone,
    this.cheers,
    this.challenge,
    this.reward,
    this.behindPace,
    this.closeToDone,
    this.windDown,
    this.morningPlan,
    this.weeklyRecap,
  });

  final bool? partnerDone;
  final bool? cheers;
  final bool? challenge;
  final bool? reward;
  final bool? behindPace;
  final bool? closeToDone;
  final bool? windDown;
  final bool? morningPlan;
  final bool? weeklyRecap;

  Map<String, dynamic> toJson() => {
    'partnerDone': ?partnerDone,
    'cheers': ?cheers,
    'challenge': ?challenge,
    'reward': ?reward,
    'behindPace': ?behindPace,
    'closeToDone': ?closeToDone,
    'windDown': ?windDown,
    'morningPlan': ?morningPlan,
    'weeklyRecap': ?weeklyRecap,
  };
}
