import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/me.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/confetti.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';
import 'cheer_style.dart';

Future<void> showCheerSheet(BuildContext context, {required BoardUser partner}) =>
    showAppSheet<void>(context, builder: (_) => CheerSheet(partner: partner));

/// Four reactions for the partner's day. Each can be sent once a day; a sent one stays marked.
class CheerSheet extends ConsumerStatefulWidget {
  const CheerSheet({super.key, required this.partner});

  final BoardUser partner;

  @override
  ConsumerState<CheerSheet> createState() => _CheerSheetState();
}

class _CheerSheetState extends ConsumerState<CheerSheet> {
  int _burst = 0;
  CheerKind? _burstKind;
  String? _error;

  String get _date =>
      ref.read(meProvider).value?.data.localToday ?? formatDateKey(ref.read(clockProvider)());

  Future<void> _send(CheerKind kind) async {
    setState(() {
      _error = null;
      _burstKind = kind;
      _burst++;
    });
    try {
      await ref
          .read(cheerMemoryProvider.notifier)
          .send(to: widget.partner.id, kind: kind, date: _date);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Could not send that cheer');
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(cheerMemoryProvider);
    final partner = widget.partner;
    final date = _date;
    final kinds = CheerKind.values;
    final burstIndex = _burstKind == null ? 0 : kinds.indexOf(_burstKind!);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            kGutter,
            4,
            kGutter,
            kGutter + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Avatar(name: partner.name, palette: accentById(partner.color), size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Cheer ${partner.name}', style: AppText.title),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'One of each a day. ${partner.name} gets a little nudge.',
                style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final kind in kinds)
                    _ReactionButton(
                      kind: kind,
                      partnerName: partner.name,
                      sent: memory.hasSent(date, partner.id, kind),
                      onTap: () => _send(kind),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
                ),
              ],
              const SizedBox(height: 22),
              ChunkyButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Positioned.fill(
          child: Confetti(
            autoplay: false,
            burst: _burst,
            origin: Alignment(-0.75 + burstIndex * 0.5, -0.1),
            colors: [
              for (final k in kinds) k.palette.fill,
              (_burstKind ?? CheerKind.heart).palette.lip,
            ],
            particles: 36,
            spread: 0.55,
            duration: const Duration(milliseconds: 1200),
          ),
        ),
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.kind,
    required this.partnerName,
    required this.sent,
    required this.onTap,
  });

  final CheerKind kind;
  final String partnerName;
  final bool sent;
  final VoidCallback onTap;

  static const _size = 72.0;

  @override
  Widget build(BuildContext context) {
    final palette = kind.palette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        button: true,
        selected: sent,
        label: sent ? '${kind.label} sent to $partnerName' : 'Send ${kind.label} to $partnerName',
        excludeSemantics: true,
        onTap: sent ? null : onTap,
        child: SizedBox(
          width: 76,
          child: Pressable(
            haptic: !sent,
            onTap: sent ? null : onTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: reduce ? Duration.zero : kMotionDuration,
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: sent ? palette.fill : palette.tint,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    border: Border.all(color: palette.fill, width: kBorderWidth),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(kind.icon, size: 38, color: sent ? palette.onFill : palette.lip),
                      if (sent)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Icon(Icons.check_circle_rounded, size: 20, color: palette.onFill),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  sent ? 'Sent' : kind.label,
                  maxLines: 1,
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w800,
                    color: sent ? palette.lip : kInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
