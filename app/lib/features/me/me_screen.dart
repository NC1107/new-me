import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/me.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/skeletons.dart';
import 'account_sections.dart';
import 'goals_sections.dart';
import 'profile_section.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: CachedView<Me>(
        value: ref.watch(meProvider),
        skeleton: const MeSkeleton(),
        errorTitle: 'Could not load your profile',
        onRetry: ref.read(meProvider.notifier).refresh,
        builder: (context, me, offline) => RefreshIndicator(
          color: context.accent,
          backgroundColor: kBgSurface,
          onRefresh: ref.read(meProvider.notifier).refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
            children: [
              const Text(
                'Me',
                style: TextStyle(color: kFgPrimary, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ProfileSection(me: me, editable: !offline),
              const SizedBox(height: 10),
              TimezoneSection(me: me, editable: !offline),
              const SectionLabel('Targets'),
              TargetsSection(me: me, editable: !offline),
              const SectionLabel('Daily quests'),
              QuestsSection(me: me, editable: !offline),
              const SectionLabel('Health'),
              const HealthSection(),
              if (me.isAdmin) ...[const SectionLabel('Pairing'), const AdminSection()],
              const SectionLabel('About'),
              const AboutSection(),
              const SizedBox(height: 20),
              const LeaveButton(),
            ],
          ),
        ),
      ),
    );
  }
}
