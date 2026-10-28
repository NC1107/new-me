import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';
import '../../state/today.dart';
import '../me/settings_row.dart';
import 'exercises_page.dart';
import 'mobility_page.dart';
import 'training_card.dart';
import 'training_progress_page.dart';
import 'training_copy.dart';
import 'training_profile_page.dart';
import '../../widgets/units_scope.dart';

/// The sources every plan is checked against (docs/design-v9.md).
const kTrainingSources =
    'Plans are checked against the WHO 2020 activity guidelines (2 or more strength days), weekly '
    'sets per muscle from Schoenfeld, Ogborn and Krieger 2017, and reps in reserve from Zourdos '
    'et al. 2016. Day-to-day progression follows the ACSM 2009 position stand, without AI.';

/// The Train tab: today's session, the setup plans are built for, the active plan, changes to it,
/// and the exercise log and weekly sets.
class TrainScreen extends ConsumerStatefulWidget {
  const TrainScreen({super.key});

  @override
  ConsumerState<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends ConsumerState<TrainScreen> {
  bool _designing = false;
  String? _error;
  List<PlanViolation> _violations = const [];

  Future<void> _run(Future<void> Function() action, {required String done}) async {
    if (_designing) return;
    setState(() {
      _designing = true;
      _error = null;
      _violations = const [];
    });
    try {
      await action();
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(done)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'plan_invalid'
            ? 'The designed plan still broke the training rules after repair, so it was not saved.'
            : errorCopy(e);
        _violations = parseViolations(e.body);
      });
    } finally {
      if (mounted) setState(() => _designing = false);
    }
  }

  Future<void> _editProfile(TrainingProfile? profile) =>
      pushPage(context, TrainingProfilePage(initial: profile));

  Future<void> _change() async {
    final picked = await showAppSheet<(PlanChange, String)>(
      context,
      builder: (_) => const _ChangeSheet(),
    );
    if (picked == null || !mounted) return;
    await _run(
      () => ref.read(trainingSetupProvider.notifier).change(picked.$1, detail: picked.$2),
      done: 'Plan updated',
    );
  }

  Future<void> _end() async {
    final ok = await confirmDialog(
      context,
      title: 'End this plan?',
      message: 'Your logged sets stay. Today will no longer show a session.',
      confirmLabel: 'End plan',
      destructive: true,
    );
    if (ok && mounted) {
      await _run(() => ref.read(trainingSetupProvider.notifier).endPlan(), done: 'Plan ended');
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(trainingSetupProvider);
    final catalog = ref.watch(exercisesProvider).value?.data;
    final localToday = ref.watch(todayProvider.select((v) => v.value?.data.localToday));
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: context.accent,
        backgroundColor: kSurface,
        onRefresh: () async {
          ref.invalidate(trainingSetupProvider);
          await ref.read(trainingTodayProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 32),
          children: [
            Semantics(header: true, child: const Text('Train', style: AppText.display)),
            const SizedBox(height: 16),
            if (localToday != null) TrainingSlot(localToday: localToday, onTrainTab: true),
            const _MobilityCard(),
            switch (setup) {
              AsyncValue(:final value?) => _body(value, catalog),
              AsyncValue(:final error?) => ErrorBlock(
                title: 'Could not load your training',
                error: error,
                onRetry: () async => ref.invalidate(trainingSetupProvider),
              ),
              _ => const SkeletonBlock(height: 160, radius: kRadiusCard),
            },
          ],
        ),
      ),
    );
  }

  Widget _body(TrainingSetup setup, ExerciseCatalog? catalog) {
    final profile = setup.profile;
    final plan = setup.plan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (profile == null) ...[
          Text(
            'Tell New Me what you have and how much time you can give, and Claude designs a plan '
            'inside published limits. Progression from session to session follows fixed rules.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 16),
          ChunkyButton(label: 'Set up training', onPressed: () => _editProfile(null)),
        ] else ...[
          _ProfileSummary(profile: profile, onEdit: () => _editProfile(profile)),
          const SizedBox(height: 20),
          if (plan == null) ...[
            const FieldLabel('Plan'),
            Text(
              'No plan yet. Designing one takes up to a minute.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 12),
            ChunkyButton(
              label: _designing ? 'Designing your plan' : 'Design my plan',
              icon: Icons.auto_awesome_rounded,
              busy: _designing,
              onPressed: () => _run(
                () => ref.read(trainingSetupProvider.notifier).generate(),
                done: 'Your plan is ready',
              ),
            ),
          ] else
            _PlanView(plan: plan, catalog: catalog),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          Text(error, style: AppText.label.copyWith(color: kDangerText)),
          for (final v in _violations)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• ${v.message}', style: AppText.caption.copyWith(color: kInkSecondary)),
            ),
        ],
        if (profile != null && plan != null) ...[
          const SizedBox(height: 16),
          ChunkyButton(
            label: _designing ? 'Updating your plan' : 'Change plan',
            icon: Icons.tune_rounded,
            busy: _designing,
            onPressed: _change,
          ),
          const SizedBox(height: 10),
          ChunkyButton.secondary(label: 'End plan', onPressed: _designing ? null : _end),
        ],
        const SizedBox(height: 20),
        SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.list_alt_rounded,
              palette: accentById('rose'),
              title: 'Exercises and sets',
              subtitle: 'Everything you have logged',
              onTap: () => pushPage(context, const ExercisesPage()),
            ),
            SettingsRow(
              icon: Icons.bar_chart_rounded,
              palette: accentById('rose'),
              title: 'Weekly sets',
              subtitle: 'Sets per muscle against the target range',
              onTap: () => pushPage(context, const TrainingProgressPage()),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(kTrainingSources, style: AppText.caption.copyWith(color: kInkMuted)),
      ],
    );
  }
}

/// The way into the guided Mobility 10 routine, which needs no plan.
class _MobilityCard extends StatelessWidget {
  const _MobilityCard();

  @override
  Widget build(BuildContext context) {
    final accent = accentById('rose');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        onTap: () => pushPage(context, const MobilityPage()),
        child: Row(
          children: [
            Icon(Icons.self_improvement_rounded, color: accent.lip, size: 28),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mobility 10', style: AppText.headline),
                  SizedBox(height: 2),
                  Text(
                    'Guided stretching, about 11 minutes. Counts toward yoga.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile, required this.onEdit});

  final TrainingProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final equipment = profile.equipment.isEmpty
        ? 'Bodyweight only'
        : [
            for (final e in profile.equipment)
              e == 'dumbbells' && profile.dumbbellMaxKg != null
                  ? 'Dumbbells to ${kgLabel(profile.dumbbellMaxKg!, context.units)}'
                  : equipmentLabel(e),
          ].join(', ');
    return AppCard(
      onTap: onEdit,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${profile.daysPerWeek} days a week, ${profile.sessionMinutes} min',
                  style: AppText.headline,
                ),
                const SizedBox(height: 2),
                Text('${profile.experience.label} · $equipment', style: AppText.caption),
                if (profile.focus.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('“${profile.focus}”', style: AppText.caption.copyWith(color: kInkSecondary)),
                ],
              ],
            ),
          ),
          const Icon(Icons.edit_rounded, color: kInkMuted, size: 20, semanticLabel: 'Edit'),
        ],
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({required this.plan, required this.catalog});

  final TrainingPlan plan;
  final ExerciseCatalog? catalog;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    final days = [...plan.days]..sort((a, b) => a.weekday.compareTo(b.weekday));
    final ends = DateFormat('d MMM').format(parseLocalDate(plan.endsOn));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel('Plan · ${plan.weeks} weeks, until $ends'),
        if (plan.notes.isNotEmpty) ...[
          Text(plan.notes, style: AppText.body.copyWith(color: kInkSecondary)),
          const SizedBox(height: 12),
        ],
        for (final day in days) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.tint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        weekdayLabel(day.weekday),
                        style: AppText.caption.copyWith(
                          color: accent.lip,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(day.label, style: AppText.headline)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final p in day.exercises)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _PrescriptionRow(prescription: p, exercise: catalog?.byKey(p.exercise)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: kCardGap),
        ],
      ],
    );
  }
}

class _PrescriptionRow extends StatelessWidget {
  const _PrescriptionRow({required this.prescription, required this.exercise});

  final Prescription prescription;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) {
    final p = prescription;
    final timed = exercise?.timed ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(exercise?.name ?? p.exercise, style: AppText.label.copyWith(color: kInk)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            '${p.sets} x ${rangeLabel(p, timed: timed)}',
            textAlign: TextAlign.end,
            style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
          ),
        ),
      ],
    );
  }
}

class _ChangeSheet extends StatefulWidget {
  const _ChangeSheet();

  @override
  State<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends State<_ChangeSheet> {
  PlanChange? _picked;
  final _detail = TextEditingController();

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _ready =>
      _picked != null && (_picked!.detailPrompt == null || _detail.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
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
            const Text('Change plan', style: AppText.title),
            const SizedBox(height: 4),
            const Text(
              'Claude rewrites only what the change needs, under the same rules.',
              style: AppText.caption,
            ),
            const SizedBox(height: 16),
            for (final c in PlanChange.values) ...[
              _ChangeOption(
                label: c.label,
                selected: picked == c,
                onTap: () => setState(() => _picked = c),
              ),
              const SizedBox(height: 8),
            ],
            if (picked?.detailPrompt case final prompt?) ...[
              const SizedBox(height: 8),
              FieldLabel(prompt),
              AppTextField(
                controller: _detail,
                hint: picked == PlanChange.pain
                    ? 'For example: left elbow'
                    : 'For example: pull-ups',
                semanticLabel: prompt,
                autofocus: true,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            ChunkyButton(
              label: 'Change plan',
              onPressed: _ready
                  ? () => Navigator.of(context).pop((picked!, _detail.text.trim()))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangeOption extends StatelessWidget {
  const _ChangeOption({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return AppCard(
      onTap: onTap,
      color: selected ? accent.tint : kSurface,
      borderColor: selected ? accent.fill : kBorder,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(label, style: AppText.label.copyWith(color: kInk)),
    );
  }
}
