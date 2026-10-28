import 'package:intl/intl.dart';

import 'dart:async';

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
import '../../state/health_history.dart';

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
          const _HistoryCard(),
          const SizedBox(height: kCardGap),
          const _AccessCard(),
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

/// "Imported back to March 2021": the Health history import, and a way to start or re-run it.
class _HistoryCard extends ConsumerWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(healthHistoryProvider);
    final reached = h.reached == null
        ? null
        : DateFormat('MMMM y').format(parseLocalDate(h.reached!));
    final line = h.running
        ? 'Importing your history${reached == null ? '' : ', back to $reached so far'}.'
        : h.done
        ? 'All of your Health history is in${reached == null ? '' : ', back to $reached'}.'
        : reached == null
        ? 'Bring in every day Apple Health holds, so insights and look-backs start from your past.'
        : 'Imported back to $reached. It carries on when you open New Me.';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Health history', style: AppText.headline.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(line, style: AppText.label.copyWith(color: kInkSecondary)),
          if (h.error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: AppText.caption.copyWith(color: kDangerText)),
          ],
          const SizedBox(height: 6),
          Text(
            'Past days fill your insights and look-backs. They never change a score.',
            style: AppText.caption.copyWith(color: kInkMuted),
          ),
          const SizedBox(height: 12),
          ChunkyButton.secondary(
            label: h.done ? 'Import again' : 'Import history',
            icon: Icons.history_rounded,
            busy: h.running,
            onPressed: () => ref.read(healthHistoryProvider.notifier).run(restart: h.done),
          ),
        ],
      ),
    );
  }
}

/// Apple Health shows its permission sheet once per kind of data, so this asks again for
/// anything not yet decided and says where to turn on what was declined.
class _AccessCard extends ConsumerWidget {
  const _AccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What New Me can read', style: AppText.headline.copyWith(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Apple asks only once for each kind of data. To share something you turned off, open '
          'Settings, then Health, then Data Access and Devices, then New Me, and turn on '
          'All Categories.',
          style: AppText.label.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 12),
        ChunkyButton.secondary(
          label: 'Ask again',
          icon: Icons.favorite_border_rounded,
          onPressed: () async {
            await ref.read(healthSyncProvider.notifier).connect();
            unawaited(ref.read(healthHistoryProvider.notifier).run());
          },
        ),
      ],
    ),
  );
}
