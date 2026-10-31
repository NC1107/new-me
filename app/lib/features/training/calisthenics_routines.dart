import 'dart:math' as math;

import '../../api/models.dart';
import 'calisthenics_voice.dart';
import 'guided_page.dart';
import 'guided_session.dart';

/// A step of a calisthenics routine: a catalog exercise done for [reps] at the person's own pace
/// or held for [seconds]. [sides] doubles a strength step into a left and a right turn; a
/// stretch takes its sides from the catalog. A step that is [sized] gets its reps from the
/// person's own max when they have one.
class CalStep {
  const CalStep.reps(this.key, int this.reps, {this.sides = false, this.sized = true})
    : seconds = null;
  const CalStep.hold(this.key, int this.seconds, {this.sides = false}) : reps = null, sized = false;

  final String key;
  final int? reps;
  final int? seconds;
  final bool sides;
  final bool sized;
}

/// One fixed routine: a warm-up, circuit rounds with rests, and a cool-down.
class CalLevel {
  const CalLevel({
    required this.id,
    required this.name,
    required this.blurb,
    required this.maxFraction,
    required this.rounds,
    required this.restBetween,
    required this.restRound,
    required this.warmup,
    required this.circuit,
    required this.cooldown,
  });

  final String id;
  final String name;
  final String blurb;

  /// The share of the person's max that a sized rep step asks for.
  final double maxFraction;
  final int rounds;

  /// Rest between two exercises of a round, and between two rounds, in seconds.
  final int restBetween;
  final int restRound;
  final List<CalStep> warmup;
  final List<CalStep> circuit;
  final List<CalStep> cooldown;

  String get title => 'Calisthenics: $name';
  int get maxPercent => (maxFraction * 100).round();
}

/// A rep takes about this long, counting the pause between reps. It only sizes the progress bar
/// and the minutes on the intro, because the person sets the pace. The figure is New Me's
/// estimate, not a published tempo.
const kCalSecondsPerRep = 3;

/// The fewest reps a max-based step can ask for.
const kCalMinReps = 3;

/// A strength workout counts as the day's strength session from this many minutes, the same
/// threshold the server applies to workouts from Apple Health.
const kCalStrengthCreditMinutes = 20;

const _stretches = [
  CalStep.hold('childs_pose', 30),
  CalStep.hold('kneeling_hip_flexor_stretch', 30),
  CalStep.hold('seated_hamstring_stretch', 30),
  CalStep.hold('cross_body_shoulder_stretch', 30),
];

const _beginner = CalLevel(
  id: 'beginner',
  name: 'Beginner',
  blurb: 'Knee push-ups, squats, bridges and a short plank. Easy rests.',
  maxFraction: 0.5,
  rounds: 3,
  restBetween: 30,
  restRound: 60,
  warmup: [
    CalStep.hold('jumping_jack', 30),
    CalStep.hold('cat_stretch', 30),
    CalStep.reps('air_squat', 8, sized: false),
  ],
  circuit: [
    CalStep.reps('knee_push_up', 8),
    CalStep.reps('air_squat', 10),
    CalStep.reps('glute_bridge', 12),
    CalStep.hold('plank', 20),
    CalStep.reps('crunch', 10),
  ],
  cooldown: _stretches,
);

const _intermediate = CalLevel(
  id: 'intermediate',
  name: 'Intermediate',
  blurb: 'Full push-ups, lunges and mountain climbers.',
  maxFraction: 0.6,
  rounds: 3,
  restBetween: 30,
  restRound: 60,
  warmup: [
    CalStep.hold('jumping_jack', 45),
    CalStep.hold('cat_stretch', 30),
    CalStep.reps('air_squat', 10, sized: false),
    CalStep.reps('knee_push_up', 6, sized: false),
  ],
  circuit: [
    CalStep.reps('push_up', 10),
    CalStep.reps('air_squat', 15),
    CalStep.reps('lunge', 8, sides: true),
    CalStep.hold('plank', 30),
    CalStep.hold('mountain_climber', 30),
  ],
  cooldown: _stretches,
);

const _advanced = CalLevel(
  id: 'advanced',
  name: 'Advanced',
  blurb: 'Split squats, pike push-ups, wall sits and hollow holds.',
  maxFraction: 0.7,
  rounds: 4,
  restBetween: 30,
  restRound: 60,
  warmup: [
    CalStep.hold('jumping_jack', 60),
    CalStep.hold('cat_stretch', 30),
    CalStep.reps('air_squat', 10, sized: false),
    CalStep.reps('push_up', 8, sized: false),
  ],
  circuit: [
    CalStep.reps('push_up', 15),
    CalStep.reps('split_squat', 10, sides: true),
    CalStep.reps('pike_push_up', 8),
    CalStep.hold('wall_sit', 45),
    CalStep.hold('hollow_hold', 30),
    CalStep.hold('mountain_climber', 40),
  ],
  cooldown: _stretches,
);

const _intense = CalLevel(
  id: 'intense',
  name: 'Intense',
  blurb: 'Burpees, decline push-ups and jump squats with short rests.',
  maxFraction: 0.75,
  rounds: 4,
  restBetween: 20,
  restRound: 60,
  warmup: [
    CalStep.hold('jumping_jack', 60),
    CalStep.hold('cat_stretch', 30),
    CalStep.reps('air_squat', 10, sized: false),
    CalStep.reps('push_up', 8, sized: false),
    CalStep.reps('burpee', 5, sized: false),
  ],
  circuit: [
    CalStep.reps('burpee', 10),
    CalStep.reps('decline_push_up', 12),
    CalStep.reps('jump_squat', 15),
    CalStep.hold('mountain_climber', 40),
    CalStep.reps('pike_push_up', 10),
    CalStep.hold('hollow_hold', 40),
    CalStep.hold('side_plank', 30, sides: true),
  ],
  cooldown: _stretches,
);

const kCalLevels = [_beginner, _intermediate, _advanced, _intense];

CalLevel? calLevelOf(String id) {
  for (final l in kCalLevels) {
    if (l.id == id) return l;
  }
  return null;
}

/// The reps a sized step asks for: [maxFraction] of the person's max for that exercise, at least
/// [kCalMinReps], or the level's own number when they have no max.
int calRepsFor(CalStep step, {required double maxFraction, int? max}) {
  final base = step.reps ?? 0;
  if (!step.sized || max == null || max < 1) return base;
  return math.max(kCalMinReps, (max * maxFraction).round());
}

/// Every key the routine of [level] can use, for tests and for the voice script.
Set<String> calKeysOf(CalLevel level) => {
  for (final s in [...level.warmup, ...level.circuit, ...level.cooldown]) s.key,
};

const kCalOrderNote = 'The exercises and their order are New Me\'s own, not from a trial.';

const kCalCitation =
    'Frequency and reps follow ACSM: 2 to 3 days a week (Garber et al., Med Sci Sports Exerc '
    '2011;43:1334) and about 8 to 12 reps for beginners (ACSM position stand, Med Sci Sports Exerc '
    '2009;41:687).';

const kCalIntervalNote =
    'Intense uses the 2 to 1 work to rest ratio of Tabata et al. (Med Sci Sports Exerc '
    '1996;28:1327), tested on a bike. The seconds are New Me\'s own.';

const kCalSizingNote =
    'Where you have tested a max, reps are 50 to 75 percent of it by level, as for your daily '
    'reps.';

const kCalSafety =
    'Move with control and stop for sharp pain, dizziness or chest pain. Check with your clinician '
    'first if you have a heart or joint condition. Finishing 20 minutes or more counts as a '
    'strength session; every minute counts as exercise.';

/// The holds of [level] in order, for the exercises the catalog has. Rep steps use the person's
/// max for the exercise when the catalog carries one. A rest leads to the exercise after it.
List<GuidedHold> buildCalisthenicsHolds(CalLevel level, ExerciseCatalog catalog) {
  final plan = <_Planned>[
    for (final (i, s) in level.warmup.indexed)
      _Planned(s, 'Warm-up', 0, i == level.warmup.length - 1 ? level.restBetween : 0),
    for (var r = 1; r <= level.rounds; r++)
      for (final (i, s) in level.circuit.indexed)
        _Planned(
          s,
          'Circuit',
          r,
          i < level.circuit.length - 1
              ? level.restBetween
              : (r < level.rounds ? level.restRound : level.restBetween),
        ),
    for (final s in level.cooldown) _Planned(s, 'Cool-down', 0, 0),
  ].where((p) => catalog.byKey(p.step.key) != null).toList();

  final holds = <GuidedHold>[];
  for (final (step, p) in plan.indexed) {
    final s = p.step;
    final e = catalog.byKey(s.key)!;
    final reps = calRepsFor(s, maxFraction: level.maxFraction, max: e.maxTest?.reps);
    final inRound = p.round > 0;
    for (final side in s.sides || e.perSide ? ['Left side', 'Right side'] : ['']) {
      final where = inRound ? 'Round ${p.round} of ${level.rounds}' : p.section;
      holds.add(
        GuidedHold(
          exercise: e,
          stepIndex: step,
          label: side.isEmpty ? where : (inRound ? '$side, ${where.toLowerCase()}' : side),
          firstOfStep: side != 'Right side',
          seconds: s.reps != null ? reps * kCalSecondsPerRep : s.seconds!,
          kind: s.reps != null ? GuidedKind.reps : GuidedKind.timed,
          reps: reps,
          round: p.round,
          rounds: inRound ? level.rounds : 0,
          section: p.section,
        ),
      );
    }
    final following = step + 1 < plan.length ? plan[step + 1] : null;
    if (p.restAfter > 0 && following != null) {
      holds.add(
        GuidedHold(
          exercise: catalog.byKey(following.step.key)!,
          stepIndex: step,
          label: 'Rest',
          firstOfStep: false,
          seconds: p.restAfter,
          kind: GuidedKind.rest,
          round: following.round,
          rounds: following.round > 0 ? level.rounds : 0,
          section: p.section,
        ),
      );
    }
  }
  return holds;
}

class _Planned {
  const _Planned(this.step, this.section, this.round, this.restAfter);

  final CalStep step;
  final String section;
  final int round;
  final int restAfter;
}

/// Minutes the routine takes at the estimated pace, for the level cards.
int calMinutes(List<GuidedHold> holds) => (guidedTotalSeconds(holds) / 60).round();

/// The rows of the intro: one section per part, one row per exercise, the circuit once.
List<GuidedOutlineSection> calOutline(List<GuidedHold> holds) {
  final sections = <GuidedOutlineSection>[];
  for (final h in holds) {
    if (h.isRest || !h.firstOfStep || h.round > 1) continue;
    final heading = h.round == 1 ? 'Circuit, ${h.rounds} rounds' : h.section;
    if (sections.isEmpty || sections.last.heading != heading) {
      sections.add(GuidedOutlineSection(heading, []));
    }
    final eachSide = holds.any((o) => o.stepIndex == h.stepIndex && o.label.startsWith('Right'));
    final amount = h.isReps ? '${h.reps} reps' : '${h.seconds} sec';
    sections.last.rows.add(
      GuidedOutlineRow(h.exercise.name, eachSide ? '$amount each side' : amount),
    );
  }
  return sections;
}

GuidedRoutine calisthenicsRoutine(CalLevel level) => GuidedRoutine(
  title: 'Calisthenics',
  stepNoun: 'exercise',
  stepNounPlural: 'exercises',
  activity: 'calisthenics',
  doneNoun: 'calisthenics',
  fallbackIntro: 'Guided bodyweight work, one exercise at a time.',
  introFor: (steps, minutes) =>
      'About $minutes minutes: a warm-up, ${level.rounds} circuit rounds and a cool-down. Rep '
      'exercises are at your own pace, so tap Done when you finish.',
  notes: const [kCalOrderNote, kCalCitation],
  emptyCopy: 'This server has no calisthenics exercises yet. Update the server to use it.',
  footnote: '$kCalIntervalNote $kCalSizingNote $kCalSafety',
  build: (catalog) => buildCalisthenicsHolds(level, catalog),
  outline: calOutline,
  voice: const CalisthenicsVoice(),
  activityType: 'calisthenics',
  loggedTo: 'your exercise minutes',
  logsReps: true,
  strengthCreditMinutes: kCalStrengthCreditMinutes,
  subtitleLead: '${level.name}, ',
  voiceCountdown: true,
);
