import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/mascot.dart';
import '../../widgets/speech_bubble.dart';

/// One onboarding screen: scrolling content with a footer of buttons pinned below it.
class StepLayout extends StatelessWidget {
  const StepLayout({super.key, required this.children, this.footer = const []});

  final List<Widget> children;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
        if (footer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, kGutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < footer.length; i++) ...[
                  if (i > 0) const SizedBox(height: kCardGap),
                  footer[i],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The mascot beside a one-line speech bubble, at the top of most steps.
class MascotLine extends StatelessWidget {
  const MascotLine({super.key, required this.line, this.state = MascotState.idle});

  final String line;
  final MascotState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Mascot(size: 84, state: state),
        const SizedBox(width: 4),
        Flexible(child: SpeechBubble(text: line)),
      ],
    );
  }
}

class StepTitle extends StatelessWidget {
  const StepTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: AppText.title)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: AppText.body.copyWith(color: kInkSecondary)),
          ],
        ],
      ),
    );
  }
}

/// The inline error line under a field or list.
class StepError extends StatelessWidget {
  const StepError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline_rounded, size: 18, color: kDanger),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message, style: AppText.label.copyWith(color: kDangerText)),
          ),
        ],
      ),
    );
  }
}
