import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
            FoodTile(food: food, enabled: widget.enabled, onTap: () => _add(food)),
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
              FoodTile(
                food: food,
                enabled: widget.enabled,
                onTap: () => _add(food),
                reserveThumbnail: _candidates.any((c) => c.imageUrl != null),
              ),
          ],
        ],
      ],
    );
  }
}

const _thumbSize = 44.0;
const _thumbGap = 10.0;

Future<void> _openSource(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// One food in a search list. A food with a photo shows it; [reserveThumbnail] keeps its siblings
/// without one aligned with it.
class FoodTile extends StatelessWidget {
  const FoodTile({
    super.key,
    required this.food,
    required this.enabled,
    required this.onTap,
    this.reserveThumbnail = false,
    this.onOpenSource = _openSource,
  });

  final SavedFood food;
  final bool enabled;
  final VoidCallback onTap;
  final bool reserveThumbnail;
  final ValueChanged<String> onOpenSource;

  @override
  Widget build(BuildContext context) {
    final imageUrl = food.imageUrl;
    final sourceUrl = food.sourceUrl;
    final showThumb = imageUrl != null || reserveThumbnail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label:
              '${food.title}, ${food.servingText}, ${food.kcal} kilocalories, ${food.source.chip}',
          excludeSemantics: true,
          onTap: enabled ? onTap : null,
          child: Pressable(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: sourceUrl == null ? 6 : 0),
                child: Row(
                  children: [
                    if (showThumb) ...[
                      FoodThumbnail(url: imageUrl),
                      const SizedBox(width: _thumbGap),
                    ],
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
        ),
        if (sourceUrl != null)
          Padding(
            padding: EdgeInsets.only(left: showThumb ? _thumbSize + _thumbGap : 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                link: true,
                label: 'Open Food Facts page for ${food.title}',
                excludeSemantics: true,
                onTap: () => onOpenSource(sourceUrl),
                child: Pressable(
                  onTap: () => onOpenSource(sourceUrl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Open Food Facts',
                          style: AppText.caption.copyWith(
                            color: kInkSecondary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.open_in_new_rounded, size: 12, color: kInkSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A rounded product photo that fades in, with the food icon behind it while it loads and in
/// its place when the photo is missing or fails.
class FoodThumbnail extends StatelessWidget {
  const FoodThumbnail({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: kBorder,
      alignment: Alignment.center,
      child: const Icon(Icons.restaurant_rounded, size: 20, color: kInkSecondary),
    );
    final cacheWidth = (_thumbSize * MediaQuery.devicePixelRatioOf(context)).round();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: _thumbSize,
          height: _thumbSize,
          child: url == null
              ? placeholder
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    placeholder,
                    Image.network(
                      url!,
                      fit: BoxFit.cover,
                      cacheWidth: cacheWidth,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, sync) => sync
                          ? child
                          : AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: const Duration(milliseconds: 200),
                              child: child,
                            ),
                      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
