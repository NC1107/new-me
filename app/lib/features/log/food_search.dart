import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/log_actions.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/pressable.dart';

const _debounce = Duration(milliseconds: 250);

/// "Search your foods": the household library, most used first, with USDA and Open Food Facts
/// results below on request. Tapping a food hands it to [onAdd] as one serving.
class FoodSearchBox extends ConsumerStatefulWidget {
  const FoodSearchBox({super.key, required this.onAdd, this.enabled = true});

  final ValueChanged<SavedFood> onAdd;
  final bool enabled;

  @override
  ConsumerState<FoodSearchBox> createState() => _FoodSearchBoxState();
}

class _FoodSearchBoxState extends ConsumerState<FoodSearchBox> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _generation = 0;
  FoodSearch _result = const FoodSearch();
  List<SavedFood> _candidates = const [];
  bool _searchingRemote = false;
  bool _failed = false;

  String get _query => _text.text.trim();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus && _result.foods.isEmpty && _query.isEmpty) _search();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String _) {
    _timer?.cancel();
    setState(() => _candidates = const []);
    _timer = Timer(_debounce, _search);
  }

  Future<void> _search() async {
    final generation = ++_generation;
    try {
      final result = await ref.read(logActionsProvider).searchFoods(_query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = result;
        _failed = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _searchDatabases() async {
    final generation = ++_generation;
    setState(() => _searchingRemote = true);
    try {
      final result = await ref.read(logActionsProvider).searchFoods(_query, remote: true);
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = result;
        _candidates = result.candidates;
        _searchingRemote = false;
        _failed = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searchingRemote = false;
        _failed = true;
      });
    }
  }

  void _add(SavedFood food) {
    widget.onAdd(food);
    _generation++;
    _text.clear();
    _focus.unfocus();
    setState(() {
      _result = const FoodSearch();
      _candidates = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = _focus.hasFocus || _query.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _text,
          hint: 'Search your foods',
          semanticLabel: 'Search your foods',
          onChanged: _typed,
          focusNode: _focus,
        ),
        if (open) ...[
          const SizedBox(height: 8),
          for (final food in _result.foods.take(6))
            _FoodTile(food: food, enabled: widget.enabled, onTap: () => _add(food)),
          if (_result.foods.isEmpty && !_failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _query.isEmpty ? 'Foods you save will show up here.' : 'Nothing saved matches.',
                style: AppText.label.copyWith(color: kInkSecondary),
              ),
            ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Could not search right now.',
                style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
              ),
            ),
          if (_query.isNotEmpty && _candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ChunkyButton.secondary(
                label: 'Search USDA and Open Food Facts',
                busy: _searchingRemote,
                onPressed: _searchingRemote ? null : _searchDatabases,
              ),
            ),
          if (_candidates.isNotEmpty) ...[
            const SizedBox(height: 8),
            const FieldLabel('From the databases'),
            for (final food in _candidates)
              _FoodTile(food: food, enabled: widget.enabled, onTap: () => _add(food)),
          ],
        ],
      ],
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.enabled, required this.onTap});

  final SavedFood food;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: '${food.title}, ${food.servingText}, ${food.kcal} kilocalories, ${food.source.chip}',
    excludeSemantics: true,
    onTap: enabled ? onTap : null,
    child: Pressable(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${food.servingText}  -  ${food.kcal.formatted} kcal  -  ${food.source.chip}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: kInkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.add_circle_outline_rounded, color: kInkSecondary),
            ],
          ),
        ),
      ),
    ),
  );
}
