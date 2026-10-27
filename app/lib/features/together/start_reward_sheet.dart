import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';

const kRewardTargetPresets = [2000, 5000, 10000];
const kRewardNameIdeas = ['Date night', 'Dinner out', 'Movie night', 'Day trip'];
const kRewardNameMax = 40;
const kRewardTargetMax = 100000;

Future<void> showStartRewardSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const StartRewardSheet());

/// Name a treat and pick how many combined points earn it.
class StartRewardSheet extends ConsumerStatefulWidget {
  const StartRewardSheet({super.key});

  @override
  ConsumerState<StartRewardSheet> createState() => _StartRewardSheetState();
}

class _StartRewardSheetState extends ConsumerState<StartRewardSheet> {
  final _name = TextEditingController();
  final _target = TextEditingController(text: '${kRewardTargetPresets[1]}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  int? get _targetValue {
    final v = int.tryParse(_target.text.trim());
    return v == null || v < 1 || v > kRewardTargetMax ? null : v;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _targetValue != null;

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(rewardsProvider.notifier)
          .start(name: _name.text.trim(), target: _targetValue!);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'reward_active') {
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not start the reward';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('Start a reward', style: AppText.title)),
          const SizedBox(height: 4),
          Text(
            'Points you both earn from now on count toward it.',
            style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          const FieldLabel('What are you earning?'),
          AppTextField(
            controller: _name,
            hint: 'Date night',
            semanticLabel: 'Reward name',
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(kRewardNameMax)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final idea in kRewardNameIdeas)
                _Pill(
                  label: idea,
                  selected: _name.text.trim() == idea,
                  palette: person,
                  onTap: () => setState(() => _name.text = idea),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const FieldLabel('How many points together?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in kRewardTargetPresets)
                _Pill(
                  label: p.formatted,
                  selected: _targetValue == p,
                  palette: person,
                  onTap: () => setState(() => _target.text = '$p'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _target,
            hint: 'Or type a number',
            semanticLabel: 'Target points',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            errorText: _target.text.isNotEmpty && _targetValue == null
                ? 'Between 1 and ${kRewardTargetMax.formatted}'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 20),
          Semantics(
            container: true,
            child: ChunkyButton(
              label: 'Start reward',
              busy: _busy,
              onPressed: _valid ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AccentPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      scale: 0.97,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? palette.tint : kSurface,
          borderRadius: BorderRadius.circular(kRadiusButton),
          border: Border.all(color: selected ? palette.fill : kBorder, width: kBorderWidth),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            style: AppText.tabular(
              AppText.label.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? palette.lip : kInk,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
