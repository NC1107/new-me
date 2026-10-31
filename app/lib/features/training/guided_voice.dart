import 'dart:math' as math;

import '../../audio/voice_clip.dart';
import '../../audio/voice_clips.dart';
import 'guided_session.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

/// A recorded line to play [at] seconds into a hold.
class VoiceCue {
  const VoiceCue(this.at, this.clip);

  final int at;
  final String clip;

  @override
  String toString() => 'VoiceCue($at, $clip)';
}

/// Where the first alignment cue lands in a hold, a few seconds after the pose has been named.
const kVoiceCueSeconds = 9;

/// Where the first breath cue lands, and the gap between breath cues in a long rest.
const kVoiceBreathSeconds = 19;
const kVoiceBreathEvery = 21;

/// Quiet kept between two lines and before the countdown ticks start.
const _gapSeconds = 2;
const _countdownRoom = kGuidedCountdownSeconds + 1;

/// The class script as a plan: which recorded clips narrate each moment of a guided session.
/// It only maps holds to clip ids, so the page plays them and tests read them. A pose without
/// clips (the Mobility stretches) gets an empty plan and the page speaks its text instead.
class GuidedVoice {
  const GuidedVoice([this.clips = kVoiceClips]);

  final Map<String, VoiceClip> clips;

  /// The welcome, then the first pose.
  List<String> opening(List<GuidedHold> holds) =>
      _all(['welcome', '${holds.first.exercise.key}.again']);

  /// What to say as the session moves on by itself from hold [index] - 1 to [index]: a new pose
  /// by name, a switch of sides, or a nudge to stay with the same pose for another round.
  List<String> advance(List<GuidedHold> holds, int index) {
    final from = holds[index - 1];
    final to = holds[index];
    if (to.stepIndex != from.stepIndex) return _all(['${to.exercise.key}.intro']);
    if (_side(to) != _side(from)) return _all(['switch_sides']);
    return _all(['stay.${1 + (_position(holds, index) % _stayVariants)}']);
  }

  /// What to say after a skip or a step back, which start the pose from its beginning.
  List<String> jump(List<GuidedHold> holds, int index) =>
      _all(['${holds[index].exercise.key}.again']);

  /// The lines to play during hold [index], keyed by the second of the hold they start at.
  /// An alignment cue and then breath cues, placed after the opening line and clear of the
  /// closing words in the final hold, with every line finished before the countdown ticks.
  Map<int, String> cues(List<GuidedHold> holds, int index) {
    final hold = holds[index];
    final key = hold.exercise.key;
    final plan = <int, String>{};
    if (!hold.exercise.yoga) return plan;
    final isLast = index == holds.length - 1;
    var limit = hold.seconds - _countdownRoom;

    if (isLast && clips.containsKey('closing')) {
      final start = hold.seconds - _ceil('closing') - _countdownRoom;
      if (start > 0) {
        plan[start] = 'closing';
        limit = start - _gapSeconds;
      }
    }

    var cursor = _leadSeconds(holds, index) + _gapSeconds;
    void place(int preferred, String clip) {
      if (!clips.containsKey(clip)) return;
      final at = math.max(preferred, cursor);
      if (at + _ceil(clip) > limit) return;
      plan[at] = clip;
      cursor = at + _ceil(clip) + _gapSeconds;
    }

    final position = _position(holds, index);
    place(kVoiceCueSeconds, '$key.${position.isEven ? 'cue' : 'cue2'}');
    for (var n = 0, at = kVoiceBreathSeconds; at < limit; n++, at += kVoiceBreathEvery) {
      place(at, 'breath.${1 + ((index + n) % _breathVariants)}');
    }
    return plan;
  }

  /// Seconds into the hold at which what is said on arrival stops, counting the lead-in as before 0.
  int _leadSeconds(List<GuidedHold> holds, int index) {
    double length(List<String> ids) => ids.fold(0, (sum, id) => sum + clips[id]!.seconds);
    // A skip or a step back plays the pose again, so allow for the longer of the two.
    final spoken = index == 0
        ? length(opening(holds))
        : math.max(length(advance(holds, index)), length(jump(holds, index)));
    return math.max(0, spoken.ceil() - kHoldLeadInSeconds);
  }

  int _ceil(String id) => clips[id]!.seconds.ceil();

  List<String> _all(List<String> ids) => ids.every(clips.containsKey) ? ids : const [];

  static const _stayVariants = 3;
  static const _breathVariants = 4;

  /// "Left", "Right", or empty for a pose done once.
  static String _side(GuidedHold h) => h.label.startsWith('Left')
      ? 'Left'
      : h.label.startsWith('Right')
      ? 'Right'
      : '';

  /// How many holds of the same pose came before this one.
  static int _position(List<GuidedHold> holds, int index) {
    var n = 0;
    for (var i = index - 1; i >= 0 && holds[i].stepIndex == holds[index].stepIndex; i--) {
      n++;
    }
    return n;
  }
}
