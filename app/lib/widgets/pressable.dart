import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Gives anything tappable the app's press feel: it shrinks while held and answers with a light
/// haptic. Semantics are the caller's job.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = kTapScale,
    this.haptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;

  /// Null disables the press feedback too.
  final VoidCallback? onTap;

  /// A press held down; it answers with a firmer haptic than a tap.
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior behavior;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final instant = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onLongPress: enabled && widget.onLongPress != null
          ? () {
              _set(false);
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      onTap: enabled
          ? () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: instant ? Duration.zero : kTapDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
