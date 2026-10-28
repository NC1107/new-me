import '../../api/models.dart';
import 'guided_page.dart';
import 'guided_session.dart';

/// One pose of a flow: which pose, how long each hold lasts and how many holds it gets.
class FlowStep {
  const FlowStep(this.key, {this.seconds = kYogaHoldSeconds, this.rounds = 1, this.label});

  final String key;
  final int seconds;

  /// Holds in a row of the same pose (and side), so a stretch can reach 60 seconds in total.
  final int rounds;

  /// Overrides the default "Hold" for a pose that is moved or rested in.
  final String? label;
}

/// 30 seconds is the top of ACSM's 10 to 30 second range for one static hold, and two of them
/// make the 60 seconds per stretch ACSM recommends in total (Garber et al., Med Sci Sports Exerc
/// 2011;43:1334). Yoga teaching commonly holds a pose for 3 to 5 breaths; 5 slow breaths of about
/// 6 seconds each is the same 30 seconds. That breath pace is New Me's choice, not a trial result.
const kYogaHoldSeconds = 30;

/// The sequences, from warm-up to cool-down, are New Me's own and not from a trial.
const kYogaOrderNote = 'The order is New Me\'s own, not from a trial.';

const kYogaCitation =
    'Holds follow ACSM (Garber et al., Med Sci Sports Exerc 2011;43:1334): 30 seconds a hold, '
    '60 seconds per stretch, at least 2 to 3 days a week.';

const kYogaSafety =
    'Move to a mild stretch, never pain. NCCIH: yoga is generally safe for healthy people, and '
    'injuries are mostly sprains and strains. Skip any pose that hurts.';

/// A flow of about [minutes] minutes, built from the pose library.
class YogaFlow {
  const YogaFlow({
    required this.minutes,
    required this.name,
    required this.blurb,
    required this.steps,
  });

  final int minutes;
  final String name;
  final String blurb;
  final List<FlowStep> steps;

  String get title => 'Yoga $minutes';
}

const _gentle = YogaFlow(
  minutes: 10,
  name: 'Yoga 10',
  blurb: 'A short flow to loosen up: standing, floor and a minute of rest.',
  steps: [
    FlowStep('yoga_easy'),
    FlowStep('yoga_cat_cow', label: 'Move with your breath'),
    FlowStep('yoga_downward_dog'),
    FlowStep('yoga_low_lunge'),
    FlowStep('yoga_standing_forward_fold'),
    FlowStep('yoga_mountain'),
    FlowStep('yoga_chair'),
    FlowStep('yoga_warrior_ii'),
    FlowStep('yoga_tree'),
    FlowStep('yoga_cobra'),
    FlowStep('yoga_childs'),
    FlowStep('yoga_bridge'),
    FlowStep('yoga_happy_baby'),
    FlowStep('yoga_corpse', seconds: 60, label: 'Rest'),
  ],
);

const _steady = YogaFlow(
  minutes: 20,
  name: 'Yoga 20',
  blurb: 'Adds the warriors, a side stretch and seated folds, with longer holds in the stretches.',
  steps: [
    FlowStep('yoga_easy'),
    FlowStep('yoga_cat_cow', label: 'Move with your breath'),
    FlowStep('yoga_childs'),
    FlowStep('yoga_downward_dog'),
    FlowStep('yoga_low_lunge', rounds: 2),
    FlowStep('yoga_standing_forward_fold'),
    FlowStep('yoga_mountain'),
    FlowStep('yoga_chair'),
    FlowStep('yoga_warrior_i'),
    FlowStep('yoga_warrior_ii'),
    FlowStep('yoga_side_angle'),
    FlowStep('yoga_triangle'),
    FlowStep('yoga_tree'),
    FlowStep('yoga_sphinx'),
    FlowStep('yoga_cobra'),
    FlowStep('yoga_childs'),
    FlowStep('yoga_bridge'),
    FlowStep('yoga_happy_baby'),
    FlowStep('yoga_knees_to_chest'),
    FlowStep('yoga_seated_forward_fold', rounds: 2),
    FlowStep('yoga_butterfly'),
    FlowStep('yoga_seated_twist'),
    FlowStep('yoga_corpse', seconds: 120, label: 'Rest'),
  ],
);

const _long = YogaFlow(
  minutes: 30,
  name: 'Yoga 30',
  blurb: 'The full library: strong standing work, a long floor stretch and a few minutes of rest.',
  steps: [
    FlowStep('yoga_easy'),
    FlowStep('yoga_cat_cow', label: 'Move with your breath'),
    FlowStep('yoga_childs'),
    FlowStep('yoga_downward_dog', rounds: 2),
    FlowStep('yoga_low_lunge', rounds: 2),
    FlowStep('yoga_standing_forward_fold', rounds: 2),
    FlowStep('yoga_mountain'),
    FlowStep('yoga_chair'),
    FlowStep('yoga_warrior_i'),
    FlowStep('yoga_warrior_ii'),
    FlowStep('yoga_side_angle', rounds: 2),
    FlowStep('yoga_triangle', rounds: 2),
    FlowStep('yoga_tree'),
    FlowStep('yoga_locust'),
    FlowStep('yoga_sphinx'),
    FlowStep('yoga_cobra'),
    FlowStep('yoga_childs'),
    FlowStep('yoga_staff'),
    FlowStep('yoga_seated_forward_fold', rounds: 2),
    FlowStep('yoga_butterfly', rounds: 2),
    FlowStep('yoga_seated_twist', rounds: 2),
    FlowStep('yoga_bridge', rounds: 2),
    FlowStep('yoga_happy_baby', rounds: 2),
    FlowStep('yoga_knees_to_chest'),
    FlowStep('yoga_legs_up_wall', seconds: 90, label: 'Rest'),
    FlowStep('yoga_corpse', seconds: 180, label: 'Rest'),
  ],
);

const kYogaFlows = [_gentle, _steady, _long];

YogaFlow? yogaFlowOf(int minutes) {
  for (final f in kYogaFlows) {
    if (f.minutes == minutes) return f;
  }
  return null;
}

/// The holds of [flow] in order, for the poses the catalog has. A pose done on each side runs
/// left then right, and a repeated hold stays on the same side.
List<GuidedHold> buildYogaHolds(YogaFlow flow, ExerciseCatalog catalog) {
  final poses = [
    for (final s in flow.steps)
      if (catalog.byKey(s.key) case final e? when e.yoga) (s, e),
  ];
  final holds = <GuidedHold>[];
  for (final (i, (step, e)) in poses.indexed) {
    final sides = e.perSide ? ['Left side', 'Right side'] : [''];
    for (final side in sides) {
      for (var r = 0; r < step.rounds; r++) {
        final repeat = 'hold ${r + 1} of ${step.rounds}';
        final label = side.isEmpty
            ? (step.rounds > 1 ? 'Hold ${r + 1} of ${step.rounds}' : step.label ?? 'Hold')
            : (step.rounds > 1 ? '$side, $repeat' : side);
        holds.add(
          GuidedHold(
            exercise: e,
            stepIndex: i,
            label: label,
            firstOfStep: holds.isEmpty || holds.last.stepIndex != i,
            seconds: step.seconds,
          ),
        );
      }
    }
  }
  return holds;
}

GuidedRoutine yogaRoutine(YogaFlow flow) => GuidedRoutine(
  title: flow.title,
  stepNoun: 'pose',
  stepNounPlural: 'poses',
  activity: 'yoga',
  doneNoun: 'yoga',
  fallbackIntro: 'A guided yoga flow, one pose at a time.',
  introFor: (steps, minutes) => '$steps poses, about $minutes minutes, timed for you.',
  notes: const [kYogaOrderNote, kYogaCitation],
  emptyCopy: 'This server has no yoga poses yet. Update the server to use yoga.',
  footnote: kYogaSafety,
  build: (catalog) => buildYogaHolds(flow, catalog),
);
