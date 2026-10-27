import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/local_prefs.dart';
import '../../state/log_actions.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/segmented.dart';
import 'log_kind.dart';
import 'log_panes.dart';

/// Opens the log sheet on [kind], or on the kind logged last.
Future<void> showLogSheet(BuildContext context, {LogKind? kind}) async {
  final initial = kind ?? LogKind.fromName(await LocalPrefs.lastLogKind());
  if (!context.mounted) return;
  await showAppSheet<void>(context, builder: (_) => LogSheet(initialKind: initial));
}

class LogSheet extends ConsumerStatefulWidget {
  const LogSheet({super.key, this.initialKind = LogKind.pushups});

  final LogKind initialKind;

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet> {
  late LogKind _kind = widget.initialKind;
  String _clientOpId = newClientOpId();
  String? _attempted;
  bool _busy = false;
  bool _yesterday = false;
  String? _error;
  Future<List<RecentMeal>>? _recent;

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

  List<LogKind> _kinds() {
    final quests = ref.watch(meProvider).value?.data.quests ?? const <QuestTemplate>[];
    final yoga = quests.any((q) => q.key == 'yoga' && q.enabled);
    return [LogKind.pushups, LogKind.reading, LogKind.meal, if (yoga) LogKind.yoga];
  }

  void _pick(LogKind kind) => setState(() {
    _kind = kind;
    _error = null;
  });

  Future<void> _submit(DraftBuilder build, {required String added, String? confirm}) async {
    if (_busy) return;
    if (confirm != null &&
        !await confirmDialog(
          context,
          title: 'Log this?',
          message: confirm,
          confirmLabel: 'Log it',
        )) {
      return;
    }
    final window = _yesterday
        ? _backdateWindow(ref.read(todayProvider).value?.data, ref.read(meProvider).value?.data)
        : null;
    final date = window == null ? null : previousDate(window.localToday);

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
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorCopy(e);
        });
      }
      return;
    }
    await LocalPrefs.setLastLogKind(_kind.name);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(added),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await actions.delete(result.log);
              } on ApiException catch (e) {
                messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
              }
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _kinds();
    final kind = kinds.contains(_kind) ? _kind : LogKind.pushups;
    final window = _backdateWindow(
      ref.watch(todayProvider).value?.data,
      ref.watch(meProvider).value?.data,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Segmented<LogKind>(
                options: [for (final k in kinds) (k, k.label)],
                selected: kind,
                onChanged: _pick,
              ),
              if (window != null)
                _BackdateToggle(
                  value: _yesterday,
                  until: window.until,
                  onChanged: (v) => setState(() => _yesterday = v),
                ),
              const SizedBox(height: 16),
              switch (kind) {
                LogKind.pushups => QuantityPane(
                  key: const ValueKey(LogKind.pushups),
                  type: 'pushups',
                  units: const [('reps', 'reps')],
                  quickValues: const [10, 15, 20, 25],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.reading => QuantityPane(
                  key: const ValueKey(LogKind.reading),
                  type: 'reading',
                  units: const [('minutes', 'Minutes'), ('pages', 'Pages')],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.yoga => QuantityPane(
                  key: const ValueKey(LogKind.yoga),
                  type: 'yoga',
                  units: const [('minutes', 'minutes')],
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
                LogKind.meal => MealPane(
                  key: const ValueKey(LogKind.meal),
                  recent: _loadRecent(),
                  busy: _busy,
                  failed: _error != null,
                  onLog: _submit,
                ),
              },
              if (_error != null) ...[const SizedBox(height: 12), _ErrorLine(message: _error!)],
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Add to yesterday - open until '
              '${hour.hour.toString().padLeft(2, '0')}:${hour.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: kFgSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
            activeThumbColor: context.onAccent,
            activeTrackColor: context.accent,
          ),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.error_outline, size: 16, color: kDanger),
      const SizedBox(width: 6),
      Expanded(
        child: Text(message, style: const TextStyle(color: kDanger, fontSize: 13, height: 1.35)),
      ),
    ],
  );
}
