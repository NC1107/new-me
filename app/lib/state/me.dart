import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';
import 'local_prefs.dart';
import 'session.dart';
import 'units.dart';
import 'targets.dart';
import 'timezone.dart';
import 'today.dart';

class MeNotifier extends CachedNotifier<Me> {
  @override
  ResponseCache<Me> get cache => meCache;

  @override
  Future<Me> fetch(ApiClient client) => client.me();

  /// Saves a partial edit. Failures are thrown so the form can show them beside the field.
  Future<void> save(MePatch patch) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final me = await client.patchMe(patch);
    await replace(me);
    if (patch.name != null || patch.color != null) {
      await ref
          .read(sessionProvider.notifier)
          .updateProfile(name: me.user.name, color: me.user.color);
      if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
    }
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
    // Height, sex, goal and birth year all feed the formulas.
    if (ref.exists(targetsProvider)) unawaited(ref.read(targetsProvider.notifier).refresh());
  }

  /// Links Audiobookshelf. The server counts the listening it finds into today's reading quest
  /// before it answers, so Me, Today and the Board are all reloaded. Failures are thrown.
  Future<void> linkAudiobookshelf({required String username, required String password}) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    await client.linkAudiobookshelf(username: username, password: password);
    await _reloadAfterListeningChange();
  }

  Future<void> unlinkAudiobookshelf() async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    await client.unlinkAudiobookshelf();
    await _reloadAfterListeningChange();
  }

  Future<void> _reloadAfterListeningChange() async {
    await refresh();
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
    if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
  }

  /// Fills in units once for someone who joined before they existed, from the phone's region,
  /// so server-written text and the app agree. A choice already made is never touched.
  Future<void> fillUnitsFromRegion() async {
    final me = (await future).data;
    if (me.user.units != null) return;
    await save(MePatch(units: ref.read(regionUnitsProvider)));
  }

  /// Follows the phone to a new time zone, but leaves a zone the user picked by hand alone:
  /// only a change of the device zone since the last run is pushed. Returns whether the device
  /// zone changed since the last run, which also means local reminders need replanning.
  Future<bool> syncDeviceTimezone() async {
    final me = (await future).data;
    final device = await ref.read(deviceTimezoneProvider)();
    if (device == null) return false;
    final known = await LocalPrefs.deviceTimezone();
    if (known == device) return false;
    if (known == null) {
      await LocalPrefs.setDeviceTimezone(device);
      return false;
    }
    // The zone is remembered only once the server has it, so a failed save is retried on the
    // next resume instead of being forgotten.
    if (me.user.timezone != device) await save(MePatch(timezone: device));
    await LocalPrefs.setDeviceTimezone(device);
    return true;
  }
}

final meProvider = AsyncNotifierProvider<MeNotifier, Cached<Me>>(MeNotifier.new);
