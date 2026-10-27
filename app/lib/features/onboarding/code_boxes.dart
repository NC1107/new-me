import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';

/// Four boxes of four characters over one hidden text field, so typing advances from box to
/// box, backspace walks back and a pasted code fills them all. A rejected code shakes them.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    this.hasError = false,
    this.shakeTick = 0,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final bool hasError;

  /// Changes every time the code is rejected, replaying the shake.
  final int shakeTick;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> with SingleTickerProviderStateMixin {
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void didUpdateWidget(CodeBoxes old) {
    super.didUpdateWidget(old);
    if (old.shakeTick != widget.shakeTick && !MediaQuery.disableAnimationsOf(context)) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final symbols = widget.controller.text.replaceAll('-', '');
    final active = math.min(symbols.length ~/ 4, 3);
    final palette = context.accentPalette;
    final reduce = MediaQuery.disableAnimationsOf(context);

    final boxes = Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : kMotionDuration,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(kRadiusField),
                border: Border.all(
                  color: widget.hasError
                      ? kDanger
                      : (_focus.hasFocus && i == active ? palette.fill : kBorder),
                  width: kBorderWidth,
                ),
              ),
              child: Text(
                symbols.length > i * 4
                    ? symbols.substring(i * 4, math.min(symbols.length, i * 4 + 4))
                    : '',
                maxLines: 1,
                style: AppText.tabular(AppText.headline.copyWith(letterSpacing: 2.5)),
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      label: 'Invite code',
      textField: true,
      child: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
        child: Stack(
          children: [
            ExcludeSemantics(child: IgnorePointer(child: boxes)),
            Positioned.fill(
              child: Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: const TextSelectionThemeData(
                    cursorColor: Colors.transparent,
                    selectionColor: Colors.transparent,
                    selectionHandleColor: Colors.transparent,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.text,
                  inputFormatters: const [InviteCodeFormatter()],
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(color: Colors.transparent, fontSize: 1),
                  cursorColor: Colors.transparent,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    isCollapsed: true,
                  ),
                  onChanged: widget.onChanged,
                  onSubmitted: (_) => widget.onSubmitted(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
