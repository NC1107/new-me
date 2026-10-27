# Conventions map of the check-in reference project

Generated 2026-10-26 by reading `/home/npc/Documents/projects/check-in`.
new-me copies these conventions so the two apps feel like siblings.

## check-in Flutter visual style and design tokens (/home/npc/Documents/projects/check-in/app)

Check-In is dark-only ("Onyx"): near-black canvas 0xFF0A0A0A, grey cards 0xFF161616 with 1px 0xFF2A2A2A borders, a single vivid green accent (0xFF37E07E) carried as a swappable ThemeExtension (6 presets), near-black text on accent. Material 3 widgets with Material Icons (outlined for inactive, rounded for active), NO custom fonts (system font, SF on iOS), typography done purely by size/weight (w600/w700 dominant, w800 for tiny caps badges). Flat look: elevation 0 everywhere, hairline borders instead of shadows, radii 10/12/14 for inputs/buttons/cards, 9999 pills, 22 for sheets. No ThemeData textTheme/component themes - every widget styles itself inline from const tokens (so screens look hand-tuned). Light theme does not exist. Haptics: selectionClick on nav/toggles, lightImpact/mediumImpact on actions. Animations are modest (200-260ms easeOut, pulsing skeletons, Hero, FadeTransition/AnimatedSwitcher), no page-transition customization (default MaterialPageRoute). Riverpod holds accentProvider (persisted per device).

### Key files

- `/home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart`: all color constants + bottom nav metrics (43 lines)
- `/home/npc/Documents/projects/check-in/app/lib/theme/accent.dart`: AccentPalette ThemeExtension, 6 presets, context.accent extension
- `/home/npc/Documents/projects/check-in/app/lib/theme/accent_picker.dart`: circular swatch picker bound to accentProvider (Riverpod)
- `/home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart`: FieldLabel, AppTextField, PrimaryButton, PillBadge - the shared form/button idioms
- `/home/npc/Documents/projects/check-in/app/lib/widgets/skeletons.dart`: pulsing FeedSkeleton loading cards (opacity 0.35-0.70, 900ms reverse repeat)
- `/home/npc/Documents/projects/check-in/app/lib/widgets/user_avatar.dart`: initial avatar on hashed palette color or photo
- `/home/npc/Documents/projects/check-in/app/lib/main.dart`: runZonedGuarded main, portrait lock, MaterialApp + ThemeData dark setup
- `/home/npc/Documents/projects/check-in/app/lib/features/settings/settings_screen.dart`: settings list: ListTile rows, AlertDialog, bottom sheet, haptics
- `/home/npc/Documents/projects/check-in/app/lib/features/profile/profile_screen.dart`: AppBar + FutureBuilder + RefreshIndicator + error/skeleton states
- `/home/npc/Documents/projects/check-in/app/lib/features/feed/home_shell.dart`: Scaffold shell: IndexedStack, BottomAppBar 64h with notch, centered accent FAB 58px, _NavItem (line ~616)
- `/home/npc/Documents/projects/check-in/app/lib/features/feed/feed_screen.dart`: _emptyState (line ~1121), snackbar usage, bottom sheets
- `/home/npc/Documents/projects/check-in/app/lib/features/feed/post_card.dart`: card decoration reference (kBgSurface, kBorder 1px, radius 14)
- `/home/npc/Documents/projects/check-in/app/pubspec.yaml`: deps (flutter_riverpod ^3.3.2, dio, flutter_secure_storage, shared_preferences, intl); only assets: assets/logo/ and worldmap bins; NO fonts section; uses-material-design: true
- `/home/npc/Documents/projects/check-in/app/ios/Runner/Assets.xcassets/AppIcon.appiconset`: app icon set (1024 + sizes); logo asset at app/assets/logo/echo-rings.png (+2.0x, 3.0x)

### Conventions

- Dark only. No light theme, no ThemeMode switching. ThemeData(brightness: dark, useMaterial3: true, colorScheme: ColorScheme.dark(primary: accent.base, onPrimary: accent.onAccent, secondary: accent.hover, surface: kBgSurface, onSurface: kFgPrimary, outline: kBorder, error: kLike), scaffoldBackgroundColor: kBgMain, cardColor: kBgSurface, dividerColor: kBorder, extensions: [accent]). No textTheme, appBarTheme, buttonTheme etc.
- Colors are file-level const k* tokens in theme/tokens.dart; screens alias them (e.g. const _bgSurface = kBgSurface). Accent is NOT const: read via context.accent / context.onAccent / context.accentLight / context.accentHover (ThemeExtension<AccentPalette>). Accent presets: green 37E07E (default, 'Onyx Green'), sky 3B9EFF, violet 9B7CFF, amber F5B83D, rose FF6F91, teal 2DD4BF; hover = lerp to white 0.18; light = 16% alpha; onAccent always 0xFF07140C.
- Contrast rule: bright accent => near-black text on accent. kFgMuted lifted to 8B8B93 for WCAG AA (~5.4:1).
- Radii: 9999 pills/chips/badges (38 uses), 10 text fields and small controls (23), 12 PrimaryButton (21), 14 cards (16), 22 top corners of modal bottom sheets, 8/9 small. Cards: color kBgSurface + Border.all(kBorder, 1) + radius 14, no shadow. Card margin fromLTRB(14,0,14,12), padding all(14). Screen horizontal gutter 14.
- Typography (system font, no fontFamily anywhere): AppBar title 18 w700 kFgPrimary; list row label 15 regular; body 14-15; secondary/meta 13 / 12.5 / 12 in kFgMuted; field label 12 w600 kFgMuted; button label 15 w700; empty-state title 15 w600 kFgSecondary + subtitle 13 kFgMuted; badge 11 w800 letterSpacing 0.6 ALL CAPS; nav label 11 w600; larger display 22 used 7x. Weights used: w600 (94x), w700 (82x), w500, w800 rarely, w400 almost never explicit.
- AppBar: backgroundColor kBgMain, elevation 0, bold 18 title, action IconButtons with outlined icons in kFgSecondary (e.g. Icons.settings_outlined).
- Icons: Material Icons only (Icons.*), outlined variants for inactive, *_rounded for active/selected (home_outlined -> home_rounded); sizes: list leading 22, chevron 18 kFgMuted, nav 23, empty-state hero 44 kFgMuted, inline badge 12. Cupertino only for a date picker.
- Bottom nav: custom BottomAppBar (height 64, color kBgMain, elevation 0, 1px top border kBorder, CircularNotchedRectangle notchMargin 9) with centerDocked circular accent FAB (58x58, elevation 4, Icons.add size 28, onAccent foreground). Nav item: icon 23 + 3px gap + 11/w600 label, selected color = accent, unselected kFgMuted, InkResponse radius 42, HapticFeedback.selectionClick.
- List rows: Material ListTile, leading icon 22 kFgSecondary, title 15 kFgPrimary, trailing chevron_right 18 kFgMuted; Divider(color: kBorder, height: 24) between groups; destructive row uses kLike for icon+text and no chevron.
- Buttons: PrimaryButton = full-width FilledButton, accent bg, onAccent fg, vertical padding 15, radius 12, w700 15, disabled bg kBgSurfaceHover/fg kFgMuted, busy = 20x20 CircularProgressIndicator strokeWidth 2 in onAccent. Secondary = TextButton with kFgSecondary label. Destructive confirm = FilledButton bg kLike fg white.
- Text field (AppTextField): filled kBgSurface, radius 10, contentPadding h14 v14, 1px kBorder enabled, 1px accent focused, kLike border + 14px error_outline icon and 12px kLike message on error, cursor accent, text 15 kFgPrimary, hint kFgMuted.
- Dialogs: AlertDialog backgroundColor kBgSurface, title kFgPrimary w700, content kFgSecondary 14 height 1.5. Bottom sheets: showModalBottomSheet isScrollControlled backgroundColor kBgSurface, top radius 22. SnackBars are default Material (hideCurrentSnackBar then showSnackBar(SnackBar(content: Text(msg)))), unthemed.
- Haptics: HapticFeedback.selectionClick (nav, toggles; 10x), mediumImpact (destructive confirm, important actions; 5x), lightImpact (4x).
- Loading: shimmer-free pulsing skeleton cards (kBgSurfaceHover at alpha 0.35-0.70, AnimationController 900ms repeat reverse) shaped like real cards; avatars circles, blocks radius 6. Error: centered kFgSecondary text + TextButton 'Try again'. Pull-to-refresh via RefreshIndicator with AlwaysScrollableScrollPhysics.
- Empty states: centered Column, 44px icon in kFgMuted, 14 gap, 15/w600 kFgSecondary title, 6 gap, 13 kFgMuted subtitle; short, lower-case-sentence friendly copy.
- Animation: restrained. Durations 180-260ms (200/220 most common), curves easeOut / easeOutCubic / easeOutBack (2x); AnimatedSwitcher, AnimatedContainer, AnimatedOpacity, AnimatedSize, AnimatedSlide, FadeTransition, SlideTransition, Hero (8x); chrome fades+slides 24px out with a shared controller. Page transitions are default MaterialPageRoute (iOS swipe-back works).
- Avatars: circle, initial letter on hashed color from palette [5557E0,13AF9D,DD1C85,E9960A,8458E9,22C55E,EF4444,3B82F6] seeded by user id; photo via ClipOval.
- PillBadge: accent.light (16% alpha) background, 9999 radius, padding h9 v4, 12px icon + 11/w800 label with letterSpacing 0.6, text/icon in accent.base.
- Portrait-locked via SystemChrome.setPreferredOrientations([portraitUp]); debugShowCheckedModeBanner false; state in flutter_riverpod (accentProvider persisted via shared_preferences); secure tokens in flutter_secure_storage.
- Code comments are long 'why' doc comments (design rationale), consistent with Nick's rule; tokens file explains the palette in a header comment.

### Reuse verbatim

- /home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart (rename header comment; optionally adjust accent)
- /home/npc/Documents/projects/check-in/app/lib/theme/accent.dart (whole file, rename preset ids/names as desired)
- /home/npc/Documents/projects/check-in/app/lib/theme/accent_picker.dart (needs an accentProvider in new-me's state; import path ../state/app_state.dart)
- /home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart (FieldLabel, AppTextField, PrimaryButton, PillBadge)
- /home/npc/Documents/projects/check-in/app/lib/widgets/skeletons.dart pulse pattern (adapt card shape to quest/scoreboard cards)
- ThemeData block from main.dart
- _NavItem + BottomAppBar + centered accent FAB pattern from home_shell.dart (drop notch/FAB if unneeded for two-tab app)
- empty-state, ListTile settings row, AlertDialog and bottom-sheet idioms from settings_screen.dart / feed_screen.dart

### Avoid or outdated

- Check-In-specific: group colors (theme/group_color.dart), multi-group sessions, memories surface/_ChromeFade, firebase/push, map/video/geocoding deps - not needed for new-me.
- The Hero/memories chrome-fade and CircularNotchedRectangle notch exist only to serve the FAB docking; skip unless new-me also wants a center FAB.
- There is no light theme and no custom font; if new-me wants a differentiated feel (so it is not a clone), the only levers are accent color, an added font via pubspec fonts, and the nonexistent textTheme - Check-In never set any.
- SnackBars are default unstyled Material; consider theming for new-me. Page transitions are default MaterialPageRoute.
- Debug log prefix '[CHECKIN]' in main.dart must be renamed.
- flutter_riverpod ^3.3.2 / flutter_secure_storage ^11 / firebase pins in pubspec are Check-In's; re-verify versions before copying.
- main.dart contains a leftover AppBar-less accent via ref.watch(accentProvider) from state/app_state.dart which was not reviewed here (state area belongs to another mapper).

### Snippets

#### /home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart

Full token file (palette) to copy verbatim, then rename/tune for new-me

```
import 'package:flutter/material.dart';

/// Central color tokens for the Check-In dark theme. Every screen aliases these, so
/// changing the palette means editing this one file.
///
/// "Onyx" - a simple near-black + greys theme with a single popping green accent (used
/// for buttons, links, and the timeline connector nodes). The accent is bright, so text
/// on it (kOnAccent) is near-black for legibility.

// Backgrounds & surfaces (near-black canvas → grey cards → hover).
const kBgMain = Color(0xFF0A0A0A);
const kBgSurface = Color(0xFF161616);
const kBgSurfaceHover = Color(0xFF1F1F1F);
const kBorder = Color(0xFF2A2A2A);

// Text hierarchy (neutral greys). kFgMuted is lifted to clear WCAG AA (~5.4:1 on the
// surface cards) since it carries a lot of small body text: timestamps, hints, helper
// lines, empty-state copy.
const kFgPrimary = Color(0xFFF4F4F5);
const kFgSecondary = Color(0xFFA1A1AA);
const kFgMuted = Color(0xFF8B8B93);

// Accent - a vivid green that pops on the black/grey base. Bright, so text on it is dark.
const kAccent = Color(0xFF37E07E);
const kAccentHover = Color(0xFF5CE89A);
const kAccentLight = Color(0x2937E07E); // ~16% alpha, for tints/connectors
const kOnAccent = Color(0xFF07140C); // near-black text/icons on the green accent

// Semantic.
const kLike = Color(0xFFF2557B); // danger / like (rose-red, pops on black, distinct from green)
const kSuccess = Color(0xFF37E07E); // online / success (matches the accent green)

const kBottomNavIconSize = 23.0;
const kBottomNavIconLabelGap = 3.0;
const kBottomNavLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

```

#### /home/npc/Documents/projects/check-in/app/lib/theme/accent.dart

ThemeExtension accent system with context.accent getters - copy as-is

```
@immutable
class AccentPalette extends ThemeExtension<AccentPalette> {
  const AccentPalette({required this.id, required this.name, required this.base, required this.hover, required this.light, required this.onAccent});
  final String id; final String name;
  final Color base;
  final Color hover; // slightly lighter, for pressed/hover states
  final Color light; // ~16% alpha tint, for connectors/badges
  final Color onAccent; // text/icons on top of the accent

  factory AccentPalette.from(String id, String name, Color base) {
    return AccentPalette(
      id: id, name: name, base: base,
      hover: Color.lerp(base, Colors.white, 0.18)!,
      light: base.withValues(alpha: 0.16),
      onAccent: const Color(0xFF07140C),
    );
  }
  @override
  AccentPalette copyWith({Color? base, Color? hover, Color? light, Color? onAccent}) => AccentPalette(id: id, name: name, base: base ?? this.base, hover: hover ?? this.hover, light: light ?? this.light, onAccent: onAccent ?? this.onAccent);
  @override
  AccentPalette lerp(ThemeExtension<AccentPalette>? other, double t) {
    if (other is! AccentPalette) return this;
    return AccentPalette(id: t < 0.5 ? id : other.id, name: t < 0.5 ? name : other.name, base: Color.lerp(base, other.base, t)!, hover: Color.lerp(hover, other.hover, t)!, light: Color.lerp(light, other.light, t)!, onAccent: Color.lerp(onAccent, other.onAccent, t)!);
  }
}

final List<AccentPalette> kAccentPresets = [
  AccentPalette.from('green', 'Onyx Green', const Color(0xFF37E07E)),
  AccentPalette.from('sky', 'Sky', const Color(0xFF3B9EFF)),
  AccentPalette.from('violet', 'Violet', const Color(0xFF9B7CFF)),
  AccentPalette.from('amber', 'Amber', const Color(0xFFF5B83D)),
  AccentPalette.from('rose', 'Rose', const Color(0xFFFF6F91)),
  AccentPalette.from('teal', 'Teal', const Color(0xFF2DD4BF)),
];

AccentPalette accentById(String? id) =>
    kAccentPresets.firstWhere((p) => p.id == id, orElse: () => kAccentPresets.first);

extension AccentContext on BuildContext {
  AccentPalette get accentPalette => Theme.of(this).extension<AccentPalette>() ?? kAccentPresets.first;
  Color get accent => accentPalette.base;
  Color get accentHover => accentPalette.hover;
  Color get accentLight => accentPalette.light;
  Color get onAccent => accentPalette.onAccent;
}

```

#### /home/npc/Documents/projects/check-in/app/lib/main.dart

Exact ThemeData setup

```
return MaterialApp(
  title: 'Check-In',
  navigatorKey: rootNavigatorKey,
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: accent.base,
      onPrimary: accent.onAccent,
      secondary: accent.hover,
      surface: kBgSurface,
      onSurface: kFgPrimary,
      outline: kBorder,
      error: kLike,
    ),
    scaffoldBackgroundColor: kBgMain,
    cardColor: kBgSurface,
    dividerColor: kBorder,
    useMaterial3: true,
    extensions: [accent],
  ),
  home: home,
);
// main(): WidgetsFlutterBinding.ensureInitialized(); await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]); wrapped in runZonedGuarded; runApp(ProviderScope(child: ...))
```

#### /home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart

PrimaryButton, AppTextField decoration, FieldLabel, PillBadge exact metrics

```
// FieldLabel
Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(color: kFgMuted, fontWeight: FontWeight.w600, fontSize: 12)))

// AppTextField decoration
TextField(style: const TextStyle(color: kFgPrimary, fontSize: 15), cursorColor: context.accent,
  decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: kFgMuted), filled: true, fillColor: kBgSurface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError ? kLike : kBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: hasError ? kLike : context.accent))))
// error row: Icon(Icons.error_outline, size: 14, color: kLike), SizedBox(width: 5), Text(errorText, style: TextStyle(color: kLike, fontSize: 12, height: 1.3)), top padding 6 left 2

// PrimaryButton
SizedBox(width: double.infinity, child: FilledButton(
  onPressed: enabled ? onTap : null,
  style: FilledButton.styleFrom(backgroundColor: context.accent, disabledBackgroundColor: kBgSurfaceHover, foregroundColor: context.onAccent, disabledForegroundColor: kFgMuted, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
  child: busy ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: context.onAccent)) : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))))

// PillBadge
Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: accent.light, borderRadius: BorderRadius.circular(9999)),
  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: accent.base), const SizedBox(width: 4), Text(label, style: TextStyle(color: accent.base, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6))]))
```

#### /home/npc/Documents/projects/check-in/app/lib/features/settings/settings_screen.dart

Screen scaffold, AppBar, list tile, dialog, sheet idioms

```
Scaffold(
  backgroundColor: kBgMain,
  appBar: AppBar(backgroundColor: kBgMain, elevation: 0,
    title: Text(title, style: const TextStyle(color: kFgPrimary, fontWeight: FontWeight.w700, fontSize: 18))),
  body: ListView(children: [ _tile(...), const Divider(color: kBorder, height: 24), _tile(..., danger: true) ]))

Widget _tile({required IconData icon, required String label, required VoidCallback onTap, bool danger = false}) {
  final color = danger ? kLike : kFgPrimary;
  return ListTile(onTap: onTap,
    leading: Icon(icon, size: 22, color: danger ? kLike : kFgSecondary),
    title: Text(label, style: TextStyle(color: color, fontSize: 15)),
    trailing: danger ? null : const Icon(Icons.chevron_right, size: 18, color: kFgMuted));
}

showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: kBgSurface,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))), builder: ...)

AlertDialog(backgroundColor: kBgSurface,
  title: const Text('Delete your account?', style: TextStyle(color: kFgPrimary, fontWeight: FontWeight.w700)),
  content: const Text('...', style: TextStyle(color: kFgSecondary, fontSize: 14, height: 1.5)),
  actions: [TextButton(onPressed: ..., child: const Text('Cancel', style: TextStyle(color: kFgSecondary))),
    FilledButton(onPressed: ..., style: FilledButton.styleFrom(backgroundColor: kLike, foregroundColor: Colors.white), child: const Text('Delete forever'))])
```

#### /home/npc/Documents/projects/check-in/app/lib/features/feed/feed_screen.dart

Empty state idiom (line ~1121)

```
Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
  Icon(icon, size: 44, color: _fgMuted),
  const SizedBox(height: 14),
  Text(title, textAlign: TextAlign.center, style: const TextStyle(color: _fgSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
  const SizedBox(height: 6),
  Text(subtitle, style: const TextStyle(color: _fgMuted, fontSize: 13)),
]))
```

#### /home/npc/Documents/projects/check-in/app/lib/features/feed/home_shell.dart

Bottom nav + accent FAB + _NavItem (core of the app chrome)

```
floatingActionButton: SizedBox(height: 58, width: 58, child: FloatingActionButton(onPressed: ..., backgroundColor: context.accent, foregroundColor: context.onAccent, elevation: 4, shape: const CircleBorder(), child: const Icon(Icons.add, size: 28))),
floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
bottomNavigationBar: BottomAppBar(color: _bgMain, elevation: 0, height: 64, padding: EdgeInsets.zero, shape: const CircularNotchedRectangle(), notchMargin: 9,
  child: DecoratedBox(decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))), child: Row(children: [_NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Feed', selected: _index == 0, onTap: ...), ...])))

class _NavItem: color = selected ? context.accent : _fgMuted;
Expanded(child: Semantics(button: true, selected: selected, label: label, child: InkResponse(onTap: () { HapticFeedback.selectionClick(); onTap!(); }, radius: 42,
  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(selected ? activeIcon : icon, size: kBottomNavIconSize, color: color),
    const SizedBox(height: kBottomNavIconLabelGap),
    Text(label, style: kBottomNavLabelStyle.copyWith(color: color))]))))
```

#### /home/npc/Documents/projects/check-in/app/lib/widgets/skeletons.dart

Loading skeleton idiom

```
late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
// in builder: final o = 0.35 + 0.35 * _pulse.value; // 0.35 → 0.70
Container(width: width, height: height, decoration: BoxDecoration(color: kBgSurfaceHover.withValues(alpha: o), borderRadius: BorderRadius.circular(radius /*6*/)))
// card shell: margin fromLTRB(14,0,14,12), padding all(14), BoxDecoration(color: kBgSurface, border: Border.all(color: kBorder), borderRadius: BorderRadius.circular(14))
```

#### /home/npc/Documents/projects/check-in/app/lib/theme/accent_picker.dart

Swatch picker visuals

```
Container(width: size /*62*/, height: size, decoration: BoxDecoration(color: palette.base, shape: BoxShape.circle, border: Border.all(color: selected ? kFgPrimary : kBorder, width: selected ? 3 : 1)), child: selected ? Icon(Icons.check, color: palette.onAccent, size: size * 0.45) : null)
// Wrap(spacing: 18, runSpacing: 16); label below: 12.5, selected kFgPrimary w600 else kFgSecondary w400, gap 8
```

## check-in Flutter app architecture and conventions (reference for new-me)

Reference repo /home/npc/Documents/projects/check-in. Flutter app lives in app/ (package name `checkin`, Flutter pinned 3.47.0 in CI, Dart sdk >=3.5.0 <4.0.0). State is Riverpod 3 (flutter_riverpod ^3.3.2) using Notifier/NotifierProvider, Provider, Provider.family, FutureProvider.autoDispose; HTTP is dio ^5.7 wrapped by a single hand-written ApiClient class (one per server, bearer token in default headers, X-Client-Version header, 401 interceptor calling onUnauthorized). Persistence: shared_preferences for non-secret state, flutter_secure_storage for tokens (key `token_<groupId>`). Navigation is plain Navigator (imperative push/pop, a rootNavigatorKey on MaterialApp; NO go_router). main.dart picks home by watching providers (terms accepted -> restored -> signed in ? HomeShell : AuthScreen). Theme is dark-only Material3 with centralized const color tokens in lib/theme/tokens.dart ("Onyx": near-black + greys + single green accent) plus a ThemeExtension AccentPalette. Onboarding: user types a server address, _normalizeServer prepends https:// and strips trailing slash, a probe GET /api/server-info (ServerInfo model with `name` and `initialized`) validates it, nothing is persisted until login/signup succeeds (_finish -> multiSessionProvider.addGroup). First-admin is detected server-side: POST /api/auth/check-phone returns {allowed, registered, isFirstAdmin}; signup AuthResult also has isFirstAdmin. check-in is multi-server (multi-group); new-me needs only a single server, so MultiSession/ServerAccount can be simplified to one account. Tests: flutter_test only (no mockito/mocktail), hand-rolled fakes via provider overrides (`multiSessionProvider.overrideWith(() => MultiSessionController.seeded(...))`), SharedPreferences.setMockInitialValues, mocked secure-storage MethodChannel, injected `clientFactory` on AuthScreen, shared fakes in test/support/. iOS: bundle id top.npcserver.checkin, deployment target 13.0, Podfile `platform :ios, '13.0'`, manual signing with Apple Distribution at Release for team 76S78SUWVM, ExportOptions.plist app-store/manual, CocoaPods only (Swift Package Manager integration disabled because it hung the app on a white launch screen), Firebase push and APNs entitlements.

### Key files

- `/home/npc/Documents/projects/check-in/CLAUDE.md`: Top-level conventions: commands, architecture, release flow (push to main -> release.yml tags version via conventional commits, deploys ghcr image, APK, Play internal, TestFlight; feat: = minor, ! = major, else patch; minor/major requires release_notes.dart entry; ci.yml only on PRs/non-main; iOS disables SPM, uses CocoaPods; pre-push hook via git config core.hooksPath .githooks runs gofmt + dart format; Flutter 3.47.0 pinned)
- `/home/npc/Documents/projects/check-in/app/pubspec.yaml`: Deps: flutter_riverpod ^3.3.2, dio ^5.7.0, http_parser, flutter_secure_storage ^11.0.0, shared_preferences ^2.3.2, url_launcher, flutter_local_notifications ^22.3.0, timezone, intl, flutter_timezone, firebase_core/messaging; dev: flutter_test, flutter_lints ^6.0.0; version 0.1.0+1; assets: assets/logo/
- `/home/npc/Documents/projects/check-in/app/analysis_options.yaml`: flutter_lints + formatter page_width 100 + extra correctness lints; excludes ios/android/web etc.
- `/home/npc/Documents/projects/check-in/app/lib/main.dart`: runZonedGuarded bootstrap, portrait lock, FlutterError.onError routing, timed Firebase init (8s cap), ProviderScope, MaterialApp with dark ThemeData built from tokens + accent, home chosen by provider state
- `/home/npc/Documents/projects/check-in/app/lib/api/api_client.dart`: ApiClient over dio; kClientVersion const kept in sync with pubspec by a test; endpoints grouped by comment banners
- `/home/npc/Documents/projects/check-in/app/lib/api/models.dart`: Plain Dart model classes with fromJson factories (ServerInfo, User, AuthResult, ...), no codegen
- `/home/npc/Documents/projects/check-in/app/lib/state/app_state.dart`: MultiSession/ServerAccount + MultiSessionController (Notifier), provider families for per-group ApiClient, AccentController, TermsController, FutureProviders
- `/home/npc/Documents/projects/check-in/app/lib/features/onboarding/auth_screen.dart`: Server-address probe (_normalizeServer, _ensureServer), login/signup/reset, first-admin detection (_isFirstAdmin), _finish -> addGroup; has injectable clientFactory for tests
- `/home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart`: Const color tokens (kBgMain, kBgSurface, kBorder, kFg*, kAccent, kOnAccent, kLike, kSuccess) and bottom-nav constants
- `/home/npc/Documents/projects/check-in/app/lib/theme/accent.dart`: AccentPalette ThemeExtension with presets, context.accent
- `/home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart`: Shared FieldLabel, AppTextField, PrimaryButton, PillBadge
- `/home/npc/Documents/projects/check-in/app/lib/notifications/local_notifications.dart`: Singleton FlutterLocalNotificationsPlugin, lazy once-only init, iOS permission NOT requested at init, tap-handler buffering for cold start, stableNotificationId FNV-1a
- `/home/npc/Documents/projects/check-in/app/ios/Runner/Info.plist`: iOS plist: portrait only, UIScene manifest, ITSAppUsesNonExemptEncryption false, UIBackgroundModes fetch+remote-notification, usage descriptions
- `/home/npc/Documents/projects/check-in/app/ios/Runner/Runner.entitlements`: aps-environment production + keychain-access-groups $(AppIdentifierPrefix)top.npcserver.checkin
- `/home/npc/Documents/projects/check-in/app/ios/Podfile`: platform :ios, '13.0'; use_frameworks!, use_modular_headers!; post_install forces IPHONEOS_DEPLOYMENT_TARGET 13.0 on pods
- `/home/npc/Documents/projects/check-in/app/ios/ExportOptions.plist`: app-store method, manual signing, team 76S78SUWVM, profile name 'Check-In App Store Distribution'
- `/home/npc/Documents/projects/check-in/app/ios/Runner.xcodeproj/project.pbxproj`: Bundle id top.npcserver.checkin, Release uses CODE_SIGN_STYLE Manual / Apple Distribution / DEVELOPMENT_TEAM 76S78SUWVM, version via $(FLUTTER_BUILD_NUMBER), deployment 13.0
- `/home/npc/Documents/projects/check-in/app/test/api_client_test.dart`: Example ApiClient unit test incl. pubspec-version-vs-kClientVersion drift guard
- `/home/npc/Documents/projects/check-in/app/test/settings_screen_test.dart`: Example widget test using seeded controller override, mocked prefs and secure-storage channel
- `/home/npc/Documents/projects/check-in/.github/workflows/release.yml`: Release/TestFlight pipeline (outside this area but referenced by CLAUDE.md)

### Conventions

- Directory layout: app/lib/{api,state,features/<area>,widgets,theme,notifications,media}; screens in features/<area>/*_screen.dart; shared UI in widgets/; no codegen (no freezed/json_serializable/riverpod_generator), models hand-written with fromJson.
- Riverpod 3 style: `class X extends Notifier<T> { @override T build() {...} }` + `final xProvider = NotifierProvider<X, T>(X.new);` Async persistence pattern: build() returns a sensible default synchronously, kicks off `_load()` which reads prefs then sets `state`; mutators set `state` first then write prefs.
- Test seam pattern: controllers expose `@visibleForTesting Controller.seeded(initial)` constructors, tests use `provider.overrideWith(() => controller)`; widgets that build ApiClients take an optional `clientFactory` param.
- One ApiClient instance per server built by a Provider that watches the session and passes onUnauthorized -> expire session; 401 only drops token when a token was sent; network errors and 403 (reverse proxy) never sign out.
- Base URL handling: user input trimmed, trailing slash removed, `https://` prefixed unless it starts with `http`; probe via GET /api/server-info before anything is stored; persist only after login/signup completes.
- Tokens in flutter_secure_storage under `token_<id>`; non-secret config JSON-encoded in shared_preferences under `_k...` const keys; id derived from URL host.
- Navigation: plain Navigator.of(context).push/pop with a global rootNavigatorKey on MaterialApp; root screen swaps automatically by watching providers in build (no named routes/go_router).
- Dark-only theme: ThemeData(brightness dark, useMaterial3, ColorScheme.dark(...) built from k* tokens), accent via ThemeExtension read as context.accent; screens alias tokens rather than hardcoding colors.
- Lints: flutter_lints plus prefer_const_constructors, avoid_print, cancel_subscriptions, close_sinks, avoid_dynamic_calls, etc.; formatter page_width 100; CI checks `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`.
- Debug logging via debugPrint with a bracketed app tag like [CHECKIN]; never print().
- Startup robustness: runZonedGuarded, FlutterError.onError and PlatformDispatcher.onError set, optional native init (Firebase) capped with timeout so app always starts; portrait lock via SystemChrome.
- Local notifications: single shared plugin instance, idempotent lazy init, iOS permission prompt deferred to the feature that needs it (requestAlertPermission false at init), deterministic ids via FNV-1a so reposting replaces.
- Tests are flat in app/test (no subfolders except test/support for fakes), named after the behavior or regression guarded; flutter_test only, no mocking library; secure-storage mocked via MethodChannel 'plugins.it_nomads.com/flutter_secure_storage'; SharedPreferences.setMockInitialValues({}).
- Comments explain why (long doc comments on non-obvious decisions); public classes get /// docs.
- iOS: CocoaPods only (SPM disabled); manual signing for Release with Apple Distribution; CFBundleShortVersionString=$(FLUTTER_BUILD_NAME), CFBundleVersion=$(FLUTTER_BUILD_NUMBER); ITSAppUsesNonExemptEncryption false; UISupportedInterfaceOrientations portrait only.
- Releases: conventional commits drive version; version in pubspec and kClientVersion must match (test-enforced).

### Reuse verbatim

- /home/npc/Documents/projects/check-in/app/analysis_options.yaml (whole file)
- /home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart color constants (kBgMain..kSuccess) and the ThemeData construction in main.dart
- /home/npc/Documents/projects/check-in/app/lib/theme/accent.dart AccentPalette ThemeExtension (copy only if a user-selectable accent is wanted; otherwise fixed kAccent)
- /home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart (FieldLabel, AppTextField, PrimaryButton, PillBadge) as the base component set
- ApiClient constructor shape (dio BaseOptions, X-Client-Version header, Bearer token, 401 interceptor) and the kClientVersion-vs-pubspec drift test
- _normalizeServer / _ensureServer probe flow from auth_screen.dart (server-info probe before persisting anything)
- Notifier + async SharedPreferences load pattern (TermsController/AccentController) and MultiSessionController.seeded test seam, simplified to one account
- local_notifications.dart shared plugin init and stableNotificationId
- main.dart runZonedGuarded bootstrap with portrait lock and error routing (drop Firebase unless push is needed; use [NEWME] log tag)
- ios Podfile, ExportOptions.plist, Runner.entitlements, Info.plist structure (change bundle id, display name, usage strings; add NSHealthShareUsageDescription for HealthKit)

### Avoid or outdated

- Multi-group/multi-server machinery (MultiSession, hiddenGroupIds, apiForGroupProvider.family, contentAccountProvider, person_directory, taggable_people, unread, group_color): new-me is a single server with two people, so use one account/one ApiClient provider.
- Legacy migration code in MultiSessionController._load (kLegacyBaseUrl/active_group_id) is check-in history only; do not copy.
- Firebase/FCM push (firebase_core, firebase_messaging, GoogleService-Info.plist, AppDelegate registerForRemoteNotifications workaround, aps-environment entitlement, UIBackgroundModes remote-notification) is only needed for cloud push; new-me can use local notifications only unless push is wanted.
- Phone-number auth (checkPhone, phone_field, country dial codes, contacts picker, invite links, birthday) is check-in specific; new-me first-admin detection should be simpler (e.g. server-info `initialized:false` -> first registrant becomes admin, user sets name).
- Heavy media deps (image_picker, video_player, video_compress, flutter_map, gal, native_exif, geocoding, cached_network_image) are irrelevant.
- iOS deployment target 13.0 is old; check-in uses UIScene template with FlutterImplicitEngineDelegate, so new-me should use the current Flutter template and likely raise to iOS 14+/15 (HealthKit package requirement) rather than copy 13.0 blindly.
- Terms/EULA gate (termsProvider, TermsScreen) exists for Apple Guideline 1.2 user-generated content; not needed for a private two-person app.
- Hardcoded identifiers to replace: bundle id top.npcserver.checkin, URL scheme `checkin`, team 76S78SUWVM (same Apple team can be reused), provisioning profile name 'Check-In App Store Distribution', package name `checkin` in test imports, [CHECKIN] log tag, app id 6783974361.

### Snippets

#### /home/npc/Documents/projects/check-in/app/lib/features/onboarding/auth_screen.dart

Server address normalization and probe flow to copy for new-me (single fixed server new-me.npc-server.top can prefill it)

```
String? _normalizeServer(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return null;
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  if (!url.startsWith('http')) url = 'https://$url';
  return url;
}

Future<bool> _ensureServer() async {
  final url = _normalizeServer(_server.text);
  if (url == null) {
    setState(() => _serverError = 'Enter your server address.');
    return false;
  }
  if (url == _connectedUrl) return true;
  try {
    final info = await _newClient(url).serverInfo();
    _serverInfo = info;
    _connectedUrl = url;
    return true;
  } on DioException catch (_) {
    setState(() =>
        _serverError = "Couldn't reach that server. Check the address and your connection.");
    return false;
  }
}

ApiClient _newClient(String baseUrl, {String? token}) =>
    widget.clientFactory?.call(baseUrl, token: token) ??
    ApiClient(baseUrl: baseUrl, token: token);
```

#### /home/npc/Documents/projects/check-in/app/lib/api/api_client.dart

dio client construction: timeouts, default headers, 401 interceptor

```
class ApiClient {
  ApiClient({required String baseUrl, String? token, void Function()? onUnauthorized})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'X-Client-Version': kClientVersion,
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )) {
    if (onUnauthorized != null) {
      _dio.interceptors.add(InterceptorsWrapper(
        onError: (e, handler) {
          if (e.response?.statusCode == 401 && token != null) onUnauthorized();
          handler.next(e);
        },
      ));
    }
  }
  final Dio _dio;

  Future<ServerInfo> serverInfo() async {
    final r = await _dio.get('/api/server-info');
    return ServerInfo.fromJson(r.data as Map<String, dynamic>);
  }

  Future<({bool allowed, bool registered, bool isFirstAdmin})> checkPhone(String phone) async {
    final r = await _dio.post('/api/auth/check-phone', data: {'phone': phone});
    final j = r.data as Map<String, dynamic>;
    return (
      allowed: j['allowed'] as bool? ?? false,
      registered: j['registered'] as bool? ?? false,
      isFirstAdmin: j['isFirstAdmin'] as bool? ?? false,
    );
  }
}
```

#### /home/npc/Documents/projects/check-in/app/lib/state/app_state.dart

Canonical Notifier + async prefs load + seeded test constructor + Provider wiring (token via secure storage)

```
class MultiSessionController extends Notifier<MultiSession> {
  MultiSessionController() : _seed = null;

  @visibleForTesting
  MultiSessionController.seeded(MultiSession initial) : _seed = initial;

  final MultiSession? _seed;
  final _secure = const FlutterSecureStorage();

  @override
  MultiSession build() {
    final seed = _seed;
    if (seed != null) return seed;
    _restoring = _load();
    return const MultiSession();
  }
  static String _tokenKey(String groupId) => 'token_$groupId';
}

final multiSessionProvider =
    NotifierProvider<MultiSessionController, MultiSession>(MultiSessionController.new);

final apiForGroupProvider = Provider.family<ApiClient, String>((ref, groupId) {
  final g = ref.watch(multiSessionProvider.select((s) => s.byId(groupId)));
  final sentToken = g?.token;
  return ApiClient(
    baseUrl: g?.baseUrl ?? '',
    token: sentToken,
    onUnauthorized: () =>
        ref.read(multiSessionProvider.notifier).expireGroup(groupId, rejectedToken: sentToken),
  );
});
```

#### /home/npc/Documents/projects/check-in/app/lib/state/app_state.dart

Simple persisted-bool Notifier pattern (TermsController) to copy for small prefs

```
class TermsController extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kTermsAccepted) ?? false;
  }

  Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTermsAccepted, true);
    state = true;
  }
}

final termsProvider = NotifierProvider<TermsController, bool>(TermsController.new);
```

#### /home/npc/Documents/projects/check-in/app/lib/main.dart

Bootstrap and root widget gating pattern

```
void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('[CHECKIN] FlutterError: ${details.exceptionAsString()}');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('[CHECKIN] $error');
        return true;
      };
      await _initFirebase().timeout(const Duration(seconds: 8), onTimeout: () {
        debugPrint('[CHECKIN] firebase init timed out; starting without push');
      });
      runApp(ProviderScope(overrides: inviteLinkOverrides(), child: const CheckInRoot()));
    },
    (error, stack) => debugPrint('[CHECKIN] uncaught: $error'),
  );
}

final Widget home = !termsAccepted
    ? const TermsScreen()
    : !session.restored
        ? const Scaffold(body: SizedBox.shrink())
        : (session.anySignedIn ? const HomeShell() : const AuthScreen());

return MaterialApp(
  title: 'Check-In',
  navigatorKey: rootNavigatorKey,
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: accent.base,
      onPrimary: accent.onAccent,
      secondary: accent.hover,
      surface: kBgSurface,
      onSurface: kFgPrimary,
      outline: kBorder,
      error: kLike,
    ),
    scaffoldBackgroundColor: kBgMain,
    cardColor: kBgSurface,
    dividerColor: kBorder,
    useMaterial3: true,
    extensions: [accent],
  ),
  home: home,
);
```

#### /home/npc/Documents/projects/check-in/app/lib/theme/tokens.dart

The visual style tokens (Onyx dark theme) to reuse exactly

```
const kBgMain = Color(0xFF0A0A0A);
const kBgSurface = Color(0xFF161616);
const kBgSurfaceHover = Color(0xFF1F1F1F);
const kBorder = Color(0xFF2A2A2A);
const kFgPrimary = Color(0xFFF4F4F5);
const kFgSecondary = Color(0xFFA1A1AA);
const kFgMuted = Color(0xFF8B8B93);
const kAccent = Color(0xFF37E07E);
const kAccentHover = Color(0xFF5CE89A);
const kAccentLight = Color(0x2937E07E);
const kOnAccent = Color(0xFF07140C);
const kLike = Color(0xFFF2557B);
const kSuccess = Color(0xFF37E07E);
const kBottomNavIconSize = 23.0;
const kBottomNavIconLabelGap = 3.0;
const kBottomNavLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
```

#### /home/npc/Documents/projects/check-in/app/lib/widgets/app_widgets.dart

Shared field label style

```
Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text,
      style: const TextStyle(color: kFgMuted, fontWeight: FontWeight.w600, fontSize: 12)),
);
```

#### /home/npc/Documents/projects/check-in/app/test/settings_screen_test.dart

Widget-test harness pattern: mock secure storage channel, prefs, seeded controller override

```
TestWidgetsFlutterBinding.ensureInitialized();
const secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
setUp(() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(secureChannel, (call) async => null);
});
final controller = MultiSessionController.seeded(MultiSession(
  groups: [account(isAdmin: isAdmin), ...extraGroups],
  restored: true,
));
await tester.pumpWidget(
  ProviderScope(
    overrides: [multiSessionProvider.overrideWith(() => controller)],
    child: const MaterialApp(home: SettingsScreen(groupId: 'alpha.invalid')),
  ),
);
await tester.pumpAndSettle();
```

#### /home/npc/Documents/projects/check-in/app/test/api_client_test.dart

Version drift guard between pubspec and kClientVersion

```
final pubspec = File('pubspec.yaml').readAsLinesSync();
final declared = pubspec.firstWhere((l) => l.startsWith('version:')).split(':')[1].trim();
expect(declared.split('+').first, kClientVersion);
```

#### /home/npc/Documents/projects/check-in/app/analysis_options.yaml

Lint/format config to copy

```
include: package:flutter_lints/flutter.yaml

formatter:
  page_width: 100

linter:
  rules:
    prefer_const_constructors: true
    avoid_print: true
    cancel_subscriptions: true
    close_sinks: true
    collection_methods_unrelated_type: true
    no_adjacent_strings_in_list: true
    literal_only_boolean_expressions: true
    throw_in_finally: true
    unnecessary_statements: true
    unnecessary_null_checks: true
    avoid_dynamic_calls: true
    avoid_slow_async_io: true
    avoid_returning_null_for_void: true
analyzer:
  exclude:
    - build/**
    - android/**
    - ios/**
    - web/**
    - windows/**
    - macos/**
    - linux/**
```

#### /home/npc/Documents/projects/check-in/app/ios/Podfile

iOS platform and pod config

```
platform :ios, '13.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}
target 'Runner' do
  use_frameworks!
  use_modular_headers!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

#### /home/npc/Documents/projects/check-in/app/ios/ExportOptions.plist

TestFlight export options (swap bundle id and profile name for new-me)

```
<key>method</key><string>app-store</string>
<key>signingStyle</key><string>manual</string>
<key>teamID</key><string>76S78SUWVM</string>
<key>provisioningProfiles</key><dict><key>top.npcserver.checkin</key><string>Check-In App Store Distribution</string></dict>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>stripSwiftSymbols</key><true/>
<key>uploadSymbols</key><true/>
```

#### /home/npc/Documents/projects/check-in/app/ios/Runner/Runner.entitlements

Entitlements (aps-environment only needed if remote push; keychain group uses bundle id)

```
<key>aps-environment</key><string>production</string>
<key>keychain-access-groups</key>
<array><string>$(AppIdentifierPrefix)top.npcserver.checkin</string></array>
```

#### /home/npc/Documents/projects/check-in/app/lib/notifications/local_notifications.dart

Shared local-notification init pattern

```
final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
Future<void>? _initialization;
Future<void> ensureLocalNotificationsInitialized() => _initialization ??= _initialize();

Future<void> _initialize() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    ),
  );
  try {
    await localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
    );
  } catch (_) {
    _initialization = null;
    rethrow;
  }
}

int stableNotificationId(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
```

## Go server conventions (check-in repo, /home/npc/Documents/projects/check-in/server)

Module github.com/nc1107/check-in/server, go 1.26.0 in go.mod (Dockerfile and CI use Go 1.27). Deps: chi/v5 v5.3.2 router, pgx/v5 v5.11.0 (pgxpool, hand-written parameterized SQL, no sqlc/ORM), golang.org/x/crypto (argon2id). No migration tool: SQL files in server/migrations/NNNN_name.sql are //go:embed-ed (migrations/embed.go) and applied on boot by db.Migrate (sorted by filename, each in its own tx, recorded in schema_migrations(name PK, applied_at), serialized by pg_advisory_lock). Layout: cmd/server/main.go; internal/{api,auth,config,db,push,storage,gazetteer}. api: Server struct {cfg, db, store, push, ...} with New(cfg, db, store, notifier) and Router() building chi router. Middleware order: ClientIPFromXFFTrustedProxies(hops), Recoverer, Timeout(30s), secureHeaders. Route groups: public (/api/health, /api/server-info), rate-limited auth group (per-IP token bucket 20/min burst 10), requireAuth group (Bearer token), nested requireAdmin group; per-user create limits via r.With(s.rateLimitUser(...)). Handlers are methods `func (s *Server) handleX(w, r)`; JSON helpers writeJSON/writeErr/decodeJSON (1MiB cap, DisallowUnknownFields); errors are `{"error": "msg"}`; constants msgServerError="server error", msgInvalidBody="invalid body" in helpers.go. Auth: argon2id password hashes (phone+password in check-in; first signup becomes admin, flagged via server_config.initialized), opaque 32-byte random base64url session token, only SHA-256 hex hash stored in sessions table; sliding expiry (SessionTTL 30d idle, SessionMaxAge 180d absolute), requireAuth does db.UserForToken then slideSession; constant-time dummy hash verify on unknown user; user put in ctx via userFrom(r). Config: env-only, `CHECKIN_*` prefix, config.Load() with getenv/getint64/getdur helpers; CHECKIN_DATABASE_URL required (no default, error if missing). Logging: stdlib `log` (log.Printf/Fatalf), no structured logger. Background jobs: plain goroutines with time.Ticker started from main (hourly session purge inline in main; Start*Scheduler(ctx) methods on Server for digest (10-min tick) and recap), each with recover() and context timeout. Graceful shutdown: signal.Notify SIGINT/SIGTERM then httpServer.Shutdown with 10s ctx; http.Server has Read/Write/Idle timeouts. Health: GET /api/health pings DB (3s timeout), 200 {"status":"ok"} or 503; `server -healthcheck` flag does self-GET for distroless container healthcheck. Tests: real Postgres via TESTDB_URL; internal/api/main_test.go TestMain fails hard if TESTDB_URL unset unless CHECKIN_SKIP_DB_TESTS set; harness_test.go builds fresh harness per test (resetDB: TRUNCATE all public tables except schema_migrations RESTART IDENTITY CASCADE, reseed server_config), real httptest server on production Router(), fluent helpers h.get/post/patch/delete -> *response with .expect(status).decode(&v), actors via h.admin(name)/h.member(admin,name) returning actor{ID,Name,Phone,Token}; tests are not parallel. server/scripts/test.sh spins throwaway postgres:16-alpine in docker on port 55432 and runs `go test -race`. CI (.github/workflows/ci.yml): postgres:16 service container, gofmt check, go vet, go build, go test ./... -race with TESTDB_URL; actions pinned by commit SHA; release.yml has test-server/test-app gate -> version -> docker build+push to ghcr.io -> GitHub release -> store deploys. Docker: multi-stage golang:1.27-alpine build, CGO_ENABLED=0 -trimpath -ldflags="-s -w", runtime gcr.io/distroless/static-debian12:nonroot, EXPOSE 8080, ENTRYPOINT /app/server. Compose: services db (postgres:16-alpine, healthcheck pg_isready), server (image ghcr.io/nc1107/check-in:latest, build ./server, networks frontend+backend, healthcheck /app/server -healthcheck), caddy (caddy:2-alpine, ports 80/443, only on frontend network), db-backup (prodrigestivill/postgres-backup-local:16 daily), media-backup (offen/docker-volume-backup:v2); memory limits per service; networks split so caddy cannot reach db. Caddyfile is a single site `{$CHECKIN_DOMAIN}` with encode zstd gzip, security headers, request_body max_size 30MB, reverse_proxy server:8080. Gaps vs new-me: no WebSocket, no sqlc, no structured logs; there is no per-server .env beyond .env.example; scripts/ at repo root is gen-stack.sh (multi-group compose generator) and new-group.sh (not needed for new-me).

### Key files

- `/home/npc/Documents/projects/check-in/server/go.mod`: module + deps (chi, pgx, x/crypto)
- `/home/npc/Documents/projects/check-in/server/cmd/server/main.go`: entrypoint: config, db connect+migrate, schedulers, http.Server, graceful shutdown, -healthcheck
- `/home/npc/Documents/projects/check-in/server/internal/api/server.go`: Server struct, New, Router (chi routes/middleware/groups), secureHeaders
- `/home/npc/Documents/projects/check-in/server/internal/api/helpers.go`: writeJSON/writeErr/decodeJSON, requireAuth, requireAdmin, slideSession, rateLimitAuth, msg constants
- `/home/npc/Documents/projects/check-in/server/internal/api/auth_handlers.go`: health, server-info, signup, login, issueSession
- `/home/npc/Documents/projects/check-in/server/internal/auth/auth.go`: argon2id hash/verify, NewToken, HashToken
- `/home/npc/Documents/projects/check-in/server/internal/config/config.go`: env config with defaults, getenv helpers
- `/home/npc/Documents/projects/check-in/server/internal/db/db.go`: pgxpool Connect, embedded migration runner with advisory lock
- `/home/npc/Documents/projects/check-in/server/internal/db/queries.go`: hand-written pgx queries (UserForToken, ExtendSession, ...)
- `/home/npc/Documents/projects/check-in/server/migrations/embed.go`: go:embed *.sql
- `/home/npc/Documents/projects/check-in/server/migrations/0001_init.sql`: initial schema style (BIGINT GENERATED ALWAYS AS IDENTITY, TIMESTAMPTZ DEFAULT now())
- `/home/npc/Documents/projects/check-in/server/internal/api/digest.go`: representative ticker scheduler with recover and timeout
- `/home/npc/Documents/projects/check-in/server/internal/api/main_test.go`: TestMain requiring TESTDB_URL
- `/home/npc/Documents/projects/check-in/server/internal/api/harness_test.go`: DB-backed HTTP test harness
- `/home/npc/Documents/projects/check-in/server/internal/api/session_expiry_test.go`: representative handler tests
- `/home/npc/Documents/projects/check-in/server/scripts/test.sh`: throwaway Postgres + go test -race
- `/home/npc/Documents/projects/check-in/server/Dockerfile`: multi-stage distroless build
- `/home/npc/Documents/projects/check-in/server/.dockerignore`: excludes secrets; must not exclude *.sql
- `/home/npc/Documents/projects/check-in/docker-compose.yml`: db, server, caddy, backups
- `/home/npc/Documents/projects/check-in/Caddyfile`: reverse proxy for domain
- `/home/npc/Documents/projects/check-in/.env.example`: env template
- `/home/npc/Documents/projects/check-in/.github/workflows/ci.yml`: server job with postgres service + app job
- `/home/npc/Documents/projects/check-in/.github/workflows/release.yml`: test gate, version, ghcr docker push, release, store deploys

### Conventions

- Go layout: cmd/server/main.go + internal/{api,auth,config,db,...}; single binary, env-only config with product prefix (CHECKIN_*; new-me would use NEWME_*)
- chi v5 router; handlers are methods on *Server named handleX; routes registered in one Router() with groups: public, rate-limited auth, requireAuth, nested requireAdmin
- Error envelope {"error": msg}; decodeJSON uses DisallowUnknownFields and 1MiB cap; capability flags in /api/server-info so new client fields gated on server support
- pgx v5 pool, hand-written SQL with $n params in internal/db; ErrNotFound sentinel mapped from pgx.ErrNoRows
- Migrations: NNNN_snake_name.sql in server/migrations, embedded, applied on boot under advisory lock, one tx per file, tracked in schema_migrations; never edit applied files
- Schema style: BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, TIMESTAMPTZ NOT NULL DEFAULT now(), singleton server_config row with CHECK (id=1), initialized flag; first signup becomes admin
- Session tokens: random 32 bytes base64url to client, SHA-256 hex hash stored; Bearer auth; sliding expiry with absolute max age; hourly purge of expired sessions
- Passwords: argon2id (t=1, m=64MiB, p=4); dummy-hash verify to equalize timing on unknown user
- Logging via stdlib log.Printf; background loops use time.Ticker + select ctx.Done + defer recover + context.WithTimeout
- Graceful shutdown on SIGINT/SIGTERM with 10s timeout; http.Server timeouts set (ReadHeader 5s, Read 30s, Write 60s, Idle 120s)
- Health endpoint /api/health pings DB; container healthcheck is the binary itself (-healthcheck) because distroless has no shell/curl
- Tests: DB-backed via TESTDB_URL, hard-fail if unset unless CHECKIN_SKIP_DB_TESTS=1; per-test TRUNCATE-all reset; real httptest server over production Router; fluent response.expect(status).decode(&v); no t.Parallel; run with -race; server/scripts/test.sh starts throwaway Postgres
- CI: gofmt check, go vet, go build, go test ./... -race with postgres service; third-party actions pinned by SHA
- Docker: golang alpine build, CGO off, static binary to distroless nonroot; compose splits frontend (caddy+server) and backend (server+db) networks; memory limits on every service; Caddy gets auto-HTTPS from {$DOMAIN} env var
- Comments explain why (long rationale comments are the repo style) - note user rules in CLAUDE.md prefer shorter why-only comments; no em dashes

### Reuse verbatim

- server/internal/api/helpers.go: writeJSON, writeErr, decodeJSON, requireAuth, requireAdmin, slideSession
- server/internal/db/db.go and server/migrations/embed.go: whole migration runner
- server/internal/auth/auth.go: HashPassword/VerifyPassword/NewToken/HashToken
- server/internal/config/config.go helpers: getenv/getint64/getdur/getPositiveInt
- server/cmd/server/main.go: healthcheck(), signal/shutdown block, http.Server timeouts, hourly session purge
- server/internal/api/harness_test.go: whole harness (response.expect/decode, resetDB catalog truncate, actor helpers) adapted to new-me config
- server/internal/api/main_test.go requireTestDB pattern and server/scripts/test.sh
- server/internal/api/digest.go ticker+recover+timeout scheduler shape
- server/Dockerfile (minus gazetteer/media layers), server/.dockerignore (keep *.sql included), Caddyfile, docker-compose.yml (db/server/caddy and network split), .github/workflows/ci.yml server job

### Avoid or outdated

- Do not copy gazetteer, storage/media, push/relay/FCM, digest/recap content, GIF/Klipy, groups/ multi-tenant scripts (gen-stack.sh, new-group.sh), debug dashboard, or phone-number allowlist/invite flow - not relevant to new-me
- go.mod says go 1.26.0 while Dockerfile/CI use 1.27 - mismatch, pick one version in new-me
- chi middleware.RealIP is deprecated (GHSA-3fxj-6jh8-hvhx); check-in uses ClientIPFromXFFTrustedProxies(hops) instead, with hops=1 behind Caddy (new-me sits behind the user's existing nginx plus possibly Caddy, so set hops to the real count)
- Check-In identity is phone+password with allowlisted invite; new-me wants server-address entry, first-install-becomes-admin, set display name 'Nick', so signup/login should be redesigned (keep token/session mechanics)
- Caddy in check-in does its own Let's Encrypt HTTPS on 80/443; new-me is behind the user's nginx at new-me.npc-server.top so Caddy may need to listen on a plain internal port without auto-HTTPS or be dropped
- Long multi-paragraph rationale comments are check-in's style but the user's CLAUDE.md says comments only explain why and briefly; no em dashes in anything
- Hourly session purge lives inline in main.go with context.Background and no stop on shutdown; consider moving into a Start*Scheduler(ctx) method
- Distroless image lacks shell/curl, hence -healthcheck flag; keep that approach

### Snippets

#### server/cmd/server/main.go (core flow, trimmed of push/relay specifics)

Boot sequence, scheduler, hourly session purge, graceful shutdown, healthcheck

```
func main() {
	if len(os.Args) > 1 && os.Args[1] == "-healthcheck" {
		os.Exit(healthcheck())
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	ctx := context.Background()
	database, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	defer database.Close()

	if err := database.Migrate(ctx); err != nil {
		log.Fatalf("migrate: %v", err)
	}

	srv := api.New(cfg, database, store, setupPush(ctx, cfg, database))
	srv.StartDigestScheduler(ctx)
	srv.StartRecapScheduler(ctx)
	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           srv.Router(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		log.Printf("check-in server listening on %s", cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	// Purge expired sessions hourly to keep the sessions table from growing forever.
	go func() {
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			if _, err := database.Pool.Exec(ctx, `DELETE FROM sessions WHERE expires_at < now()`); err != nil {
				log.Printf("session cleanup: %v", err)
			}
		}
	}()

	// Graceful shutdown on SIGINT/SIGTERM.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop
	log.Println("shutting down...")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}

func healthcheck() int {
	addr := os.Getenv("CHECKIN_HTTP_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	client := http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get("http://127.0.0.1" + addr + "/api/health")
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}
```

#### server/internal/api/helpers.go

JSON helpers, auth middleware, session slide

```
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token := strings.TrimPrefix(header, "Bearer ")
		if token == "" || token == header {
			writeErr(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		hash := auth.HashToken(token)
		user, err := s.db.UserForToken(r.Context(), hash, s.cfg.SessionMaxAge)
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "invalid or expired session")
			return
		}
		s.slideSession(r.Context(), hash)
		ctx := context.WithValue(r.Context(), userCtxKey, user)
		ctx = context.WithValue(ctx, tokenCtxKey, token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (s *Server) requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !userFrom(r).IsAdmin {
			writeErr(w, http.StatusForbidden, "admin only")
			return
		}
		next.ServeHTTP(w, r)
	})
}
```

#### server/internal/api/server.go (Router skeleton)

Router/middleware/group structure

```
r := chi.NewRouter()
r.Use(middleware.ClientIPFromXFFTrustedProxies(trustedHops))
r.Use(middleware.Recoverer)
r.Use(middleware.Timeout(30 * time.Second))
r.Use(secureHeaders)

r.Get("/api/health", s.handleHealth)
r.Get("/api/server-info", s.handleServerInfo)

r.Group(func(r chi.Router) {
	r.Use(s.rateLimitAuth)
	r.Post("/api/auth/signup", s.handleSignup)
	r.Post("/api/auth/login", s.handleLogin)
})

r.Group(func(r chi.Router) {
	r.Use(s.requireAuth)
	r.Post("/api/auth/logout", s.handleLogout)
	r.Get(pathMe, s.handleMe)
	r.With(s.rateLimitUser(s.content.posts)).Post("/api/posts", s.handleCreatePost)
	r.Group(func(r chi.Router) {
		r.Use(s.requireAdmin)
		r.Patch("/api/admin/server", s.handleUpdateServer)
	})
})
return r
```

#### server/internal/api/auth_handlers.go

Representative handlers: health, login, issueSession

```
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 3*time.Second)
	defer cancel()
	if err := s.db.Pool.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := decodeJSON(w, r, &req); err != nil {
		writeErr(w, http.StatusBadRequest, msgInvalidBody)
		return
	}
	phone := auth.NormalizePhone(req.Phone, s.cfg.DefaultCountryCode)
	password := auth.NormalizePassword(req.Password)
	user, hash, err := s.db.GetUserByPhone(r.Context(), phone)
	if err != nil {
		auth.VerifyPassword(password, dummyPasswordHash)
		writeErr(w, http.StatusUnauthorized, "incorrect phone or password")
		return
	}
	if !auth.VerifyPassword(password, hash) {
		writeErr(w, http.StatusUnauthorized, "incorrect phone or password")
		return
	}
	if user.Status != "active" {
		writeErr(w, http.StatusForbidden, "this account has been disabled")
		return
	}
	s.issueSession(w, r, user)
}

func (s *Server) issueSession(w http.ResponseWriter, r *http.Request, user db.User) {
	token, hash, err := auth.NewToken()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, msgServerError)
		return
	}
	expires := time.Now().Add(s.cfg.SessionTTL)
	if err := s.db.CreateSession(r.Context(), user.ID, hash, expires); err != nil {
		writeErr(w, http.StatusInternalServerError, msgServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"token":     token,
		"expiresAt": expires,
		"user":      user,
	})
}
```

#### server/internal/db/db.go

pgx pool + embedded migration runner

```
func Connect(ctx context.Context, url string) (*DB, error) {
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &DB{Pool: pool}, nil
}

const migrationLockKey int64 = 4915012025

func (d *DB) Migrate(ctx context.Context) error {
	conn, err := d.Pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration conn: %w", err)
	}
	defer conn.Release()
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, migrationLockKey); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}
	defer func() {
		_, _ = conn.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, migrationLockKey)
	}()
	if _, err := d.Pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		name TEXT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}
	names, err := migrationNames()
	if err != nil {
		return err
	}
	for _, name := range names {
		applied, err := d.migrationApplied(ctx, name)
		if err != nil {
			return err
		}
		if applied {
			continue
		}
		if err := d.applyMigration(ctx, name); err != nil {
			return err
		}
	}
	return nil
}

// migrations/embed.go
package migrations

import "embed"

//go:embed *.sql
var Files embed.FS
```

#### server/internal/api/digest.go

Representative scheduler pattern (ticker, ctx, recover, timeout) - template for a 4am-3pm quest/reset scheduler

```
func (s *Server) StartDigestScheduler(ctx context.Context) {
	if s.push == nil {
		return
	}
	go func() {
		t := time.NewTicker(digestTick)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				s.runDigest(ctx)
			}
		}
	}()
}

func (s *Server) runDigest(ctx context.Context) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("runDigest: recovered: %v", rec)
		}
	}()
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	// ...
}
```

#### server/internal/api/main_test.go + harness_test.go

TESTDB_URL gating and the harness API

```
const testDBEnv = "TESTDB_URL"
const skipOptOutEnv = "CHECKIN_SKIP_DB_TESTS"

func TestMain(m *testing.M) {
	requireTestDB()
	code := m.Run()
	os.Exit(code)
}

func requireTestDB() {
	if os.Getenv(testDBEnv) != "" || os.Getenv(skipOptOutEnv) != "" {
		return
	}
	fmt.Fprintf(os.Stderr, "%s is not set ... Run server/scripts/test.sh ...", testDBEnv)
	os.Exit(1)
}

func openTestDB(t *testing.T) *db.DB {
	t.Helper()
	url := requireTestDBURL(t)
	testDBOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if testDB, testDBErr = db.Connect(ctx, url); testDBErr != nil {
			return
		}
		testDBErr = testDB.Migrate(ctx)
	})
	if testDBErr != nil {
		t.Fatalf("test database: %v", testDBErr)
	}
	return testDB
}

// resetDB: SELECT quote_ident(tablename) FROM pg_tables WHERE schemaname='public' AND tablename <> 'schema_migrations'
// then: TRUNCATE <all> RESTART IDENTITY CASCADE; then INSERT INTO server_config (id) VALUES (1)

func newHarnessOn(t *testing.T, database *db.DB, mutate func(*config.Config), notifier push.Notifier) *harness {
	t.Helper()
	resetDB(t, database)
	dir := t.TempDir()
	store, err := storage.New(dir)
	if err != nil {
		t.Fatalf("storage: %v", err)
	}
	cfg := config.Config{ServerName: "Check-In", SessionTTL: time.Hour, SessionMaxAge: 24 * time.Hour}
	if mutate != nil {
		mutate(&cfg)
	}
	srv := New(cfg, database, store, notifier)
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)
	return &harness{t: t, db: database, store: store, mediaDir: dir, http: ts, srv: srv}
}

func (r *response) expect(status int) *response {
	r.t.Helper()
	if r.Status != status {
		r.t.Fatalf("status = %d, want %d; body: %s", r.Status, status, r.Body)
	}
	return r
}

func (r *response) decode(v any) *response {
	r.t.Helper()
	if err := json.Unmarshal(r.Body, v); err != nil {
		r.t.Fatalf("decode %T: %v; body: %s", v, err, r.Body)
	}
	return r
}

func (h *harness) admin(name string) actor {
	h.t.Helper()
	phone := h.nextPhone()
	var got authResp
	h.signup(phone, name).expect(http.StatusOK).decode(&got)
	if !got.User.IsAdmin {
		h.t.Fatal("the first member to sign up must become the admin")
	}
	return actor{ID: got.User.ID, Name: got.User.Name, Phone: phone, Token: got.Token}
}
```

#### server/internal/api/session_expiry_test.go

Representative handler test

```
func TestActiveSessionSurvivesTTL(t *testing.T) {
	h := newHarness(t)
	a := h.admin("Ada")

	h.setSessionExpiry(a, time.Now().Add(5*time.Minute))
	h.get("/api/me", a.Token).expect(http.StatusOK)

	if got := h.sessionExpiry(a); time.Until(got) < 50*time.Minute {
		t.Fatalf("an actively used session must have its expiry pushed out, but it still ends in %v", time.Until(got))
	}
}

func TestIdleSessionStillExpires(t *testing.T) {
	h := newHarness(t)
	a := h.admin("Ada")

	h.setSessionExpiry(a, time.Now().Add(-time.Minute))
	h.get("/api/me", a.Token).expect(http.StatusUnauthorized)
}
```

#### server/internal/db/queries.go

Query style (pgx, ErrNotFound mapping, session sliding)

```
func (d *DB) UserForToken(ctx context.Context, tokenHash string, maxAge time.Duration) (User, error) {
	var u User
	err := d.Pool.QueryRow(ctx, `
		SELECT u.id, u.phone, u.name, ... u.is_admin, u.status, u.created_at
		FROM sessions s
		JOIN users u ON u.id = s.user_id
		WHERE s.token_hash = $1 AND s.expires_at > now() AND s.created_at > now() - $2::interval
		  AND u.status = 'active'`, tokenHash, maxAge,
	).Scan(&u.ID, &u.Phone, &u.Name, ...)
	if errors.Is(err, pgx.ErrNoRows) {
		return u, ErrNotFound
	}
	return u, err
}
```

#### server/internal/config/config.go

Config pattern

```
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:      getenv("CHECKIN_HTTP_ADDR", ":8080"),
		DatabaseURL:   os.Getenv("CHECKIN_DATABASE_URL"),
		ServerName:    getenv("CHECKIN_SERVER_NAME", "Check-In"),
		SessionTTL:    getdur("CHECKIN_SESSION_TTL", 30*24*time.Hour),
		SessionMaxAge: getdur("CHECKIN_SESSION_MAX_AGE", 180*24*time.Hour),
		TrustedProxyHops: getPositiveInt("CHECKIN_TRUSTED_PROXY_HOPS", 1),
	}
	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf("CHECKIN_DATABASE_URL is required, e.g. postgres://user:password@host:5432/checkin?sslmode=disable")
	}
	return cfg, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
```

#### server/Dockerfile (minus gazetteer/media bits)

Static build onto distroless

```
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/server"]
```

#### Caddyfile

Reverse proxy template

```
{$CHECKIN_DOMAIN} {
	encode zstd gzip
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		X-Frame-Options "DENY"
		Referrer-Policy "no-referrer"
		Permissions-Policy "geolocation=(), camera=(), microphone=()"
		-Server
	}
	request_body {
		max_size 30MB
	}
	reverse_proxy server:8080
}
```

#### docker-compose.yml (db + server + caddy core)

Compose service wiring

```
networks:
  frontend:
  backend:

services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    networks: [backend]
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-checkin}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env}
      POSTGRES_DB: ${POSTGRES_DB:-checkin}
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-checkin}"]
      interval: 5s
      timeout: 5s
      retries: 10
    deploy: {resources: {limits: {memory: 512M}}}

  server:
    image: ${CHECKIN_IMAGE:-ghcr.io/nc1107/check-in:latest}
    build: ./server
    restart: unless-stopped
    networks: [frontend, backend]
    depends_on:
      db: {condition: service_healthy}
    healthcheck:
      test: ["CMD", "/app/server", "-healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    environment:
      CHECKIN_HTTP_ADDR: ":8080"
      CHECKIN_DATABASE_URL: "postgres://${POSTGRES_USER:-checkin}:${POSTGRES_PASSWORD}@db:5432/${POSTGRES_DB:-checkin}?sslmode=disable"

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    networks: [frontend]
    depends_on: [server]
    ports: ["80:80", "443:443"]
    environment:
      CHECKIN_DOMAIN: ${CHECKIN_DOMAIN:?set CHECKIN_DOMAIN in .env}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  db_data:
  caddy_data:
  caddy_config:
```

#### .github/workflows/ci.yml (server job)

CI with Postgres service and TESTDB_URL

```
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_USER: checkin
      POSTGRES_PASSWORD: ci-${{ github.run_id }}
      POSTGRES_DB: checkin_test
    ports: ["5432:5432"]
    options: >-
      --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
  - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7
    with: {go-version: "1.27", cache-dependency-path: server/go.sum}
  - run: test -z "$(gofmt -l .)" || { gofmt -l .; exit 1; }
  - run: go vet ./...
  - run: go build ./...
  - run: go test ./... -race
    env:
      TESTDB_URL: postgres://checkin:ci-${{ github.run_id }}@localhost:5432/checkin_test?sslmode=disable
```

#### server/scripts/test.sh

Local DB-backed test runner

```
#!/bin/sh
set -e
cd "$(dirname "$0")/.."
CONTAINER=checkin-test-postgres-$$
PORT=${CHECKIN_TEST_PG_PORT:-55432}
PASSWORD=test-$$
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
docker run -d --name "$CONTAINER" -e POSTGRES_USER=checkin -e POSTGRES_PASSWORD="$PASSWORD" -e POSTGRES_DB=checkin_test -p "$PORT":5432 postgres:16-alpine >/dev/null
i=0
until docker exec "$CONTAINER" pg_isready -U checkin >/dev/null 2>&1; do
  i=$((i + 1)); [ "$i" -gt 60 ] && { echo "Postgres did not become ready in 60s" >&2; exit 1; }; sleep 1
done
TESTDB_URL="postgres://checkin:$PASSWORD@127.0.0.1:$PORT/checkin_test?sslmode=disable" \
  go test -race "${@:-./...}"
```

#### .env.example

Env template shape

```
CHECKIN_DOMAIN=your-domain.example.com
CHECKIN_SERVER_NAME=Check-In
POSTGRES_USER=checkin
# Generate with: openssl rand -base64 32
POSTGRES_PASSWORD=
POSTGRES_DB=checkin
# CHECKIN_SESSION_TTL=720h
# CHECKIN_SESSION_MAX_AGE=4320h
# CHECKIN_IMAGE=ghcr.io/nc1107/check-in:v1.0.0
```

#### server/migrations/0001_init.sql

Schema style

```
CREATE TABLE server_config (
    id          INT PRIMARY KEY DEFAULT 1,
    name        TEXT NOT NULL DEFAULT 'Check-In',
    initialized BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT server_config_singleton CHECK (id = 1)
);
INSERT INTO server_config (id) VALUES (1);

CREATE TABLE sessions (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_idx ON sessions(user_id);
```

## CI and release pipeline (check-in reference repo, /home/npc/Documents/projects/check-in)

Two workflows. ci.yml: PR + non-main push, jobs `server` (Go 1.27, gofmt/vet/build/test -race with postgres:16 service, TESTDB_URL) and `app` (Flutter 3.47.0 pinned, pub get --enforce-lockfile, dart format, analyze, test). release.yml: push to main, concurrency group `release` (no cancel). Job graph: test-server + test-app -> version (conventional-commit bump, plain-git tag, build_number = run_number*100+run_attempt, release-notes gate, secrets detection outputs) -> docker (ghcr push :latest and :X.Y.Z) | android | app-store (macos-15, TestFlight via altool, manual signing with imported p12 + mobileprovision) ; release (GitHub Release w/ APK) needs version,docker,android; play-store via fastlane. iOS uses NO fastlane/match; fastlane exists only for Android (app/fastlane/Fastfile). No deploy-to-server automation exists: no watchtower, no ssh, no deploy job. Server is updated manually on the host with `git pull; docker compose pull; docker compose up -d` (docs/self-hosting/operations.md); compose image is `${CHECKIN_IMAGE:-ghcr.io/nc1107/check-in:latest}`. Migrations run at server startup. All actions pinned by full commit SHA with a version comment. Permissions are least-privilege per job (no workflow-level permissions). Check-in specifics to swap for new-me: owner/image `ghcr.io/nc1107/check-in`, bundle id `top.npcserver.checkin`, team ID `76S78SUWVM`, profile name `Check-In App Store Distribution`, DB user/name `checkin`, itc_team_id `18944112454`, apple_id nickpconn@gmail.com.

### Key files

- `/home/npc/Documents/projects/check-in/.github/workflows/ci.yml`: PR/branch CI: Go server job + Flutter app job (76 lines)
- `/home/npc/Documents/projects/check-in/.github/workflows/release.yml`: Release pipeline on push to main (421 lines): test-server, test-app, version, docker, android, release, play-store, app-store
- `/home/npc/Documents/projects/check-in/docs/DEPLOYMENT.md`: Secrets table and one-time Apple/Play setup
- `/home/npc/Documents/projects/check-in/app/ios/ExportOptions.plist`: Manual app-store export options (team, profile name, Apple Distribution cert)
- `/home/npc/Documents/projects/check-in/app/fastlane/Fastfile`: Android-only lane `internal` (Play internal track); iOS does not use fastlane
- `/home/npc/Documents/projects/check-in/app/fastlane/Appfile`: app_identifier, apple_id, team_id, itc_team_id
- `/home/npc/Documents/projects/check-in/app/Gemfile`: just `gem "fastlane"`
- `/home/npc/Documents/projects/check-in/app/ios/Runner.xcodeproj/project.pbxproj`: Release config: CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY=Apple Distribution, DEVELOPMENT_TEAM=76S78SUWVM, PROVISIONING_PROFILE_SPECIFIER="Check-In App Store Distribution", CURRENT_PROJECT_VERSION=$(FLUTTER_BUILD_NUMBER)
- `/home/npc/Documents/projects/check-in/app/ios/Runner/Runner.entitlements`: aps-environment production + keychain-access-groups
- `/home/npc/Documents/projects/check-in/app/ios/Runner/Info.plist`: CFBundleShortVersionString=$(FLUTTER_BUILD_NAME), CFBundleVersion=$(FLUTTER_BUILD_NUMBER), ITSAppUsesNonExemptEncryption=false
- `/home/npc/Documents/projects/check-in/app/lib/features/whats_new/release_notes.dart`: Curated ReleaseNote list; release gate greps first `version: '` line
- `/home/npc/Documents/projects/check-in/.githooks/pre-push`: Local gofmt + dart format gate mirroring CI (core.hooksPath .githooks)
- `/home/npc/Documents/projects/check-in/docker-compose.yml`: db (postgres:16-alpine) + server (ghcr image) + caddy:2-alpine + db-backup + media-backup
- `/home/npc/Documents/projects/check-in/Caddyfile`: Caddy reverse proxy to server:8080 with {$CHECKIN_DOMAIN}, security headers, 30MB body limit
- `/home/npc/Documents/projects/check-in/server/Dockerfile`: Multi-stage golang:1.27-alpine -> distroless static nonroot; self-healthcheck binary flag
- `/home/npc/Documents/projects/check-in/docs/self-hosting/operations.md`: Manual upgrade procedure (pull/up -d), pin via CHECKIN_IMAGE

### Conventions

- Pinned action SHAs (all with trailing version comment): actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7; actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7; subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2 (channel: stable, flutter-version "3.47.0"); actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6; docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4; docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4; docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7; actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7; actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8; softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228 # v3; actions/setup-java@de7274f081f381c8f8158605e0321c36c376e2e6 # v6.0.1 (temurin 17); ruby/setup-ruby@a0102e0972be65f351c307e2d64b9314a57c8073 # v1.324.0 (ruby 3.3, bundler-cache, working-directory app)
- Versions: Flutter 3.47.0 stable (pinned deliberately, comment says bump deliberately); Go 1.27; postgres:16 in CI, postgres:16-alpine in compose; macos-15 runner; CocoaPods gem 1.17.0; Xcode = highest /Applications/Xcode*.app via sort -V (not pinned); timeout-minutes 90 on iOS job
- Version scheme: tag vMAJOR.MINOR.PATCH from conventional commits since last tag (`feat:` -> minor, `BREAKING CHANGE` or `type!:` -> major, else patch); first tag baseline v0.0.0; pubspec version (0.1.0+1) is ignored, CI passes --build-name/--build-number; build_number = run_number*100 + run_attempt (monotonic, satisfies TestFlight uniqueness)
- Feature (minor/major) releases fail unless release_notes.dart first `version: '` equals MAJOR.MINOR; patch releases exempt
- Tagging done with plain git (github-actions[bot] identity, `git push origin $tag`) after the notes gate, because a third-party tag action broke on Node 20 migration
- iOS job gated by `has_appstore == 'true'` which is computed in the version job from `IOS_CERTIFICATE_BASE64` being non-empty; same pattern for has_play (PLAY_SERVICE_ACCOUNT_JSON) and has_keystore (ANDROID_KEYSTORE_BASE64); all store jobs are dormant until secrets exist
- iOS build disables Flutter SPM integration (`flutter config --no-enable-swift-package-manager`) so plugins link via CocoaPods; `pod repo update` before build to avoid stale CDN index; pub cache and Pods cached keyed on hashFiles('app/pubspec.lock')
- Docker image tags: ghcr.io/nc1107/check-in:latest and :X.Y.Z; build-push uses GHA cache (cache-from type=gha, cache-to type=gha,mode=max); login via GITHUB_TOKEN with packages: write
- Release gating: release.yml re-runs server and app tests (ci.yml ignores main) before version job; concurrency group `release`, cancel-in-progress false
- Secrets (from DEPLOYMENT.md): IOS_CERTIFICATE_BASE64 = Apple Distribution identity exported from Keychain Access as .p12, `base64 -w0 cert.p12`; IOS_CERTIFICATE_PASSWORD = password chosen at p12 export; IOS_PROVISIONING_PROFILE_BASE64 = App Store profile for the bundle id from Developer portal, `base64 -w0 profile.mobileprovision`; ASC_API_KEY_BASE64 = App Store Connect API .p8 (App Manager role), `base64 -w0 AuthKey_*.p8`; ASC_KEY_ID = key ID shown in App Store Connect; ASC_ISSUER_ID = issuer ID at top of API keys page. Android (not needed for iPhone-only new-me): ANDROID_KEYSTORE_BASE64, ANDROID_KEY_PROPERTIES, PLAY_SERVICE_ACCOUNT_JSON. GITHUB_TOKEN is built in.
- One-time Apple prerequisites: register Bundle ID in developer portal, create app record in App Store Connect, create Distribution cert and App Store provisioning profile (name must match ExportOptions.plist and PROVISIONING_PROFILE_SPECIFIER exactly)
- Project-side iOS signing is Manual in Release config only (RunnerTests targets stay Automatic); `.gitignore` excludes `.env`, `*.p8`, `AuthKey_*.p8`, service-account json
- Deployment to server: NOT automated. No watchtower, no ssh, no deploy job, nothing in compose/scripts/docs mentions them (grep confirmed). Operator runs `git pull; docker compose pull; docker compose up -d` on the host; migrations auto-run on server startup. Optional pin via CHECKIN_IMAGE env. new-me should add its own deploy mechanism if wanted (e.g. watchtower or ssh job) since the reference has none.
- Repo-level CI conventions: ci.yml on `pull_request` and `push: branches-ignore: [main]`; per-job `permissions:` least privilege; Go job uses per-run DB password `ci-${{ github.run_id }}` to avoid secret scanner hits; server tests require TESTDB_URL and refuse to run without it; pre-push git hook mirrors gofmt and dart format

### Reuse verbatim

- The entire app-store job (macos-15, flutter 3.47.0, pub/Pods caches, Xcode select, cocoapods 1.17.0, pod repo update, keychain + profile install, ASC key placement, flutter build ipa with --export-options-plist, altool upload), only swapping needs/if gating if the version job is renamed
- The version job in full (build_number, notes gate, plain-git tagging, secret detection); point the notes-gate path at new-me's release notes file or drop that step if new-me has no What's New sheet
- The docker job pattern with new image name ghcr.io/<owner>/new-me; context ./server
- test-server/test-app/ci.yml structure and pinned SHAs, adjusting DB user/name from checkin to newme
- ExportOptions.plist with new bundle id key, new profile name, same team ID 76S78SUWVM (same Apple developer account)
- The six iOS secrets list and how each is produced from DEPLOYMENT.md; GITHUB_TOKEN covers ghcr
- Pre-push hook .githooks/pre-push as-is (only if desired)

### Avoid or outdated

- Android jobs (android, play-store), fastlane Fastfile/Gemfile/Appfile Android lane, and ANDROID_*/PLAY_* secrets: new-me is iPhone-only, drop them (release job then needs no APK artifact; drop download-artifact/files or attach nothing)
- Firebase-specific comments/pods in the Build IPA step: the SPM-disable rationale mentions Firebase/grpc; keep the `flutter config --no-enable-swift-package-manager` line only if new-me hits the same issue, otherwise reword
- Caddy Let's Encrypt setup in check-in's Caddyfile will not apply as-is: Nick said nginx already fronts new-me.npc-server.top, restricted to the iPhone app, so new-me needs no Caddy container (expose server port to nginx instead)
- Check-in compose includes push relay, KLIPY, media backups, multi-group scripts (gen-stack.sh, new-group.sh, groups/): not relevant to new-me
- check-in has no automated server deploy: do not assume watchtower or ssh exists; new-me must add or document its own (manual `docker compose pull && up -d`, watchtower on the host, or an ssh deploy job)
- Xcode is not pinned (picks newest installed on macos-15) and cocoapods is installed via gem each run; fastlane's itc_team_id and apple_id are check-in-specific
- pubspec version 0.1.0+1 is a placeholder; real version/build number come only from CI flags, do not rely on pubspec
- The release-notes gate greps the first `version: '` line of a Dart file; if new-me omits that file the gate step errors on feature releases (grep finds nothing), so remove or adapt it
- Pre-push hook falls back to golang:1.24-alpine docker image while CI uses Go 1.27 (minor inconsistency)

### Snippets

#### /home/npc/Documents/projects/check-in/.github/workflows/release.yml (lines 316-421, app-store job)

Entire iOS Build & upload to TestFlight job, copy as-is and swap secrets/bundle only

```
  app-store:
    name: Build & upload iOS to TestFlight
    needs: [version]
    if: >
      needs.version.outputs.has_appstore == 'true' &&
      needs.version.outputs.new_tag != ''
    runs-on: macos-15
    permissions:
      contents: read
    timeout-minutes: 90
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - uses: subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2
        with:
          channel: stable
          flutter-version: "3.47.0"
          cache: true
      - name: Cache pub-cache
        uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
        with:
          path: |
            ~/.pub-cache
            app/.dart_tool
          key: ${{ runner.os }}-pubcache-${{ hashFiles('app/pubspec.lock') }}
          restore-keys: ${{ runner.os }}-pubcache-
      - name: Cache CocoaPods
        uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6
        with:
          path: |
            app/ios/Pods
            ~/.cocoapods
          key: ${{ runner.os }}-pods-${{ hashFiles('app/pubspec.lock') }}
          restore-keys: ${{ runner.os }}-pods-
      - name: Select latest Xcode
        run: |
          XCODE_PATH=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)
          sudo xcode-select -s "$XCODE_PATH/Contents/Developer"
          xcodebuild -version
      - name: Install CocoaPods
        run: gem install cocoapods -v 1.17.0
      # The runner ships a CocoaPods CDN index that is however old its image is, and a
      # plugin bump can point at a pod version published after it. That is not a stale
      # cache to shrug at: pod install does not refresh the index on its own, so it simply
      # reports the version does not exist and the whole iOS build fails - which is exactly
      # how a firebase_core 4.13 -> 4.14 bump broke this, wanting Firebase 12.18.0 against
      # an index that stopped at 12.17.0. Refreshing here is cheap next to an archive.
      - name: Refresh the CocoaPods spec index
        run: pod repo update
      - name: Set up code signing
        env:
          IOS_CERTIFICATE_BASE64: ${{ secrets.IOS_CERTIFICATE_BASE64 }}
          IOS_CERTIFICATE_PASSWORD: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
          IOS_PROVISIONING_PROFILE_BASE64: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
        run: |
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

          echo "$IOS_CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
          echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PP_PATH"

          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security import "$CERTIFICATE_PATH" -P "$IOS_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
          security set-key-partition-list -S apple-tool:,apple: \
            -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security list-keychain -d user -s "$KEYCHAIN_PATH"

          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          UUID=$(/usr/libexec/PlistBuddy -c "Print UUID" /dev/stdin <<< \
            $(security cms -D -i "$PP_PATH"))
          cp "$PP_PATH" ~/Library/MobileDevice/Provisioning\ Profiles/${UUID}.mobileprovision
      - name: Set up App Store Connect API key
        env:
          ASC_API_KEY_BASE64: ${{ secrets.ASC_API_KEY_BASE64 }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
        run: |
          mkdir -p ~/private_keys
          echo "$ASC_API_KEY_BASE64" | base64 --decode > ~/private_keys/AuthKey_${ASC_KEY_ID}.p8
      - name: Build IPA
        working-directory: app
        run: |
          # Disable Flutter's experimental Swift Package Manager integration so every iOS
          # plugin (Firebase, app_links, …) links via CocoaPods (flutter_install_all_ios_pods
          # in the Podfile) - the stable path 1.0 shipped on. SPM's linking left the app stuck
          # on a white launch screen (Firebase's grpc native init trapped before runApp).
          flutter config --no-enable-swift-package-manager
          flutter pub get --enforce-lockfile
          flutter build ipa --release \
            --build-name=${{ needs.version.outputs.new_version }} \
            --build-number=${{ needs.version.outputs.build_number }} \
            --export-options-plist=ios/ExportOptions.plist
      - name: Upload to TestFlight
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          IPA=$(find app/build/ios -name "*.ipa" | head -1)
          xcrun altool --upload-app \
            -f "$IPA" -t ios \
            --apiKey "$ASC_KEY_ID" \
            --apiIssuer "$ASC_ISSUER_ID" \
            --show-progress
```

#### /home/npc/Documents/projects/check-in/.github/workflows/release.yml (lines 88-186, version job)

Version/tag computation, build number, release-notes gate, secret detection

```
  version:
    name: Compute version
    needs: [test-server, test-app]
    runs-on: ubuntu-latest
    permissions:
      contents: write # pushes the release tag
    outputs:
      new_tag: ${{ steps.tag.outputs.new_tag }}
      new_version: ${{ steps.tag.outputs.new_version }}
      changelog: ${{ steps.tag.outputs.changelog }}
      has_play: ${{ steps.secrets.outputs.has_play }}
      has_appstore: ${{ steps.secrets.outputs.has_appstore }}
      has_keystore: ${{ steps.secrets.outputs.has_keystore }}
      build_number: ${{ steps.build.outputs.build_number }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          fetch-depth: 0
      - name: Compute build number
        id: build
        # Expression syntax has no arithmetic, so derive a single monotonic build number
        # (run_number * 100 + run_attempt) in the shell and share it via an output.
        run: echo "build_number=$(( ${{ github.run_number }} * 100 + ${{ github.run_attempt }} ))" >> "$GITHUB_OUTPUT"
      - name: Require release notes for a feature release
        run: |
          last=$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
          log=$(git log --format='%s%n%b' "$last"..HEAD)
          major=$(echo "$last" | sed 's/^v//' | cut -d. -f1)
          minor=$(echo "$last" | sed 's/^v//' | cut -d. -f2)
          if echo "$log" | grep -qE '^BREAKING CHANGE|^[a-z]+(\([^)]*\))?!:'; then
            major=$((major+1)); minor=0
          elif echo "$log" | grep -qE '^feat(\([^)]*\))?:'; then
            minor=$((minor+1))
          else
            echo "patch release: no notes required"; exit 0
          fi
          want="$major.$minor"
          have=$(grep -m1 "version: '" app/lib/features/whats_new/release_notes.dart | sed "s/.*version: '\([^']*\)'.*/\1/")
          if [ "$have" != "$want" ]; then
            echo "::error::This release bumps to $want but the newest What's New entry is '$have'."
            echo "::error::Members who update will see no changelog. Add a ReleaseNote(version: '$want', ...) to app/lib/features/whats_new/release_notes.dart."
            exit 1
          fi
          echo "release notes present for $want"
      - name: Bump version and tag
        id: tag
        run: |
          last=$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)
          log=$(git log --format='%s%n%b' "$last"..HEAD)
          major=$(echo "$last" | sed 's/^v//' | cut -d. -f1)
          minor=$(echo "$last" | sed 's/^v//' | cut -d. -f2)
          patch=$(echo "$last" | sed 's/^v//' | cut -d. -f3)
          if echo "$log" | grep -qE '^BREAKING CHANGE|^[a-z]+(\([^)]*\))?!:'; then
            major=$((major+1)); minor=0; patch=0
          elif echo "$log" | grep -qE '^feat(\([^)]*\))?:'; then
            minor=$((minor+1)); patch=0
          else
            patch=$((patch+1))
          fi
          version="$major.$minor.$patch"
          tag="v$version"
          if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
            echo "::error::$tag already exists. A release for it either succeeded or was tagged by hand."
            exit 1
          fi
          {
            echo "new_version=$version"
            echo "new_tag=$tag"
            echo "changelog<<RELEASE_CHANGELOG"
            git log --format='- %s' "$last"..HEAD
            echo "RELEASE_CHANGELOG"
          } >> "$GITHUB_OUTPUT"
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag "$tag"
          git push origin "$tag"
          echo "tagged $tag (previous $last)"
      - name: Detect store secrets
        id: secrets
        env:
          PLAY_JSON: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          IOS_CERT: ${{ secrets.IOS_CERTIFICATE_BASE64 }}
          KEYSTORE: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          echo "has_play=$([ -n "$PLAY_JSON" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
          echo "has_appstore=$([ -n "$IOS_CERT" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
          echo "has_keystore=$([ -n "$KEYSTORE" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
```

#### /home/npc/Documents/projects/check-in/.github/workflows/release.yml (lines 188-212, docker job)

Docker build+push to ghcr with pinned SHAs

```
  docker:
    name: Build & push server image
    needs: version
    if: needs.version.outputs.new_tag != ''
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write # pushes the image to ghcr
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4
      - uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7
        with:
          context: ./server
          push: true
          tags: |
            ghcr.io/nc1107/check-in:latest
            ghcr.io/nc1107/check-in:${{ needs.version.outputs.new_version }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

#### /home/npc/Documents/projects/check-in/.github/workflows/release.yml (lines 1-20, header/concurrency) and test jobs 24-86

Trigger, concurrency, and test gate jobs (test-server with postgres service, test-app with pinned Flutter)

```
on:
  push:
    branches: [main]

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  test-server:
    name: Test server (Go)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    defaults:
      run:
        working-directory: server
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: checkin
          POSTGRES_PASSWORD: ci-${{ github.run_id }}
          POSTGRES_DB: checkin_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7
        with:
          go-version: "1.27"
          cache-dependency-path: server/go.sum
      - name: Check formatting (gofmt)
        run: test -z "$(gofmt -l .)" || { echo 'These files need gofmt:'; gofmt -l .; exit 1; }
      - run: go vet ./...
      - run: go build ./...
      - run: go test ./... -race
        env:
          TESTDB_URL: postgres://checkin:ci-${{ github.run_id }}@localhost:5432/checkin_test?sslmode=disable

  test-app:
    name: Test app (Flutter)
    runs-on: ubuntu-latest
    permissions:
      contents: read
    defaults:
      run:
        working-directory: app
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
      - uses: subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2 # v2
        with:
          channel: stable
          flutter-version: "3.47.0"
      - run: flutter pub get --enforce-lockfile
      - name: Check formatting (dart format)
        run: dart format --output=none --set-exit-if-changed lib test
      - run: flutter analyze
      - run: flutter test
```

#### /home/npc/Documents/projects/check-in/.github/workflows/release.yml (lines 256-273, GitHub Release job)

Release creation (check-in attaches Android APK; new-me iPhone-only could drop files or attach nothing)

```
  release:
    name: GitHub Release
    needs: [version, docker, android]
    if: needs.version.outputs.new_tag != ''
    runs-on: ubuntu-latest
    permissions:
      contents: write # creates the GitHub release
    steps:
      - uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8
        with:
          name: android
          path: ./artifacts
      - uses: softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228 # v3
        with:
          tag_name: ${{ needs.version.outputs.new_tag }}
          name: ${{ needs.version.outputs.new_tag }}
          body: ${{ needs.version.outputs.changelog }}
          files: ./artifacts/**/*.apk
```

#### /home/npc/Documents/projects/check-in/app/ios/ExportOptions.plist

Full export options for manual app-store signing

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>76S78SUWVM</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>top.npcserver.checkin</key>
		<string>Check-In App Store Distribution</string>
	</dict>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
```

#### /home/npc/Documents/projects/check-in/app/ios/Runner.xcodeproj/project.pbxproj (Release Runner target, ~L575-598)

Xcode project signing settings that must match ExportOptions.plist

```
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
CODE_SIGN_IDENTITY = "Apple Distribution";
CODE_SIGN_STYLE = Manual;
CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
DEVELOPMENT_TEAM = 76S78SUWVM;
PRODUCT_BUNDLE_IDENTIFIER = top.npcserver.checkin;
PROVISIONING_PROFILE_SPECIFIER = "Check-In App Store Distribution";
VERSIONING_SYSTEM = "apple-generic";
```

#### /home/npc/Documents/projects/check-in/docker-compose.yml (server+caddy excerpt)

How the server image is consumed on the host (no auto-deploy; manual pull)

```
  server:
    image: ${CHECKIN_IMAGE:-ghcr.io/nc1107/check-in:latest}
    build: ./server
    restart: unless-stopped
    networks: [frontend, backend]
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "/app/server", "-healthcheck"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
  caddy:
    image: caddy:2-alpine
    ports: ["80:80", "443:443"]
    environment:
      CHECKIN_DOMAIN: ${CHECKIN_DOMAIN:?set CHECKIN_DOMAIN in .env}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
```

#### /home/npc/Documents/projects/check-in/docs/self-hosting/operations.md (lines ~25-32)

Only documented deploy procedure for the server image

```
git pull                          # get any compose/Caddyfile changes
docker compose pull               # fetch the newest server image
docker compose up -d              # recreate changed containers
```

#### /home/npc/Documents/projects/check-in/app/fastlane/Appfile

Apple identifiers used by fastlane (Android lane only uses package_name)

```
app_identifier "top.npcserver.checkin"
apple_id "nickpconn@gmail.com"
team_id "76S78SUWVM"
itc_team_id "18944112454"
```
