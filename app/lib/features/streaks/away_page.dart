import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/today.dart';
import '../../state/v7.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../log/log_chip.dart';
import 'streak_visuals.dart';

const kMaxAwayDays = 14;

/// "Fri 30 Oct" for one day, "Fri 30 Oct to Sun 1 Nov" for a span.
String awayRangeLabel(String from, String to) {
  final f = DateFormat('E d MMM');
  final a = f.format(parseLocalDate(from));
  return from == to ? a : '$a to ${f.format(parseLocalDate(to))}';
}

/// "3 days" for a span, counting both ends.
String awayLengthLabel(String from, String to) {
  final n = parseLocalDate(to).difference(parseLocalDate(from)).inDays + 1;
  return n == 1 ? '1 day' : '$n days';
}

String awayError(Object e) {
  if (e is ApiException && e.code == 'away_overlap') {
    return 'You already have away days on some of those dates.';
  }
  return errorCopy(e);
}

/// Me > Away days, also reached from "Can't today?": pick a span, say why if you like, and see
/// or remove the ones already set.
class AwayPage extends ConsumerStatefulWidget {
  const AwayPage({super.key});

  @override
  ConsumerState<AwayPage> createState() => _AwayPageState();
}

class _AwayPageState extends ConsumerState<AwayPage> {
  final _note = TextEditingController();
  String? _from;
  String? _to;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _today() =>
      ref.read(todayProvider).value?.data.localToday ?? formatDateKey(ref.read(clockProvider)());

  String _plus(String date, int days) {
    final d = parseLocalDate(date);
    return formatDateKey(DateTime.utc(d.year, d.month, d.day + days));
  }

  String get _start => _from ?? _today();

  String get _end => _to ?? _start;

  void _preset(int fromOffset, int length) {
    final from = _plus(_today(), fromOffset);
    setState(() {
      _from = from;
      _to = _plus(from, length - 1);
      _error = null;
    });
  }

  bool _isPreset(int fromOffset, int length) {
    final from = _plus(_today(), fromOffset);
    return _start == from && _end == _plus(from, length - 1);
  }

  Future<String?> _pick(String initial, String first, String last) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseLocalDate(initial),
      firstDate: parseLocalDate(first),
      lastDate: parseLocalDate(last),
    );
    return picked == null || !mounted ? null : formatDateKey(picked);
  }

  Future<void> _pickFrom() async {
    final today = _today();
    final picked = await _pick(_start, today, _plus(today, kMaxAwayDays));
    if (picked == null || !mounted) return;
    setState(() {
      _from = picked;
      if (_end.compareTo(picked) < 0 || _end.compareTo(_plus(picked, kMaxAwayDays - 1)) > 0) {
        _to = picked;
      }
      _error = null;
    });
  }

  Future<void> _pickTo() async {
    final picked = await _pick(_end, _start, _plus(_start, kMaxAwayDays - 1));
    if (picked != null && mounted) setState(() => _to = picked);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(streakActionsProvider)
          .createAway(from: _start, to: _end, note: _note.text.trim());
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _from = null;
        _to = null;
        _note.clear();
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = awayError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(AwaySpan span) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove these away days?',
      message:
          '${awayRangeLabel(span.from, span.to)} will count like any other day again. Days that '
          'already passed as away stay away.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(streakActionsProvider).deleteAway(span.id);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(awayError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final away = ref.watch(todayProvider.select((t) => t.value?.data.away)) ?? const AwayState();
    final spans = away.all;
    return PageScaffold(
      title: 'Away days',
      children: [
        Text(
          'Sick or travelling? Away days neither break nor extend your streak, use no freeze and '
          'keep the nudges quiet. Your partner sees you as away.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        const FieldLabel('How long?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            LogChip(label: 'Today', selected: _isPreset(0, 1), onTap: () => _preset(0, 1)),
            LogChip(label: 'Tomorrow', selected: _isPreset(1, 1), onTap: () => _preset(1, 1)),
            LogChip(label: '3 days', selected: _isPreset(0, 3), onTap: () => _preset(0, 3)),
            LogChip(label: 'A week', selected: _isPreset(0, 7), onTap: () => _preset(0, 7)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DateField(label: 'From', value: _start, onTap: _pickFrom),
            ),
            const SizedBox(width: kCardGap),
            Expanded(
              child: _DateField(label: 'To', value: _end, onTap: _pickTo),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Note (optional)'),
        AppTextField(
          controller: _note,
          hint: 'Flu, flight to Lisbon...',
          semanticLabel: 'Note',
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: [LengthLimitingTextInputFormatter(200)],
        ),
        const SizedBox(height: 16),
        ChunkyButton(
          label: 'Mark ${awayLengthLabel(_start, _end)} as away',
          icon: Icons.pause_circle_rounded,
          busy: _busy,
          onPressed: _save,
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: kDangerText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _error!,
                  style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        Semantics(header: true, child: const Text('Your away days', style: AppText.headline)),
        const SizedBox(height: 10),
        if (spans.isEmpty)
          Text(
            'No away days set. Starting today or up to $kMaxAwayDays days ahead, for at most '
            '$kMaxAwayDays days at a time.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, span) in spans.indexed) ...[
                  if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                  _SpanRow(
                    span: span,
                    now: away.current?.id == span.id,
                    onDelete: () => _delete(span),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = DateFormat('E d MMM').format(parseLocalDate(value));
    return Semantics(
      button: true,
      label: '$label, $text',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: kSunken,
            borderRadius: BorderRadius.circular(kRadiusField),
            border: Border.all(color: kBorder, width: kBorderWidth),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.caption),
              Text(text, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpanRow extends StatelessWidget {
  const _SpanRow({required this.span, required this.now, required this.onDelete});

  final AwaySpan span;
  final bool now;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final range = awayRangeLabel(span.from, span.to);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: accentById('sky').tint, shape: BoxShape.circle),
              child: const Icon(Icons.pause_circle_rounded, size: 24, color: kFreezeText),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(range, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    [
                      if (now) 'Away now',
                      awayLengthLabel(span.from, span.to),
                      if (span.note.isNotEmpty) span.note,
                    ].join(' - '),
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: 'Remove away days, $range',
              excludeSemantics: true,
              onTap: onDelete,
              child: IconButton(
                onPressed: onDelete,
                tooltip: 'Remove',
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                icon: const Icon(Icons.delete_outline_rounded, color: kInkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
