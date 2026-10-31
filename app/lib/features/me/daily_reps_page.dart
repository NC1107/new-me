import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/daily_reps_models.dart';
import '../../state/daily_reps.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/choice_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../log/log_chip.dart';
import 'me_support.dart';
import 'number_field.dart';

/// The most a max test takes here; the server holds the same bound.
const kMaxRepsMax = 200;

/// The most a self-chosen starting set takes.
const kMaxStartingReps = 150;

/// Pick the exercise the push-ups quest counts and size the daily target from a max test: three
/// sets at 75% of one set to near failure (docs/design-v18-daily-reps.md). It saves on its own
/// and pops the saved [DailyReps].
class DailyRepsPage extends ConsumerStatefulWidget {
  const DailyRepsPage({super.key});

  @override
  ConsumerState<DailyRepsPage> createState() => _DailyRepsPageState();
}

class _DailyRepsPageState extends ConsumerState<DailyRepsPage> {
  String? _exercise;
  bool _knowsMax = true;
  final _field = TextEditingController();
  Timer? _debounce;
  int? _previewMax;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _start(DailyReps data) {
    _exercise = data.exercise;
    _fillFrom(data.option(data.exercise));
  }

  void _fillFrom(RepsExerciseOption? option) {
    final max = option?.latestMax?.reps;
    _field.text = max == null ? '' : '$max';
    _knowsMax = true;
    _previewMax = max;
  }

  int? get _typed => int.tryParse(_field.text);

  bool get _valid {
    final n = _typed;
    if (n == null || n < 1) return false;
    return n <= (_knowsMax ? kMaxRepsMax : kMaxStartingReps);
  }

  String? get _fieldError {
    final n = _typed;
    final cap = _knowsMax ? kMaxRepsMax : kMaxStartingReps;
    if (n != null && n > cap) return 'At most $cap';
    return null;
  }

  void _pick(RepsExerciseOption option) {
    HapticFeedback.selectionClick();
    setState(() {
      _exercise = option.key;
      _error = null;
      _fillFrom(option);
    });
  }

  void _setMode({required bool knowsMax}) {
    if (_knowsMax == knowsMax) return;
    HapticFeedback.selectionClick();
    setState(() {
      _knowsMax = knowsMax;
      _field.clear();
      _previewMax = null;
      _error = null;
    });
  }

  void _typedChanged() {
    setState(() => _error = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _previewMax = _knowsMax && _valid ? _typed : null);
    });
  }

  Future<void> _save(DailyReps data) async {
    final n = _typed;
    final exercise = _exercise;
    if (n == null || exercise == null || !_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(dailyRepsActionsProvider)
          .save(exercise: exercise, max: _knowsMax ? n : null, repsPerSet: _knowsMax ? null : n);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final waits = saved.dayExercise != saved.exercise;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              waits
                  ? 'Saved. Today still counts ${repsLabel(saved, saved.dayExercise)}; '
                        '${repsLabel(saved, saved.exercise)} start tomorrow.'
                  : _knowsMax
                  ? 'Saved: ${saved.target.formatted} a day'
                  : 'Saved: ${saved.target.formatted} a day. A max test will size it properly.',
            ),
          ),
        );
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorCopy(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(dailyRepsProvider);
    final data = value.value;
    if (data == null) {
      return PageScaffold(
        title: 'Daily reps',
        children: [
          if (value.hasError)
            ErrorBlock(
              title: 'Could not load your exercises',
              error: value.error!,
              onRetry: () async => ref.invalidate(dailyRepsProvider),
            )
          else
            const SizedBox(height: 320, child: MeSkeleton()),
        ],
      );
    }
    if (_exercise == null) _start(data);
    final option = data.option(_exercise!);
    final palette = questPalette('pushups');
    return PageScaffold(
      title: 'Daily reps',
      subtitle: 'Pick one exercise. Your daily target is sized from your own max.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) SaveError(_error!),
          ChunkyButton(
            label: _error != null ? 'Try again' : 'Save',
            palette: palette,
            busy: _saving,
            onPressed: _valid && !_saving ? () => _save(data) : null,
          ),
        ],
      ),
      children: [
        Semantics(header: true, child: const Text('Exercise', style: AppText.headline)),
        const SizedBox(height: 10),
        for (final (i, e) in data.exercises.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _ExerciseCard(
            option: e,
            selected: e.key == _exercise,
            current: e.key == data.exercise,
            onTap: e.available ? () => _pick(e) : null,
          ),
        ],
        const SizedBox(height: 24),
        Semantics(header: true, child: const Text('Your max', style: AppText.headline)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LogChip(
              label: 'I know my max',
              selected: _knowsMax,
              onTap: () => _setMode(knowsMax: true),
            ),
            LogChip(
              label: 'Not sure yet',
              selected: !_knowsMax,
              onTap: () => _setMode(knowsMax: false),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (option != null) _knowsMax ? _knownMax(option, data) : _unknownMax(option, data),
      ],
    );
  }

  Widget _knownMax(RepsExerciseOption option, DailyReps data) {
    final preview = _previewMax == null || !_valid
        ? null
        : ref.watch(repsPreviewProvider((exercise: option.key, max: _previewMax!)));
    final latest = option.latestMax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NumberField(
          controller: _field,
          label: 'Most ${option.noun} in one set',
          hint: 'Your max',
          unit: 'reps',
          onChanged: _typedChanged,
        ),
        if (_fieldError != null) ...[
          const SizedBox(height: 6),
          Text(_fieldError!, style: AppText.caption.copyWith(color: kDangerText)),
        ],
        if (latest != null) ...[
          const SizedBox(height: 6),
          Text(
            'Last tested ${latest.date}: ${latest.reps} ${repsWord(option, latest.reps)}.',
            style: AppText.caption.copyWith(color: kInkSecondary),
          ),
        ],
        const SizedBox(height: 14),
        _TestNowCard(option: option),
        if (preview != null) ...[
          const SizedBox(height: 14),
          preview.when(
            data: (p) => _PreviewCard(preview: p, option: option),
            loading: () => const SkeletonBlock(height: 120, radius: 14),
            error: (e, _) =>
                Text(errorCopy(e), style: AppText.caption.copyWith(color: kDangerText)),
          ),
        ],
      ],
    );
  }

  Widget _unknownMax(RepsExerciseOption option, DailyReps data) {
    final n = _typed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: kSunken,
          child: Text(
            'We do not pick a starting number for you. No published research gives one that is '
            'safe for everyone, and a guess that is too high is how people quit. Choose a number '
            'you can do with good form and plenty left, a low one is fine. Test your max in the '
            'first few days and the target is sized from it.',
            style: AppText.body.copyWith(fontSize: 14, color: kInkSecondary),
          ),
        ),
        const SizedBox(height: 14),
        NumberField(
          controller: _field,
          label: 'Easy ${option.noun} in one set',
          hint: 'Your number',
          unit: 'reps',
          onChanged: _typedChanged,
        ),
        if (_fieldError != null) ...[
          const SizedBox(height: 6),
          Text(_fieldError!, style: AppText.caption.copyWith(color: kDangerText)),
        ],
        if (n != null && _valid) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${data.sets} sets of $n ${repsWord(option, n)}',
                  style: AppText.tabular(AppText.title.copyWith(fontSize: 22)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${(data.sets * n).formatted} a day, the number you picked times ${data.sets}.',
                  style: AppText.body.copyWith(fontSize: 14, color: kInkSecondary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _TestNowCard(option: option),
      ],
    );
  }
}

/// "30 squats" style words for a count of the option's reps.
String repsWord(RepsExerciseOption option, num n) => n == 1 ? option.singular : option.noun;

/// The exercise's plural noun, from the saved list.
String repsLabel(DailyReps data, String key) => data.option(key)?.noun ?? 'reps';

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.option,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final RepsExerciseOption option;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('pushups');
    // Only the picked exercise explains itself, which keeps the list short enough that the max
    // field is not far below it.
    final note = !option.available
        ? 'Needs a pull-up bar. Add it under Training > Equipment to use it.'
        : selected
        ? option.hint
        : null;
    final card = ChoiceCard(
      icon: questIcon('pushups'),
      iconPalette: palette,
      palette: palette,
      title: current ? '${option.name} (current)' : option.name,
      subtitle: note,
      selected: selected,
      onTap: onTap,
    );
    return onTap == null ? Opacity(opacity: 0.55, child: card) : card;
  }
}

class _TestNowCard extends StatelessWidget {
  const _TestNowCard({required this.option});

  final RepsExerciseOption option;

  @override
  Widget build(BuildContext context) => AppCard(
    color: kSunken,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.timer_outlined, size: 18, color: kInkSecondary),
            const SizedBox(width: 8),
            Text('Test now', style: AppText.label.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Warm up for a minute, then do one set of ${option.noun} with good form. Stop when you '
          'could manage only one or two more, and count the reps. Retest every 2 to 4 weeks.',
          style: AppText.body.copyWith(fontSize: 14, color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview, required this.option});

  final RepsPreview preview;
  final RepsExerciseOption option;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your daily target', style: AppText.caption.copyWith(color: kInkMuted)),
        const SizedBox(height: 2),
        Text(
          '${preview.sets} sets of ${preview.repsPerSet} ${repsWord(option, preview.repsPerSet)}',
          style: AppText.tabular(AppText.title.copyWith(fontSize: 22)),
        ),
        const SizedBox(height: 2),
        Text(
          '${preview.daily.formatted} a day. The range is ${preview.low} to ${preview.high} a '
          'set, 70 to 80% of your max of ${preview.max}.',
          style: AppText.body.copyWith(fontSize: 14, color: kInkSecondary),
        ),
        const SizedBox(height: 10),
        Text(
          'A derivation from reps-in-reserve and progression guidance, not a published constant. '
          'After 5 of 7 days with every set done, each set grows by 5%.',
          style: AppText.caption.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 8),
        for (final s in preview.sources)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(s.text, style: AppText.caption.copyWith(color: kInkMuted)),
          ),
      ],
    ),
  );
}
