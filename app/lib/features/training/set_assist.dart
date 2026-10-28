import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/pressable.dart';

/// The rep counter says the count aloud every this many reps.
const kRepAnnounceEvery = 5;

/// Seconds of "get ready" before a timed hold starts counting down.
const kHoldLeadInSeconds = 3;

/// The largest tap target in the set sheet, so a person can count without looking.
const kCounterHeight = 168.0;

void _announce(BuildContext context, String message) {
  SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

/// Counts reps one tap at a time: a big tap target with a haptic and the number, an undo, and a
/// Done that hands the count to the set form.
class RepCounter extends StatefulWidget {
  const RepCounter({super.key, required this.max, required this.onDone, required this.onCancel});

  final int max;
  final ValueChanged<int> onDone;
  final VoidCallback onCancel;

  @override
  State<RepCounter> createState() => _RepCounterState();
}

class _RepCounterState extends State<RepCounter> {
  int _count = 0;

  void _tap() {
    if (_count >= widget.max) return;
    setState(() => _count += 1);
    if (_count % kRepAnnounceEvery == 0) {
      HapticFeedback.mediumImpact();
      _announce(context, '$_count reps');
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _undo() {
    if (_count == 0) return;
    setState(() => _count -= 1);
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: 'Count a rep',
          value: '$_count ${_plural(_count, 'rep', 'reps')}',
          excludeSemantics: true,
          onTap: _tap,
          child: Pressable(
            haptic: false,
            onTap: _tap,
            child: Container(
              height: kCounterHeight,
              decoration: BoxDecoration(
                color: accent.tint,
                borderRadius: BorderRadius.circular(kRadiusCard),
                border: Border.all(color: accent.fill, width: kBorderWidth),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MediaQuery.withNoTextScaling(
                    child: Text(
                      '$_count',
                      style: AppText.tabular(AppText.display.copyWith(fontSize: 72, height: 1)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _count == 0 ? 'Tap for each rep' : _plural(_count, 'rep', 'reps'),
                    style: AppText.label.copyWith(color: kInkSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _TextAction(label: 'Undo', onTap: _count > 0 ? _undo : null),
            const SizedBox(width: 8),
            _TextAction(label: 'Cancel', onTap: widget.onCancel),
            const SizedBox(width: 12),
            Expanded(
              child: ChunkyButton(
                label: _count == 0 ? 'Done' : 'Use $_count',
                onPressed: _count > 0 ? () => widget.onDone(_count) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _HoldPhase { leadIn, running }

/// Times a hold: a 3 second lead-in, then a countdown from [seconds] with the remaining time in
/// big digits and a firm haptic at the end. Calls [onDone] with the seconds held, which is the full
/// time unless stopped early.
class HoldTimer extends StatefulWidget {
  const HoldTimer({
    super.key,
    required this.seconds,
    required this.onDone,
    required this.onCancel,
    this.now = DateTime.now,
  });

  final int seconds;

  /// The wall clock, read only to measure time spent in the background.
  final DateTime Function() now;
  final ValueChanged<int> onDone;
  final VoidCallback onCancel;

  @override
  State<HoldTimer> createState() => _HoldTimerState();
}

class _HoldTimerState extends State<HoldTimer> {
  Timer? _ticker;
  // Ticks stop while the app is in the background, so a locked phone mid-hold catches up on
  // the time it was away when it comes back.
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;
  _HoldPhase _phase = _HoldPhase.leadIn;
  int _leadIn = kHoldLeadInSeconds;
  late int _remaining = widget.seconds;
  bool _announcedStart = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
    _lifecycle = AppLifecycleListener(onHide: () => _hiddenAt = widget.now(), onShow: _catchUp);
    HapticFeedback.selectionClick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_announcedStart) {
      _announcedStart = true;
      _announce(context, 'Get ready. Starting in $kHoldLeadInSeconds seconds');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _catchUp() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || !(_ticker?.isActive ?? false)) return;
    for (var away = widget.now().difference(hiddenAt).inSeconds; away > 0; away--) {
      _tick(_ticker!);
      if (!(_ticker?.isActive ?? false)) break;
    }
  }

  int get _held => widget.seconds - _remaining;

  void _tick(Timer t) {
    if (!mounted) return t.cancel();
    if (_phase == _HoldPhase.leadIn) {
      setState(() => _leadIn -= 1);
      if (_leadIn > 0) {
        HapticFeedback.selectionClick();
        return;
      }
      setState(() => _phase = _HoldPhase.running);
      HapticFeedback.mediumImpact();
      _announce(context, 'Go');
      return;
    }
    setState(() => _remaining -= 1);
    if (_remaining <= 0) {
      t.cancel();
      HapticFeedback.heavyImpact();
      _announce(context, 'Time. ${widget.seconds} seconds done');
      widget.onDone(widget.seconds);
    }
  }

  void _stop() {
    _ticker?.cancel();
    if (_phase == _HoldPhase.running && _held > 0) {
      widget.onDone(_held);
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    final leadIn = _phase == _HoldPhase.leadIn;
    // The digits are decoration for sighted people: a label that changed every second would have
    // VoiceOver read each one, so the start and the end are announced instead.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: leadIn ? 'Get ready' : 'Hold timer running',
          excludeSemantics: true,
          child: Container(
            height: kCounterHeight,
            decoration: BoxDecoration(
              color: leadIn ? kSunken : accent.tint,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: leadIn ? kBorder : accent.fill, width: kBorderWidth),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MediaQuery.withNoTextScaling(
                  child: Text(
                    leadIn ? '$_leadIn' : '$_remaining',
                    style: AppText.tabular(AppText.display.copyWith(fontSize: 72, height: 1)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  leadIn ? 'Get ready' : 'seconds left',
                  style: AppText.label.copyWith(color: kInkSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ChunkyButton.secondary(
          label: !leadIn && _held > 0
              ? 'Stop at $_held ${_held == 1 ? 'second' : 'seconds'}'
              : 'Cancel',
          onPressed: _stop,
        ),
      ],
    );
  }
}

/// A plain text action with a 44 point tap target.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: context.accentPalette.lip,
        disabledForegroundColor: kInkMuted,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
