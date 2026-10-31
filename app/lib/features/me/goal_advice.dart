import '../../api/models.dart';
import '../onboarding/goal_catalog.dart';

/// The personal recommendation for one daily goal, taken from GET /api/targets.
class GoalAdvice {
  const GoalAdvice(this.target);

  final Target target;

  int get value => target.value!;

  /// One plain line on where the number comes from.
  String get why => target.why;

  /// The short citation, "Paluch 2022, Ding 2025".
  String get cite => target.cite;

  /// Other published figures, each saying what it is.
  List<TargetAlternative> get alternatives => target.alternatives;

  /// What one serving looks like, for the fruit and vegetables goal.
  List<String> get servingExamples => [
    if (target.details['servingExamples'] is List)
      for (final e in target.details['servingExamples'] as List)
        if (e is String) e,
  ];
}

/// The recommendation behind [questKey], or null when the goal has no published figure, the
/// report has not loaded, or the server could not work the number out yet.
GoalAdvice? goalAdvice(String questKey, TargetsReport? report) {
  final key = kGoalSpecs[questKey]?.targetKey;
  final target = key == null ? null : report?.target(key);
  if (target == null || target.value == null) return null;
  return GoalAdvice(target);
}
