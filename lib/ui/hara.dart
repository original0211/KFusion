import 'package:material_ui/material_ui.dart';

/// Hara A ("white") palette: one field per brightness, hierarchy carried by
/// type, hairlines and space rather than surface steps.
class HaraPalette {
  const HaraPalette({
    required this.bg,
    required this.ink,
    required this.sub,
    required this.dim,
    required this.line,
    required this.vermilion,
  });

  // The one literal allowed outside a palette instance: fully clear, for
  // slots that must keep their geometry while showing nothing (the mode
  // row's unselected underlines).
  static const Color transparent = Color(0x00000000);

  final Color bg;
  final Color ink;
  final Color sub;
  final Color dim;
  final Color line;

  /// Marks "current / connected" only; at most one dot per screen, consumed
  /// solely through [HaraDot].
  final Color vermilion;

  static const light = HaraPalette(
    bg: Color(0xFFFFFFFF),
    ink: Color(0xFF1A1A1A),
    sub: Color(0xFF6F6F6F),
    dim: Color(0xFFB4B4B0),
    line: Color(0xFFE9E9E6),
    vermilion: Color(0xFF7F0019),
  );

  static const dark = HaraPalette(
    bg: Color(0xFF101010),
    ink: Color(0xFFEDEDEA),
    sub: Color(0xFF8F8F8A),
    dim: Color(0xFF55554F),
    line: Color(0xFF262624),
    vermilion: Color(0xFFB03A30),
  );

  factory HaraPalette.of(Brightness brightness, {bool pureBlack = false}) {
    if (brightness == Brightness.light) return light;
    if (!pureBlack) return dark;
    return dark.copyWith(
      bg: const Color(0xFF000000),
      line: const Color(0xFF1C1C1C),
    );
  }

  HaraPalette copyWith({Color? bg, Color? line}) {
    return HaraPalette(
      bg: bg ?? this.bg,
      ink: ink,
      sub: sub,
      dim: dim,
      line: line ?? this.line,
      vermilion: vermilion,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HaraPalette &&
        other.bg == bg &&
        other.ink == ink &&
        other.sub == sub &&
        other.dim == dim &&
        other.line == line &&
        other.vermilion == vermilion;
  }

  @override
  int get hashCode => Object.hash(bg, ink, sub, dim, line, vermilion);
}

/// Carries the [HaraPalette] on the theme so migrated surfaces read one
/// token source while unmigrated surfaces keep the cabin tokens untouched.
class HaraTheme extends ThemeExtension<HaraTheme> {
  const HaraTheme(this.palette);

  final HaraPalette palette;

  @override
  HaraTheme copyWith({HaraPalette? palette}) {
    return HaraTheme(palette ?? this.palette);
  }

  @override
  HaraTheme lerp(ThemeExtension<HaraTheme>? other, double t) {
    if (other is! HaraTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension HaraPaletteContext on BuildContext {
  HaraPalette get haraPalette {
    return Theme.of(this).extension<HaraTheme>()?.palette ??
        HaraPalette.of(Theme.of(this).brightness);
  }
}

/// The A type scale. Sizes, weights and tracking are the settled values of
/// the design spec; nothing here falls back to a second reading.
abstract final class HaraText {
  static TextStyle _of(
    BuildContext context, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    bool mono = false,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static TextStyle brand(BuildContext context, Color color) {
    return _of(context, size: 10, letterSpacing: 3.4, color: color);
  }

  static TextStyle pageTitle(BuildContext context, Color color) {
    return _of(context, size: 20, color: color);
  }

  static TextStyle status(BuildContext context, Color color) {
    return _of(
      context,
      size: 15,
      weight: FontWeight.w500,
      letterSpacing: 6,
      color: color,
    );
  }

  static TextStyle statusNode(BuildContext context, Color color) {
    return _of(context, size: 12.5, color: color);
  }

  static TextStyle dataKey(BuildContext context, Color color) {
    return _of(context, size: 11.5, letterSpacing: 2.2, color: color);
  }

  static TextStyle dataValue(BuildContext context, Color color) {
    return _of(
      context,
      size: 13,
      weight: FontWeight.w500,
      color: color,
      mono: true,
    );
  }

  static TextStyle dataUnit(BuildContext context, Color color) {
    return _of(context, size: 11.5, color: color);
  }

  static TextStyle mode(
    BuildContext context,
    Color color, {
    required bool selected,
  }) {
    return _of(
      context,
      size: 13.5,
      weight: selected ? FontWeight.w500 : FontWeight.w400,
      color: color,
    );
  }

  static TextStyle sectionTitle(BuildContext context, Color color) {
    return _of(context, size: 11, letterSpacing: 3, color: color);
  }

  static TextStyle nodeName(
    BuildContext context,
    Color color, {
    required bool current,
  }) {
    return _of(
      context,
      size: 15,
      weight: current ? FontWeight.w600 : FontWeight.w400,
      color: color,
    );
  }

  static TextStyle delay(BuildContext context, Color color) {
    return _of(
      context,
      size: 12.5,
      weight: FontWeight.w500,
      color: color,
      mono: true,
    );
  }

  static TextStyle delayUnit(BuildContext context, Color color) {
    return _of(context, size: 12, color: color);
  }

  static TextStyle untested(BuildContext context, Color color) {
    return _of(context, size: 12, color: color);
  }

  static TextStyle profileName(
    BuildContext context,
    Color color, {
    required bool current,
  }) {
    return _of(
      context,
      size: 17,
      weight: current ? FontWeight.w600 : FontWeight.w400,
      color: color,
    );
  }

  static TextStyle profileMeta(BuildContext context, Color color) {
    return _of(context, size: 12, color: color);
  }

  static TextStyle inUse(BuildContext context, Color color) {
    return _of(context, size: 11, letterSpacing: 2, color: color);
  }

  static TextStyle addRow(BuildContext context, Color color) {
    return _of(context, size: 14.5, color: color);
  }

  static TextStyle navLabel(
    BuildContext context,
    Color color, {
    required bool current,
  }) {
    return _of(
      context,
      size: 12.5,
      weight: current ? FontWeight.w500 : FontWeight.w400,
      color: color,
    );
  }

  static TextStyle pageAction(BuildContext context, Color color) {
    return _of(context, size: 12.5, color: color);
  }
}

/// Settled A measurements: the single hairline, the page inset and the
/// vertical rhythm anchors shared by every migrated surface.
abstract final class HaraSpace {
  static const hairline = 0.7;
  static const pageInset = 28.0;
  static const navHeight = 64.0;
  static const navTopPadding = 15.0;
  static const navUnderlineGap = 6.0;
  static const navUnderlineWidth = 18.0;
  static const navUnderlineHeight = 2.0;
  static const railWidth = 200.0;
  static const contentMaxWidth = 720.0;
  static const wideContentMaxWidth = 960.0;
  static const ringSize = 216.0;
  static const ringStroke = 1.3;
  static const ringEmpty = 72.0;
  static const ringCompact = 28.0;
  static const dotStatus = 7.0;
  static const dotRow = 6.0;
  static const dotNameGap = 9.0;
  static const modeUnderline = 1.2;
  static const modeUnderlineGap = 5.0;
  static const modeItemGap = 30.0;
  static const brandTopGap = 12.0;
  static const ringTopGap = 58.0;
  static const statusTopGap = 32.0;
  static const nodeTopGap = 11.0;
  static const dataRowVertical = 13.5;
  static const listToModeGap = 34.0;
  static const modeToNavGap = 30.0;
}

/// The one hairline of the A surfaces: 0.7 logical pixels, palette line
/// colour unless a caller overrides it.
class HaraHairline extends StatelessWidget {
  const HaraHairline({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HaraSpace.hairline,
      child: ColoredBox(color: color ?? context.haraPalette.line),
    );
  }
}

/// The vermilion dot. Its size is one of the two settled diameters; the
/// whitelist test pins which surfaces may instantiate it.
class HaraDot extends StatelessWidget {
  const HaraDot({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.haraPalette.vermilion,
        shape: BoxShape.circle,
      ),
    );
  }
}
