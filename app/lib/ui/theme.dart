// The approved design (owner, 2026-11-04; docs/design/prototype_v2.html): soft off-white surfaces (#fdfdfb cards on
// #f7f6f2; pure white and cream were turned down), blue #1d5bd8 (navy was turned down), hairline borders, pill
// buttons. Type (owner's pick, 2026-11-16): Inter for the interface, Newsreader for the large headings and the
// therapist's words (below). Every font is bundled in the app (assets/fonts, SIL Open Font License), never fetched.
//
// Appearance (owner, 2026-11-14: "select their preferred font and also the font size", "rich quality colours and
// hues", "dark or light theme"): Settings > Appearance chooses light, dark or the device's own; one of five colour
// palettes (Ocean is the approved blue and the default); one of five reading fonts; the text size on top of the
// device's own; and whether headings and the therapist's words use the serif. Every palette was checked for contrast
// (WCAG AA, 4.5 to 1 for text) in light and dark: docs/DECISIONS.md 2026-11-14.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'premium.dart' show CalmPageTransitions, Radii, Widths, smoothShape;

const appName = 'Solace'; // the owner's choice, 2026-11-14 ("for now"); change it here

// ---- Typography: the faces, the pairing and the type scale, in one place ----------------------------------------
// The owner's pick (2026-11-16, "Editorial", of three drawn; the old look was "too basic"): Newsreader for the
// headings and the therapist's words, one serif family drawn at every optical size, so the large titles and her words
// are visibly one voice; Inter for the interface. Both are variable fonts (weight and optical size), bundled under the
// SIL Open Font License (assets/fonts, licence files beside them; source and checksums in app/README.md).

/// A typeface as the design sets it: its family, its optical-size range, and the faces that stand in for letters it
/// lacks. A variable font's optical size follows the type size within the range (a browser does this on its own;
/// Flutter does not), so large text gets the face's display drawing and small text its sturdier text drawing. The
/// weight axis follows the style's weight on its own (the engine sets wght from fontWeight).
class Face {
  const Face(this.family, {this.opsz, this.fallback});
  final String family;
  final (double, double)? opsz;
  final List<String>? fallback; // then the device's own fonts, for any script neither has

  List<FontVariation>? at(double size) =>
      opsz == null ? null : [FontVariation('opsz', size.clamp(opsz!.$1, opsz!.$2).toDouble())];

  /// This face at a size, a weight, a line height (a multiple of the size) and a letter spacing in em (a share of
  /// the size, so it scales with the size).
  TextStyle style(double size, FontWeight weight, {double? height, double tracking = 0, Color? color}) => TextStyle(
      fontFamily: family, fontFamilyFallback: fallback, fontSize: size, fontWeight: weight, height: height,
      letterSpacing: tracking * size, fontVariations: at(size), color: color);
}

/// The design's pairing: a sans for the interface and body, a heading face for the large titles, and the face the
/// therapist's words are set in at reading sizes. Sizes in the scale are the design's; the heading face sets them
/// scaled by [headingScale] (1 for Newsreader; a condensed or a wide face would need less or more).
class Pairing {
  const Pairing({required this.name, required this.ui, required this.heading, required this.reading,
      required this.headingScale, required this.headingWeight, required this.headingTracking,
      required this.readingScale, required this.readingWeight, this.headingHeight = 1.12, this.readingHeight = 1.5,
      this.uiTracking = 0});
  final String name;
  final Face ui, heading, reading;
  final double headingScale, headingTracking, headingHeight;
  final FontWeight headingWeight;
  final double readingScale, readingHeight;
  final FontWeight readingWeight;
  final double uiTracking; // added to every interface role's letter spacing (em)

  /// A heading at the design's [size].
  TextStyle headingAt(double size, {Color? color}) =>
      heading.style(size * headingScale, headingWeight, height: headingHeight, tracking: headingTracking, color: color);

  /// The therapist's words at the design's [size]: the heading's display drawing from 28 up, the text drawing below.
  TextStyle voiceAt(double size, {Color? color}) => size >= 28
      ? heading.style(size * headingScale, headingWeight, height: 1.2, tracking: headingTracking, color: color)
      : reading.style(size * readingScale, readingWeight, height: readingHeight, color: color);
}

const _inter = Face('Inter', opsz: (14, 32));
const _newsreader = Face('Newsreader', opsz: (6, 72), fallback: ['Inter']); // Inter has the Greek and Cyrillic

/// Newsreader's headings at its display drawing (optical size 36 and up: finer contrast, tighter spacing), regular
/// weight; her words at 18 in a chat bubble (20 x 0.9), a touch heavier than regular so the text drawing holds on a
/// phone (research report 2026-11-14, P1 9: a text face for message text, never a display face), on the same line
/// pitch as before (1.22 x the design size: the call's layout counts three lines of her words); Inter a hair tighter
/// than its default, as Linear and Apple set their interface.
const pairing = Pairing(name: 'Editorial', ui: _inter,
    heading: Face('Newsreader', opsz: (36, 72), fallback: ['Inter']), headingScale: 1, headingWeight: FontWeight.w400,
    headingTracking: -0.01, reading: _newsreader, readingScale: 0.9, readingWeight: FontWeight(450),
    readingHeight: 1.36, uiTracking: -0.004);

/// The interface font a person has before choosing one.
const defaultFont = 'inter';

/// The interface fonts a person can choose: id -> (family, name shown, what it is good for). Figtree (the default
/// until 2026-11-16) and Literata (the old reading serif) went with the old look: a saved choice of either moves to
/// Inter or to Newsreader, the same kind of face (core/store.dart).
const fontChoices = <String, (String, String, String)>{
  'inter': ('Inter', 'Inter', 'Clear and calm, the standard'),
  'atkinson': ('AtkinsonHyperlegibleNext', 'Atkinson Hyperlegible', 'Every letter easy to tell apart, made for low vision'),
  'lexend': ('Lexend', 'Lexend', 'Wide and even, made for easy reading'),
  'nunito': ('Nunito', 'Nunito', 'Soft and rounded'),
  'newsreader': ('Newsreader', 'Newsreader', 'Classic, like a good book'),
};

/// The interface face for a family: Inter and Newsreader with their optical sizes; another chosen font as it is, with
/// Inter for the Greek and Cyrillic it lacks.
Face uiFace(String family) =>
    switch (family) { 'Inter' => _inter, 'Newsreader' => _newsreader, _ => Face(family, fallback: const ['Inter']) };

/// The type scale: every interface role's size, weight, line height and letter spacing (em), in one place. Sizes are
/// before the person's text size. Titles and buttons are semibold, never bold (bold at small sizes reads as
/// shouting); letter spacing tightens as text grows and opens slightly for the smallest labels; body text keeps
/// generous lines. Headings (display and headline) are in the heading face, or, with the serif off, in the interface
/// face a step smaller and firmer. Numbers that must line up add [numerals].
TextTheme typeScale(Look look) {
  final ui = uiFace(look.family);
  TextStyle role(double size, FontWeight weight, double height, double tracking) =>
      ui.style(size, weight, height: height, tracking: tracking + pairing.uiTracking);
  TextStyle heading(double size) => look.serif
      ? pairing.headingAt(size)
      : ui.style(size * 0.8, FontWeight.w600, height: 1.15, tracking: -0.016);
  return TextTheme(
    displayLarge: heading(52), displayMedium: heading(44), displaySmall: heading(38), // the timer, a big moment
    headlineLarge: heading(36), headlineMedium: heading(32), headlineSmall: heading(28), // a tab's or a screen's title
    titleLarge: role(20, FontWeight.w600, 1.3, -0.014), // a bar's title, a section
    titleMedium: role(16, FontWeight.w600, 1.35, -0.008), // a card's title
    titleSmall: role(14, FontWeight.w600, 1.35, -0.004), // a list row
    bodyLarge: role(16, FontWeight.w400, 1.5, -0.006), // reading text, the person's own words
    bodyMedium: role(14, FontWeight.w400, 1.45, -0.002), // most text
    bodySmall: role(12, FontWeight(450), 1.4, 0.004), // a caption, a hint: a touch firmer, so it holds over a photo
    labelLarge: role(14, FontWeight.w600, 1.25, 0), // a button
    labelMedium: role(12, FontWeight.w500, 1.3, 0.008), // a chip, a rail label
    labelSmall: role(11, FontWeight.w500, 1.3, 0.016), // the smallest label
  );
}

/// Numbers that line up (a timer, a count, a chart): tabular figures, which Inter, Newsreader and Atkinson Hyperlegible
/// have (Lexend and Nunito keep their own figures). Merge it into a role: `t.titleSmall?.merge(numerals)`.
const numerals = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// Text sizes on top of the device's own setting: (factor, name).
const textSizes = <(double, String)>[
  (0.9, 'Smaller'), (1.0, 'Standard'), (1.15, 'Larger'), (1.3, 'Largest'), (1.5, 'Extra large'),
];

/// One colour palette, light and dark.
class Accent {
  const Accent(this.name, {required this.primary, required this.light, required this.deep, required this.container,
      required this.container2, required this.darkPrimary, required this.darkContainer, required this.darkOnContainer});
  final String name;
  final Color primary, light, deep, container, container2; // light theme
  final Color darkPrimary, darkContainer, darkOnContainer; // dark theme
}

const accents = <String, Accent>{
  'ocean': Accent('Ocean', primary: Color(0xFF1D5BD8), light: Color(0xFF3B7BF0), deep: Color(0xFF0C2F73),
      container: Color(0xFFE8F0FD), container2: Color(0xFFD5E3FB),
      darkPrimary: Color(0xFF7FA8F5), darkContainer: Color(0xFF0C2F73), darkOnContainer: Color(0xFFD5E3FB)),
  'lagoon': Accent('Lagoon', primary: Color(0xFF0B7A70), light: Color(0xFF0E8C7E), deep: Color(0xFF05433F),
      container: Color(0xFFDFF3EF), container2: Color(0xFFC6EAE3),
      darkPrimary: Color(0xFF5CD3C2), darkContainer: Color(0xFF0A3D39), darkOnContainer: Color(0xFFC9EFE8)),
  'plum': Accent('Plum', primary: Color(0xFF6B3FC6), light: Color(0xFF8459E8), deep: Color(0xFF341A73),
      container: Color(0xFFEFE9FC), container2: Color(0xFFE0D5FA),
      darkPrimary: Color(0xFFB9A0F7), darkContainer: Color(0xFF2E1A63), darkOnContainer: Color(0xFFE3D9FB)),
  'rose': Accent('Rose', primary: Color(0xFFB8235F), light: Color(0xFFD23F72), deep: Color(0xFF6E0F37),
      container: Color(0xFFFCE8EF), container2: Color(0xFFF8D3E1),
      darkPrimary: Color(0xFFF39ABD), darkContainer: Color(0xFF5A1030), darkOnContainer: Color(0xFFFAD5E3)),
  'honey': Accent('Honey', primary: Color(0xFF9A5806), light: Color(0xFFB06A0C), deep: Color(0xFF563003),
      container: Color(0xFFFCF0DD), container2: Color(0xFFF8E1BD),
      darkPrimary: Color(0xFFF1B968), darkContainer: Color(0xFF4A2C06), darkOnContainer: Color(0xFFF8E3C2)),
};

/// What the person chose in Settings > Appearance (the text size and light or dark are applied in main.dart).
class Look {
  const Look({this.font = defaultFont, this.accent = 'ocean', this.serif = true, this.contrast = false});
  final String font;
  final String accent;
  final bool serif;
  final bool contrast; // the device asks for more contrast (iOS Increase Contrast, Android high-contrast text)
  Look withContrast() => Look(font: font, accent: accent, serif: serif, contrast: true);
  String get family => (fontChoices[font] ?? fontChoices[defaultFont]!).$1;
  Accent get palette => accents[accent] ?? accents['ocean']!;
  @override
  bool operator ==(Object other) => other is Look && other.font == font && other.accent == accent &&
      other.serif == serif && other.contrast == contrast;
  @override
  int get hashCode => Object.hash(font, accent, serif, contrast);
}

final _themes = <(Brightness, Look), ThemeData>{};

/// The theme for a choice, built once: the app rebuilds often (every save), the theme only when the choice changes.
ThemeData themeFor(Brightness b, Look look) => _themes.putIfAbsent((b, look), () => appTheme(b, look));

// The neutrals of the approved design (the prototype's CSS tokens, same names).
const _white = Color(0xFFFDFDFB), _ice = Color(0xFFF7F6F2), _night = Color(0xFF081A3D);
// the quiet text a step deeper than the prototype's #5A6A84 (5.1 to 1 on the page): small grey text kept its AA margin
// only on paper; at 12 pixels, anti-aliased, it measured 4.2 to 1, so it is now 6.2 to 1 and holds in sunlight
const _ink = Color(0xFF0B1B33), _slate = Color(0xFF4E5D74), _hair = Color(0xFFDEDBD3); // hairline readable in sunlight
const _good = Color(0xFF11845A), _goodSoft = Color(0xFFE2F4EC), _alert = Color(0xFFD0423B), _alertSoft = Color(0xFFFBE9E8);
// Dark: a lifted navy base, not near-black, with depth shown by four lighter surfaces, as Material and iOS do
// (research report 2026-11-14, P1 10; the old page was 1.09:1 from black, with one raised step).
const _darkPage = Color(0xFF0D1626), _darkCard = Color(0xFF141E31), _darkInk = Color(0xFFE7EEF9);
const _darkStep2 = Color(0xFF1B263B), _darkStep3 = Color(0xFF232F46), _darkStep4 = Color(0xFF2B3852);
const _darkMuted = Color(0xFF9DADC6), _darkLine = Color(0xFF26324A);

// A hue for each kind of practice: (icon, its soft circle) in light, then in dark.
const _categoryLight = <String, (Color, Color)>{
  'morning': (Color(0xFFB45309), Color(0xFFFDF0DC)), 'calm': (Color(0xFF0F766E), Color(0xFFDCF3EF)),
  'kindness': (Color(0xFFBE185D), Color(0xFFFBE4EE)), 'direction': (Color(0xFF4338CA), Color(0xFFE7E8FB)),
  'let_go': (Color(0xFF0369A1), Color(0xFFDCEFFF)), 'urges': (Color(0xFF0E7490), Color(0xFFD9F2F7)),
  'deep': (Color(0xFF7C3AED), Color(0xFFEFE6FD)), 'sleep': (Color(0xFF3730A3), Color(0xFFE4E3F7)),
  'feel_good': (Color(0xFFA16207), Color(0xFFFBF1D0)), 'safe': (Color(0xFF4D7C0F), Color(0xFFEBF3DC)),
  'tools': (Color(0xFF1D4ED8), Color(0xFFE3EBFD)),
};
const _categoryDark = <String, (Color, Color)>{
  'morning': (Color(0xFFF6C27A), Color(0xFF32343C)), 'calm': (Color(0xFF6FD6C6), Color(0xFF1D3748)),
  'kindness': (Color(0xFFF5A3C4), Color(0xFF322F48)), 'direction': (Color(0xFFA5ABF5), Color(0xFF253050)),
  'let_go': (Color(0xFF8CCBF5), Color(0xFF213550)), 'urges': (Color(0xFF79D3E6), Color(0xFF1E374D)),
  'deep': (Color(0xFFC4A6F8), Color(0xFF2A3050)), 'sleep': (Color(0xFFA9A5EF), Color(0xFF262F4F)),
  'feel_good': (Color(0xFFF2CF6B), Color(0xFF323639)), 'safe': (Color(0xFFB3D77A), Color(0xFF28373C)),
  'tools': (Color(0xFF93B4F7), Color(0xFF223250)),
};

// The mood scale, 0 to 10: a calm turn from indigo through blue to green; never red (no mood is wrong).
const _moodLight = [Color(0xFF482BA1), Color(0xFF352BA1), Color(0xFF2B35A1), Color(0xFF2B48A1), Color(0xFF2B5CA1),
    Color(0xFF296A99), Color(0xFF277691), Color(0xFF248189), Color(0xFF228179), Color(0xFF207963), Color(0xFF1E714E)];
const _moodDark = [Color(0xFFA690EA), Color(0xFF9790EA), Color(0xFF9097EA), Color(0xFF90A6EA), Color(0xFF90B5EA),
    Color(0xFF90C4EA), Color(0xFF90D3EA), Color(0xFF90E2EA), Color(0xFF90EAE2), Color(0xFF90EAD3), Color(0xFF90EAC4)];

/// The colours beyond Material's scheme: the therapist's card, the call, each kind of practice, the mood scale.
class Hues extends ThemeExtension<Hues> {
  const Hues({required this.therapist, required this.call, required this.categories, required this.mood,
      required this.serif, required this.uiFamily, required this.onPill});
  final LinearGradient therapist; // the therapist's card, top left to bottom right
  final Color onPill; // the words on a white pill over Solace's card: the palette's deep ink, in light and dark alike
  final List<Color> call; // the call screen's background, top to bottom
  final Map<String, (Color, Color)> categories;
  final List<Color> mood;
  final bool serif; // the therapist's words in the pairing's voice; off, in the person's reading font
  final String uiFamily; // the person's reading font

  (Color, Color) category(String c) => categories[c] ?? categories['tools']!;

  @override
  Hues copyWith({LinearGradient? therapist, List<Color>? call, Map<String, (Color, Color)>? categories,
          List<Color>? mood, bool? serif, String? uiFamily, Color? onPill}) =>
      Hues(therapist: therapist ?? this.therapist, call: call ?? this.call, categories: categories ?? this.categories,
          mood: mood ?? this.mood, serif: serif ?? this.serif, uiFamily: uiFamily ?? this.uiFamily,
          onPill: onPill ?? this.onPill);

  @override
  Hues lerp(Hues? other, double t) => other == null || t < 0.5 ? this : other;
}

Hues huesOf(BuildContext context) => Theme.of(context).extension<Hues>()!;

/// The therapist's words: the pairing's voice (or the person's reading font, if they turned the serif off). The large
/// sizes (28 and up) are in the heading face; reading sizes in the reading face at its text optical size, about
/// 18/27 in a chat bubble (research report 2026-11-14, P1 9: a text face for message text, never a display face).
TextStyle voiceStyle(BuildContext context, {double size = 20, Color? color}) {
  final hues = huesOf(context);
  final c = color ?? Theme.of(context).colorScheme.onSurface;
  if (!hues.serif) return uiFace(hues.uiFamily).style(size * 0.82, FontWeight.w400, height: 1.45, color: c);
  return pairing.voiceAt(size, color: c);
}

/// The person's text size on top of the device's own (which may scale small and large text differently), kept
/// below 2.5 times so no screen breaks apart.
class ChosenTextScaler extends TextScaler {
  const ChosenTextScaler(this.device, this.factor);
  final TextScaler device;
  final double factor;
  @override
  double scale(double fontSize) => math.min(device.scale(fontSize * factor), fontSize * 2.5);
  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => math.min(device.textScaleFactor * factor, 2.5);
  @override
  bool operator ==(Object other) => other is ChosenTextScaler && other.device == device && other.factor == factor;
  @override
  int get hashCode => Object.hash(device, factor);
}

ThemeData appTheme(Brightness b, [Look look = const Look()]) {
  final light = b == Brightness.light;
  final a = look.palette;
  final ui = look.family;
  final normal = light
      ? ColorScheme.light(primary: a.primary, onPrimary: _white, primaryContainer: a.container,
          onPrimaryContainer: a.deep, secondary: a.light, onSecondary: _white, secondaryContainer: a.container2,
          onSecondaryContainer: a.deep, tertiary: _good, onTertiary: _white, tertiaryContainer: _goodSoft,
          onTertiaryContainer: const Color(0xFF0B5A3E), error: _alert, onError: _white, errorContainer: _alertSoft,
          onErrorContainer: const Color(0xFF7A1F1A), surface: _white, onSurface: _ink, onSurfaceVariant: _slate,
          outline: const Color(0xFFC9C6BD), outlineVariant: _hair, surfaceContainerLowest: const Color(0xFFFFFFFF),
          surfaceContainerLow: _white, surfaceContainer: _ice, surfaceContainerHigh: const Color(0xFFEFEEEA),
          surfaceContainerHighest: const Color(0xFFE9E7E1), inverseSurface: _night, onInverseSurface: _darkInk,
          inversePrimary: a.darkPrimary, shadow: const Color(0x1A0B1B33))
      : ColorScheme.dark(primary: a.darkPrimary, onPrimary: _night, primaryContainer: a.darkContainer,
          onPrimaryContainer: a.darkOnContainer, secondary: a.light, onSecondary: _white,
          secondaryContainer: a.darkContainer, onSecondaryContainer: a.darkOnContainer,
          tertiary: const Color(0xFF6FD3A4), onTertiary: const Color(0xFF00391F),
          tertiaryContainer: const Color(0xFF0E3B2A), onTertiaryContainer: _goodSoft, error: const Color(0xFFF2877F),
          onError: const Color(0xFF4A0C08), errorContainer: const Color(0xFF5C1A15), onErrorContainer: _alertSoft,
          surface: _darkCard, onSurface: _darkInk, onSurfaceVariant: _darkMuted, outline: const Color(0xFF41536F),
          outlineVariant: _darkLine, surfaceContainerLowest: _darkPage, surfaceContainerLow: _darkCard,
          surfaceContainer: _darkStep2, surfaceContainerHigh: _darkStep3,
          surfaceContainerHighest: _darkStep4, inverseSurface: _ice, onInverseSurface: _ink,
          inversePrimary: a.primary, shadow: const Color(0x66000000));
  // more contrast when the device asks for it: stronger ink, muted text and edges, a deeper (or brighter) accent
  final scheme = !look.contrast ? normal : light
      ? normal.copyWith(primary: a.deep, onSurface: const Color(0xFF020B1A), onSurfaceVariant: const Color(0xFF26364F),
          outline: const Color(0xFF6E6A60), outlineVariant: const Color(0xFF8C887E), surface: Colors.white)
      : normal.copyWith(primary: Color.lerp(a.darkPrimary, Colors.white, 0.35), onSurface: Colors.white,
          onSurfaceVariant: const Color(0xFFD3DCEA), outline: const Color(0xFF8293B0),
          outlineVariant: const Color(0xFF6A7B99), surface: const Color(0xFF101828));
  final page = look.contrast ? (light ? _white : const Color(0xFF070C16)) : (light ? _ice : _darkPage);
  final line = look.contrast ? (light ? const Color(0xFF8C887E) : const Color(0xFF6A7B99)) : (light ? _hair : _darkLine);
  final base = (light ? Typography.material2021().black : Typography.material2021().white).merge(typeScale(look))
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  final text = base.copyWith(bodySmall: base.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
  final hues = Hues(
    therapist: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: light ? [a.light, a.primary, a.deep] : [a.primary, a.deep, Color.lerp(a.deep, _darkPage, 0.55)!]),
    call: light ? [a.primary, _night] : [a.deep, _darkPage],
    categories: light ? _categoryLight : _categoryDark,
    mood: light ? _moodLight : _moodDark,
    serif: look.serif,
    uiFamily: ui,
    onPill: a.deep,
  );
  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: ui,
    textTheme: text,
    extensions: [hues],
    scaffoldBackgroundColor: page,
    canvasColor: page,
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(backgroundColor: page, foregroundColor: scheme.onSurface, surfaceTintColor: Colors.transparent,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface)),
    // continuous corners and a hairline on every card; depth comes from the surface steps, never a grey shadow
    // no side margin: a card's edge lines up with the headers and words above it, on every screen (the default of 4
    // put most cards 4 pixels in from the rest)
    cardTheme: CardThemeData(elevation: 0, color: scheme.surface, surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 4), shape: smoothShape(Radii.card, BorderSide(color: line))),
    listTileTheme: ListTileThemeData(iconColor: scheme.primary,
        titleTextStyle: text.titleSmall?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
    // calm page transitions: each platform's own (the iPhone and Mac swipe back), a soft fade forwards elsewhere; a
    // plain fade when the device asks for less motion (ui/premium.dart CalmPageTransitions)
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CalmPageTransitions(CupertinoPageTransitionsBuilder()),
      TargetPlatform.macOS: CalmPageTransitions(CupertinoPageTransitionsBuilder()),
      TargetPlatform.android: CalmPageTransitions(FadeForwardsPageTransitionsBuilder()),
      TargetPlatform.linux: CalmPageTransitions(FadeForwardsPageTransitionsBuilder()),
      TargetPlatform.windows: CalmPageTransitions(FadeForwardsPageTransitionsBuilder()),
    }),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: page, indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary), unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, elevation: 0, height: 68,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 24,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => text.labelSmall?.copyWith(fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), textStyle: text.labelLarge)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: pill,
        side: BorderSide(color: line), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: text.labelLarge)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill, textStyle: text.labelLarge)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: pill, elevation: 0)),
    segmentedButtonTheme: SegmentedButtonThemeData(style: SegmentedButton.styleFrom(
        side: BorderSide(color: line), selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer, textStyle: text.labelLarge)),
    chipTheme: ChipThemeData(shape: StadiumBorder(side: BorderSide(color: line)), side: BorderSide(color: line),
        backgroundColor: scheme.surface, selectedColor: scheme.primaryContainer,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface), showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.primary, width: 1.5))),
    // on a tablet or the Mac a sheet keeps a comfortable width instead of spanning the screen
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent,
        showDragHandle: true, constraints: const BoxConstraints(maxWidth: Widths.sheet),
        shape: const RoundedSuperellipseBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)))),
    // a dialog keeps a sensible width on a large window (it spanned a 1920-pixel window edge to edge)
    dialogTheme: DialogThemeData(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: Widths.dialog),
        shape: smoothShape(Radii.large)),
    bannerTheme: MaterialBannerThemeData(backgroundColor: scheme.primaryContainer, elevation: 0),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: scheme.inverseSurface,
        shape: smoothShape(Radii.small + 4)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary, linearTrackColor: line),
    sliderTheme: SliderThemeData(activeTrackColor: scheme.primary, inactiveTrackColor: line, thumbColor: scheme.primary),
    switchTheme: SwitchThemeData(trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.transparent : line)),
  );
}
