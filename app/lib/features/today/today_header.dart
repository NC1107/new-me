import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/mascot.dart';
import '../../widgets/speech_bubble.dart';

String greetingFor(DateTime now, String name) {
  final part = now.hour < 12
      ? 'Good morning'
      : now.hour < 18
      ? 'Good afternoon'
      : 'Good evening';
  return name.trim().isEmpty ? part : '$part, ${name.trim()}';
}

int questsToGo(Today t) => t.quests.where((q) => !q.done).length;

/// One short, encouraging line for the mascot that matches where the day stands.
String mascotLine(Today t) {
  if (t.day.counted) return 'Streak saved for today!';
  final left = questsToGo(t);
  if (left == 0 && t.quests.isNotEmpty) return 'Every quest done. Amazing!';
  if (t.day.points == 0 && t.streak.restAvailable && t.streak.restUsedOn == null) {
    return 'Rest day available';
  }
  return left == 1 ? '1 quest to go' : '$left quests to go';
}

MascotState mascotStateFor(Today t) => t.day.counted ? MascotState.happy : MascotState.idle;

/// The greeting, the date, and the mascot with what it has to say about the day.
class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key, required this.today, required this.name, required this.now});

  final Today today;
  final String name;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(greetingFor(now, name), style: AppText.title)),
        const SizedBox(height: 2),
        Text(
          DateFormat('EEEE, MMM d').format(parseLocalDate(today.localToday)),
          style: AppText.caption,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 84, height: 84, child: Mascot(size: 84, state: mascotStateFor(today))),
            const SizedBox(width: 2),
            Expanded(child: SpeechBubble(text: mascotLine(today))),
          ],
        ),
      ],
    );
  }
}
