import 'package:flutter/widgets.dart';

import '../util/units.dart';

/// Makes the person's units readable anywhere below as `context.units`, the way the theme is.
class UnitsScope extends InheritedWidget {
  const UnitsScope({super.key, required this.units, required super.child});

  final Units units;

  @override
  bool updateShouldNotify(UnitsScope oldWidget) => oldWidget.units != units;
}

extension UnitsContext on BuildContext {
  /// Metric when no scope is above, as in a test that pumps a bare widget.
  Units get units => dependOnInheritedWidgetOfExactType<UnitsScope>()?.units ?? Units.metric;
}
