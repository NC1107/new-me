import 'package:flutter/material.dart';

import '../state/cached_resource.dart';
import '../theme/tokens.dart';
import '../util/time_format.dart';

/// The slim strip above a screen that is drawn from its last good response.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.info});

  final OfflineInfo info;

  @override
  Widget build(BuildContext context) {
    final time = formatClock(info.updatedAt.toLocal());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: kBgSurface,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 14, color: kFgMuted),
          const SizedBox(width: 8),
          Text(
            'Offline, updated $time',
            style: const TextStyle(color: kFgSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
