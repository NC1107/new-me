import '../../widgets/app_switch.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/log_actions.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../state/units.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../util/reps_exercises.dart';
import '../../util/time_format.dart';
import '../../widgets/dialogs.dart';
import 'activity_pane.dart';
import 'breathing_pane.dart';
import 'log_kind.dart';
import 'log_panes.dart';
import 'produce_pane.dart';
import 'water_pane.dart';

/// Opens the log sheet for [kind], from a quest card's + or the food card.
Future<void> showLogSheet(
  BuildContext context, {
  required LogKind kind,
  bool maxTest = false,
  bool focusSearch = false,
}) => showAppSheet<void>(
  context,
  builder: (_) => LogSheet(kind: kind, maxTest: maxTest, focusSearch: focusSearch),
);

class LogSheet extends ConsumerStatefulWidget {
  const LogSheet({super.key, required this.kind, this.maxTest = false, this.focusSearch = false});

  final LogKind kind;

  /// Opens the push-up form on its max test, for the Targets page's link.
  final bool maxTest;

  /// Puts the cursor in the meal pane's food search.
  final bool focusSearch;

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet> {
  String _clientOpId = newClientOpId();
  String? _attempted;
  bool _busy = false;
  bool _yesterday = false;
  String? _error;
  Future<List<RecentMeal>>? _recent;

  /// The exercise the push-ups quest counts today, which the rep form logs and tests.
  String get _repsExercise =>
      ref
          .read(todayProvider)
          .value
          ?.data
          .quests
          .where((q) => q.key == 'pushups')
          .firstOrNull
          ?.exercise ??
      kDefaultRepsExercise;

  Future<List<RecentMeal>> _loadRecent() => _recent ??= ref
      .read(logActionsProvider)
      .recentMeals()
      .catchError((Object _) => <RecentMeal>[]);

  ({String localToday, DateTime until})? _backdateWindow(Today? today, Me? me) {
    final until = today?.backdateUntil ?? me?.backdateUntil;
    final localToday = today?.localToday ?? me?.localToday;
    if (until == null || localToday == null) return null;
    if (!ref.read(clockProvider)().isBefore(until)) return null;
    return (localToday: localToday, until: until);
  }

  Future<bool> _confirmed(String? confirm) async =>
      confirm == null ||
      await confirmDialog(context, title: 'Log this?', message: confirm, confirmLabel: 'Log it');

  String? _entryDate() {
    final window = _yesterday
        ? _backdateWindow(ref.read(todayProvider).value?.data, ref.read(meProvider).value?.data)
        : null;
    return window == null ? null : previousDate(window.localToday);
  }

  Future<void> _submit(
    DraftBuilder build, {
    required String added,
    String? confirm,
    List<MealItem>? libraryItems,
  }) async {
    if (_busy) return;
    if (!await _confirmed(confirm)) return;
    final date = _entryDate();

    // A retry of the same entry keeps its id; a different entry is a different operation.
    final signature = jsonEncode(build('', date).toJson()..remove('clientOpId'));
    if (_attempted != null && _attempted != signature) _clientOpId = newClientOpId();
    _attempted = signature;

    setState(() {
      _busy = true;
      _error = null;
    });
    final actions = ref.read(logActionsProvider);
    final LogResult result;
    try {
      result = await actions.create(build(_clientOpId, date));
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
      return;
    }
    if (libraryItems != null) unawaited(actions.syncLibrary(libraryItems));
    if (!mounted) return;
    _finish(added, [result]);
  }

  /// A max test is a measurement and not a set, so it has no Undo: testing again on the same day
  /// replaces it.
  Future<void> _submitMax(int reps) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(logActionsProvider).recordRepsMax(_repsExercise, reps, date: _entryDate());
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Max test saved: $reps ${repsNoun(_repsExercise, reps)}')),
      );
  }

  /// Closes the sheet and offers one Undo that removes everything this save logged.
  void _finish(String added, List<LogResult> results) {
    final actions = ref.read(logActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added),
          // An action makes a snack bar stay until tapped; Undo is offered for a while only.
          persist: false,
          duration: kUndoWindow,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                for (final r in results) {
                  await actions.delete(r.log);
                }
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
              }
            },
          ),
        ),
      );
  }

  // Each entry of a "Log separately" keeps its own idempotency key across retries, and the
  // ones already saved are skipped, so a failure halfway never double-logs.
  List<String> _manyIds = const [];
  final Set<int> _manyDone = {};
  final List<LogResult> _manyResults = [];
  String? _manySignature;

  Future<void> _submitMany(
    List<DraftBuilder> builds, {
    required String added,
    String? confirm,
    List<MealItem>? libraryItems,
  }) async {
    if (_busy || builds.isEmpty) return;
    if (!await _confirmed(confirm)) return;
    final date = _entryDate();
    final signature = jsonEncode([
      for (final b in builds) b('', date).toJson()..remove('clientOpId'),
    ]);
    if (_manySignature != signature) {
      _manySignature = signature;
      _manyIds = [for (final _ in builds) newClientOpId()];
      _manyDone.clear();
      _manyResults.clear();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final actions = ref.read(logActionsProvider);
    for (var i = 0; i < builds.length; i++) {
      if (_manyDone.contains(i)) continue;
      try {
        _manyResults.add(await actions.create(builds[i](_manyIds[i], date)));
        _manyDone.add(i);
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error =
                'Logged ${_manyDone.length} of ${builds.length}. ${errorCopy(e)} '
                'Tap again to log the rest.';
          });
        }
        return;
      }
    }
    if (libraryItems != null) unawaited(actions.syncLibrary(libraryItems));
    if (!mounted) return;
    _finish(added, List.of(_manyResults));
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final palette = questPalette(kind.questKey);
    final reps = _repsExercise;
    final window = _backdateWindow(
      ref.watch(todayProvider).value?.data,
      ref.watch(meProvider).value?.data,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                    child: Icon(questIcon(kind.questKey), size: 24, color: palette.lip),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        kind == LogKind.pushups ? 'Log ${repsNoun(reps, 2)}' : kind.title,
                        style: AppText.title,
                      ),
                    ),
                  ),
                ],
              ),
              if (window != null)
                _BackdateToggle(
                  value: _yesterday,
                  until: window.until,
                  onChanged: (v) => setState(() => _yesterday = v),
                ),
              const SizedBox(height: 20),
              switch (kind) {
                LogKind.pushups => QuantityPane(
                  key: const ValueKey(LogKind.pushups),
                  type: 'pushups',
                  exercise: reps,
                  initialUnit: widget.maxTest ? kMaxTestUnit : null,
                  units: [
                    UnitSpec(
                      unit: 'reps',
                      label: repsNoun(reps, 2),
                      start: 10,
                      step: 1,
                      chips: const [5, 10, 20],
                    ),
                    UnitSpec(
                      unit: kMaxTestUnit,
                      label: 'Max test',
                      countLabel: '${repsNoun(reps, 2)} in one set',
                      start: 20,
                      step: 1,
                      chips: const [5, 10, 20],
                      caption:
                          'One set to near failure with good form. It sizes your daily '
                          '${repsNoun(reps, 1)} target. Testing every 2 to 4 weeks keeps it honest.',
                      saveLabel: 'Save max test',
                    ),
                  ],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                  onMaxTest: _submitMax,
                ),
                LogKind.reading => QuantityPane(
                  key: const ValueKey(LogKind.reading),
                  type: 'reading',
                  units: const [
                    UnitSpec(
                      unit: 'minutes',
                      label: 'Minutes',
                      start: 15,
                      step: 5,
                      chips: [5, 10, 15],
                    ),
                    UnitSpec(unit: 'pages', label: 'Pages', start: 10, step: 5, chips: [5, 10, 20]),
                  ],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.yoga => QuantityPane(
                  key: const ValueKey(LogKind.yoga),
                  type: 'yoga',
                  units: const [
                    UnitSpec(
                      unit: 'minutes',
                      label: 'Minutes',
                      start: 30,
                      step: 5,
                      chips: [],
                      choices: [15, 30, 45, 60, 75, 90],
                    ),
                  ],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.water => WaterPane(
                  key: const ValueKey(LogKind.water),
                  units: ref.watch(unitsProvider),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.produce => ProducePane(
                  key: const ValueKey(LogKind.produce),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.breathing => BreathingPane(
                  key: const ValueKey(LogKind.breathing),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.activity => ActivityPane(
                  key: const ValueKey(LogKind.activity),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.meal => MealPane(
                  key: const ValueKey(LogKind.meal),
                  recent: _loadRecent(),
                  canEstimate: ref.watch(
                    meProvider.select((m) => m.value?.data.features.mealEstimate ?? false),
                  ),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                  onLogMany: _submitMany,
                  autofocusSearch: widget.focusSearch,
                ),
              },
              if (_error != null) ...[const SizedBox(height: 12), LogErrorLine(message: _error!)],
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdateToggle extends StatelessWidget {
  const _BackdateToggle({required this.value, required this.until, required this.onChanged});

  final bool value;
  final DateTime until;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hour = until.toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Log for yesterday', style: AppText.label.copyWith(color: kInk)),
                  Text('Open until ${formatClock(hour)}', style: AppText.caption),
                ],
              ),
            ),
            AppSwitch(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline failure line under a sheet's save button.
class LogErrorLine extends StatelessWidget {
  const LogErrorLine({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.error_outline_rounded, size: 18, color: kDangerText),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}
