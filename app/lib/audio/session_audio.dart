import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// What a guided session plays. The page asks for cues by meaning, so tests use a fake and a later
/// spoken-instruction or time-call cue only adds a method here.
abstract class SessionAudio {
  /// Gets the audio session ready, mixing with the person's own music.
  Future<void> prepare();

  /// The short tick at 3, 2 and 1 seconds left.
  void tick();

  /// The soft tone at the midpoint of a long hold.
  void halfway();

  /// The chime when a hold ends and the next pose or side starts, and at the end of a session.
  void chime();

  /// Says [text] through text-to-speech.
  void speak(String text);

  /// Cuts speech off, for a pause or an early end.
  void stopSpeaking();

  Future<void> dispose();
}

/// Keeps the screen on while a session runs, so the phone can sit on the floor.
abstract class ScreenAwake {
  Future<void> enable();
  Future<void> disable();
}

/// Plays the bundled cues and speaks through the platform voice. The audio session is `playback`
/// with `mixWithOthers` and `duckOthers`, so music from another app dips while a cue plays and
/// then comes back, plays through the silent switch and keeps playing as the screen dims.
class PlatformSessionAudio implements SessionAudio {
  final _tickPlayer = AudioPlayer(playerId: 'newme.session.tick');
  final _chimePlayer = AudioPlayer(playerId: 'newme.session.chime');
  final _halfwayPlayer = AudioPlayer(playerId: 'newme.session.halfway');
  final _tts = FlutterTts();
  bool _ready = false;

  /// Every call is guarded: a cue that cannot play must never end a session.
  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on Object catch (e) {
      debugPrint('[NEWME] session audio: $e');
    }
  }

  @override
  Future<void> prepare() => _guard(() async {
    if (_ready) return;
    _ready = true;
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers, AVAudioSessionOptions.duckOthers},
        ),
        android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.gainTransientMayDuck),
      ),
    );
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
      IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      IosTextToSpeechAudioCategoryOptions.duckOthers,
    ], IosTextToSpeechAudioMode.voicePrompt);
    await _tts.setSpeechRate(0.5);
    await _tts.awaitSpeakCompletion(false);
  });

  Future<void> _play(AudioPlayer player, String asset) => _guard(() async {
    await player.stop();
    await player.play(AssetSource(asset), mode: PlayerMode.lowLatency);
  });

  @override
  void tick() => unawaited(_play(_tickPlayer, 'audio/tick.wav'));

  @override
  void halfway() => unawaited(_play(_halfwayPlayer, 'audio/halfway.wav'));

  @override
  void chime() => unawaited(_play(_chimePlayer, 'audio/chime.wav'));

  @override
  void speak(String text) => unawaited(
    _guard(() async {
      await _tts.stop();
      await _tts.speak(text);
    }),
  );

  @override
  void stopSpeaking() => unawaited(
    _guard(() async {
      await _tts.stop();
    }),
  );

  @override
  Future<void> dispose() => _guard(() async {
    await _tts.stop();
    await _tickPlayer.dispose();
    await _chimePlayer.dispose();
    await _halfwayPlayer.dispose();
  });
}

class PlatformScreenAwake implements ScreenAwake {
  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } on Object catch (e) {
      // Wake lock failures must never stop a session.
      debugPrint('[NEWME] wakelock: $e');
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } on Object catch (e) {
      // Wake lock failures must never stop a session.
      debugPrint('[NEWME] wakelock: $e');
    }
  }
}

final sessionAudioProvider = Provider<SessionAudio>((ref) {
  final audio = PlatformSessionAudio();
  ref.onDispose(audio.dispose);
  return audio;
});

final screenAwakeProvider = Provider<ScreenAwake>((ref) => PlatformScreenAwake());
