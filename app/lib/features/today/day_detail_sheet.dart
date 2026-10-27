import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../util/client_op_id.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/skeletons.dart';

Future<void> showDayDetailSheet(BuildContext context, {required String date}) =>
    showAppSheet<void>(context, builder: (_) => DayDetailSheet(date: date));

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
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return ScaffoldMessenger(
      child: Builder(
        builder: (context) => SizedBox(
          height: height,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      "Today's entries",
                      style: TextStyle(
                        color: kFgPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
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
          SkeletonBlock(height: 52, radius: 12),
          SizedBox(height: 8),
          SkeletonBlock(height: 52, radius: 12),
        ],
      );
    }
    if (entries.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text('Nothing logged yet.', style: TextStyle(color: kFgSecondary, fontSize: 14)),
      );
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: kBorder),
      itemBuilder: (context, i) {
        final entry = entries[i];
        return Dismissible(
          key: ValueKey('${entry.kind}-${entry.id}'),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => _delete(entry, messenger),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 18),
            color: kDanger.withValues(alpha: 0.2),
            child: const Icon(Icons.delete_outline_rounded, color: kDanger),
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
    final (icon, title, quantity, detail) = _describe(entry);
    final time = DateFormat.Hm().format(entry.loggedAt.toLocal());
    return Container(
      color: kBgSurface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: kFgSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kFgPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail == null ? time : '$time - $detail',
                  style: const TextStyle(color: kFgMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            quantity,
            style: const TextStyle(color: kFgPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  (IconData, String, String, String?) _describe(LogEntry entry) => switch (entry) {
    final ActivityLog a => (
      switch (a.type) {
        'pushups' => Icons.fitness_center_outlined,
        'reading' => Icons.menu_book_outlined,
        _ => Icons.self_improvement_outlined,
      },
      '${a.type[0].toUpperCase()}${a.type.substring(1)}',
      '${a.quantity.formatted} ${shortUnit(a.unit)}',
      null,
    ),
    final MealLog m => (
      Icons.restaurant_outlined,
      m.name,
      '${m.kcal.formatted} kcal',
      'P ${m.protein.formatted} C ${m.carbs.formatted} F ${m.fat.formatted}',
    ),
  };
}
