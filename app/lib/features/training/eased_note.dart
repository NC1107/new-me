import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';

/// Why today's session is eased, with a small way to take the full session instead. The action
/// goes once a set is logged, because the server keeps a started session as it was.
class EasedNote extends ConsumerStatefulWidget {
  const EasedNote({super.key, required this.session});

  final TrainingSession session;

  @override
  ConsumerState<EasedNote> createState() => _EasedNoteState();
}

class _EasedNoteState extends ConsumerState<EasedNote> {
  bool _busy = false;
  String? _error;

  Future<void> _takeFull() async {
    HapticFeedback.selectionClick();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(trainingTodayProvider.notifier).takeFullSession();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final accent = context.accentPalette;
    final reason = session.easedReason.isEmpty ? 'Today is one set lighter.' : session.easedReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(reason, style: AppText.caption.copyWith(color: kInkSecondary)),
        if (_error case final error?)
          Text(error, style: AppText.caption.copyWith(color: kDangerText)),
        if (session.canTakeFull)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _takeFull,
              style: TextButton.styleFrom(
                foregroundColor: accent.lip,
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Do the full session',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
      ],
    );
  }
}
