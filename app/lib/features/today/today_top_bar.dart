import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/pressable.dart';

/// Dark enough to read on the canvas; the flame fill itself is too light for text.
const _kFlameText = Color(0xFFB45309);

String greetingFor(DateTime now, String name) {
  final part = now.hour < 12
      ? 'Good morning'
      : now.hour < 18
      ? 'Good afternoon'
      : 'Good evening';
  return name.trim().isEmpty ? part : '$part, ${name.trim()}';
}

/// The one row above the day: the greeting and date, and the streak (opens the streak sheet).
class TodayTopBar extends StatelessWidget {
  const TodayTopBar({
    super.key,
    required this.name,
    required this.now,
    required this.localToday,
    required this.streak,
    required this.onStreak,
  });

  final String name;
  final DateTime now;
  final String localToday;
  final int streak;
  final VoidCallback onStreak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                container: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(greetingFor(now, name), maxLines: 1, style: AppText.title),
                ),
              ),
              const SizedBox(height: 2),
              Text(dayLong(localToday), style: AppText.caption),
            ],
          ),
        ),
        const SizedBox(width: 8),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: _Stat(
            icon: Icons.local_fire_department_rounded,
            iconColor: kFlame,
            textColor: _kFlameText,
            value: streak.formatted,
            label: 'Your streak, $streak day streak',
            onTap: onStreak,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 26, color: iconColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.tabular(
                AppText.headline.copyWith(color: textColor, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: onTap == null ? content : Pressable(onTap: onTap, child: content),
    );
  }
}
