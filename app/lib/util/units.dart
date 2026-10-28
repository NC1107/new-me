import 'format.dart';

/// Kilograms in a pound (exact by definition).
const kKgPerLb = 0.45359237;

/// Centimetres in an inch (exact by definition).
const kCmPerInch = 2.54;

/// What a person reads: metric, or pounds, feet and inches. Everything is stored metric.
enum Units {
  metric,
  imperial;

  /// An unknown or missing word reads as metric, the server's default.
  static Units parse(Object? v) => v == 'imperial' ? Units.imperial : Units.metric;

  bool get isImperial => this == Units.imperial;

  /// "lb" or "kg".
  String get weightUnit => isImperial ? 'lb' : 'kg';

  /// A weight in this unit's number, from kg.
  double weightIn(double kg) => isImperial ? kg / kKgPerLb : kg;

  /// A weight in kg, from this unit's number.
  double weightToKg(double v) => isImperial ? v * kKgPerLb : v;

  /// "181.7 lb" or "82.4 kg", joined by a non-breaking space so a wrap never strands the unit.
  String weight(double kg, {int decimals = 1}) =>
      '${_round(weightIn(kg), decimals).formatted} $weightUnit';

  /// A training load: pounds to the half pound, kilograms to the tenth.
  String load(double kg) {
    final v = isImperial ? (weightIn(kg) * 2).round() / 2 : _round(kg, 1);
    return '${v.formatted} $weightUnit';
  }

  /// "5 ft 10 in" or "178 cm".
  String height(double cm) {
    if (!isImperial) return '${_round(cm, 1).formatted} cm';
    final (feet, inches) = feetInches(cm);
    return '$feet ft $inches in';
  }

  /// A weekly weight-goal pace: "1 lb a week" or "0.5 kg a week".
  String pace(double kgPerWeek) {
    if (!isImperial) return '${_plain(_round(kgPerWeek, 2))} kg a week';
    final lb = (kgPerWeek / kKgPerLb * 4).round() / 4;
    return '${_plain(lb)} lb a week';
  }

  /// Paces offered for losing weight, stored in kg: 0.25 and 0.5 kg, or 0.5 and 1 lb.
  List<double> get losePaces => isImperial ? const [0.23, 0.45] : const [0.25, 0.5];

  /// Paces offered for gaining weight: 0.1, 0.25 and 0.5 kg, or 0.25, 0.5 and 1 lb.
  List<double> get gainPaces => isImperial ? const [0.11, 0.23, 0.45] : const [0.1, 0.25, 0.5];
}

/// Whole feet and the remaining inches, rounded to the inch.
(int, int) feetInches(double cm) {
  final total = (cm / kCmPerInch).round();
  return (total ~/ 12, total % 12);
}

/// Centimetres from feet and inches, to the tenth.
double cmFromFeetInches(int feet, double inches) => _round((feet * 12 + inches) * kCmPerInch, 1);

/// The default for a phone's region: the United States, Liberia and Myanmar use pounds and feet.
Units unitsForRegion(String? countryCode) =>
    const {'US', 'LR', 'MM'}.contains(countryCode?.toUpperCase()) ? Units.imperial : Units.metric;

double _round(double v, int decimals) {
  var f = 1.0;
  for (var i = 0; i < decimals; i++) {
    f *= 10;
  }
  return (v * f).round() / f;
}

/// 0.25 as "0.25", 1.0 as "1": up to two decimals without trailing zeros.
String _plain(double v) {
  final text = v.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
