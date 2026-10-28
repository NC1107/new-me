import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Pushes a full page. With reduced motion the page appears at once; otherwise the platform
/// transition runs, which keeps the iOS swipe back gesture.
Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push(_pageRoute<T>(context, page));

/// Swaps the current page for [page], so back goes to where the current one came from.
Future<T?> replacePage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).pushReplacement(_pageRoute<T>(context, page));

Route<T> _pageRoute<T>(BuildContext context, Widget page) => MediaQuery.disableAnimationsOf(context)
    ? PageRouteBuilder<T>(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      )
    : MaterialPageRoute<T>(builder: (_) => page);

/// A full page with a back arrow and a title above scrolling content and an optional footer
/// pinned below it. The subtitle scrolls with the content; only the title row and the footer
/// stay put, and the footer has an opaque background and a top border.
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
                ?banner,
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      kGutter,
                      16,
                      kGutter,
                      footer == null ? 32 + MediaQuery.paddingOf(context).bottom : 24,
                    ),
                    children: [
                      if (subtitle != null) ...[
                        Text(subtitle!, style: AppText.caption),
                        const SizedBox(height: 12),
                      ],
                      ...children,
                    ],
                  ),
                ),
                if (footer != null)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: kCanvas,
                      border: Border(top: BorderSide(color: kBorder)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        kGutter,
                        12,
                        kGutter,
                        kGutter + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: footer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
