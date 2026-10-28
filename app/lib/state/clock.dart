import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/format.dart';

/// Every time-dependent rule reads the clock through this, so tests can move time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ticks once a minute, so a label such as "5m ago" that watches it never goes stale.
final minuteTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream.periodic(const Duration(minutes: 1), (i) => i),
);

/// The one wording of when Health last synced, shared by every screen that shows it.
String lastSyncLabel(WidgetRef ref, DateTime synced) {
  ref.watch(minuteTickProvider);
  return 'Last sync ${relativeTime(synced, ref.watch(clockProvider)())}';
}
