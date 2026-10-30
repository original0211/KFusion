import 'package:kfusion/ui/hara.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the factory resolves each brightness, pure black dark-only', () {
    expect(HaraPalette.of(Brightness.light), HaraPalette.light);
    expect(
      HaraPalette.of(Brightness.light, pureBlack: true),
      HaraPalette.light,
    );
    expect(HaraPalette.of(Brightness.dark), HaraPalette.dark);

    final black = HaraPalette.of(Brightness.dark, pureBlack: true);
    expect(black.bg, const Color(0xFF000000));
    expect(black.line, const Color(0xFF1C1C1C));
    expect(black.ink, HaraPalette.dark.ink);
    expect(black.sub, HaraPalette.dark.sub);
    expect(black.dim, HaraPalette.dark.dim);
    expect(black.vermilion, HaraPalette.dark.vermilion);
    expect(black, isNot(HaraPalette.dark));
  });

  test('copyWith replaces only the named fields', () {
    final changed = HaraPalette.light.copyWith(
      bg: const Color(0xFF000001),
      line: const Color(0xFF000002),
    );
    expect(changed.bg, const Color(0xFF000001));
    expect(changed.line, const Color(0xFF000002));
    expect(changed.ink, HaraPalette.light.ink);
    expect(changed.sub, HaraPalette.light.sub);
    expect(changed.dim, HaraPalette.light.dim);
    expect(changed.vermilion, HaraPalette.light.vermilion);
    expect(HaraPalette.light.copyWith(), HaraPalette.light);
  });

  test('equality and hashCode read every field', () {
    const base = HaraPalette.light;
    final rebuilt = HaraPalette(
      bg: base.bg,
      ink: base.ink,
      sub: base.sub,
      dim: base.dim,
      line: base.line,
      vermilion: base.vermilion,
    );
    expect(rebuilt, base);
    expect(rebuilt.hashCode, base.hashCode);

    const off = Color(0xFF010203);
    HaraPalette variant({
      Color? bg,
      Color? ink,
      Color? sub,
      Color? dim,
      Color? line,
      Color? vermilion,
    }) => HaraPalette(
      bg: bg ?? base.bg,
      ink: ink ?? base.ink,
      sub: sub ?? base.sub,
      dim: dim ?? base.dim,
      line: line ?? base.line,
      vermilion: vermilion ?? base.vermilion,
    );
    for (final changed in [
      variant(bg: off),
      variant(ink: off),
      variant(sub: off),
      variant(dim: off),
      variant(line: off),
      variant(vermilion: off),
    ]) {
      expect(changed, isNot(base));
    }
  });

  test('the theme extension copies and lerps by the halfway rule', () {
    const light = HaraTheme(HaraPalette.light);
    const dark = HaraTheme(HaraPalette.dark);
    expect(light.copyWith().palette, HaraPalette.light);
    expect(light.copyWith(palette: HaraPalette.dark).palette, HaraPalette.dark);
    expect(light.lerp(null, 0.7), same(light));
    expect(light.lerp(dark, 0.4).palette, HaraPalette.light);
    expect(light.lerp(dark, 0.6).palette, HaraPalette.dark);
  });

  testWidgets('context falls back to the brightness palette when none is '
      'carried', (tester) async {
    HaraPalette? seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: const ColorScheme.dark()),
        home: Builder(
          builder: (context) {
            seen = context.haraPalette;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, HaraPalette.dark);
  });

  testWidgets('context reads the carried palette before the brightness '
      'fallback', (tester) async {
    HaraPalette? seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(),
          extensions: const [HaraTheme(HaraPalette.light)],
        ),
        home: Builder(
          builder: (context) {
            seen = context.haraPalette;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, HaraPalette.light);
  });
}
