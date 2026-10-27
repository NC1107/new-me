import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/accent.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

enum ChunkyKind { primary, secondary }

/// The app's tactile button: a 52 tall face resting on a 4px lip. Pressed, the face drops onto
/// the lip. Primary is filled in the person's colour, secondary is white with a border.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ChunkyKind.primary,
    this.busy = false,
    this.fullWidth = true,
    this.icon,
    this.palette,
  });

  const ChunkyButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.fullWidth = true,
    this.icon,
    this.palette,
  }) : kind = ChunkyKind.secondary;

  static const faceHeight = 52.0;
  static const lipHeight = 4.0;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final ChunkyKind kind;

  /// Shows a spinner and ignores taps, without changing the button's size.
  final bool busy;
  final bool fullWidth;
  final IconData? icon;

  /// Overrides the person colour from the theme.
  final AccentPalette? palette;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? context.accentPalette;
    final primary = widget.kind == ChunkyKind.primary;
    final disabled = widget.onPressed == null;

    final Color face;
    final Color lip;
    final Color text;
    final Color? border;
    if (disabled) {
      face = kSunken;
      lip = kBorder;
      text = kInkMuted;
      border = null;
    } else if (primary) {
      face = palette.fill;
      lip = palette.lip;
      text = palette.onFill;
      border = null;
    } else {
      face = kSurface;
      lip = kLip;
      text = palette.lip;
      border = kBorder;
    }

    final travel = _down && _enabled ? ChunkyButton.lipHeight : 0.0;
    final instant = MediaQuery.disableAnimationsOf(context);
    final duration = instant ? Duration.zero : kTapDuration;
    final radius = BorderRadius.circular(kRadiusButton);

    final content = widget.busy
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 3, color: text),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: text),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.button.copyWith(color: text),
                ),
              ),
            ],
          );

    final button = SizedBox(
      height: ChunkyButton.faceHeight + ChunkyButton.lipHeight,
      width: widget.fullWidth ? double.infinity : null,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: ChunkyButton.lipHeight,
            height: ChunkyButton.faceHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(color: lip, borderRadius: radius),
            ),
          ),
          AnimatedPositioned(
            duration: duration,
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            top: travel,
            height: ChunkyButton.faceHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: face,
                borderRadius: radius,
                border: border == null ? null : Border.all(color: border, width: kBorderWidth),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(widthFactor: widget.fullWidth ? null : 1, child: content),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _set(true) : null,
        onTapUp: _enabled ? (_) => _set(false) : null,
        onTapCancel: _enabled ? () => _set(false) : null,
        onTap: _enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: widget.fullWidth
            ? button
            : IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 96),
                  child: button,
                ),
              ),
      ),
    );
  }
}
