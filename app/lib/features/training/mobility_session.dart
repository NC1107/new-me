import '../../api/models.dart';
import 'guided_session.dart';

/// Mobility 10, in New Me's own order: floor work first, then lying, then standing. The order is
/// not from a trial, and the page says so. A key the server does not know is skipped.
const kMobilitySequence = [
  'cat_stretch',
  'childs_pose',
  'kneeling_hip_flexor_stretch',
  'seated_hamstring_stretch',
  'figure_four_stretch',
  'knee_across_body_stretch',
  'standing_calf_stretch',
  'standing_trunk_twist',
  'cross_body_shoulder_stretch',
  'triceps_stretch',
];

/// 60 seconds per stretch (Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334),
/// done as two holds. A stretch done on each side takes one hold per side.
const kMobilityHoldSeconds = 30;

const kMobilityCitation =
    'Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334: 60 seconds per '
    'stretch, at least 2 days a week.';

const kMobilityOrderNote = 'The order is New Me\'s own, not from a trial.';

/// The holds of Mobility 10 in order, for the stretches the catalog has.
List<GuidedHold> buildMobilityHolds(ExerciseCatalog catalog) {
  final stretches = [
    for (final key in kMobilitySequence)
      if (catalog.byKey(key) case final e? when e.stretch) e,
  ];
  return [
    for (final (i, e) in stretches.indexed) ...[
      GuidedHold(
        exercise: e,
        stepIndex: i,
        label: e.perSide ? 'Left side' : 'Hold 1 of 2',
        firstOfStep: true,
        seconds: kMobilityHoldSeconds,
      ),
      GuidedHold(
        exercise: e,
        stepIndex: i,
        label: e.perSide ? 'Right side' : 'Hold 2 of 2',
        firstOfStep: false,
        seconds: kMobilityHoldSeconds,
      ),
    ],
  ];
}
