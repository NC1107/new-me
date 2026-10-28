/// Wire models for itemized meal estimates and the household food library. Parsing is tolerant:
/// a field the server leaves out reads as "nothing", and an old server without `items` degrades
/// to the single-meal estimate.
library;

import 'v6_models.dart';

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

double _dbl(Object? v, [double fallback = 0]) => (v as num?)?.toDouble() ?? fallback;

String _str(Object? v, [String fallback = '']) => v as String? ?? fallback;

double _tenth(double v) => (v * 10).round() / 10;

String _plain(double v) => v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Where an item's numbers came from.
enum FoodSource {
  usda('USDA'),
  openfoodfacts('Label'),
  library('Saved'),
  manual('Label'),
  estimated('Estimated');

  const FoodSource(this.chip);

  /// The word on the small source chip.
  final String chip;

  static FoodSource parse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return estimated;
  }

  /// Numbers a person can trust without checking: a database row or a label.
  bool get fromDatabase => this == usda || this == openfoodfacts || this == manual;
}

/// One alternate serving of a saved food.
class FoodServing {
  const FoodServing({required this.text, required this.grams});

  factory FoodServing.fromJson(Map<String, dynamic> j) =>
      FoodServing(text: _str(j['text']), grams: _dbl(j['grams']));

  final String text;
  final double grams;

  Map<String, dynamic> toJson() => {'text': text, 'grams': grams};
}

/// A food in the household library, or an unsaved candidate from a database (id null).
class SavedFood {
  const SavedFood({
    this.id,
    required this.name,
    this.brand = '',
    required this.servingText,
    this.servingGrams = 0,
    required this.kcal,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.fiber = 0,
    this.source = FoodSource.manual,
    this.sourceId = '',
    this.servings = const [],
    this.useCount = 0,
    this.lastUsedAt,
    this.imageUrl,
    this.sourceUrl,
  });

  factory SavedFood.fromJson(Map<String, dynamic> j) => SavedFood(
    id: (j['id'] as num?)?.toInt(),
    name: _str(j['name']),
    brand: _str(j['brand']),
    servingText: _str(j['servingText'], '1 serving'),
    servingGrams: _dbl(j['servingGrams']),
    kcal: _int(j['kcal']),
    protein: _dbl(j['protein']),
    carbs: _dbl(j['carbs']),
    fat: _dbl(j['fat']),
    fiber: _dbl(j['fiber']),
    source: FoodSource.parse(j['source']),
    sourceId: _str(j['sourceId']),
    servings: [
      if (j['servings'] is List)
        for (final s in j['servings'] as List)
          if (s is Map) FoodServing.fromJson(s.cast<String, dynamic>()),
    ],
    useCount: _int(j['useCount']),
    lastUsedAt: _time(j['lastUsedAt']),
    imageUrl: _url(j['imageUrl']),
    sourceUrl: _url(j['sourceUrl']),
  );

  final int? id;
  final String name;
  final String brand;

  /// What one serving is, such as "1 medium (182 g)".
  final String servingText;
  final double servingGrams;
  final int kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final FoodSource source;
  final String sourceId;
  final List<FoodServing> servings;
  final int useCount;
  final DateTime? lastUsedAt;

  /// Open Food Facts photo and product page; null for saved foods and USDA rows.
  final String? imageUrl;
  final String? sourceUrl;

  bool get saved => id != null;

  /// The name with its brand, for lists.
  String get title =>
      brand.isEmpty || name.toLowerCase().contains(brand.toLowerCase()) ? name : '$brand $name';

  Map<String, dynamic> toJson() => {
    'name': name,
    'brand': brand,
    'servingText': servingText,
    'servingGrams': servingGrams,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'source': source.name,
    'sourceId': sourceId,
    'servings': [for (final s in servings) s.toJson()],
  };
}

/// What GET /foods answers: saved foods first, then unsaved database candidates.
class FoodSearch {
  const FoodSearch({this.foods = const [], this.candidates = const []});

  factory FoodSearch.fromJson(Map<String, dynamic> j) =>
      FoodSearch(foods: _foods(j['foods']), candidates: _foods(j['candidates']));

  static List<SavedFood> _foods(Object? v) => [
    if (v is List)
      for (final f in v)
        if (f is Map) SavedFood.fromJson(f.cast<String, dynamic>()),
  ];

  final List<SavedFood> foods;
  final List<SavedFood> candidates;
}

/// One food of a described meal. Numbers scale with [quantity] from the per-unit values taken
/// when the item was built, so stepping up and back down never drifts.
class MealItem {
  const MealItem._({
    required this.text,
    required this.name,
    required this.brand,
    required this.quantity,
    required this.unit,
    required this.source,
    required this.sourceId,
    required this.matchedName,
    required this.confidence,
    required this.origin,
    required this.perKcal,
    required this.perProtein,
    required this.perCarbs,
    required this.perFat,
    required this.perFiber,
    required this.perGrams,
    required this.saveToLibrary,
    required this.servingText,
  });

  /// An item from the estimate endpoint.
  factory MealItem.fromJson(Map<String, dynamic> j) {
    final q = _dbl(j['quantity'], 1);
    final quantity = q > 0 ? q : 1.0;
    return MealItem._(
      text: _str(j['text']),
      name: _str(j['name'], _str(j['text'], 'Food')),
      brand: _str(j['brand']),
      quantity: quantity,
      unit: _str(j['unit'], 'serving'),
      source: FoodSource.parse(j['source']),
      sourceId: _str(j['sourceId']),
      matchedName: _str(j['matchedName']),
      confidence: EstimateConfidence.parse(j['confidence']),
      origin: FoodSource.parse(j['origin']),
      perKcal: _dbl(j['kcal']) / quantity,
      perProtein: _dbl(j['protein']) / quantity,
      perCarbs: _dbl(j['carbs']) / quantity,
      perFat: _dbl(j['fat']) / quantity,
      perFiber: _dbl(j['fiber']) / quantity,
      perGrams: _dbl(j['grams']) / quantity,
      saveToLibrary: false,
      servingText: '',
    );
  }

  /// A saved food or a database candidate added with one serving.
  factory MealItem.fromFood(SavedFood f) => MealItem._(
    text: f.title,
    name: f.name,
    brand: f.brand,
    quantity: 1,
    unit: f.unitLabel,
    source: f.saved ? FoodSource.library : f.source,
    sourceId: f.saved ? '${f.id}' : f.sourceId,
    matchedName: f.title,
    confidence: EstimateConfidence.high,
    origin: f.saved ? f.source : FoodSource.estimated,
    perKcal: f.kcal.toDouble(),
    perProtein: f.protein,
    perCarbs: f.carbs,
    perFat: f.fat,
    perFiber: f.fiber,
    perGrams: f.servingGrams,
    saveToLibrary: false,
    servingText: f.servingText,
  );

  final String text;
  final String name;
  final String brand;
  final double quantity;
  final String unit;
  final FoodSource source;
  final String sourceId;
  final String matchedName;
  final EstimateConfidence confidence;

  /// For a saved food, where its numbers first came from.
  final FoodSource origin;
  final bool saveToLibrary;

  /// The full serving wording of a candidate, kept for saving it unchanged.
  final String servingText;

  /// Numbers for one unit of the item.
  final double perKcal;
  final double perProtein;
  final double perCarbs;
  final double perFat;
  final double perFiber;
  final double perGrams;

  int get kcal => (perKcal * quantity).round().clamp(0, 10000);
  double get protein => _tenth(perProtein * quantity);
  double get carbs => _tenth(perCarbs * quantity);
  double get fat => _tenth(perFat * quantity);
  double get fiber => _tenth(perFiber * quantity);
  double get grams => _tenth(perGrams * quantity);

  /// Counts toward "from nutrition databases": a database row, a label, or a saved food that
  /// began as one.
  bool get fromDatabase => source == FoodSource.library ? origin.fromDatabase : source.fromDatabase;

  /// A saved food, a database food (saved when logged) or an estimate the person chose to keep.
  bool get willSave => source != FoodSource.library && (source.fromDatabase || saveToLibrary);

  MealItem _copy({String? name, double? quantity, bool? saveToLibrary}) => MealItem._(
    text: text,
    name: name ?? this.name,
    brand: brand,
    quantity: quantity ?? this.quantity,
    unit: unit,
    source: source,
    sourceId: sourceId,
    matchedName: matchedName,
    confidence: confidence,
    origin: origin,
    perKcal: perKcal,
    perProtein: perProtein,
    perCarbs: perCarbs,
    perFat: perFat,
    perFiber: perFiber,
    perGrams: perGrams,
    saveToLibrary: saveToLibrary ?? this.saveToLibrary,
    servingText: servingText,
  );

  MealItem withQuantity(double q) => _copy(quantity: q);

  MealItem withName(String n) => _copy(name: n);

  MealItem withSave(bool v) => _copy(saveToLibrary: v);

  /// This item as a library entry: the numbers for one unit.
  SavedFood toSavedFood() {
    final perUnitGrams = _tenth(perGrams);
    final text = servingText.isNotEmpty
        ? servingText
        : '1 $unit${perUnitGrams > 0 && !unit.contains('g)') ? ' (${_plain(perUnitGrams)} g)' : ''}';
    return SavedFood(
      name: name,
      brand: brand,
      servingText: text,
      servingGrams: perUnitGrams,
      kcal: perKcal.round(),
      protein: _tenth(perProtein),
      carbs: _tenth(perCarbs),
      fat: _tenth(perFat),
      fiber: _tenth(perFiber),
      source: source,
      sourceId: sourceId,
    );
  }
}

extension on SavedFood {
  /// The serving without its leading amount: "1 medium (182 g)" counts in "medium (182 g)".
  String get unitLabel {
    final stripped = servingText.replaceFirst(RegExp(r'^\s*[\d./]+(\s+\d+/\d+)?\s*'), '').trim();
    return stripped.isEmpty ? 'serving' : stripped;
  }
}

/// The answer to POST /meals/estimate. [items] is empty from a server that predates itemizing;
/// [legacy] then carries the single-meal numbers.
class MealBreakdown {
  const MealBreakdown({required this.items, required this.legacy});

  factory MealBreakdown.fromJson(Map<String, dynamic> j) => MealBreakdown(
    items: [
      if (j['items'] is List)
        for (final i in j['items'] as List)
          if (i is Map) MealItem.fromJson(i.cast<String, dynamic>()),
    ],
    legacy: MealEstimate.fromJson(j),
  );

  final List<MealItem> items;
  final MealEstimate legacy;
}

String? _url(Object? v) => v is String && v.isNotEmpty ? v : null;
