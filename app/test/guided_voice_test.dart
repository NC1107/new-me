import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/audio/voice_clip.dart';
import 'package:newme/audio/voice_clips.dart';
import 'package:newme/features/training/guided_session.dart';
import 'package:newme/features/training/guided_voice.dart';
import 'package:newme/features/training/yoga_flows.dart';

ExerciseCatalog get _catalog =>
    ExerciseCatalog.parse(jsonDecode(File('test/contract_v9/exercises.json').readAsStringSync()));

const _voice = GuidedVoice();

List<GuidedHold> _holds(int flow) => buildYogaHolds(kYogaFlows[flow], _catalog);

void main() {
  group('the bundled clips', () {
    final manifest = jsonDecode(File('../tools/voice/manifest.json').readAsStringSync()) as Map;
    final texts = (manifest['clips'] as Map).cast<String, String>();

    test('match the manifest and have a file each', () {
      expect(kVoiceClips.keys.toSet(), texts.keys.toSet());
      for (final MapEntry(:key, :value) in kVoiceClips.entries) {
        expect(value.text, texts[key], reason: key);
        expect(File('assets/audio/voice/$key.m4a').existsSync(), isTrue, reason: key);
        expect(value.seconds, greaterThan(0.5), reason: key);
      }
    });

    test('stay small enough to bundle', () {
      final bytes = Directory('assets/audio/voice')
          .listSync()
          .whereType<File>()
          .fold(0, (sum, f) => sum + f.lengthSync());
      expect(bytes, lessThan(6 * 1000 * 1000));
    });

    test('use no em dash', () {
      for (final MapEntry(:key, :value) in texts.entries) {
        expect(value, isNot(contains(String.fromCharCode(0x2014))), reason: key);
      }
    });

    test('cover every pose of every flow', () {
      for (final flow in kYogaFlows) {
        for (final step in flow.steps) {
          for (final part in ['intro', 'again', 'cue', 'cue2']) {
            expect(kVoiceClips, contains('${step.key}.$part'));
          }
        }
      }
    });

    test('name the pose and its side in the intro', () {
      expect(kVoiceClips['yoga_downward_dog.intro']!.text, startsWith('Next, Downward dog.'));
      expect(
        kVoiceClips['yoga_warrior_i.intro']!.text,
        startsWith('Next, Warrior one, left side.'),
      );
    });
  });

  group('the class script', () {
    test('opens with the welcome and the first pose', () {
      expect(_voice.opening(_holds(0)), ['welcome', 'yoga_easy.again']);
    });

    test('names the next pose, the other side and a repeated round', () {
      final holds = _holds(1);
      int at(String key, [String label = '']) =>
          holds.indexWhere((h) => h.exercise.key == key && h.label.startsWith(label));
      expect(_voice.advance(holds, at('yoga_cat_cow')), ['yoga_cat_cow.intro']);
      expect(_voice.advance(holds, at('yoga_low_lunge', 'Right')), ['switch_sides']);
      final second = holds.indexWhere(
        (h) => h.exercise.key == 'yoga_seated_forward_fold' && h.label == 'Hold 2 of 2',
      );
      expect(_voice.advance(holds, second).single, startsWith('stay.'));
    });

    test('a skip or step back plays the pose from its start', () {
      final holds = _holds(0);
      expect(_voice.jump(holds, 2), ['yoga_downward_dog.again']);
    });

    test('has nothing to say for a pose without recordings, so the page speaks it', () {
      final holds = _holds(0);
      const bare = GuidedVoice({});
      expect(bare.opening(holds), isEmpty);
      expect(bare.advance(holds, 1), isEmpty);
      expect(bare.jump(holds, 1), isEmpty);
      expect(bare.cues(holds, 1), isEmpty);
      final stretch = _catalog.exercises.firstWhere((e) => !e.strength && !e.yoga);
      final mobility = [
        GuidedHold(exercise: stretch, stepIndex: 0, label: 'Hold', firstOfStep: true, seconds: 30),
        GuidedHold(exercise: stretch, stepIndex: 1, label: 'Hold', firstOfStep: true, seconds: 30),
      ];
      expect(_voice.opening(mobility), isEmpty);
      expect(_voice.advance(mobility, 1), isEmpty);
      expect(_voice.cues(mobility, 1), isEmpty);
    });
  });

  group('cues inside a hold', () {
    VoiceClip clip(String id) => kVoiceClips[id]!;

    test('every hold of every flow gets an alignment cue and none talk over each other', () {
      for (var f = 0; f < kYogaFlows.length; f++) {
        final holds = _holds(f);
        for (var i = 0; i < holds.length; i++) {
          final cues = _voice.cues(holds, i);
          final at = cues.keys.toList()..sort();
          expect(
            cues.values.any((c) => c.contains('.cue')),
            isTrue,
            reason: '${holds[i].exercise.key} in flow $f',
          );
          for (var n = 0; n < at.length; n++) {
            final end = at[n] + clip(cues[at[n]]!).seconds;
            expect(at[n], greaterThanOrEqualTo(0));
            if (n + 1 < at.length) {
              expect(end, lessThan(at[n + 1]), reason: '${holds[i].exercise.key} $cues');
            } else {
              expect(
                end,
                lessThanOrEqualTo(holds[i].seconds - kGuidedCountdownSeconds),
                reason: '${holds[i].exercise.key} $cues',
              );
            }
          }
        }
      }
    });

    test('the alignment cue alternates between holds of one pose', () {
      final holds = _holds(1);
      final lunge = [
        for (var i = 0; i < holds.length; i++)
          if (holds[i].exercise.key == 'yoga_low_lunge') i,
      ];
      expect(lunge, hasLength(4));
      final firsts = [for (final i in lunge) _voice.cues(holds, i).values.firstWhere(_isCue)];
      expect(firsts, [
        'yoga_low_lunge.cue',
        'yoga_low_lunge.cue2',
        'yoga_low_lunge.cue',
        'yoga_low_lunge.cue2',
      ]);
    });

    test('the closing words end before the last hold does', () {
      for (var f = 0; f < kYogaFlows.length; f++) {
        final holds = _holds(f);
        final cues = _voice.cues(holds, holds.length - 1);
        final start = cues.entries.firstWhere((e) => e.value == 'closing').key;
        expect(
          start + clip('closing').seconds,
          lessThanOrEqualTo(holds.last.seconds - kGuidedCountdownSeconds),
        );
        expect(cues.values.where((c) => c == 'closing'), hasLength(1));
        expect(_voice.cues(holds, holds.length - 2).values, isNot(contains('closing')));
      }
    });

    test('a long rest keeps breathing cues coming', () {
      final holds = _holds(2);
      final legsUp = holds.indexWhere((h) => h.exercise.key == 'yoga_legs_up_wall');
      final breaths = _voice.cues(holds, legsUp).values.where((c) => c.startsWith('breath.'));
      expect(breaths.length, greaterThan(2));
    });

    test('holds the first pose back until the welcome has been said', () {
      final holds = _holds(0);
      final first = _voice.cues(holds, 0).keys.reduce((a, b) => a < b ? a : b);
      final welcome = clip('welcome').seconds + clip('yoga_easy.again').seconds;
      expect(first, greaterThan(welcome - 3));
    });
  });
}

bool _isCue(String id) => id.endsWith('.cue') || id.endsWith('.cue2');
