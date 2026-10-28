/// Wire models for cheers, the weekly challenge, rewards and notification switches. Parsing is
/// tolerant: a missing or malformed piece degrades to "nothing to show" instead of failing the
/// screen that carries it.
library;

import 'v7_models.dart';

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
    this.people = const [],
    this.missed = false,
    this.reason = '',
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
      people: [
        if (j['people'] is List)
          for (final p in j['people'] as List) ?ChallengeShare.tryParse(p),
      ],
      missed: j['missed'] as bool? ?? false,
      reason: _str(j['reason']),
    );
  }

  /// steps, workouts, counted_days, reading or one of the v13 kinds (sleep_nights, meal_days,
  /// protein_days, pushup_reps, yoga_minutes, habit_marks, active_days); unknown kinds still
  /// render with generic copy.
  final String kind;
  final String title;
  final int target;
  final int progress;
  final bool done;

  /// Local date (yyyy-MM-dd) of the last day of the week.
  final String endsOn;

  /// Each person's own share and progress. Empty on servers older than v7 and on challenges
  /// from before them, which are measured on the pair's total.
  final List<ChallengeShare> people;

  /// True once the week ended with the challenge unfinished. It costs nothing.
  final bool missed;

  /// Why the server picked this kind, empty on servers older than v13.
  final String reason;

  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'title': title,
    'target': target,
    'progress': progress,
    'done': done,
    'endsOn': endsOn,
    if (people.isNotEmpty) 'people': [for (final p in people) p.toJson()],
    if (missed) 'missed': true,
    if (reason.isNotEmpty) 'reason': reason,
  };
}

/// One wishlist entry, priced in gems. [status] is `pending`, `declined`, `approved` or
/// `claimed`; builds before shared rewards sent only a target and no status, which reads as an
/// approved reward.
class Reward {
  const Reward({
    required this.id,
    required this.name,
    required this.price,
    required this.progress,
    this.status = 'approved',
    this.focus = false,
    this.ready = false,
    this.startedAt,
    this.reachedAt,
    this.claimedAt,
    this.proposedBy,
    this.proposedByName = '',
  });

  static Reward? tryParse(Object? v) {
    final j = _map(v);
    final price = j == null ? 0 : _int(j['price'], _int(j['target']));
    if (j == null || _int(j['id']) < 1 || price < 1) return null;
    final status = _str(j['status'], 'approved');
    final claimedAt = _time(j['claimedAt']);
    final reachedAt = _time(j['reachedAt']);
    return Reward(
      id: _int(j['id']),
      name: _str(j['name']),
      price: price,
      progress: _int(j['progress']),
      status: status,
      focus: j['focus'] as bool? ?? false,
      ready:
          status == 'approved' && claimedAt == null && (j['ready'] as bool? ?? reachedAt != null),
      startedAt: _time(j['startedAt']),
      reachedAt: reachedAt,
      claimedAt: claimedAt,
      proposedBy: (j['proposedBy'] as num?)?.toInt() ?? (j['createdBy'] as num?)?.toInt(),
      proposedByName: _str(j['proposedByName']),
    );
  }

  final int id;
  final String name;
  final int price;
  final int progress;
  final String status;
  final bool focus;

  /// The bank covers the price and nobody has claimed it yet.
  final bool ready;
  final DateTime? startedAt;
  final DateTime? reachedAt;
  final DateTime? claimedAt;
  final int? proposedBy;
  final String proposedByName;

  bool get pending => status == 'pending';
  bool get declined => status == 'declined';
  bool get approved => status == 'approved';
  bool get claimed => status == 'claimed' || claimedAt != null;
  bool get reached => reachedAt != null;

  double get fraction => (progress / price).clamp(0.0, 1.0);

  bool proposedByUser(int? userId) => userId != null && proposedBy == userId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'target': price,
    'progress': progress,
    'status': status,
    'focus': focus,
    'ready': ready,
    'startedAt': _timeJson(startedAt),
    'reachedAt': _timeJson(reachedAt),
    'claimedAt': _timeJson(claimedAt),
    'proposedBy': proposedBy,
    'proposedByName': proposedByName,
    'createdBy': proposedBy,
  };
}

/// A suggested price: what the pair earns at its own pace over [days] days.
class PriceOption {
  const PriceOption({required this.days, required this.price});

  final int days;
  final int price;

  /// "1 week", "2 weeks", "about a month".
  String get span => switch (days) {
    7 => '1 week',
    14 => '2 weeks',
    30 => 'about a month',
    _ => '$days days',
  };
}

/// The pair's median combined gems per day over its last full days, and the prices that follow.
class PriceHelp {
  const PriceHelp({required this.medianDaily, required this.sampleDays, required this.options});

  static PriceHelp? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _int(j['medianDaily']) < 1) return null;
    final options = [
      if (j['options'] is List)
        for (final o in j['options'] as List)
          if (_map(o) case final m? when _int(m['price']) >= 1)
            PriceOption(days: _int(m['days']), price: _int(m['price'])),
    ];
    if (options.isEmpty) return null;
    return PriceHelp(
      medianDaily: _int(j['medianDaily']),
      sampleDays: _int(j['sampleDays']),
      options: options,
    );
  }

  final int medianDaily;
  final int sampleDays;
  final List<PriceOption> options;
}

/// GET /api/rewards: the focus reward, the whole wishlist (focus first, with the proposals that
/// wait on someone), the claimed history newest first, the gem bank and the price helper.
class RewardList {
  const RewardList({
    this.active,
    this.items = const [],
    this.history = const [],
    this.bank = 0,
    this.priceHelp,
  });

  factory RewardList.fromJson(Map<String, dynamic> j) => RewardList(
    active: Reward.tryParse(j['reward']),
    items: [
      if (j['rewards'] is List)
        for (final item in j['rewards'] as List) ?Reward.tryParse(item),
    ],
    history: [
      if (j['history'] is List)
        for (final item in j['history'] as List) ?Reward.tryParse(item),
    ],
    bank: _int(j['bank']),
    priceHelp: PriceHelp.tryParse(j['priceHelp']),
  );

  final Reward? active;
  final List<Reward> items;
  final List<Reward> history;
  final int bank;
  final PriceHelp? priceHelp;

  /// Approved rewards waiting behind the focus.
  List<Reward> get queued => [
    for (final r in items)
      if (r.approved && !r.focus) r,
  ];

  /// Proposals from my partner that wait for my answer.
  List<Reward> proposalsFor(int? userId) => [
    for (final r in items)
      if (r.pending && !r.proposedByUser(userId)) r,
  ];

  /// What I proposed and is still pending or was declined.
  List<Reward> mineOpen(int? userId) => [
    for (final r in items)
      if ((r.pending || r.declined) && r.proposedByUser(userId)) r,
  ];
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
    this.milestones = true,
    this.lookback = true,
    this.partnerNudges = true,
    this.cover = true,
    this.approvals = true,
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
      milestones: j['milestones'] as bool? ?? true,
      lookback: j['lookback'] as bool? ?? true,
      partnerNudges: j['partnerNudges'] as bool? ?? true,
      cover: j['cover'] as bool? ?? true,
      approvals: j['approvals'] as bool? ?? true,
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

  /// Streak and shared-streak milestones, and the monthly look-back summary.
  final bool milestones;
  final bool lookback;

  /// The v13 switches: gentle prompts about the partner (cheer prompt, reward progress, Thursday
  /// check-in), cover chances and covers, and habit approvals.
  final bool partnerNudges;
  final bool cover;
  final bool approvals;

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
    // Left out while on (the default), so an older server's answer re-encodes to what it sent.
    if (!milestones) 'milestones': false,
    if (!lookback) 'lookback': false,
    if (!partnerNudges) 'partnerNudges': false,
    if (!cover) 'cover': false,
    if (!approvals) 'approvals': false,
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
    this.milestones,
    this.lookback,
    this.partnerNudges,
    this.cover,
    this.approvals,
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
  final bool? milestones;
  final bool? lookback;
  final bool? partnerNudges;
  final bool? cover;
  final bool? approvals;

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
    'milestones': ?milestones,
    'lookback': ?lookback,
    'partnerNudges': ?partnerNudges,
    'cover': ?cover,
    'approvals': ?approvals,
  };
}
