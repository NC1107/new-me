import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Flips on when any request is answered with 426. The root gate then blocks the whole app.
class UpdateGate extends Notifier<bool> {
  @override
  bool build() => false;

  void require() => state = true;
}

final updateGateProvider = NotifierProvider<UpdateGate, bool>(UpdateGate.new);
