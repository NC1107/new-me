import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../state/cached_resource.dart';
import '../../state/me.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/skeletons.dart';

/// Me as a pushed page sees it: the profile once loaded, otherwise a page that says why not.
/// It follows the same cache rules as [CachedView] but keeps its back arrow while loading.
class MeView {
  const MeView._({this.me, this.offline, this.placeholder});

  final Me? me;
  final OfflineInfo? offline;
  final Widget? placeholder;

  bool get editable => offline == null;
  Widget? get banner => offline == null ? null : OfflineBanner(info: offline!);
}

MeView readMe(WidgetRef ref, {required String title}) {
  final value = ref.watch(meProvider);
  final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
  final held = value.value;
  if (held != null && held.userId == userId) {
    return MeView._(me: held.data, offline: held.offline);
  }
  if (value.hasError) {
    return MeView._(
      placeholder: PageScaffold(
        title: title,
        children: [
          ErrorBlock(
            title: 'Could not load your profile',
            error: value.error!,
            onRetry: ref.read(meProvider.notifier).refresh,
          ),
        ],
      ),
    );
  }
  return MeView._(
    placeholder: PageScaffold(
      title: title,
      children: const [SizedBox(height: 320, child: MeSkeleton())],
    ),
  );
}

/// Save state shared by the Me pages that edit and PATCH /api/me.
mixin MeSaving<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool saving = false;
  String? saveError;

  /// True when the server took the edit. A failure leaves its message in [saveError].
  Future<bool> saveMe(MePatch patch, {String Function(ApiException e)? copy}) async {
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await ref.read(meProvider.notifier).save(patch);
      HapticFeedback.lightImpact();
      if (mounted) setState(() => saving = false);
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          saveError = copy == null ? errorCopy(e) : copy(e);
        });
      }
      return false;
    }
  }

  void toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The failure from the last save, shown above the page's button.
class SaveError extends StatelessWidget {
  const SaveError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_rounded, size: 18, color: kDangerText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppText.label.copyWith(color: kDangerText, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}
