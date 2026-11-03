/// Wire models for agreed tasks: a chore worth gems. Parsing is tolerant, so a malformed
/// row is dropped instead of failing the list that carries it.
library;

import 'models.dart';

abstract final class TaskStatus {
  static const proposed = 'proposed';
  static const declined = 'declined';
  static const agreed = 'agreed';
  static const done = 'done';
  static const missed = 'missed';
}

const kTaskTitleMax = 60;
const kTaskStakeMax = 100000;

/// One task between the two people. [daysLeft] counts from the assignee's today to [deadline]:
/// 0 is due today and a negative number is overdue.
class GemTask {
  const GemTask({
    required this.id,
    required this.title,
    required this.creatorId,
    required this.creatorName,
    required this.assigneeId,
    required this.assigneeName,
    required this.stake,
    required this.loseIfMissed,
    required this.lost,
    required this.deadline,
    required this.daysLeft,
    required this.status,
  });

  static GemTask? tryParse(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, dynamic>();
    final id = (j['id'] as num?)?.toInt() ?? 0;
    final stake = (j['stake'] as num?)?.toInt() ?? 0;
    final deadline = j['deadline'] as String? ?? '';
    if (id < 1 || stake < 1 || DateTime.tryParse(deadline) == null) return null;
    return GemTask(
      id: id,
      title: j['title'] as String? ?? '',
      creatorId: (j['creatorId'] as num?)?.toInt() ?? 0,
      creatorName: j['creatorName'] as String? ?? '',
      assigneeId: (j['assigneeId'] as num?)?.toInt() ?? 0,
      assigneeName: j['assigneeName'] as String? ?? '',
      stake: stake,
      loseIfMissed: j['loseIfMissed'] as bool? ?? false,
      lost: (j['lost'] as num?)?.toInt() ?? 0,
      deadline: deadline,
      daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
      status: j['status'] as String? ?? TaskStatus.proposed,
    );
  }

  final int id;
  final String title;
  final int creatorId;
  final String creatorName;
  final int assigneeId;
  final String assigneeName;
  final int stake;

  /// The assignee chose to lose the gems if the deadline passes; a miss never takes more than
  /// they held, and [lost] is what it did take.
  final bool loseIfMissed;
  final int lost;

  /// The last day it counts, as YYYY-MM-DD.
  final String deadline;
  final int daysLeft;
  final String status;

  bool get proposed => status == TaskStatus.proposed;
  bool get declined => status == TaskStatus.declined;
  bool get agreed => status == TaskStatus.agreed;
  bool get done => status == TaskStatus.done;
  bool get missed => status == TaskStatus.missed;
  bool get overdue => daysLeft < 0;

  bool createdBy(int? userId) => userId != null && creatorId == userId;
  bool assignedTo(int? userId) => userId != null && assigneeId == userId;
}

/// Open tasks of both people, the newest finished ones, and the balances they move.
class TaskList {
  const TaskList({
    this.open = const [],
    this.history = const [],
    this.bank = 0,
    this.balances = const [],
  });

  factory TaskList.fromJson(Map<String, dynamic> j) => TaskList(
    open: [
      if (j['tasks'] is List)
        for (final item in j['tasks'] as List) ?GemTask.tryParse(item),
    ],
    history: [
      if (j['history'] is List)
        for (final item in j['history'] as List) ?GemTask.tryParse(item),
    ],
    bank: (j['bank'] as num?)?.toInt() ?? 0,
    balances: [
      if (j['balances'] is List)
        for (final item in j['balances'] as List) ?GemBalance.tryParse(item),
    ],
  );

  final List<GemTask> open;
  final List<GemTask> history;
  final int bank;
  final List<GemBalance> balances;

  /// Agreed tasks, soonest deadline first.
  List<GemTask> get live => [
    for (final t in open)
      if (t.agreed) t,
  ];

  /// Proposals my partner made that wait for my answer.
  List<GemTask> proposalsFor(int? userId) => [
    for (final t in open)
      if (t.proposed && !t.createdBy(userId)) t,
  ];

  /// What I proposed that is still unanswered or was declined.
  List<GemTask> mineOpen(int? userId) => [
    for (final t in open)
      if ((t.proposed || t.declined) && t.createdBy(userId)) t,
  ];
}
