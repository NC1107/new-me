import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import '../shell/home_tab.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/skeletons.dart';
import '../../util/time_format.dart';

/// Where an empty sheet sends the person: to log a meal, or to the Train tab for a set.
enum _Next { meal, set }

Future<void> showDayDetailSheet(BuildContext context, {required String date}) async {
  final container = ProviderScope.containerOf(context);
  final next = await showAppSheet<_Next>(context, builder: (_) => DayDetailSheet(date: date));
  if (next == null || !context.mounted) return;
  switch (next) {
    case _Next.meal:
      await showLogSheet(context, kind: LogKind.meal, focusSearch: true);
    case _Next.set:
      container.read(homeTabProvider.notifier).select(HomeTab.train);
  }
}

/// The day's entries with their time and quantity, each removable with a swipe.
class DayDetailSheet extends ConsumerStatefulWidget {
  const DayDetailSheet({super.key, required this.date});

  final String date;

  @override
  ConsumerState<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends ConsumerState<DayDetailSheet> {
  List<LogEntry>? _entries;
  Object? _error;

  /// Set only by a fresh load, so deleting the last entry keeps the sheet (and its Undo) put.
  bool _emptyOnLoad = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await ref.read(logActionsProvider).entriesFor(widget.date);
      if (mounted) {
        setState(() {
          _entries = entries;
          _emptyOnLoad = entries.isEmpty;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delete(LogEntry entry, ScaffoldMessengerState messenger) async {
    HapticFeedback.mediumImpact();
    setState(() => _entries = [...?_entries]..removeWhere((e) => e.id == entry.id));
    try {
      await ref.read(logActionsProvider).delete(entry);
    } on ApiException catch (e) {
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Deleted'),
          // An action makes a snack bar stay until tapped; Undo is offered for a while only.
          persist: false,
          duration: kUndoWindow,
          action: SnackBarAction(label: 'Undo', onPressed: () => _undo(entry, messenger)),
        ),
      );
  }

  Future<void> _undo(LogEntry entry, ScaffoldMessengerState messenger) async {
    try {
      await ref.read(logActionsProvider).create(entry.toDraft(newClientOpId()));
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_emptyOnLoad) return _empty(context);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return ScaffoldMessenger(
      child: Builder(
        builder: (context) => SizedBox(
          height: height,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: kGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      header: true,
                      child: const Text("Today's entries", style: AppText.title),
                    ),
                  ),
                  Expanded(child: _content(ScaffoldMessenger.of(context))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Nothing to list, so the sheet is only as tall as its title, line and two actions.
  Widget _empty(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      kGutter,
      0,
      kGutter,
      kGutter + MediaQuery.paddingOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: const Text("Today's entries", style: AppText.title)),
        const SizedBox(height: 8),
        Text('No meals or sets logged yet.', style: AppText.body.copyWith(color: kInkSecondary)),
        const SizedBox(height: 20),
        ChunkyButton(
          label: 'Log a meal',
          icon: Icons.add_rounded,
          onPressed: () => Navigator.of(context).pop(_Next.meal),
        ),
        const SizedBox(height: kCardGap),
        ChunkyButton.secondary(
          label: 'Log a set',
          icon: Icons.fitness_center_rounded,
          onPressed: () => Navigator.of(context).pop(_Next.set),
        ),
      ],
    ),
  );

  Widget _content(ScaffoldMessengerState messenger) {
    final entries = _entries;
    if (entries == null) {
      if (_error != null) {
        return Center(
          child: ErrorBlock(
            title: 'Could not load entries',
            error: _error!,
            onRetry: () async {
              setState(() => _error = null);
              await _load();
            },
          ),
        );
      }
      return const Column(
        children: [
          SkeletonBlock(height: 56, radius: kRadiusField),
          SizedBox(height: 8),
          SkeletonBlock(height: 56, radius: kRadiusField),
        ],
      );
    }
    if (entries.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No meals or sets logged yet.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 2, thickness: 2, color: kSunken),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Dismissible(
          key: ValueKey('${entry.kind}-${entry.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _delete(entry, messenger),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            color: kDanger.withValues(alpha: 0.15),
            child: const Icon(Icons.delete_rounded, color: kDangerText),
          ),
          child: Semantics(
            customSemanticsActions: {
              const CustomSemanticsAction(label: 'Delete'): () => _delete(entry, messenger),
            },
            child: _EntryRow(entry: entry),
          ),
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final (key, title, quantity, detail) = _describe(entry);
    final palette = questPalette(key);
    final time = formatClock(entry.loggedAt.toLocal());
    return Container(
      color: kSurface,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
            child: Icon(questIcon(key), size: 22, color: palette.lip),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(fontSize: 16),
                ),
                Text(detail == null ? time : '$time · $detail', style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(quantity, style: AppText.tabular(AppText.label.copyWith(fontSize: 15))),
        ],
      ),
    );
  }

  (String, String, String, String?) _describe(LogEntry entry) => switch (entry) {
    final ActivityLog a => (
      switch (a.type) {
        'pushups' => 'pushups',
        'reading' => 'reading',
        'other' => 'exercise',
        _ => 'yoga',
      },
      switch (a.type) {
        'pushups' => 'Push-ups',
        'reading' => 'Reading',
        'other' => a.name.isEmpty ? 'Activity' : a.name,
        _ => 'Yoga',
      },
      '${a.quantity.formatted} ${shortUnit(a.unit)}',
      a.type == 'other' && a.intensity != null ? '${a.intensity} effort' : null,
    ),
    final MealLog m => (
      'meals_logged',
      m.name,
      '${m.kcal.formatted} kcal',
      'P ${m.protein.formatted} C ${m.carbs.formatted} F ${m.fat.formatted}',
    ),
  };
}
