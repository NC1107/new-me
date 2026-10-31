import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/coach_models.dart';
import '../../state/coach_chat.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';

/// Opens the coach chat from Today or Insights.
Future<void> openCoachChat(BuildContext context) => pushPage(context, const CoachChatPage());

/// Questions the empty chat offers, each answerable from the person's own data.
const kCoachStarters = [
  'How was my week?',
  'What should I improve first?',
  'Why did I miss my sleep goal?',
];

const _kDisclaimer =
    'Answers come only from your own numbers and the research behind your targets. '
    'General guidance, not medical advice.';

/// A chat with the coach: plain text in and out, the thread kept on the phone for the day.
class CoachChatPage extends ConsumerStatefulWidget {
  const CoachChatPage({super.key});

  @override
  ConsumerState<CoachChatPage> createState() => _CoachChatPageState();
}

class _CoachChatPageState extends ConsumerState<CoachChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String text) {
    HapticFeedback.selectionClick();
    _input.clear();
    ref.read(coachChatProvider.notifier).send(text);
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: kMotionDuration, curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(coachChatProvider);
    ref.listen(coachChatProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length ||
          prev?.sending != next.sending ||
          prev?.error != next.error) {
        _toEnd();
      }
    });
    final empty = chat.messages.isEmpty && !chat.sending;
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Column(
              children: [
                _Header(onNew: chat.messages.isEmpty || chat.sending ? null : _confirmNew),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 16),
                    children: [
                      if (empty) _Intro(onPick: _send) else const _Disclaimer(),
                      for (final m in chat.messages) _Bubble(message: m),
                      if (chat.sending) const _Typing(),
                      if (chat.error != null)
                        _ErrorBubble(
                          message: chat.error!,
                          onRetry: () => ref.read(coachChatProvider.notifier).retry(),
                        ),
                    ],
                  ),
                ),
                _Composer(controller: _input, busy: chat.sending, onSend: _send),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmNew() async {
    HapticFeedback.selectionClick();
    await ref.read(coachChatProvider.notifier).clear();
    _input.clear();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNew});

  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.arrow_back_rounded, size: 28, color: kInk),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(header: true, child: const Text('Coach', style: AppText.title)),
          ),
          IconButton(
            onPressed: onNew,
            tooltip: 'New chat',
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: Icon(Icons.edit_square, size: 24, color: onNew == null ? kLip : kInkSecondary),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 12),
    child: Text(_kDisclaimer, style: AppText.caption),
  );
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_rounded, size: 28, color: palette.lip),
        ),
        const SizedBox(height: 16),
        const Text('Ask about your days', style: AppText.headline),
        const SizedBox(height: 6),
        const Text(_kDisclaimer, style: AppText.caption),
        const SizedBox(height: 20),
        for (final q in kCoachStarters) ...[
          _Starter(text: q, onTap: () => onPick(q)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Starter extends StatelessWidget {
  const _Starter({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusButton),
              border: Border.all(color: kBorder, width: kBorderWidth),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(text, style: AppText.body.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.north_east_rounded, size: 20, color: kInkMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.isUser;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(kRadiusCard),
      topRight: const Radius.circular(kRadiusCard),
      bottomLeft: Radius.circular(mine ? kRadiusCard : 4),
      bottomRight: Radius.circular(mine ? 4 : kRadiusCard),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
          child: Semantics(
            container: true,
            label: '${mine ? 'You' : 'Coach'}: ${message.text}',
            excludeSemantics: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: mine ? context.accentTint : kSurface,
                borderRadius: radius,
                border: mine ? null : Border.all(color: kBorder, width: kBorderWidth),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: SelectableText(message.text, style: AppText.body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that fade in turn while the coach works; still when motion is reduced.
class _Typing extends StatefulWidget {
  const _Typing();

  @override
  State<_Typing> createState() => _TypingState();
}

class _TypingState extends State<_Typing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          liveRegion: true,
          label: 'Coach is typing',
          excludeSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(kRadiusCard),
                topRight: Radius.circular(kRadiusCard),
                bottomRight: Radius.circular(kRadiusCard),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: kBorder, width: kBorderWidth),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Opacity(opacity: _opacity(i), child: const _Dot()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _opacity(int i) {
    if (!_c.isAnimating) return 0.6;
    final phase = (_c.value - i * 0.18) % 1.0;
    return 0.25 + 0.75 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 8,
    height: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(color: kInkMuted, shape: BoxShape.circle),
    ),
  );
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.84),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: kDanger, width: kBorderWidth),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(message, style: AppText.body.copyWith(color: kDangerText)),
                  ),
                  const SizedBox(height: 10),
                  ChunkyButton.secondary(
                    label: 'TRY AGAIN',
                    icon: Icons.refresh_rounded,
                    fullWidth: false,
                    onPressed: onRetry,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.busy, required this.onSend});

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: kCanvas,
        border: Border(top: BorderSide(color: kBorder)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(kGutter, 10, 12, 10 + MediaQuery.paddingOf(context).bottom),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final canSend = !busy && controller.text.trim().isNotEmpty;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: kCoachMaxChars,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: canSend ? onSend : null,
                    style: AppText.body,
                    decoration: InputDecoration(
                      hintText: 'Ask your coach',
                      counterText: '',
                      filled: true,
                      fillColor: kSurface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: _border(kBorder),
                      enabledBorder: _border(kBorder),
                      focusedBorder: _border(palette.fill),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  enabled: canSend,
                  label: 'Send',
                  excludeSemantics: true,
                  onTap: canSend ? () => onSend(controller.text) : null,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Pressable(
                      onTap: canSend ? () => onSend(controller.text) : null,
                      child: Center(
                        child: AnimatedContainer(
                          duration: kMotionDuration,
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: canSend ? palette.fill : kSunken,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 22,
                            color: canSend ? palette.onFill : kInkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(kRadiusField),
    borderSide: BorderSide(color: color, width: kBorderWidth),
  );
}
