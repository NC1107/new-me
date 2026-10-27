import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/tokens.dart';
import '../../widgets/step_progress_bar.dart';
import 'about_you.dart';
import 'about_you_steps.dart';

/// "About you" outside onboarding: the same questions, one per screen, from [start] to the
/// targets. Opened from Me, from the Today setup card and from the Targets page.
class AboutYouPage extends ConsumerStatefulWidget {
  const AboutYouPage({super.key, this.start = AboutQuestion.birthYear});

  final AboutQuestion start;

  @override
  ConsumerState<AboutYouPage> createState() => _AboutYouPageState();
}

class _AboutYouPageState extends ConsumerState<AboutYouPage> {
  late int _index = widget.start.index;
  bool _forward = true;

  static const _last = 5;

  @override
  void initState() {
    super.initState();
    // Providers cannot change while the tree is building.
    Future.microtask(() {
      if (mounted) ref.read(aboutYouProvider.notifier).begin();
    });
  }

  void _next() {
    if (_index >= _last) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _forward = true;
      _index++;
    });
  }

  void _back() {
    if (_index <= widget.start.index) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _forward = false;
      _index--;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final span = _last - widget.start.index;
    final key = ValueKey(_index);
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StepProgressBar(
                progress: span == 0 ? 1 : (_index - widget.start.index) / span,
                onBack: _back,
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: AnimatedSwitcher(
                    duration: reduce ? Duration.zero : kPageDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (current, previous) =>
                        Stack(fit: StackFit.expand, children: [...previous, ?current]),
                    transitionBuilder: (child, animation) {
                      final incoming = child.key == key;
                      final shift = (_forward ? 1.0 : -1.0) * 0.12;
                      final offset = Tween<Offset>(
                        begin: Offset(incoming ? shift : -shift, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(position: offset, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: key,
                      child: AboutYouStep(question: AboutQuestion.values[_index], onNext: _next),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
