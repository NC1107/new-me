import 'dart:math' as math;

import '../../audio/voice_line.dart';
import 'guided_session.dart';
import 'guided_voice.dart';

/// The most reps the coach says aloud. A bigger target (from a high max) is read off the screen.
const kCalVoicedRepsMax = 50;

/// The coach's script for the calisthenics routines, as a plan like [GuidedVoice]: which clips
/// narrate each moment. Clips are built from parts, so one recording of "ten" serves every
/// exercise: the number, then the exercise's own "push-ups, at your own pace. Tap done when you
/// finish". A hold with a missing clip is left silent rather than half spoken.
class CalisthenicsVoice extends GuidedVoice {
  const CalisthenicsVoice([super.clips]);

  @override
  List<VoiceLine> opening(List<GuidedHold> holds) {
    final first = intro(holds.first);
    return first.isEmpty ? const [] : all(['cal.welcome', ...first.map((l) => l.clip!)]);
  }

  @override
  List<VoiceLine> advance(List<GuidedHold> holds, int index) {
    final from = holds[index - 1];
    final to = holds[index];
    if (to.isRest) return rest(to);
    if (to.stepIndex == from.stepIndex) return all(['cal.switch_sides']);
    final newRound = from.isRest && to.round > 1 && holds[math.max(0, index - 2)].round != to.round;
    final marker = newRound
        ? [to.lastRound ? 'cal.last_round' : 'cal.round.${to.round}']
        : <String>[];
    return all([...marker, ..._intro(to)]);
  }

  @override
  List<VoiceLine> jump(List<GuidedHold> holds, int index) {
    final to = holds[index];
    return to.isRest ? rest(to) : all(_intro(to));
  }

  /// "Rest. Next up, squats."
  List<VoiceLine> rest(GuidedHold to) => all(['cal.rest_next', 'cal.${to.exercise.key}.name']);

  /// The exercise's name and how to set up for it.
  List<VoiceLine> intro(GuidedHold hold) => all(_intro(hold));

  List<String> _intro(GuidedHold hold) => ['cal.${hold.exercise.key}.intro'];

  /// What the coach says once the lead-in ends: how many, or how long, and then one form cue.
  List<String> _task(GuidedHold hold) {
    final key = hold.exercise.key;
    if (hold.isReps) {
      final n = hold.reps;
      return [n <= kCalVoicedRepsMax ? 'cal.n.$n' : 'cal.n.screen', 'cal.$key.reps'];
    }
    return [hold.exercise.stretch ? 'cal.hold_stretch' : 'cal.$key.go', 'cal.t.${hold.seconds}'];
  }

  @override
  Map<int, List<VoiceLine>> cueLines(List<GuidedHold> holds, int index) {
    final hold = holds[index];
    final plan = <int, List<VoiceLine>>{};
    if (hold.isRest) {
      final tip = 'cal.rest.${1 + index % 3}';
      final at = _spokenSeconds(holds, index) + kVoiceGapSeconds;
      if (clips.containsKey(tip) && at + ceil(tip) <= hold.seconds - kVoiceCountdownRoom) {
        plan[at] = [line(tip)];
      }
      return plan;
    }

    final isLast = index == holds.length - 1;
    var limit = hold.isReps ? 1 << 30 : hold.seconds - kVoiceCountdownRoom;
    if (!hold.isReps) {
      for (var n = kGuidedCountdownSeconds; n >= 1; n--) {
        if (clips.containsKey('cal.count.$n')) plan[hold.seconds - n] = [line('cal.count.$n')];
      }
    }
    if (isLast && clips.containsKey('cal.closing')) {
      final start = hold.seconds - ceil('cal.closing') - kVoiceCountdownRoom;
      if (start > 0) {
        plan[start] = [line('cal.closing')];
        limit = start - kVoiceGapSeconds;
      }
    }

    var cursor = leadSeconds(holds, index);
    final task = _task(hold);
    final total = task.fold(0, (sum, id) => sum + (clips.containsKey(id) ? ceil(id) : 0));
    if (task.every(clips.containsKey) && cursor + total <= limit) {
      plan[cursor] = all(task);
      cursor += total + kVoiceGapSeconds;
    }
    final cue = 'cal.${hold.exercise.key}.cue';
    if (clips.containsKey(cue) && cursor + ceil(cue) <= limit) plan[cursor] = [line(cue)];
    return plan;
  }

  /// Seconds the arrival line runs, for a hold that has no lead-in to hide it in.
  int _spokenSeconds(List<GuidedHold> holds, int index) {
    final spoken = index == 0 ? opening(holds) : advance(holds, index);
    return spoken.fold<double>(0, (sum, l) => sum + clips[l.clip]!.seconds).ceil();
  }
}
