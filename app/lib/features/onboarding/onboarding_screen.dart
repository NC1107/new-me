import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/app_widgets.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Text(
                'New Me',
                textAlign: TextAlign.center,
                style: TextStyle(color: kFgPrimary, fontSize: 34, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              PrimaryButton(label: 'Get started', enabled: false, onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}
