import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cached_resource.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../util/errors.dart';
import 'offline_banner.dart';

/// The one loading, error and offline rule set for a screen backed by a cached read.
class CachedView<T> extends ConsumerWidget {
  const CachedView({
    super.key,
    required this.value,
    required this.skeleton,
    required this.onRetry,
    required this.builder,
    required this.errorTitle,
  });

  final AsyncValue<Cached<T>> value;
  final Widget skeleton;
  final Future<void> Function() onRetry;
  final String errorTitle;

  /// Builds the content; [offline] is set when it is drawn from the cache.
  final Widget Function(BuildContext context, T data, bool offline) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final held = value.value;
    final cached = held != null && held.userId == userId ? held : null;
    if (cached == null) {
      if (value.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ErrorBlock(title: errorTitle, error: value.error!, onRetry: onRetry),
          ),
        );
      }
      return skeleton;
    }
    return Column(
      children: [
        if (cached.offline != null) OfflineBanner(info: cached.offline!),
        if (value.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: ErrorBlock(title: errorTitle, error: value.error!, onRetry: onRetry),
          ),
        Expanded(child: builder(context, cached.data, cached.offline != null)),
      ],
    );
  }
}

/// Centered error text with a retry; used on its own or above cached content.
class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.title, required this.error, required this.onRetry});

  final String title;
  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(color: kFgPrimary, fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        errorCopy(error),
        textAlign: TextAlign.center,
        style: const TextStyle(color: kFgSecondary, fontSize: 13, height: 1.4),
      ),
      TextButton(
        onPressed: onRetry,
        style: TextButton.styleFrom(foregroundColor: kFgPrimary),
        child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );
}
