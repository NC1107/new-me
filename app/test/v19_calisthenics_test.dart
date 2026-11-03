import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/audio/voice_clips.dart';
import 'package:newme/features/training/calisthenics_page.dart';
import 'package:newme/features/training/calisthenics_routines.dart';
import 'package:newme/features/training/calisthenics_voice.dart';
import 'package:newme/features/training/guided_page.dart';
import 'package:newme/features/training/guided_session.dart';
import 'package:newme/features/training/set_assist.dart' show kHoldLeadInSeconds;
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _stretchKeys = {
  'cat_stretch',
  'childs_pose',
  'kneeling_hip_flexor_stretch',
  'seated_hamstring_stretch',
  'cross_body_shoulder_stretch',
};
const _sidedStretches = {
  'kneeling_hip_flexor_stretch',
  'seated_hamstring_stretch',
  'cross_body_shoulder_stretch',
};

/// A catalog with every exercise the four levels use, as the migration would seed it.
ExerciseCatalog _catalog({Map<String, int> maxes = const {}, Set<String> without = const {}}) {
  final keys = {for (final l in kCalLevels) ...calKeysOf(l)}.difference(without);
  return ExerciseCatalog(
    exercises: [
      for (final key in keys)
        Exercise(
          key: key,
          name: key.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' '),
          steps: const ['Get into position.'],
          cues: const ['Stay controlled.'],
          kind: _stretchKeys.contains(key) ? ExerciseKind.stretch : ExerciseKind.strength,
          perSide: _sidedStretches.contains(key),
          maxTest: maxes[key] == null ? null : SetAmount(date: '2026-10-01', reps: maxes[key]),
        ),
    ],
  );
}

List<GuidedHold> _holds(CalLevel level, [ExerciseCatalog? catalog]) =>
    buildCalisthenicsHolds(level, catalog ?? _catalog());

GuidedController _controller(List<GuidedHold> holds) => GuidedController(holds);

void _tick(GuidedController c, int n) {
  for (var i = 0; i < n; i++) {
    c.tick();
  }
}

/// Runs the controller to the start of the first rep hold's work phase.
GuidedController _atFirstReps(List<GuidedHold> holds) {
  final c = _controller(holds);
  while (!c.current.isReps) {
    c.skipStep();
  }
  _tick(c, kHoldLeadInSeconds);
  return c;
}

void main() {
  group('the session clock with rep steps', () {
    final holds = _holds(kCalLevels.first);

    test('a rep step waits for Done and does not count down', () {
      final c = _atFirstReps(holds);
      expect(c.phase, GuidedPhase.hold);
      expect(c.awaitingDone, isTrue);
      final index = c.index;
      _tick(c, 120);
      expect(c.index, index, reason: 'two minutes later it is still the same step');
      expect(c.holdElapsed, 120);
      expect(c.progress, lessThan(1));
    });

    test('Done moves on, and a rest with a countdown follows with no lead-in', () {
      final c = _atFirstReps(holds);
      expect(c.complete(), GuidedEvent.nextHold);
      expect(c.current.isRest, isTrue);
      expect(c.phase, GuidedPhase.hold, reason: 'a rest has no get-ready');
      final rest = c.current.seconds;
      _tick(c, rest - 1);
      expect(c.holdLeft, 1);
      expect(c.tick(), GuidedEvent.nextHold);
      expect(c.current.isRest, isFalse);
      expect(c.phase, GuidedPhase.leadIn, reason: 'the next exercise starts with the get-ready');
    });

    test('a timed step counts down, ticks the last three seconds and moves on', () {
      final c = _controller(holds);
      expect(c.current.isReps, isFalse);
      _tick(c, kHoldLeadInSeconds);
      expect(c.phase, GuidedPhase.hold);
      final events = <GuidedEvent?>[];
      for (var i = 0; i < c.current.seconds; i++) {
        events.add(c.tick());
      }
      expect(events.where((e) => e == GuidedEvent.countdown), hasLength(3));
      expect(events.last, GuidedEvent.nextHold);
    });

    test('Done does nothing during get-ready, on a timed step or while paused', () {
      final c = _controller(holds);
      expect(c.complete(), isNull);
      final r = _controller(holds);
      while (!r.current.isReps) {
        r.skipStep();
      }
      expect(r.complete(), isNull, reason: 'still in the get-ready');
      _tick(r, kHoldLeadInSeconds);
      r.pause();
      expect(r.complete(), isNull);
      expect(r.tick(), isNull);
      r.resume();
      expect(r.complete(), GuidedEvent.nextHold);
    });

    test('adjusted reps are what is recorded, defaulting to the target', () {
      final c = _atFirstReps(holds);
      final key = c.current.exercise.key;
      final target = c.current.reps;
      expect(c.currentReps, target);
      c.adjustReps(-2);
      c.adjustReps(1);
      expect(c.currentReps, target - 1);
      c.complete();
      expect(c.repsDone, {key: target - 1});
    });

    test('reps stay between 1 and the maximum', () {
      final c = _atFirstReps(holds);
      c.adjustReps(-1000);
      expect(c.currentReps, 1);
      c.adjustReps(5000);
      expect(c.currentReps, GuidedController.maxReps);
    });

    test('a skipped rep step records nothing and the finished one is kept', () {
      final c = _atFirstReps(holds);
      final first = c.current;
      c.complete();
      c.skipStep();
      expect(c.current.isReps, isTrue);
      _tick(c, kHoldLeadInSeconds);
      c.skipStep();
      expect(c.repsDone, {first.exercise.key: first.reps});
    });

    test('previous restarts the rep step and forgets its reps', () {
      final c = _atFirstReps(holds);
      c.adjustReps(3);
      c.complete();
      c.backStep();
      expect(c.current.isReps, isTrue);
      expect(c.phase, GuidedPhase.leadIn);
      expect(c.repsDone, isEmpty);
      expect(c.currentReps, c.current.reps, reason: 'the change was for the old attempt');
    });

    test('the last Done finishes the session', () {
      final c = _controller([holds.firstWhere((h) => h.isReps)]);
      _tick(c, kHoldLeadInSeconds);
      expect(c.complete(), GuidedEvent.finished);
      expect(c.finished, isTrue);
      expect(c.progress, 1);
    });

    test('minutes count the time waiting on reps', () {
      final c = _atFirstReps(holds);
      _tick(c, 90);
      expect(c.activeSeconds, kHoldLeadInSeconds + 90);
      expect(c.minutes, 2);
    });
  });

  group('the four levels', () {
    test('are beginner, intermediate, advanced and intense', () {
      expect(
        [for (final l in kCalLevels) l.name],
        ['Beginner', 'Intermediate', 'Advanced', 'Intense'],
      );
    });

    test('build a warm-up, circuit rounds with rests and a cool-down in order', () {
      for (final level in kCalLevels) {
        final holds = _holds(level);
        final sections = <String>[];
        for (final h in holds.where((h) => !h.isRest)) {
          if (sections.isEmpty || sections.last != h.section) sections.add(h.section);
        }
        expect(sections, ['Warm-up', 'Circuit', 'Cool-down'], reason: level.id);
        expect(holds.last.isRest, isFalse, reason: 'no rest after the very last hold');
        expect(holds.first.isRest, isFalse);
        final rounds = holds.where((h) => h.round > 0).map((h) => h.round).toSet();
        expect(rounds, {for (var r = 1; r <= level.rounds; r++) r}, reason: level.id);
        for (final h in holds.where((h) => h.isRest)) {
          expect(h.seconds, anyOf(level.restBetween, level.restRound), reason: level.id);
        }
      }
    });

    test('every rest leads to the exercise that follows it', () {
      final holds = _holds(kCalLevels[1]);
      for (final (i, h) in holds.indexed) {
        if (!h.isRest) continue;
        expect(h.exercise.key, holds[i + 1].exercise.key);
      }
    });

    test('a rest between rounds is longer than a rest between exercises', () {
      final holds = _holds(kCalLevels[1]);
      final roundRests = holds.where(
        (h) => h.isRest && h.round == 2 && holds[holds.indexOf(h) - 1].round == 1,
      );
      expect(roundRests, isNotEmpty);
      expect(roundRests.first.seconds, kCalLevels[1].restRound);
    });

    test('the first level is long enough to count as a strength session', () {
      final minutes = calMinutes(_holds(kCalLevels.first));
      expect(minutes, greaterThanOrEqualTo(kCalStrengthCreditMinutes));
    });

    test('levels get longer and harder', () {
      final minutes = [for (final l in kCalLevels) calMinutes(_holds(l))];
      for (var i = 1; i < minutes.length; i++) {
        expect(minutes[i], greaterThanOrEqualTo(minutes[i - 1]));
      }
      final shares = [for (final l in kCalLevels) l.maxFraction];
      expect(shares, [0.5, 0.6, 0.7, 0.75]);
    });

    test('a side-by-side exercise runs left then right, the second side not a new step', () {
      final holds = _holds(kCalLevels[1]);
      final lunges = holds.where((h) => !h.isRest && h.exercise.key == 'lunge').take(2).toList();
      expect(lunges.map((h) => h.label), ['Left side, round 1 of 3', 'Right side, round 1 of 3']);
      expect(lunges[0].stepIndex, lunges[1].stepIndex);
      expect(lunges[0].firstOfStep, isTrue);
      expect(lunges[1].firstOfStep, isFalse);
    });

    test('an exercise the server does not have is skipped', () {
      final holds = buildCalisthenicsHolds(
        kCalLevels.last,
        _catalog(without: {'burpee', 'jump_squat'}),
      );
      expect(holds.any((h) => h.exercise.key == 'burpee'), isFalse);
      expect(holds.any((h) => h.exercise.key == 'decline_push_up'), isTrue);
      expect(
        holds.map((h) => h.stepIndex).toSet().length,
        holds.last.stepIndex + 1,
        reason: 'steps stay numbered without gaps',
      );
      expect(buildCalisthenicsHolds(kCalLevels.first, const ExerciseCatalog()), isEmpty);
    });
  });

  group('reps from the person\'s own max', () {
    test('use the level\'s numbers without a max', () {
      final holds = _holds(kCalLevels[1]);
      final pushups = holds.firstWhere(
        (h) => !h.isRest && h.exercise.key == 'push_up' && h.round == 1,
      );
      expect(pushups.reps, 10);
    });

    test('are the level\'s share of the max, rounded', () {
      for (final (level, share) in [
        (kCalLevels[0], 0.5),
        (kCalLevels[1], 0.6),
        (kCalLevels[2], 0.7),
        (kCalLevels[3], 0.75),
      ]) {
        final holds = _holds(
          level,
          _catalog(maxes: {'push_up': 30, 'knee_push_up': 30, 'decline_push_up': 30}),
        );
        final key = switch (level.id) {
          'beginner' => 'knee_push_up',
          'intense' => 'decline_push_up',
          _ => 'push_up',
        };
        final target = holds.firstWhere((h) => !h.isRest && h.exercise.key == key && h.round == 1);
        expect(target.reps, (30 * share).round(), reason: level.id);
      }
    });

    test('never fall under the minimum, and leave the warm-up alone', () {
      final holds = _holds(
        kCalLevels[1],
        _catalog(maxes: {'push_up': 2, 'air_squat': 40, 'knee_push_up': 40}),
      );
      expect(holds.firstWhere((h) => !h.isRest && h.exercise.key == 'push_up').reps, kCalMinReps);
      final warmupSquat = holds.firstWhere(
        (h) => h.section == 'Warm-up' && h.exercise.key == 'air_squat',
      );
      expect(warmupSquat.reps, 10, reason: 'a warm-up is never sized up');
      final knee = holds.firstWhere((h) => !h.isRest && h.exercise.key == 'knee_push_up');
      expect(knee.reps, 6);
    });

    test('a time hold ignores the max', () {
      final holds = _holds(kCalLevels[1], _catalog(maxes: {'plank': 100}));
      expect(holds.firstWhere((h) => !h.isRest && h.exercise.key == 'plank').seconds, 30);
    });
  });

  group('the coach voice', () {
    const voice = CalisthenicsVoice();

    test('has a recording for every part of every level at its default numbers', () {
      for (final level in kCalLevels) {
        final holds = _holds(level);
        expect(voice.opening(holds), isNotEmpty, reason: level.id);
        for (var i = 0; i < holds.length; i++) {
          if (i > 0) expect(voice.advance(holds, i), isNotEmpty, reason: '${level.id} $i');
          expect(voice.jump(holds, i), isNotEmpty, reason: '${level.id} $i');
          if (!holds[i].isRest) {
            final cues = voice.cueLines(holds, i);
            expect(cues, isNotEmpty, reason: '${level.id} ${holds[i].exercise.key}');
            expect(
              cues.values
                  .expand((l) => l)
                  .any(
                    (l) =>
                        l.clip!.endsWith('.reps') ||
                        l.clip!.endsWith('.go') ||
                        l.clip == 'cal.hold_stretch',
                  ),
              isTrue,
              reason: '${level.id} ${holds[i].exercise.key} says what to do',
            );
          }
        }
      }
    });

    test('says a rep target as a number and the exercise at its own pace', () {
      final holds = _holds(kCalLevels[1]);
      final i = holds.indexWhere((h) => h.isReps && h.exercise.key == 'push_up');
      final lines = voice.cueLines(holds, i)[voice.cueLines(holds, i).keys.first]!;
      expect(lines.map((l) => l.clip), ['cal.n.10', 'cal.push_up.reps']);
      expect(kVoiceClips['cal.push_up.reps']!.text, contains('at your own pace'));
      expect(kVoiceClips['cal.push_up.reps']!.text, contains('Tap done when you finish'));
    });

    test('reads a target over fifty off the screen', () {
      final holds = buildCalisthenicsHolds(
        kCalLevels.last,
        _catalog(maxes: {'decline_push_up': 90}),
      );
      final i = holds.indexWhere((h) => h.isReps && h.reps > kCalVoicedRepsMax);
      expect(i, isNonNegative);
      final cues = voice.cueLines(holds, i);
      final first = cues[(cues.keys.toList()..sort()).first]!;
      expect(first.map((l) => l.clip).first, 'cal.n.screen');
    });

    test('says how long a hold lasts and counts down the last three seconds', () {
      final holds = _holds(kCalLevels[1]);
      final i = holds.indexWhere((h) => !h.isReps && !h.isRest && h.exercise.key == 'plank');
      final cues = voice.cueLines(holds, i);
      final first = cues[(cues.keys.toList()..sort()).first]!.map((l) => l.clip).toList();
      expect(first, ['cal.plank.go', 'cal.t.30']);
      expect(cues[27]!.single.clip, 'cal.count.3');
      expect(cues[28]!.single.clip, 'cal.count.2');
      expect(cues[29]!.single.clip, 'cal.count.1');
    });

    test('announces a rest and what comes next, and the last round', () {
      final holds = _holds(kCalLevels[1]);
      final rest = holds.indexWhere((h) => h.isRest && h.exercise.key == 'push_up' && h.round == 1);
      expect(voice.advance(holds, rest).map((l) => l.clip), ['cal.rest_next', 'cal.push_up.name']);
      final lastRoundStart = holds.indexWhere((h) => h.lastRound && !h.isRest);
      expect(voice.advance(holds, lastRoundStart).first.clip, 'cal.last_round');
      final secondRoundStart = holds.indexWhere((h) => h.round == 2 && !h.isRest);
      expect(voice.advance(holds, secondRoundStart).first.clip, 'cal.round.2');
    });

    test('says switch sides on the other side of an exercise', () {
      final holds = _holds(kCalLevels[1]);
      final right = holds.indexWhere((h) => h.label.startsWith('Right'));
      expect(voice.advance(holds, right).map((l) => l.clip), ['cal.switch_sides']);
    });

    test('lines never overlap inside a hold and finish before the countdown', () {
      double len(String id) => kVoiceClips[id]!.seconds;
      for (final level in kCalLevels) {
        final holds = _holds(level);
        for (var i = 0; i < holds.length; i++) {
          final cues = voice.cueLines(holds, i);
          final at = cues.keys.toList()..sort();
          for (var n = 0; n < at.length; n++) {
            final end = at[n] + cues[at[n]]!.fold(0.0, (s, l) => s + len(l.clip!));
            if (n + 1 < at.length) {
              expect(
                end,
                lessThan(at[n + 1] + 1),
                reason: '${level.id} ${holds[i].exercise.key} $at',
              );
            }
            if (holds[i].isRest && !holds[i].isReps) {
              expect(end, lessThanOrEqualTo(holds[i].seconds - kGuidedCountdownSeconds));
            }
          }
        }
      }
    });

    test('every clip the routines can ask for exists, for reps up to fifty', () {
      for (var n = 1; n <= kCalVoicedRepsMax; n++) {
        expect(kVoiceClips, contains('cal.n.$n'));
      }
      for (final level in kCalLevels) {
        for (final step in [...level.warmup, ...level.circuit, ...level.cooldown]) {
          expect(kVoiceClips, contains('cal.${step.key}.intro'), reason: step.key);
          expect(kVoiceClips, contains('cal.${step.key}.name'), reason: step.key);
          if (step.seconds != null) expect(kVoiceClips, contains('cal.t.${step.seconds}'));
        }
      }
    });
  });

  group('the Calisthenics page', () {
    StubAdapter server({Map<String, int> maxes = const {}}) => fullServer()
      ..on('GET /api/exercises', StubResponse(200, _catalog(maxes: maxes).toJson()))
      ..on('POST /api/logs', StubResponse(201, logResultJson()));

    setUp(() {
      FakeStorage().install();
      Mascot.idleMotion = false;
    });

    Finder button(String label) => find.text(label.toUpperCase());

    Future<TestApp> open(WidgetTester tester, CalLevel level, {StubAdapter? stub}) async {
      final app = TestApp(tester, stub ?? server(), surfaceHeight: 844);
      await app.pump(GuidedPage(routine: calisthenicsRoutine(level)));
      await tester.pumpAndSettle();
      await tester.tap(button('Start'));
      await tester.pump();
      return app;
    }

    Future<void> seconds(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('lists the four levels with their time and what each has', (tester) async {
      final app = TestApp(tester, server(), surfaceHeight: 2800);
      await app.pump(const CalisthenicsPage());
      await tester.pumpAndSettle();
      for (final level in kCalLevels) {
        expect(find.text(level.name), findsOneWidget);
      }
      expect(find.textContaining('About '), findsNWidgets(4));
      expect(find.textContaining('rounds'), findsWidgets);
      expect(find.textContaining('Tabata'), findsNothing);
      expect(find.textContaining('Garber'), findsNothing);
      expect(find.textContaining('not from a trial'), findsNothing);
      await tester.tap(find.text('Sources and safety'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tabata'), findsOneWidget);
      expect(find.textContaining('Garber'), findsOneWidget);
      expect(find.textContaining('own, not from a trial'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the intro outlines warm-up, circuit and cool-down', (tester) async {
      final app = TestApp(tester, server(), surfaceHeight: 1800);
      await app.pump(GuidedPage(routine: calisthenicsRoutine(kCalLevels.first)));
      await tester.pumpAndSettle();
      expect(find.text('Warm-up'), findsOneWidget);
      expect(find.text('Circuit, 3 rounds'), findsOneWidget);
      expect(find.text('Cool-down'), findsOneWidget);
      expect(find.text('8 reps'), findsWidgets);
      expect(find.text('20 sec'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a rep step shows the target large and the centre button says Done', (
      tester,
    ) async {
      await open(tester, kCalLevels.first);
      // Warm-up: jumping jacks 30 s, cat stretch 30 s, then the squats.
      expect(find.text('Jumping Jack'), findsWidgets);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Next exercise'));
      await tester.pump();
      await tester.tap(find.byTooltip('Next exercise'));
      await tester.pump();
      expect(find.text('8'), findsOneWidget, reason: 'the target, large');
      expect(find.text('reps'), findsOneWidget);
      expect(find.byTooltip('Done'), findsNothing, reason: 'not during the get-ready');
      await seconds(tester, 3);
      expect(find.byTooltip('Done'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget, reason: 'pause moves to the app bar');
      await seconds(tester, 60);
      expect(find.text('8'), findsOneWidget, reason: 'a minute later it is still waiting');
      expect(find.byTooltip('Done'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('plus and minus change the count, and Done starts a rest that counts down', (
      tester,
    ) async {
      final app = await open(tester, kCalLevels.first);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next exercise'));
        await tester.pump();
      }
      await seconds(tester, 3);
      await tester.tap(find.byTooltip('One more rep'));
      await tester.pump();
      expect(find.text('9'), findsOneWidget);
      await tester.tap(find.byTooltip('One fewer rep'));
      await tester.tap(find.byTooltip('One fewer rep'));
      await tester.pump();
      expect(find.text('7'), findsOneWidget);
      app.audio.cues.clear();
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      // After the warm-up the next exercise is the first of the circuit, behind a rest.
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Up next: Knee Push Up'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(app.audio.cues, contains('play: cal.rest_next cal.knee_push_up.name'));
      await seconds(tester, 5);
      expect(find.text('25'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('pause holds a rep step and resume continues it', (tester) async {
      final app = await open(tester, kCalLevels.first);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next exercise'));
        await tester.pump();
      }
      await seconds(tester, 3);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(find.byTooltip('Resume'), findsOneWidget);
      expect(find.byTooltip('Done'), findsNothing);
      expect(app.audio.cues.last, 'stop');
      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      expect(find.byTooltip('Done'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a timed step counts down in seconds and speaks the length', (tester) async {
      final app = await open(tester, kCalLevels.first);
      expect(app.audio.cues, contains(startsWith('play: cal.welcome')));
      // The welcome and the first exercise's setup run about 16 seconds, so the length follows.
      await seconds(tester, 3 + 14);
      expect(find.text('16'), findsOneWidget);
      var plays = app.audio.cues.where((c) => c.startsWith('play:')).toList();
      expect(
        plays.any((c) => c.contains('cal.jumping_jack.go cal.t.30')),
        isTrue,
        reason: '$plays',
      );
      await seconds(tester, 16);
      expect(app.audio.cues, isNot(contains('tick')), reason: 'the voice counts instead');
      plays = app.audio.cues.where((c) => c.startsWith('play:')).toList();
      expect(plays, containsAll(['play: cal.count.3', 'play: cal.count.2', 'play: cal.count.1']));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('finishing logs the minutes and the daily reps of the quest exercise', (
      tester,
    ) async {
      final stub = server();
      final app = await open(tester, kCalLevels.first, stub: stub);
      // Do the squat warm-up step (8 reps) and a few more, then end early and log.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next exercise'));
        await tester.pump();
      }
      await seconds(tester, 3);
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      await seconds(tester, 35);
      await tester.tap(find.byTooltip('Previous exercise'));
      await tester.pump();
      await seconds(tester, 3);
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      await app.tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(button('Log 1 min and end'));
      await tester.pumpAndSettle();
      final logs = stub
          .to('POST /api/logs')
          .map((r) => (r.data as Map).cast<String, dynamic>())
          .toList();
      expect(logs.first['type'], 'calisthenics');
      expect(logs.first['unit'], 'minutes');
      expect(find.text('Nice work'), findsOneWidget);
      expect(find.textContaining('Under 20 minutes'), findsOneWidget);
      await tester.tap(button('Done'));
      await tester.pumpAndSettle();
    });
  });

  group('recording a finished session', () {
    setUp(() {
      FakeStorage().install();
      Mascot.idleMotion = false;
    });

    Map<String, dynamic> todayWith(String? exercise) {
      final today = jsonDecode(jsonEncode(richTodayJson())) as Map<String, dynamic>;
      for (final q in today['quests'] as List) {
        if ((q as Map)['key'] == 'pushups' && exercise != null) q['exercise'] = exercise;
      }
      return today;
    }

    Future<List<Map<String, dynamic>>> sessionLogs(WidgetTester tester, String? exercise) async {
      final stub = fullServer()
        ..on('GET /api/today', StubResponse(200, todayWith(exercise)))
        ..on('GET /api/exercises', StubResponse(200, _catalog().toJson()))
        ..on('POST /api/logs', StubResponse(201, logResultJson()));
      final app = TestApp(tester, stub, surfaceHeight: 844);
      await app.pump(GuidedPage(routine: calisthenicsRoutine(kCalLevels.first)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('START'));
      await tester.pump();
      // The warm-up's squats are the first rep step: 8 reps, changed to 10 before Done.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next exercise'));
        await tester.pump();
      }
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.byTooltip('One more rep'));
      await tester.tap(find.byTooltip('One more rep'));
      await tester.pump();
      await tester.tap(find.byTooltip('Done'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('LOG 1 MIN AND END'));
      await tester.pumpAndSettle();
      final logs = [
        for (final r in stub.to('POST /api/logs')) (r.data as Map).cast<String, dynamic>(),
      ];
      await tester.tap(find.text('DONE'));
      await tester.pumpAndSettle();
      return logs;
    }

    testWidgets('minutes go in as calisthenics, with the reps of the quest exercise', (
      tester,
    ) async {
      final logs = await sessionLogs(tester, 'air_squat');
      expect(logs, hasLength(2));
      expect(logs[0]['type'], 'calisthenics');
      expect(logs[0]['unit'], 'minutes');
      expect(logs[0]['quantity'], 1);
      expect(logs[1]['type'], 'pushups');
      expect(logs[1]['unit'], 'reps');
      expect(logs[1]['exercise'], 'air_squat');
      expect(logs[1]['quantity'], 10, reason: 'the reps the person set before Done');
      expect(logs[0]['clientOpId'], isNot(logs[1]['clientOpId']));
    });

    testWidgets('reps of another exercise than the quest exercise are not logged', (tester) async {
      final logs = await sessionLogs(tester, null);
      expect(logs.map((l) => l['type']), ['calisthenics']);
    });
  });

  group('the Train tab', () {
    testWidgets('has a Calisthenics card next to Yoga and Mobility that opens the levels', (
      tester,
    ) async {
      FakeStorage().install();
      final stub = fullServer()
        ..on('GET /api/exercises', StubResponse(200, _catalog().toJson()))
        ..on(
          'GET /api/yoga/plan',
          StubResponse(200, jsonDecode(File('test/contract_v9/yoga_plan.json').readAsStringSync())),
        );
      final app = TestApp(tester, stub, surfaceHeight: 1800);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(find.text('START A WORKOUT'), findsOneWidget);
      expect(find.text('Calisthenics'), findsNothing);
      await app.tap(find.text('START A WORKOUT'));
      await tester.pumpAndSettle();
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('Calisthenics'), findsOneWidget);
      expect(find.text('Mobility'), findsOneWidget);
      await app.tap(find.text('Calisthenics'));
      await tester.pumpAndSettle();
      expect(find.text('Beginner'), findsOneWidget);
      expect(find.text('Intense'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
