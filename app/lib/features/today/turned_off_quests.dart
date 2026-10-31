import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/me.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/dialogs.dart';

/// Switches a quest on or off from Today. The server re-snapshots today, so Today follows at once.
Future<void> setQuestEnabled(WidgetRef ref, String key, bool enabled) => ref
    .read(meProvider.notifier)
    .save(
      MePatch(
        questTemplates: [QuestEdit(key: key, enabled: enabled)],
      ),
    );

List<QuestTemplate> _turnedOff(WidgetRef ref) {
  final templates = ref.watch(meProvider.select((m) => m.value?.data.questTemplates)) ?? const [];
  return [
    for (final t in templates)
      if (!t.enabled) t,
  ]..sort((a, b) => a.position.compareTo(b.position));
}

/// A quiet line under the quest cards naming how many quests are off, opening a sheet to bring
/// one back. Hidden when every quest is on.
class TurnedOffRow extends ConsumerWidget {
  const TurnedOffRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = _turnedOff(ref);
    if (off.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: TextButton.icon(
          onPressed: () => showAppSheet<void>(context, builder: (_) => const TurnedOffSheet()),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: Text(
            off.length == 1 ? '1 quest is off' : '${off.length} quests are off',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            foregroundColor: kInkSecondary,
            minimumSize: const Size(48, 48),
          ),
        ),
      ),
    );
  }
}

/// The quests that are off, each with a button that turns it on for today and onwards.
class TurnedOffSheet extends ConsumerStatefulWidget {
  const TurnedOffSheet({super.key});

  @override
  ConsumerState<TurnedOffSheet> createState() => _TurnedOffSheetState();
}

class _TurnedOffSheetState extends ConsumerState<TurnedOffSheet> {
  String? _busyKey;
  String? _error;

  Future<void> _turnOn(String key) async {
    setState(() {
      _busyKey = key;
      _error = null;
    });
    try {
      await setQuestEnabled(ref, key, true);
      HapticFeedback.lightImpact();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = _turnedOff(ref);
    if (off.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        0,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('Quests that are off', style: AppText.title)),
          const SizedBox(height: 4),
          Text(
            'Turning one on adds it to today.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 12),
          for (final t in off)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: questPalette(t.key).tint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(questIcon(t.key), size: 22, color: questPalette(t.key).lip),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(t.title, style: AppText.label.copyWith(fontSize: 16))),
                  Text('+${t.points}', style: AppText.tabular(AppText.caption)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busyKey == null ? () => _turnOn(t.key) : null,
                    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                    child: Text(
                      _busyKey == t.key ? 'Turning on' : 'Turn on',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: AppText.label.copyWith(color: kDangerText)),
            ),
        ],
      ),
    );
  }
}
