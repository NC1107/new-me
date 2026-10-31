import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_clip.dart';

/// One line of a class script: the words, and the bundled recording of them when there is one.
/// A script is a list of these per event, so a lesson written later can bring only text and
/// still be spoken by the server voice.
@immutable
class VoiceLine {
  const VoiceLine(this.text, {this.clip});

  final String text;

  /// Id of the bundled clip that says [text], or null for a line with no recording.
  final String? clip;

  @override
  bool operator ==(Object other) => other is VoiceLine && other.text == text && other.clip == clip;

  @override
  int get hashCode => Object.hash(text, clip);

  @override
  String toString() => clip ?? 'text:$text';
}

/// How a line will be heard.
sealed class ResolvedLine {
  const ResolvedLine(this.line);

  final VoiceLine line;
}

/// The recording bundled in the app, which works offline.
class BundledLine extends ResolvedLine {
  const BundledLine(super.line, this.clip);

  final String clip;
}

/// Audio the server synthesised in the class voice.
class ServerLine extends ResolvedLine {
  const ServerLine(super.line, this.audio);

  final Uint8List audio;
}

/// The phone's own text-to-speech, the last resort.
class DeviceLine extends ResolvedLine {
  const DeviceLine(super.line);
}

typedef VoiceFetch = Future<Uint8List> Function(String text);

/// Decides how each line is heard: the bundled clip, else the server voice, else the device
/// voice. Server audio is kept in memory, so [prefetch] on the next few lines of a session
/// leaves no gap when their turn comes.
class LineResolver {
  LineResolver({
    required this.bundled,
    this.fetch,
    bool Function()? enabled,
    this.wait = const Duration(seconds: 6),
    this.keep = 40,
  }) : _enabled = enabled ?? (() => true);

  /// Ids of the clips the app ships with.
  final Map<String, VoiceClip> bundled;

  /// Asks the server for a line, or null when this build has no server voice.
  final VoiceFetch? fetch;

  /// How long a line may take before the device voice speaks instead.
  final Duration wait;

  /// Fetched lines held in memory.
  final int keep;

  /// Whether the server says it can speak, read at each use so a change shows at once.
  final bool Function() _enabled;

  final _fetched = <String, Future<Uint8List>>{};

  bool _needsServer(VoiceLine line) =>
      fetch != null && _enabled() && !bundled.containsKey(line.clip);

  /// Starts fetching every line that will need the server, once each.
  void prefetch(Iterable<VoiceLine> lines) {
    for (final line in lines) {
      if (_needsServer(line)) unawaited(_request(line.text).then((_) {}, onError: (_) {}));
    }
  }

  Future<Uint8List> _request(String text) {
    final held = _fetched.remove(text);
    if (held != null) return _fetched[text] = held;
    final request = fetch!(text);
    _fetched[text] = request;
    // A failed fetch is forgotten so a later try can succeed.
    request.then(
      (_) {},
      onError: (Object _) {
        _fetched.remove(text);
      },
    );
    while (_fetched.length > keep) {
      _fetched.remove(_fetched.keys.first);
    }
    return request;
  }

  Future<ResolvedLine> resolve(VoiceLine line) async {
    final clip = line.clip;
    if (clip != null && bundled.containsKey(clip)) return BundledLine(line, clip);
    if (!_needsServer(line)) return DeviceLine(line);
    try {
      final audio = await _request(line.text).timeout(wait);
      if (audio.isNotEmpty) return ServerLine(line, audio);
    } on Object catch (e) {
      debugPrint('[NEWME] server voice: $e');
    }
    return DeviceLine(line);
  }
}
