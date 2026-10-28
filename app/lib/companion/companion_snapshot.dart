import 'dart:ui';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/session.dart';
import '../theme/accent.dart';

/// The Swift side (`CompanionSnapshot.swift`) ignores any other version, so a breaking change to
/// this shape bumps it on both sides together.
const kCompanionSnapshotVersion = 1;

/// What the widgets and the Watch show and need: today's score, quests and due habits, plus the
/// session so a widget button or a Watch tap can mark a habit without the app running.
Json companionSnapshot({
  required Session session,
  required Today today,
  String appKey = kAppKey,
  String clientVersion = kClientVersion,
}) {
  final accent = accentById(session.color);
  return {
    'version': kCompanionSnapshotVersion,
    'date': today.localToday,
    'name': session.userName,
    'accent': {'fill': _hex(accent.fill), 'tint': _hex(accent.tint)},
    'points': today.day.points,
    'percent': today.day.goalPercent,
    'streakLine': 100,
    'counted': today.day.counted,
    'streak': today.streak.current,
    'quests': [
      for (final q in today.quests) {'key': q.key, 'title': q.title, 'done': q.done},
    ],
    // One entry per tappable thing: each slot of a check habit, or a count habit as a whole.
    'habits': [
      for (final h in today.habits)
        if (h.isCount)
          {
            'habitId': h.id,
            'slot': null,
            'name': h.name,
            'label': '',
            'icon': h.icon,
            'done': h.countDone,
            'count': h.count,
            'target': h.target,
            'time': null,
          }
        else
          for (final s in h.slots)
            {
              'habitId': h.id,
              'slot': s.index,
              'name': h.name,
              'label': s.label,
              'icon': h.icon,
              'done': s.done,
              'count': 0,
              'target': null,
              'time': s.time,
            },
    ],
    'session': {
      'baseUrl': session.baseUrl,
      'token': session.token,
      'appKey': appKey,
      'clientVersion': clientVersion,
    },
  };
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
