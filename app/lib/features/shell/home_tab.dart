import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session.dart';

enum HomeTab { today, food, train, board, me }

/// The selected bottom tab, a provider so a screen can send the user to another one.
class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() {
    // A new session starts on Today instead of wherever the last one left off.
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    return HomeTab.today;
  }

  void select(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);
