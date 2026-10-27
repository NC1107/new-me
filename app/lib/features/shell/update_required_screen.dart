import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Blocks the whole app when the server no longer accepts this build.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_outlined, size: 44, color: kFgMuted),
                SizedBox(height: 14),
                Text(
                  'Update required',
                  style: TextStyle(color: kFgPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'This version of New Me is too old for the server. '
                  'Install the latest build from TestFlight, then open the app again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
