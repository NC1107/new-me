import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../insights/insights_logic.dart';
import '../streaks/streak_visuals.dart';

Future<void> showPersonSheet(
  BuildContext context, {
  required BoardUser user,
  required DateTime now,
}) => showAppSheet<void>(
  context,
  builder: (_) => PersonSheet(user: user, now: now),
);

/// The detail behind a person card: week, workouts, season, freezes and when health last synced.
class PersonSheet extends StatelessWidget {
  const PersonSheet({super.key, required this.user, required this.now});

  final BoardUser user;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final held = user.freezes.held;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: user.name, palette: accentById(user.color), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(header: true, child: Text(user.name, style: AppText.title)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Row(label: 'Week', value: '${user.week.formatted} points'),
          if (user.workoutsThisWeek case final n?)
            _Row(
              label: 'Workouts',
              value: workoutCountLabel(n),
              semantics: '${workoutCountLabel(n)} this week',
            ),
          _Row(label: 'Season', value: '${user.season.formatted} points'),
          _Row(
            label: 'Freezes',
            value: '$held',
            leading: FreezeFlakes(held: held, size: 18),
            semantics: freezesLabel(held),
          ),
          _Row(
            label: 'Health',
            value: user.syncedAt == null
                ? 'Not synced'
                : 'Synced ${relativeTime(user.syncedAt!, now)}',
          ),
          const SizedBox(height: 18),
          ChunkyButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.leading, this.semantics});

  final String label;
  final String value;
  final Widget? leading;
  final String? semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semantics ?? '$label, $value',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder, width: 2)),
      ),
      child: Row(
        children: [
          Text(label, style: AppText.label.copyWith(color: kInkSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
