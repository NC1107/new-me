import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'log_actions.dart';

/// The saved foods for My foods, most used first. Invalidate it after a save or delete.
final foodLibraryProvider = FutureProvider.autoDispose<List<SavedFood>>(
  (ref) async => (await ref.read(logActionsProvider).searchFoods('')).foods,
);
