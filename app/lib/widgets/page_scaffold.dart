import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Pushes a full page. With reduced motion the page appears at once; otherwise the platform
/// transition runs, which keeps the iOS swipe back gesture.
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  final route = MediaQuery.disableAnimationsOf(context)
      ? PageRouteBuilder<T>(
          pageBuilder: (_, _, _) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
      : MaterialPageRoute<T>(builder: (_) => page);
  return Navigator.of(context).push(route);
}

/// A full page with a back arrow and a title above scrolling content and an optional footer
/// pinned below it.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
    this.banner,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Pinned under the content, for the page's save button.
  final Widget? footer;

  /// Sits between the header and the content, for the offline strip.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, kGutter, 0),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Back',
                        excludeSemantics: true,
                        onTap: () => Navigator.of(context).maybePop(),
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          tooltip: 'Back',
                          hoverColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                          icon: const Icon(Icons.arrow_back_rounded, size: 28, color: kInk),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(kGutter, 0, kGutter, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(subtitle!, style: AppText.caption),
                    ),
                  ),
                ?banner,
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      kGutter,
                      16,
                      kGutter,
                      footer == null ? 32 + MediaQuery.paddingOf(context).bottom : 16,
                    ),
                    children: children,
                  ),
                ),
                if (footer != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      kGutter,
                      8,
                      kGutter,
                      kGutter + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: footer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
