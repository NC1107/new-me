import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'onboardingProgress';

/// What a person has answered so far, kept so leaving the app mid-flow resumes at the first
/// unanswered step. Written once the profile exists and removed when onboarding finishes.
@immutable
class OnboardingProgress {
  const OnboardingProgress({
    this.returning = false,
    this.name = '',
    this.focuses = const [],
    this.goals = const {},
    this.kcal,
    this.foodAnswered = false,
    this.planSaved = false,
    this.healthAnswered = false,
    this.reminderAnswered = false,
  });

  factory OnboardingProgress.fromJson(Map<String, dynamic> j) => OnboardingProgress(
    returning: j['returning'] as bool? ?? false,
    name: j['name'] as String? ?? '',
    focuses: [for (final f in j['focuses'] as List? ?? const []) f as String],
    goals: {
      for (final e in (j['goals'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
    kcal: (j['kcal'] as num?)?.toInt(),
    foodAnswered: j['foodAnswered'] as bool? ?? false,
    planSaved: j['planSaved'] as bool? ?? false,
    healthAnswered: j['healthAnswered'] as bool? ?? false,
    reminderAnswered: j['reminderAnswered'] as bool? ?? false,
  );

  /// A re-paired person skips the plan steps.
  final bool returning;
  final String name;
  final List<String> focuses;
  final Map<String, int> goals;
  final int? kcal;
  final bool foodAnswered;
  final bool planSaved;
  final bool healthAnswered;
  final bool reminderAnswered;

  Map<String, dynamic> toJson() => {
    'returning': returning,
    'name': name,
    'focuses': focuses,
    'goals': goals,
    'kcal': kcal,
    'foodAnswered': foodAnswered,
    'planSaved': planSaved,
    'healthAnswered': healthAnswered,
    'reminderAnswered': reminderAnswered,
  };

  static Future<OnboardingProgress?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kKey);
      if (raw == null) return null;
      return OnboardingProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (e) {
      debugPrint('[NEWME] onboarding progress unreadable: $e');
      return null;
    }
  }

  Future<void> save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_kKey, jsonEncode(toJson()));
    } on Object catch (e) {
      debugPrint('[NEWME] onboarding progress not saved: $e');
    }
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_kKey);
    } on Object catch (e) {
      debugPrint('[NEWME] onboarding progress not cleared: $e');
    }
  }
}
