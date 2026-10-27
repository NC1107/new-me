import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Scales and fades its child in with a small overshoot, for badges and checks that appear.
/// Jumps straight to the end when animations are disabled.
class PopIn extends StatefulWidget {
  const PopIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = kPopDuration,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_controller.value);
        return Opacity(
          opacity: (_controller.value * 3).clamp(0.0, 1.0),
          child: Transform.scale(scale: t.clamp(0.0, 1.4), child: child),
        );
      },
    );
  }
}
