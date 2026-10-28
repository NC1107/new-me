import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/zone_time.dart';
import '../../widgets/app_card.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/quest_copy.dart';
import 'insights_logic.dart';
import 'insights_widgets.dart';
import 'workout_types.dart';
import '../../widgets/units_scope.dart';

Future<void> showWorkoutSheet(BuildContext context, {required Workout workout, String? zone}) =>
    showAppSheet<void>(
      context,
      builder: (_) => WorkoutSheet(workout: workout, zone: zone),
    );

/// One workout in full: when it happened, how long, and whatever Health recorded with it.
class WorkoutSheet extends StatelessWidget {
  const WorkoutSheet({super.key, required this.workout, this.zone});

  final Workout workout;

  /// The person's zone, so the start and end read the way they lived the day.
  final String? zone;

  @override
  Widget build(BuildContext context) {
    final w = workout;
    final palette = questPalette('exercise');
    final start = inZone(w.startedAt, zone);
    final end = inZone(w.endedAt, zone);
    final tiles = [
      (Icons.timer_rounded, 'Duration', durationLabel(w.durationMin)),
      if (w.kcal != null)
        (Icons.local_fire_department_rounded, 'Energy', '${w.kcal!.formatted} kcal'),
      if (w.distanceM != null && w.distanceM! > 0)
        (Icons.straighten_rounded, 'Distance', distanceLabel(w.distanceM!, context.units)),
      if (w.avgHr != null) (Icons.favorite_rounded, 'Avg heart rate', '${w.avgHr} bpm'),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: workoutTypeIcon(w.type), palette: palette, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(workoutTypeName(w.type), style: AppText.title),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${DateFormat.MMMEd().format(start)}, ${timeLabel(start)} to ${timeLabel(end)}',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 16),
            for (final (i, t) in tiles.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _Fact(icon: t.$1, label: t.$2, value: t.$3),
            ],
            if (tiles.length == 1) ...[
              const SizedBox(height: 12),
              Text(
                'Apple Health did not record energy, distance or heart rate for this one.',
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label $value',
    excludeSemantics: true,
    child: AppCard(
      color: kSunken,
      borderColor: kSunken,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: kInkSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: AppText.label.copyWith(color: kInkSecondary)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppText.tabular(AppText.headline.copyWith(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    ),
  );
}
