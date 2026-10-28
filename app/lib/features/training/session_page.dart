import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import 'eased_note.dart';
import 'how_to_sheet.dart';
import 'set_form.dart';
import 'training_copy.dart';
import '../../widgets/units_scope.dart';

/// Today's planned session: each exercise with its target and the reason for it, a set log
/// prefilled with the target, a rest timer after every set, and Finish.
class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({super.key});

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  Timer? _ticker;
  int _restLeft = 0;
  bool _finishing = false;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startRest(int seconds) {
    _ticker?.cancel();
    setState(() => _restLeft = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _restLeft -= 1);
      if (_restLeft <= 0) {
        t.cancel();
        HapticFeedback.mediumImpact();
        SemanticsService.sendAnnouncement(View.of(context), 'Rest done', TextDirection.ltr);
      }
    });
  }

  void _skipRest() {
    _ticker?.cancel();
    setState(() => _restLeft = 0);
  }

  Future<void> _log(TrainingSession session, SessionExercise e) async {
    final logged = await showAppSheet<bool>(
      context,
      builder: (context) => _LogSetSheet(session: session, exercise: e),
    );
    if (logged == true && mounted) _startRest(e.plan.restSec);
  }

  Future<void> _delete(ExerciseSet set) async {
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
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    }
  }

  Future<void> _finish(TrainingSession session) async {
    if (session.setsLogged < session.setsPlanned) {
      final ok = await confirmDialog(
        context,
        title: 'Finish the session?',
        message: 'You logged ${sessionProgressLabel(session)}. It still counts as done.',
        confirmLabel: 'Finish',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      await ref.read(trainingTodayProvider.notifier).complete();
      HapticFeedback.heavyImpact();
      _skipRest();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(trainingTodayProvider.select((v) => v.value?.data.session));
    if (session == null) {
      return const PageScaffold(title: 'Session', children: [SizedBox.shrink()]);
    }
    return PageScaffold(
      title: session.label,
      subtitle: session.completed
          ? 'Done. Get stronger is complete.'
          : sessionProgressLabel(session),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_restLeft > 0) ...[
            _RestBar(seconds: _restLeft, onSkip: _skipRest),
            const SizedBox(height: 10),
          ],
          if (!session.completed)
            ChunkyButton(
              label: 'Finish session',
              icon: Icons.check_rounded,
              busy: _finishing,
              onPressed: session.setsLogged == 0 ? null : () => _finish(session),
            ),
        ],
      ),
      children: [
        if (_error case final error?) ...[
          Text(error, style: AppText.label.copyWith(color: kDangerText)),
          const SizedBox(height: 12),
        ],
        if (session.eased) ...[EasedNote(session: session), const SizedBox(height: kCardGap)],
        for (final e in session.exercises) ...[
          _ExerciseCard(exercise: e, onLog: () => _log(session, e), onDelete: _delete),
          const SizedBox(height: kCardGap),
        ],
      ],
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise, required this.onLog, required this.onDelete});

  final SessionExercise exercise;
  final VoidCallback onLog;
  final ValueChanged<ExerciseSet> onDelete;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final accent = context.accentPalette;
    final next = e.logged.length + 1;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.name, style: AppText.headline)),
              HowToButton(exerciseKey: e.exercise, name: e.name),
              if (e.complete)
                Icon(
                  Icons.check_circle_rounded,
                  color: accent.fill,
                  semanticLabel: 'All sets logged',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            targetLabel(e, context.units),
            style: AppText.tabular(AppText.label.copyWith(color: kInk)),
          ),
          if (e.exercise != e.plan.exercise) ...[
            const SizedBox(height: 2),
            Text(
              'In place of ${e.planName.isEmpty ? 'the planned exercise' : e.planName}',
              style: AppText.caption,
            ),
          ],
          if (e.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.reason, style: AppText.caption.copyWith(color: kInkMuted)),
          ],
          if (e.logged.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in e.logged.indexed)
                  _SetPill(index: i + 1, set: s, onLongPress: () => onDelete(s)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ChunkyButton.secondary(
            label: e.complete ? 'Log an extra set' : 'Log set $next of ${e.target.sets}',
            icon: Icons.add_rounded,
            onPressed: onLog,
          ),
        ],
      ),
    );
  }
}

class _SetPill extends StatelessWidget {
  const _SetPill({required this.index, required this.set, required this.onLongPress});

  final int index;
  final ExerciseSet set;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    final rir = rirLabel(set.rir);
    return Semantics(
      container: true,
      label:
          'Set $index, ${setLabel(set, context.units)}${rir.isEmpty ? '' : ', $rir'}. Long press to delete.',
      excludeSemantics: true,
      child: Pressable(
        onTap: null,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: accent.tint,
            borderRadius: BorderRadius.circular(kRadiusField),
          ),
          child: Text(
            rir.isEmpty
                ? setLabel(set, context.units)
                : '${setLabel(set, context.units)} · ${set.rir} RIR',
            style: AppText.tabular(
              AppText.caption.copyWith(color: kInk, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestBar extends StatelessWidget {
  const _RestBar({required this.seconds, required this.onSkip});

  final int seconds;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    // A fixed label: a countdown in the label would make VoiceOver read every second. The end of
    // the rest is announced once instead.
    return Semantics(
      container: true,
      label: 'Rest timer running',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: BoxDecoration(
          color: accent.tint,
          borderRadius: BorderRadius.circular(kRadiusButton),
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: accent.lip, size: 22),
                  const SizedBox(width: 10),
                  Text('Rest', style: AppText.label.copyWith(color: kInk)),
                  const SizedBox(width: 8),
                  Text(
                    clockLabel(seconds),
                    style: AppText.tabular(AppText.headline.copyWith(color: kInk)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(foregroundColor: accent.lip),
              child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogSetSheet extends ConsumerStatefulWidget {
  const _LogSetSheet({required this.session, required this.exercise});

  final TrainingSession session;
  final SessionExercise exercise;

  @override
  ConsumerState<_LogSetSheet> createState() => _LogSetSheetState();
}

class _LogSetSheetState extends ConsumerState<_LogSetSheet> {
  // One op id per sheet, so a retried tap after a lost answer never logs the set twice.
  final _opId = newClientOpId();
  String? _error;

  Future<void> _log(SetValues v) async {
    final e = widget.exercise;
    setState(() => _error = null);
    try {
      await ref
          .read(trainingTodayProvider.notifier)
          .logSet(
            SetDraft(
              clientOpId: _opId,
              exercise: e.exercise,
              reps: e.timed ? null : v.amount,
              seconds: e.timed ? v.amount : null,
              loadKg: v.loadKg,
              rir: v.rir,
              sessionId: widget.session.id,
            ),
          );
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (err) {
      if (mounted) setState(() => _error = errorCopy(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final last = e.logged.lastOrNull;
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
            Text(e.name, style: AppText.title),
            const SizedBox(height: 4),
            Text(
              'Set ${e.logged.length + 1} of ${e.target.sets} · aim for ${perSetLabel(e, context.units)}',
              style: AppText.caption,
            ),
            const SizedBox(height: 20),
            SetForm(
              timed: e.timed,
              loaded: e.loaded,
              initialAmount: e.target.amount,
              initialLoadKg: last?.loadKg ?? e.target.loadKg,
              initialRir: e.timed ? null : e.plan.rir,
              onLog: _log,
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
