import 'dart:math' as math;

import 'package:flutter/foundation.dart' show protected;

import '../../audio/voice_clip.dart';
import '../../audio/voice_clips.dart';
import '../../audio/voice_line.dart';
import 'guided_session.dart';
import 'set_assist.dart' show kHoldLeadInSeconds;

/// Where the first alignment cue lands in a hold, a few seconds after the pose has been named.
const kVoiceCueSeconds = 9;

/// Where the first breath cue lands, and the gap between breath cues in a long rest.
const kVoiceBreathSeconds = 19;
const kVoiceBreathEvery = 21;

/// Quiet kept between two lines and before the countdown ticks start.
const kVoiceGapSeconds = 2;
const kVoiceCountdownRoom = kGuidedCountdownSeconds + 1;

/// The class script as a plan: which recorded clips narrate each moment of a guided session.
/// It only maps holds to clip ids, so the page plays them and tests read them. A pose without
/// clips (the Mobility stretches) gets an empty plan and the page speaks its text instead.
class GuidedVoice {
  const GuidedVoice([this.clips = kVoiceClips]);

  final Map<String, VoiceClip> clips;

  /// The welcome, then the first pose.
  List<VoiceLine> opening(List<GuidedHold> holds) =>
      all(['welcome', '${holds.first.exercise.key}.again']);

  /// What to say as the session moves on by itself from hold [index] - 1 to [index]: a new pose
  /// by name, a switch of sides, or a nudge to stay with the same pose for another round.
  List<VoiceLine> advance(List<GuidedHold> holds, int index) {
    final from = holds[index - 1];
    final to = holds[index];
    if (!to.exercise.yoga) return const [];
    if (to.stepIndex != from.stepIndex) return all(['${to.exercise.key}.intro']);
    if (_side(to) != _side(from)) return all(['switch_sides']);
    return all(['stay.${1 + (_position(holds, index) % _stayVariants)}']);
  }

  /// What to say after a skip or a step back, which start the pose from its beginning.
  List<VoiceLine> jump(List<GuidedHold> holds, int index) =>
      all(['${holds[index].exercise.key}.again']);

  /// [cues] with each moment allowed to say several clips in a row. A routine with number
  /// clips overrides this; the yoga script has one clip per moment.
  Map<int, List<VoiceLine>> cueLines(List<GuidedHold> holds, int index) => {
    for (final e in cues(holds, index).entries) e.key: [e.value],
  };

  /// The lines to play during hold [index], keyed by the second of the hold they start at.
  /// An alignment cue and then breath cues, placed after the opening line and clear of the
  /// closing words in the final hold, with every line finished before the countdown ticks.
  Map<int, VoiceLine> cues(List<GuidedHold> holds, int index) {
    final hold = holds[index];
    final key = hold.exercise.key;
    final plan = <int, VoiceLine>{};
    if (!hold.exercise.yoga) return plan;
    final isLast = index == holds.length - 1;
    var limit = hold.seconds - kVoiceCountdownRoom;

    if (isLast && clips.containsKey('closing')) {
      final start = hold.seconds - ceil('closing') - kVoiceCountdownRoom;
      if (start > 0) {
        plan[start] = line('closing');
        limit = start - kVoiceGapSeconds;
      }
    }

    var cursor = leadSeconds(holds, index) + kVoiceGapSeconds;
    void place(int preferred, String clip) {
      if (!clips.containsKey(clip)) return;
      final at = math.max(preferred, cursor);
      if (at + ceil(clip) > limit) return;
      plan[at] = line(clip);
      cursor = at + ceil(clip) + kVoiceGapSeconds;
    }

    final position = _position(holds, index);
    place(kVoiceCueSeconds, '$key.${position.isEven ? 'cue' : 'cue2'}');
    for (var n = 0, at = kVoiceBreathSeconds; at < limit; n++, at += kVoiceBreathEvery) {
      place(at, 'breath.${1 + ((index + n) % _breathVariants)}');
    }
    return plan;
  }

  /// Seconds into the hold at which what is said on arrival stops, counting the lead-in as before 0.
  @protected
  int leadSeconds(List<GuidedHold> holds, int index) {
    double length(List<VoiceLine> ids) =>
        ids.fold(0, (sum, line) => sum + clips[line.clip]!.seconds);
    // A skip or a step back plays the pose again, so allow for the longer of the two.
    final spoken = index == 0
        ? length(opening(holds))
        : math.max(length(advance(holds, index)), length(jump(holds, index)));
    return math.max(0, spoken.ceil() - kHoldLeadInSeconds);
  }

  @protected
  VoiceLine line(String id) => VoiceLine(clips[id]!.text, clip: id);

  @protected
  int ceil(String id) => clips[id]!.seconds.ceil();

  /// The lines for [ids], or none at all if any has no recording, so a pose is never half spoken.
  @protected
  List<VoiceLine> all(List<String> ids) => ids.every(clips.containsKey)
      ? [for (final id in ids) VoiceLine(clips[id]!.text, clip: id)]
      : const [];

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
