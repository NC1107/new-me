import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSound = 'guided.sound';
const _kVoice = 'guided.voice';

/// Whether guided sessions play their ticks and chimes, and whether they speak. Both start on and
/// are remembered on this phone.
class GuidedSound {
  const GuidedSound({this.sound = true, this.voice = true});

  final bool sound;
  final bool voice;

  /// The speaker button's three states in turn: everything, tones only, silent.
  GuidedSound get next => switch ((sound, voice)) {
    (true, true) => const GuidedSound(sound: true, voice: false),
    (true, false) => const GuidedSound(sound: false, voice: false),
    _ => const GuidedSound(),
  };
}

class GuidedSoundNotifier extends Notifier<GuidedSound> {
  @override
  GuidedSound build() {
    _load();
    return const GuidedSound();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = GuidedSound(
      sound: prefs.getBool(_kSound) ?? true,
      voice: prefs.getBool(_kVoice) ?? true,
    );
  }

  Future<void> set(GuidedSound value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSound, value.sound);
    await prefs.setBool(_kVoice, value.voice);
  }
}

final guidedSoundProvider = NotifierProvider<GuidedSoundNotifier, GuidedSound>(
  GuidedSoundNotifier.new,
);
