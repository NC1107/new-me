import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../health/health_source.dart';
import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../state/targets.dart';
import '../../state/today.dart';
import '../../state/units.dart';
import '../../util/errors.dart';
import '../insights/birth_year_sheet.dart' show kEarliestBirthYear;

/// The questions of "About you", in the order they are asked. The last one only shows the result.
enum AboutQuestion { birthYear, sex, height, weight, goal, review }

const kHeightRange = (min: 100.0, max: 250.0);
const kWeightRange = (min: 20.0, max: 400.0);

/// The targets that make up the final screen, in the order the research doc lists them.
const kReviewKeys = ['calories', 'protein', 'fat', 'carbs', 'fiber', 'sleep', 'water'];

/// The inputs a targets report is waiting for, as the questions that supply them.
Set<AboutQuestion> missingQuestions(TargetsReport report) => {
  for (final input in report.inputs)
    if (input.isMissing)
      ?switch (input.key) {
        'age' => AboutQuestion.birthYear,
        'sex' => AboutQuestion.sex,
        'heightCm' => AboutQuestion.height,
        'weightKg' => AboutQuestion.weight,
        _ => null,
      },
};

/// Where "Finish your setup" starts: the first of the four measurements still missing.
AboutQuestion? firstMissingQuestion(TargetsReport report) {
  final missing = missingQuestions(report);
  return [
    for (final q in AboutQuestion.values)
      if (missing.contains(q)) q,
  ].firstOrNull;
}

/// The question a "Needed to work these out" row opens, by the input's key.
AboutQuestion? questionForInput(String key) => switch (key) {
  'age' => AboutQuestion.birthYear,
  'sex' => AboutQuestion.sex,
  'heightCm' => AboutQuestion.height,
  'weightKg' => AboutQuestion.weight,
  _ => null,
};

double? parseDecimal(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

@immutable
class AboutYouState {
  const AboutYouState({
    this.ready = false,
    this.birthYear = '',
    this.sex,
    this.units = Units.metric,
    this.heightCm,
    this.heightTyped = true,
    this.heightEdited = false,
    this.heightFromHealth = false,
    this.weight = '',
    this.weightFromHealth = false,
    this.kind = GoalKind.maintain,
    this.pace = 0,
    this.busy = false,
    this.error,
    this.applyError,
  });

  /// False until the person's profile and targets have been read, so no field flashes empty
  /// before a prefilled value arrives.
  final bool ready;
  final String birthYear;
  final String? sex;

  /// What the person reads; the weight is typed in it.
  final Units units;

  /// The height in cm, or null while empty or impossible.
  final double? heightCm;

  /// False while the height field holds something impossible, so Continue waits.
  final bool heightTyped;

  /// True once the person typed a height, so a late Health value never replaces it.
  final bool heightEdited;

  /// The prefilled value came from Apple Health and has not been edited.
  final bool heightFromHealth;

  /// The weight as typed, in [units].
  final String weight;
  final bool weightFromHealth;
  final GoalKind kind;
  final double pace;
  final bool busy;
  final String? error;
  final String? applyError;

  int? get birthYearValue {
    final year = int.tryParse(birthYear.trim());
    return year != null && year >= kEarliestBirthYear ? year : null;
  }

  double? get heightValue => heightCm;

  /// The typed weight in kg.
  double? get weightValue {
    final v = parseDecimal(weight);
    return v == null ? null : (units.weightToKg(v) * 10).round() / 10;
  }

  bool get heightValid =>
      heightCm != null && heightCm! >= kHeightRange.min && heightCm! <= kHeightRange.max;
  bool get weightValid =>
      weightValue != null && weightValue! >= kWeightRange.min && weightValue! <= kWeightRange.max;

  GoalSetting get goal => GoalSetting(kind: kind, paceKgPerWeek: pace);

  AboutYouState copyWith({
    bool? ready,
    String? birthYear,
    String? sex,
    bool clearSex = false,
    Units? units,
    double? heightCm,
    bool clearHeight = false,
    bool? heightTyped,
    bool? heightEdited,
    bool? heightFromHealth,
    String? weight,
    bool? weightFromHealth,
    GoalKind? kind,
    double? pace,
    bool? busy,
    String? error,
    bool clearError = false,
    String? applyError,
    bool clearApplyError = false,
  }) => AboutYouState(
    ready: ready ?? this.ready,
    birthYear: birthYear ?? this.birthYear,
    sex: clearSex ? null : (sex ?? this.sex),
    units: units ?? this.units,
    heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
    heightTyped: heightTyped ?? this.heightTyped,
    heightEdited: heightEdited ?? this.heightEdited,
    heightFromHealth: heightFromHealth ?? this.heightFromHealth,
    weight: weight ?? this.weight,
    weightFromHealth: weightFromHealth ?? this.weightFromHealth,
    kind: kind ?? this.kind,
    pace: pace ?? this.pace,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    applyError: clearApplyError ? null : (applyError ?? this.applyError),
  );
}

/// Holds the answers on screen while someone moves through the questions, and saves each one as
/// it is confirmed: birth year, sex, height and goal through PATCH /api/me, weight as a manual
/// reading. Nothing is saved for a question that was skipped or left as prefilled.
class AboutYouController extends Notifier<AboutYouState> {
  Future<void>? _seeding;

  @override
  AboutYouState build() => const AboutYouState();

  /// Reads what is already known; Apple Health values come through the targets inputs, because
  /// the server picks the newest Health height and the weight trend.
  Future<void> begin() => _seeding = _seed();

  /// Starts once per flow; a screen that rebuilds, or a step walked back to, keeps its answers.
  Future<void> ensureBegun() => _seeding ?? begin();

  Future<void> _seed() async {
    state = const AboutYouState();
    try {
      await ref.read(targetsProvider.notifier).refresh();
    } on Object catch (e) {
      debugPrint('[NEWME] about you: targets unavailable: $e');
    }
    Me? me;
    try {
      me = (await ref.read(meProvider.future)).data;
    } on Object catch (e) {
      debugPrint('[NEWME] about you: profile unavailable: $e');
    }
    final report = ref.read(targetsProvider).value?.data;
    final user = me?.user;
    final healthHeight = report?.input('heightCm');
    final healthWeight = report?.input('weightKg');
    final height = user?.heightCm ?? _health(healthHeight);
    final weight = _health(healthWeight);
    final goal = user?.goalSetting ?? const GoalSetting();
    final units = ref.read(unitsProvider);
    state = AboutYouState(
      ready: true,
      units: units,
      birthYear: user?.birthYear?.toString() ?? '',
      sex: user?.sex,
      heightCm: height,
      heightFromHealth: user?.heightCm == null && height != null,
      weight: weight == null ? '' : _plain(units.weightIn(weight)),
      weightFromHealth: weight != null,
      kind: goal.kind,
      pace: goal.paceKgPerWeek,
    );
    unawaited(_fillFromHealthLater());
  }

  /// Health's first sync may still be running when the questions open; once it lands, a height
  /// or weight it shared fills the fields that are still empty and were not typed in.
  Future<void> _fillFromHealthLater() async {
    final sync = ref.read(healthSyncProvider.notifier);
    if (!ref.read(healthSyncProvider).syncing) return;
    await sync.whenIdle();
    try {
      await ref.read(targetsProvider.notifier).refresh();
    } on Object catch (e) {
      debugPrint('[NEWME] about you: targets unavailable after sync: $e');
      return;
    }
    final report = ref.read(targetsProvider).value?.data;
    final height = _health(report?.input('heightCm'));
    final weight = _health(report?.input('weightKg'));
    final s = state;
    state = s.copyWith(
      heightCm: s.heightCm == null && !s.heightEdited ? height : null,
      heightFromHealth: s.heightCm == null && !s.heightEdited && height != null ? true : null,
      weight: s.weight.isEmpty && weight != null ? _plain(s.units.weightIn(weight)) : null,
      weightFromHealth: s.weight.isEmpty && weight != null ? true : null,
    );
  }

  double? _health(TargetInput? input) =>
      input != null && !input.isMissing && input.source == 'health' && input.value is num
      ? (input.value! as num).toDouble()
      : null;

  String _plain(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  void setBirthYear(String v) => state = state.copyWith(birthYear: v, clearError: true);

  void setSex(String v) => state = state.copyWith(sex: v, clearError: true);

  void setHeight(double? cm, {required bool valid}) => state = state.copyWith(
    heightCm: cm,
    clearHeight: cm == null,
    heightTyped: valid,
    heightEdited: true,
    heightFromHealth: false,
    clearError: true,
  );

  void setWeight(String v) =>
      state = state.copyWith(weight: v, weightFromHealth: false, clearError: true);

  void setKind(GoalKind kind) {
    if (kind == state.kind) return;
    state = state.copyWith(
      kind: kind,
      pace: switch (kind) {
        GoalKind.lose => state.units.losePaces.first,
        GoalKind.gain => state.units.gainPaces[1],
        GoalKind.maintain => 0,
      },
    );
  }

  void setPace(double pace) => state = state.copyWith(pace: pace);

  /// Saves the answer to [question] when it needs saving; true when the flow may move on.
  Future<bool> confirm(AboutQuestion question) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      await _save(question);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: errorCopy(e));
      return false;
    }
  }

  Future<void> _save(AboutQuestion question) async {
    final me = ref.read(meProvider).value?.data;
    final user = me?.user;
    switch (question) {
      case AboutQuestion.birthYear:
        final year = state.birthYearValue;
        if (year != null && year != user?.birthYear) {
          await ref.read(meProvider.notifier).save(MePatch(birthYear: year));
        }
      case AboutQuestion.sex:
        if (state.sex != null && state.sex != user?.sex) {
          await ref.read(meProvider.notifier).save(MePatch(sex: state.sex));
        }
      case AboutQuestion.height:
        final cm = state.heightValue;
        if (!state.heightFromHealth && cm != null && cm != user?.heightCm) {
          await ref.read(meProvider.notifier).save(MePatch(heightCm: cm));
        }
      case AboutQuestion.weight:
        final kg = state.weightValue;
        if (!state.weightFromHealth && kg != null) await _saveWeight(kg, me);
      case AboutQuestion.goal:
        if (state.goal != user?.goalSetting) {
          await ref.read(meProvider.notifier).save(MePatch(goal: state.goal));
        }
      case AboutQuestion.review:
        break;
    }
  }

  /// Saves birth year, sex, height and weight from the one-screen version in onboarding: one
  /// profile PATCH and, for a typed weight, one reading. True when the flow may move on.
  Future<bool> confirmBody() async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final me = ref.read(meProvider).value?.data;
      final user = me?.user;
      final year = state.birthYearValue;
      final cm = state.heightValid && !state.heightFromHealth ? state.heightCm : null;
      final patch = MePatch(
        birthYear: year != null && year != user?.birthYear ? year : null,
        sex: state.sex != null && state.sex != user?.sex ? state.sex : null,
        heightCm: cm != null && cm != user?.heightCm ? cm : null,
      );
      if (patch.birthYear != null || patch.sex != null || patch.heightCm != null) {
        await ref.read(meProvider.notifier).save(patch);
      }
      final kg = state.weightValue;
      if (state.weightValid && !state.weightFromHealth && kg != null) await _saveWeight(kg, me);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, error: errorCopy(e));
      return false;
    }
  }

  Future<void> _saveWeight(double kg, Me? me) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final now = ref.read(clockProvider)();
    await client.putHealthDaily([
      HealthItem(
        date: (me?.localToday.isNotEmpty ?? false) ? me!.localToday : _dateKey(now),
        metric: HealthMetric.weightKg,
        value: double.parse(kg.toStringAsFixed(1)),
        source: 'manual',
        measuredAt: now.toUtc(),
      ),
    ]);
    if (ref.exists(targetsProvider)) unawaited(ref.read(targetsProvider.notifier).refresh());
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
  }

  /// Applies the final screen's targets all or nothing; true when the flow may move on.
  Future<bool> applyTargets(List<String> keys) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearApplyError: true);
    try {
      await ref.read(targetsProvider.notifier).apply(keys);
      state = state.copyWith(busy: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, applyError: errorCopy(e));
      return false;
    }
  }
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final aboutYouProvider = NotifierProvider<AboutYouController, AboutYouState>(
  AboutYouController.new,
);
