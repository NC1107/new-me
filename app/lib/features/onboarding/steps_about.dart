import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../setup/about_you.dart';
import '../setup/about_you_steps.dart';

/// One "About you" screen inside onboarding. Reading starts here, once Health has had its say,
/// so a height or weight it shared is already on the server when the answers are seeded.
class AboutStep extends ConsumerStatefulWidget {
  const AboutStep({super.key, required this.question, required this.onNext});

  final AboutQuestion question;
  final VoidCallback onNext;

  @override
  ConsumerState<AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends ConsumerState<AboutStep> {
  @override
  void initState() {
    super.initState();
    // Providers cannot change while the tree is building.
    Future.microtask(() {
      if (mounted) ref.read(aboutYouProvider.notifier).ensureBegun();
    });
  }

  @override
  Widget build(BuildContext context) =>
      AboutYouStep(question: widget.question, onNext: widget.onNext);
}
