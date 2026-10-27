import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/clock.dart';
import '../../state/health_sync.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/page_scaffold.dart';
import '../health/health_metrics.dart';
import '../health/health_screen.dart';
import 'settings_row.dart';

/// Whether Apple Health is connected, when it last synced and what New Me reads from it.
class AppleHealthPage extends ConsumerWidget {
  const AppleHealthPage({super.key});

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(healthSyncProvider.notifier).sync(SyncTrigger.manual);
    if (ok || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Could not sync right now. Try again soon.')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthSyncProvider);
    final synced = health.lastSyncedAt;
    final connected = health.prompted;
    final heartPalette = accentById('rose');
    return PageScaffold(
      title: 'Apple Health',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Mascot(size: 64, state: connected ? MascotState.happy : MascotState.thinking),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(connected ? 'Connected' : 'Not connected', style: AppText.headline),
                        const SizedBox(height: 2),
                        Text(
                          !connected
                              ? 'Connect it so your days count on their own.'
                              : synced == null
                              ? 'Not synced yet'
                              : 'Last sync ${relativeTime(synced, ref.watch(clockProvider)())}',
                          style: AppText.label.copyWith(color: kInkSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (connected)
                ChunkyButton(
                  label: 'Sync now',
                  icon: Icons.sync_rounded,
                  busy: health.syncing,
                  onPressed: () => _sync(context, ref),
                )
              else
                ChunkyButton(
                  label: 'Connect Apple Health',
                  icon: Icons.favorite_rounded,
                  busy: health.syncing,
                  onPressed: () => ref.read(healthSyncProvider.notifier).connect(),
                ),
            ],
          ),
        ),
        if (connected) ...[
          const SizedBox(height: kCardGap),
          SettingsGroup(
            rows: [
              SettingsRow(
                icon: Icons.insights_rounded,
                palette: heartPalette,
                title: 'See your numbers',
                subtitle: 'Today and the last 90 days',
                onTap: () => pushPage(context, const HealthScreen()),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text('What New Me reads', style: AppText.headline.copyWith(fontSize: 18)),
        ),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (final (i, group) in kHealthGroups.indexed) ...[
                if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                _ReadGroup(group: group),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_rounded, size: 18, color: kInkSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'New Me never writes to Health. To change what it can read, open Health > '
                'Sharing > Apps > New Me.',
                style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadGroup extends StatelessWidget {
  const _ReadGroup({required this.group});

  final HealthGroup group;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: group.palette.tint, shape: BoxShape.circle),
          child: Icon(group.icon, size: 22, color: group.palette.lip),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
              Text(
                group.metrics.map((m) => m.name).join(', '),
                style: AppText.caption.copyWith(color: kInkSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
