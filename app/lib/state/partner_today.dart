import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'session.dart';

/// The partner's today, read fresh each time their sheet opens.
final partnerTodayProvider = FutureProvider.autoDispose<PartnerToday>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return Future.error(StateError('Not signed in'));
  return client.partnerToday();
});
