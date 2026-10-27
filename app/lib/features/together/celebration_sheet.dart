import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/confetti.dart';
import '../../widgets/mascot.dart';

/// A full-height "we did it" moment in the style of the day-counted sheet. [onPressed] runs
/// before the sheet closes (a claim, say); if it throws, the sheet stays and says so.
Future<void> showCelebrationSheet(
  BuildContext context, {
  required String title,
  required String message,
  required List<BoardUser> users,
  String buttonLabel = 'Continue',
  Future<void> Function()? onPressed,
}) {
  HapticFeedback.heavyImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: kSurface,
    builder: (_) => CelebrationSheet(
      title: title,
      message: message,
      users: users,
      buttonLabel: buttonLabel,
      onPressed: onPressed,
    ),
  );
}

class CelebrationSheet extends StatefulWidget {
  const CelebrationSheet({
    super.key,
    required this.title,
    required this.message,
    required this.users,
    this.buttonLabel = 'Continue',
    this.onPressed,
  });

  final String title;
  final String message;
  final List<BoardUser> users;
  final String buttonLabel;
  final Future<void> Function()? onPressed;

  @override
  State<CelebrationSheet> createState() => _CelebrationSheetState();
}

class _CelebrationSheetState extends State<CelebrationSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _press() async {
    final action = widget.onPressed;
    if (action == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'That did not go through. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Mascot(size: 150, state: MascotState.cheer),
        const SizedBox(height: 12),
        if (widget.users.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final u in widget.users)
                Avatar(name: u.name, palette: accentById(u.color), size: 40),
            ],
          ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(widget.title, textAlign: TextAlign.center, style: AppText.display),
        ),
        const SizedBox(height: 10),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: AppText.headline.copyWith(color: kInkSecondary, fontWeight: FontWeight.w700),
        ),
      ],
    );
    return SizedBox.expand(
      child: Stack(
        children: [
          const Positioned.fill(
            child: Confetti(origin: Alignment(0, -0.35), particles: 90, spread: 1.1),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 20),
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Center(child: content),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppText.label.copyWith(
                        color: kDangerText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  ChunkyButton(label: widget.buttonLabel, busy: _busy, onPressed: _press),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
