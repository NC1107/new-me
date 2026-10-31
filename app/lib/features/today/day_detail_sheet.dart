import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../state/units.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../food/edit_meal_sheet.dart';
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
class DayDetailSheet extends StatefulWidget {
  const DayDetailSheet({super.key, required this.date});

  final String date;

  @override
  State<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<DayDetailSheet> {
  /// Set only by a fresh load, so deleting the last entry keeps the sheet (and its Undo) put.
  bool _emptyOnLoad = false;

  @override
  Widget build(BuildContext context) {
    if (_emptyOnLoad) return _empty(context);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return ScaffoldMessenger(
      child: SizedBox(
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
                Expanded(
                  child: EntryList(
                    date: widget.date,
                    onLoaded: (entries) => setState(() => _emptyOnLoad = entries.isEmpty),
                  ),
                ),
              ],
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
}

/// One day's log entries, each removable with a swipe and Undo, a meal opening its editor.
/// [matches] narrows the list (the quest sheet shows one quest's entries); [shrinkWrap] sizes it
/// to its rows for use inside another scroll view. [onLoaded] is called with every fresh load.
class EntryList extends ConsumerStatefulWidget {
  const EntryList({
    super.key,
    required this.date,
    this.matches,
    this.emptyText = 'No meals or sets logged yet.',
    this.shrinkWrap = false,
    this.onLoaded,
  });

  final String date;
  final bool Function(LogEntry entry)? matches;
  final String emptyText;
  final bool shrinkWrap;
  final ValueChanged<List<LogEntry>>? onLoaded;

  @override
  ConsumerState<EntryList> createState() => _EntryListState();
}

class _EntryListState extends ConsumerState<EntryList> {
  List<LogEntry>? _entries;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await ref.read(logActionsProvider).entriesFor(widget.date);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
      widget.onLoaded?.call(entries);
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

  Future<void> _edit(MealLog meal) async {
    final changed = await showEditMealSheet(context, meal, onUndone: _load);
    if (changed && mounted) await _load();
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
    final all = _entries;
    if (all == null) {
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
    final test = widget.matches;
    final entries = test == null ? all : all.where(test).toList();
    if (entries.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(widget.emptyText, style: AppText.body.copyWith(color: kInkSecondary)),
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    return ListView.separated(
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.zero,
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
            child: EntryRow(
              entry: entry,
              units: ref.watch(unitsProvider),
              onTap: entry is MealLog ? () => _edit(entry) : null,
            ),
          ),
        );
      },
    );
  }
}

class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry, required this.units, this.onTap});

  final LogEntry entry;
  final Units units;

  /// Set for a meal, which opens its editor.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (key, title, quantity, detail) = _describe(entry, units);
    final palette = questPalette(key);
    final time = formatClock(entry.loggedAt.toLocal());
    final row = Container(
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
    final tap = onTap;
    if (tap == null) return row;
    return Semantics(
      button: true,
      onTapHint: 'Edit',
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          tap();
        },
        child: row,
      ),
    );
  }

  (String, String, String, String?) _describe(LogEntry entry, Units units) => switch (entry) {
    final ActivityLog a => (
      switch (a.type) {
        'pushups' => 'pushups',
        'reading' => 'reading',
        'other' => 'exercise',
        'water' => 'water',
        'produce' => 'produce',
        'breathing' => 'breathing',
        _ => 'yoga',
      },
      switch (a.type) {
        'pushups' => 'Push-ups',
        'reading' => 'Reading',
        'other' => a.name.isEmpty ? 'Activity' : a.name,
        'water' => 'Water',
        'produce' => 'Fruit and vegetables',
        'breathing' => 'Breathing',
        _ => 'Yoga',
      },
      a.type == 'water' ? units.volume(a.quantity) : '${a.quantity.formatted} ${shortUnit(a.unit)}',
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
