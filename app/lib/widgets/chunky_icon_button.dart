import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'chunky_button.dart';

/// A round chunky button with an icon: the face rests on a lip and drops onto it when pressed.
/// The tap target is at least 44 square even when the disc is smaller.
class ChunkyIconButton extends StatefulWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 36,
    this.kind = ChunkyKind.primary,
    this.palette,
    this.iconSize,
  });

  final IconData icon;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// Diameter of the disc.
  final double size;
  final ChunkyKind kind;
  final AccentPalette? palette;
  final double? iconSize;

  @override
  State<ChunkyIconButton> createState() => _ChunkyIconButtonState();
}

class _ChunkyIconButtonState extends State<ChunkyIconButton> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? context.accentPalette;
    final enabled = widget.onPressed != null;
    final primary = widget.kind == ChunkyKind.primary;
    final Color face;
    final Color lip;
    final Color icon;
    if (!enabled) {
      face = kSunken;
      lip = kBorder;
      icon = kInkMuted;
    } else if (primary) {
      face = palette.fill;
      lip = palette.lip;
      icon = palette.onFill;
    } else {
      face = kSurface;
      lip = kLip;
      icon = palette.lip;
    }

    final lipHeight = (widget.size * 0.1).clamp(3.0, 5.0);
    final hit = widget.size < 44 ? 44.0 : widget.size;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : kTapDuration;
    final disc = SizedBox(
      width: widget.size,
      height: widget.size + lipHeight,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: lipHeight,
            height: widget.size,
            child: DecoratedBox(
              decoration: BoxDecoration(color: lip, shape: BoxShape.circle),
            ),
          ),
          AnimatedPositioned(
            duration: duration,
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: _down && enabled ? lipHeight : 0,
            height: widget.size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: face,
                shape: BoxShape.circle,
                border: primary || !enabled
                    ? null
                    : Border.all(color: kBorder, width: kBorderWidth),
              ),
              child: Icon(widget.icon, size: widget.iconSize ?? widget.size * 0.56, color: icon),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          width: hit,
          height: hit,
          child: Center(child: disc),
        ),
      ),
    );
  }
}
