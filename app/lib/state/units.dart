import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../util/units.dart';
import 'me.dart';

/// The phone region's default, used before the profile has loaded and during sign-up.
final regionUnitsProvider = Provider<Units>(
  (ref) => unitsForRegion(PlatformDispatcher.instance.locale.countryCode),
);

/// The choice made during sign-up, before there is a profile to hold it.
class SignupUnits extends Notifier<Units?> {
  @override
  Units? build() => null;

  void choose(Units units) => state = units;
}

final signupUnitsProvider = NotifierProvider<SignupUnits, Units?>(SignupUnits.new);

/// What the person reads: their profile's choice once loaded, then a sign-up choice, then the
/// region's default.
final unitsProvider = Provider<Units>((ref) {
  final me = ref.watch(meProvider.select((v) => v.value?.data.user.units));
  return me ?? ref.watch(signupUnitsProvider) ?? ref.watch(regionUnitsProvider);
});
