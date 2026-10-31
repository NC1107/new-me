import 'package:flutter/foundation.dart';

/// One rendered line of the guided class voice: the words it says, for the text-to-speech
/// fallback, and how long it plays, for scheduling cues so they do not talk over each other.
@immutable
class VoiceClip {
  const VoiceClip(this.text, this.seconds);

  final String text;
  final double seconds;
}
