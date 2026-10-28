import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/session.dart';
import '../../state/training.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../log/log_chip.dart';
import 'how_to_sheet.dart';
import 'set_form.dart';
import 'strength_chart.dart';
import 'training_copy.dart';
import '../../widgets/units_scope.dart';

/// The muscle an exercise is listed under: its first primary muscle.
String groupOf(Exercise e) => e.primaryMuscles.firstOrNull ?? 'other';

/// Exercises whose name matches [query], grouped by muscle in the server's muscle order.
List<(String, List<Exercise>)> groupExercises(ExerciseCatalog catalog, String query) {
  final q = query.trim().toLowerCase();
  final matching = [
    for (final e in catalog.exercises)
      if (q.isEmpty || e.name.toLowerCase().contains(q)) e,
  ];
  final order = [...catalog.muscles, 'other'];
  return [
    for (final m in order)
      if (matching.where((e) => groupOf(e) == m).toList() case final list when list.isNotEmpty)
        (m, list),
  ];
}

/// The exercise library: search, the catalog by muscle, custom exercises, and each exercise's
/// sets and bests.
class ExercisesPage extends ConsumerStatefulWidget {
  const ExercisesPage({super.key});

  @override
  ConsumerState<ExercisesPage> createState() => _ExercisesPageState();
}

class _ExercisesPageState extends ConsumerState<ExercisesPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addCustom() async {
    final created = await showAppSheet<Exercise>(
      context,
      builder: (_) => const _CustomExerciseSheet(),
    );
    if (created != null && mounted) {
      unawaited(pushPage(context, ExercisePage(exerciseKey: created.key)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(exercisesProvider);
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final held = value.value;
    final cached = held != null && held.userId == userId ? held : null;
    final offline = cached?.offline;
    return PageScaffold(
      title: 'Exercises',
      banner: offline == null ? null : OfflineBanner(info: offline),
      footer: ChunkyButton.secondary(
        label: 'Add your own',
        icon: Icons.add_rounded,
        onPressed: _addCustom,
      ),
      children: [
        AppTextField(
          controller: _search,
          hint: 'Search exercises',
          semanticLabel: 'Search exercises',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (value.hasError) ...[
          ErrorBlock(
            title: 'Could not load exercises',
            error: value.error!,
            onRetry: ref.read(exercisesProvider.notifier).refresh,
          ),
          const SizedBox(height: 16),
        ],
        if (cached != null)
          _Library(groups: groupExercises(cached.data, _search.text))
        else if (!value.hasError)
          const SkeletonBlock(height: 240, radius: kRadiusCard),
      ],
    );
  }
}

class _Library extends StatelessWidget {
  const _Library({required this.groups});

  final List<(String, List<Exercise>)> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const EmptyState(icon: Icons.search_off_rounded, title: 'No exercise by that name');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (muscle, list) in groups) ...[
          FieldLabel(muscleLabel(muscle)),
          AppCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              // Inside the 2px border, so a row's splash stays within the card's corners.
              borderRadius: BorderRadius.circular(kRadiusCard - kBorderWidth),
              child: Column(
                children: [
                  for (final (i, e) in list.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: kBorder),
                    _ExerciseRow(
                      exercise: e,
                      onTap: () => pushPage(context, ExercisePage(exerciseKey: e.key)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise, required this.onTap});

  final Exercise exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final detail = e.best != null
        ? bestLabel(e.best!, context.units)
        : e.equipment.isEmpty
        ? (e.timed ? 'Hold, bodyweight' : 'Bodyweight')
        : e.equipment.map(equipmentLabel).join(', ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.custom ? '${e.name} (yours)' : e.name,
                    style: AppText.label.copyWith(color: kInk),
                  ),
                  Text(
                    detail,
                    style: AppText.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (!e.custom) HowToButton(exerciseKey: e.key, name: e.name),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}

/// One exercise: its best set and max test, a set log, a max test, and every set by day.
class ExercisePage extends ConsumerStatefulWidget {
  const ExercisePage({super.key, required this.exerciseKey});

  final String exerciseKey;

  @override
  ConsumerState<ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends ConsumerState<ExercisePage> {
  String? _error;

  Future<void> _logSet(Exercise e) async {
    final logged = await showAppSheet<bool>(
      context,
      builder: (_) => _SetSheet(exercise: e, maxTest: false),
    );
    if (logged == true) ref.invalidate(exerciseSetsProvider(e.key));
  }

  Future<void> _maxTest(Exercise e) =>
      showAppSheet<bool>(context, builder: (_) => _SetSheet(exercise: e, maxTest: true));

  Future<void> _deleteSet(ExerciseSet set) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this set?',
      message: setLabel(set, context.units),
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(trainingTodayProvider.notifier).deleteSet(set);
      ref.invalidate(exerciseSetsProvider(widget.exerciseKey));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    }
  }

  Future<void> _deleteExercise(Exercise e) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${e.name}?',
      message: 'Your logged sets of it stay in your history.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(exercisesProvider.notifier).deleteCustom(e);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = errorCopy(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = ref.watch(
      exercisesProvider.select((v) => v.value?.data.byKey(widget.exerciseKey)),
    );
    if (exercise == null) {
      return const PageScaffold(
        title: 'Exercise',
        children: [SkeletonBlock(height: 120, radius: kRadiusCard)],
      );
    }
    final e = exercise;
    final sets = ref.watch(exerciseSetsProvider(e.key));
    final muscles = [...e.primaryMuscles, ...e.secondaryMuscles].map(muscleLabel).join(', ');
    return PageScaffold(
      title: e.name,
      subtitle: muscles,
      footer: ChunkyButton(
        label: 'Log a set',
        icon: Icons.add_rounded,
        onPressed: () => _logSet(e),
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                e.best == null ? 'No sets yet' : bestLabel(e.best!, context.units),
                style: AppText.headline,
              ),
              if (e.best?.e1rmKg != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Estimated by the Epley formula, load x (1 + reps / 30); less accurate past about 10 reps.',
                  style: AppText.caption.copyWith(color: kInkMuted),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                e.maxTest == null
                    ? 'No max test yet'
                    : '${maxTestLabel(e.maxTest!)} on ${_day(e.maxTest!.date)}',
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
              const SizedBox(height: 12),
              ChunkyButton.secondary(
                label: 'How to do it',
                icon: Icons.info_outline_rounded,
                onPressed: () => showHowTo(context, exerciseKey: e.key, name: e.name),
              ),
              if (!e.loaded) ...[
                const SizedBox(height: 12),
                ChunkyButton.secondary(label: 'Record a max test', onPressed: () => _maxTest(e)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        switch (ref.watch(exerciseHistoryProvider(e.key))) {
          AsyncValue(:final value?) => StrengthChart(history: value, units: context.units),
          AsyncValue(:final error?) => ErrorBlock(
            title: 'Could not load the strength chart',
            error: error,
            onRetry: () async => ref.invalidate(exerciseHistoryProvider(e.key)),
          ),
          _ => const SkeletonBlock(height: 180, radius: kRadiusCard),
        },
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(error, style: AppText.label.copyWith(color: kDangerText)),
        ],
        const SizedBox(height: 20),
        const FieldLabel('Sets'),
        switch (sets) {
          AsyncValue(:final value?) when value.isEmpty => Text(
            'Logged sets show here, newest first.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          AsyncValue(:final value?) => _SetHistory(sets: value, onDelete: _deleteSet),
          AsyncValue(:final error?) => ErrorBlock(
            title: 'Could not load the sets',
            error: error,
            onRetry: () async => ref.invalidate(exerciseSetsProvider(e.key)),
          ),
          _ => const SkeletonBlock(height: 80, radius: kRadiusCard),
        },
        if (e.custom) ...[
          const SizedBox(height: 24),
          ChunkyButton.secondary(label: 'Delete exercise', onPressed: () => _deleteExercise(e)),
        ],
      ],
    );
  }
}

String _day(String date) =>
    date.isEmpty ? '' : DateFormat('EEE d MMM').format(parseLocalDate(date));

/// A day's sets in the order they were done, newest day first. The server lists sets oldest
/// first.
class _SetHistory extends StatelessWidget {
  const _SetHistory({required this.sets, required this.onDelete});

  final List<ExerciseSet> sets;
  final ValueChanged<ExerciseSet> onDelete;

  @override
  Widget build(BuildContext context) {
    final days = <String, List<ExerciseSet>>{};
    for (final s in sets) {
      days.putIfAbsent(s.localDate, () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: date, value: daySets) in days.entries.toList().reversed) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_day(date), style: AppText.caption.copyWith(color: kInkMuted)),
                const SizedBox(height: 4),
                for (final s in daySets)
                  InkWell(
                    onLongPress: () => onDelete(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              setLabel(s, context.units),
                              style: AppText.tabular(AppText.label.copyWith(color: kInk)),
                            ),
                          ),
                          Text(rirLabel(s.rir), style: AppText.caption),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text('Long press a set to delete it.', style: AppText.caption.copyWith(color: kInkMuted)),
      ],
    );
  }
}

class _SetSheet extends ConsumerStatefulWidget {
  const _SetSheet({required this.exercise, required this.maxTest});

  final Exercise exercise;
  final bool maxTest;

  @override
  ConsumerState<_SetSheet> createState() => _SetSheetState();
}

class _SetSheetState extends ConsumerState<_SetSheet> {
  final _opId = newClientOpId();
  String? _error;

  Future<void> _save(SetValues v) async {
    final e = widget.exercise;
    setState(() => _error = null);
    try {
      if (widget.maxTest) {
        await ref.read(exercisesProvider.notifier).recordMaxTest(e, v.amount);
      } else {
        await ref
            .read(trainingTodayProvider.notifier)
            .logSet(
              SetDraft(
                clientOpId: _opId,
                exercise: e.key,
                reps: e.timed ? null : v.amount,
                seconds: e.timed ? v.amount : null,
                loadKg: v.loadKg,
                rir: v.rir,
              ),
            );
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = errorCopy(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        0,
        kGutter,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.maxTest ? 'Max test' : e.name, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              widget.maxTest
                  ? 'One ${e.timed ? 'hold' : 'set'} to near failure with good form.'
                  : 'Counts toward today.',
              style: AppText.caption,
            ),
            const SizedBox(height: 20),
            SetForm(
              timed: e.timed,
              loaded: e.loaded && !widget.maxTest,
              initialAmount: e.timed ? 30 : 8,
              initialLoadKg: e.best?.loadKg,
              buttonLabel: widget.maxTest ? 'Save max test' : 'Log set',
              onLog: _save,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: AppText.label.copyWith(color: kDangerText)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomExerciseSheet extends ConsumerStatefulWidget {
  const _CustomExerciseSheet();

  @override
  ConsumerState<_CustomExerciseSheet> createState() => _CustomExerciseSheetState();
}

class _CustomExerciseSheetState extends ConsumerState<_CustomExerciseSheet> {
  final _name = TextEditingController();
  String? _muscle;
  Measure _measure = Measure.reps;
  LoadKind _load = LoadKind.bodyweight;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready => _name.text.trim().isNotEmpty && _muscle != null;

  Future<void> _save() async {
    if (!_ready || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(exercisesProvider.notifier)
          .createCustom(name: _name.text.trim(), muscle: _muscle!, measure: _measure, load: _load);
      if (mounted) Navigator.of(context).pop(created);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muscles = ref.watch(exercisesProvider.select((v) => v.value?.data.muscles)) ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        0,
        kGutter,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add an exercise', style: AppText.title),
            const SizedBox(height: 4),
            const Text('Only you see your own exercises.', style: AppText.caption),
            const SizedBox(height: 16),
            const FieldLabel('Name'),
            AppTextField(
              controller: _name,
              hint: 'For example: kettlebell swing',
              semanticLabel: 'Name',
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Main muscle'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in muscles)
                  LogChip(
                    label: muscleLabel(m),
                    selected: _muscle == m,
                    onTap: () => setState(() => _muscle = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel('Counted in'),
            Row(
              children: [
                for (final (i, m) in Measure.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: LogChip(
                      label: m == Measure.reps ? 'Reps' : 'Seconds',
                      selected: _measure == m,
                      onTap: () => setState(() => _measure = m),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const FieldLabel('Load'),
            Row(
              children: [
                for (final (i, l) in LoadKind.values.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: LogChip(
                      label: l == LoadKind.bodyweight ? 'Bodyweight' : 'Weights',
                      selected: _load == l,
                      onTap: () => setState(() => _load = l),
                    ),
                  ),
                ],
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: AppText.label.copyWith(color: kDangerText)),
            ],
            const SizedBox(height: 20),
            ChunkyButton(label: 'Add exercise', busy: _saving, onPressed: _ready ? _save : null),
          ],
        ),
      ),
    );
  }
}
