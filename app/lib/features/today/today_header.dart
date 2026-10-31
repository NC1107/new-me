import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable.dart';
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
    return 'A freeze is ready';
  }
  return t.day.points == 0 ? 'A fresh day. Start with one.' : 'Nice, keep it rolling.';
}

MascotState mascotStateFor(Today t) => t.day.counted ? MascotState.happy : MascotState.idle;

/// What the mascot says. The plan's full summary lives in the plan sheet, so the bubble stays one
/// short line that never restates quest progress.
String bubbleLine(Today t) => mascotLine(t);

/// The greeting, the date, and the mascot whose bubble carries one short line. With a plan
/// the bubble is a button that opens it.
class TodayHeader extends StatelessWidget {
  const TodayHeader({
    super.key,
    required this.today,
    required this.name,
    required this.now,
    this.onPlan,
    this.onCoach,
  });

  final Today today;
  final String name;
  final DateTime now;

  /// Opens the plan; null leaves the bubble as plain text.
  final VoidCallback? onPlan;

  /// Opens the coach chat; null hides the button, as when the server has no Claude key.
  final VoidCallback? onCoach;

  @override
  Widget build(BuildContext context) {
    final coach = onCoach;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    container: true,
                    child: Text(greetingFor(now, name), style: AppText.title),
                  ),
                  const SizedBox(height: 2),
                  Text(dayLong(today.localToday), style: AppText.caption),
                ],
              ),
            ),
            if (coach != null) _CoachButton(onTap: coach),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 84, height: 84, child: Mascot(size: 84, state: mascotStateFor(today))),
            const SizedBox(width: 2),
            Expanded(child: _bubble(context)),
          ],
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context) {
    final open = onPlan;
    final bubble = SpeechBubble(
      text: bubbleLine(today),
      footer: open == null
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      "See today's plan",
                      style: AppText.label.copyWith(color: context.accentText),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: context.accentText),
                ],
              ),
            ),
    );
    if (open == null) return bubble;
    return Semantics(
      container: true,
      button: true,
      label: "${bubbleLine(today)} Open today's plan",
      excludeSemantics: true,
      onTap: open,
      child: Pressable(onTap: open, scale: 0.99, child: bubble),
    );
  }
}

/// A round button beside the greeting that opens the coach chat.
class _CoachButton extends StatelessWidget {
  const _CoachButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      container: true,
      button: true,
      label: 'Ask your coach',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.chat_bubble_rounded, size: 20, color: palette.lip),
            ),
          ),
        ),
      ),
    );
  }
}
