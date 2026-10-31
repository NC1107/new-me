import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/audio/voice_clip.dart';
import 'package:newme/audio/voice_line.dart';

const _clips = {'welcome': VoiceClip('Welcome.', 7)};
const _bundled = VoiceLine('Welcome.', clip: 'welcome');
const _typed = VoiceLine('A line written today.');

Uint8List _audio(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  late List<String> fetched;

  setUp(() => fetched = []);

  LineResolver resolver({
    VoiceFetch? fetch,
    bool enabled = true,
    Duration wait = const Duration(seconds: 6),
    int keep = 40,
  }) => LineResolver(bundled: _clips, fetch: fetch, enabled: () => enabled, wait: wait, keep: keep);

  Future<Uint8List> ok(String text) async {
    fetched.add(text);
    return _audio(text);
  }

  group('resolution order', () {
    test('a bundled clip wins and never asks the server', () async {
      final r = await resolver(fetch: ok).resolve(_bundled);
      expect(r, isA<BundledLine>());
      expect((r as BundledLine).clip, 'welcome');
      expect(fetched, isEmpty);
    });

    test('a line with no clip comes from the server', () async {
      final r = await resolver(fetch: ok).resolve(_typed);
      expect(r, isA<ServerLine>());
      expect((r as ServerLine).audio, _audio(_typed.text));
      expect(fetched, [_typed.text]);
    });

    test('a clip id the app does not have is treated as text', () async {
      final r = await resolver(fetch: ok).resolve(const VoiceLine('Hello.', clip: 'gone'));
      expect(r, isA<ServerLine>());
    });

    test('the device voice speaks when the server fails', () async {
      final r = await resolver(fetch: (_) => Future.error(StateError('down'))).resolve(_typed);
      expect(r, isA<DeviceLine>());
    });

    test('the device voice speaks when the server answers with nothing', () async {
      final r = await resolver(fetch: (_) async => Uint8List(0)).resolve(_typed);
      expect(r, isA<DeviceLine>());
    });

    test('the device voice speaks when the server is too slow', () async {
      final never = Completer<Uint8List>();
      final r = await resolver(
        fetch: (_) => never.future,
        wait: const Duration(milliseconds: 20),
      ).resolve(_typed);
      expect(r, isA<DeviceLine>());
    });

    test('the device voice speaks when the server has no voice', () async {
      expect(await resolver().resolve(_typed), isA<DeviceLine>());
      final off = resolver(fetch: ok, enabled: false);
      expect(await off.resolve(_typed), isA<DeviceLine>());
      expect(fetched, isEmpty);
    });
  });

  group('prefetch', () {
    test('asks once, and the line is ready when its turn comes', () async {
      final r = resolver(fetch: ok)..prefetch([_typed, _typed]);
      expect(fetched, [_typed.text]);
      expect(await r.resolve(_typed), isA<ServerLine>());
      expect(fetched, [_typed.text], reason: 'resolved from the prefetched audio');
    });

    test('skips bundled lines and does nothing without a server voice', () {
      resolver(fetch: ok).prefetch([_bundled]);
      resolver(fetch: ok, enabled: false).prefetch([_typed]);
      resolver().prefetch([_typed]);
      expect(fetched, isEmpty);
    });

    test('a failed fetch is tried again later', () async {
      var attempts = 0;
      final r = resolver(
        fetch: (t) async {
          if (++attempts == 1) throw StateError('once');
          return _audio(t);
        },
      )..prefetch([_typed]);
      expect(await r.resolve(_typed), isA<DeviceLine>());
      expect(await r.resolve(_typed), isA<ServerLine>());
    });

    test('keeps only the most recent lines in memory', () async {
      final r = resolver(fetch: ok, keep: 2);
      for (final t in ['a', 'b', 'c']) {
        await r.resolve(VoiceLine(t));
      }
      fetched.clear();
      await r.resolve(const VoiceLine('c'));
      expect(fetched, isEmpty);
      await r.resolve(const VoiceLine('a'));
      expect(fetched, ['a']);
    });
  });
}
