import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/habit_proposals.dart';
import '../../state/session.dart';
import '../../state/together.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/pressable.dart';

const kRewardNameIdeas = ['Date night', 'Dinner out', 'Movie night', 'Day trip'];
const kRewardNameMax = 40;
const kRewardPriceMax = 100000;

/// Adds a reward to the wishlist, or edits [reward].
Future<void> showRewardSheet(BuildContext context, {Reward? reward}) =>
    showAppSheet<void>(context, builder: (_) => RewardSheet(reward: reward));

/// Name a treat and price it in gems, with prices suggested from the pair's own pace. For an
/// existing reward it also holds what can be done with it: withdraw, cancel, focus or claim.
class RewardSheet extends ConsumerStatefulWidget {
  const RewardSheet({super.key, this.reward});

  final Reward? reward;

  @override
  ConsumerState<RewardSheet> createState() => _RewardSheetState();
}

class _RewardSheetState extends ConsumerState<RewardSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.reward?.name ?? '');
  late final TextEditingController _price = TextEditingController(
    text: widget.reward == null ? _suggestedStart() : '${widget.reward!.price}',
  );
  bool _busy = false;
  String? _error;

  Reward? get _existing => widget.reward;

  String _suggestedStart() {
    final options = ref.read(rewardsProvider).value?.priceHelp?.options ?? const <PriceOption>[];
    final twoWeeks = options.where((o) => o.days == 14);
    return twoWeeks.isEmpty ? '' : '${twoWeeks.first.price}';
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  int? get _priceValue {
    final v = int.tryParse(_price.text.trim());
    return v == null || v < 1 || v > kRewardPriceMax ? null : v;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _priceValue != null;

  bool get _priceChangesApproved =>
      _existing != null && _existing!.approved && _priceValue != _existing!.price;

  Future<void> _run(
    Future<void> Function(RewardsNotifier rewards) action, {
    String? failure,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(rewardsProvider.notifier));
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failure ?? errorCopy(e);
        });
      }
    }
  }

  Future<void> _submit() {
    final name = _name.text.trim();
    final price = _priceValue!;
    final existing = _existing;
    if (!_valid) return Future.value();
    return _run(
      (rewards) => existing == null
          ? rewards.propose(name: name, price: price)
          : rewards.edit(
              existing.id,
              name: name == existing.name ? null : name,
              price: price == existing.price ? null : price,
            ),
    );
  }

  String _submitLabel(String? partner) {
    final existing = _existing;
    if (existing == null) return partner == null ? 'Add reward' : 'Propose reward';
    if (existing.declined) return 'Propose again';
    if (_priceChangesApproved && partner != null) return 'Propose new price';
    return 'Save';
  }

  String _caption(String? partner) {
    final existing = _existing;
    if (existing == null) {
      return partner == null
          ? 'Gems you earn pile up in the shared bank.'
          : '$partner approves it before it joins the wishlist.';
    }
    if (existing.pending) return 'Waiting for ${partner ?? 'your partner'} to answer.';
    if (existing.declined) {
      return '${partner ?? 'Your partner'} declined it. Change it or withdraw it.';
    }
    if (_priceChangesApproved && partner != null) {
      return 'A new price goes to $partner to approve again.';
    }
    return 'Both of you can rename it.';
  }

  @override
  Widget build(BuildContext context) {
    final person = context.accentPalette;
    final partner = ref.watch(partnerNameProvider);
    final list = ref.watch(rewardsProvider).value;
    final help = list?.priceHelp;
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final existing = _existing;
    final mine = existing != null && existing.proposedByUser(userId);
    final selected = help?.options.where((o) => o.price == _priceValue);
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
          Semantics(
            header: true,
            child: Text(existing == null ? 'Add a reward' : 'Edit reward', style: AppText.title),
          ),
          const SizedBox(height: 4),
          Text(
            _caption(partner),
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
          if (existing == null) ...[
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
          ],
          const SizedBox(height: 20),
          const FieldLabel('Price in gems'),
          if (help != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in help.options)
                  _Pill(
                    label: '${o.price.formatted} - ${o.span}',
                    selected: _priceValue == o.price,
                    palette: person,
                    onTap: () => setState(() => _price.text = '${o.price}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selected != null && selected.isNotEmpty
                  ? 'About ${selected.first.span} at your pace.'
                  : 'A typical day for you two is ${help.medianDaily.formatted} gems '
                        '(last ${help.sampleDays} days).',
              style: AppText.caption,
            ),
            const SizedBox(height: 10),
          ],
          AppTextField(
            controller: _price,
            hint: help == null ? 'Gems, like 1,500' : 'Or type a number',
            semanticLabel: 'Price in gems',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            errorText: _price.text.isNotEmpty && _priceValue == null
                ? 'Between 1 and ${kRewardPriceMax.formatted}'
                : null,
            onChanged: (_) => setState(() {}),
          ),
          if (list != null) ...[
            const SizedBox(height: 8),
            Text('Bank: ${list.bank.formatted} gems', style: AppText.caption),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 20),
          if (existing != null && existing.ready) ...[
            Semantics(
              container: true,
              child: ChunkyButton(
                label: 'We did it',
                icon: Icons.celebration_rounded,
                busy: _busy,
                onPressed: _busy ? null : () => _run((r) => r.claim(existing.id)),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Semantics(
            container: true,
            child: existing != null && existing.ready
                ? ChunkyButton.secondary(
                    label: _submitLabel(partner),
                    busy: _busy,
                    onPressed: _valid && !_busy ? _submit : null,
                  )
                : ChunkyButton(
                    label: _submitLabel(partner),
                    busy: _busy,
                    onPressed: _valid && !_busy ? _submit : null,
                  ),
          ),
          if (existing != null && existing.approved && !existing.focus) ...[
            const SizedBox(height: 10),
            ChunkyButton.secondary(
              label: 'Make it the focus',
              icon: Icons.flag_rounded,
              onPressed: _busy ? null : () => _run((r) => r.setFocus(existing.id)),
            ),
          ],
          if (existing != null && (existing.pending || existing.declined) && mine) ...[
            const SizedBox(height: 10),
            ChunkyButton.secondary(
              label: 'Withdraw',
              onPressed: _busy ? null : () => _run((r) => r.withdraw(existing.id)),
            ),
          ],
          if (existing != null && existing.approved) ...[
            const SizedBox(height: 10),
            ChunkyButton.secondary(
              label: 'Cancel reward',
              onPressed: _busy ? null : () => _run((r) => r.cancel(existing.id)),
            ),
          ],
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
