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
  }

  /// Follows the phone to a new time zone, but leaves a zone the user picked by hand alone:
  /// only a change of the device zone since the last run is pushed.
  Future<void> syncDeviceTimezone() async {
    final me = (await future).data;
    final device = await ref.read(deviceTimezoneProvider)();
    if (device == null) return;
    final known = await LocalPrefs.deviceTimezone();
    await LocalPrefs.setDeviceTimezone(device);
    if (known == null || known == device || me.user.timezone == device) return;
    await save(MePatch(timezone: device));
  }
}

final meProvider = AsyncNotifierProvider<MeNotifier, Cached<Me>>(MeNotifier.new);
