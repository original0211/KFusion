import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/surface.dart';
import 'package:kfusion/ui/typography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a surface reads as a page until a scope says otherwise', (
    tester,
  ) async {
    late SurfaceLevel seen;
    late SurfaceLevel raised;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            seen = context.surfaceLevel;
            raised = context.raisedSurfaceLevel;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen, SurfaceLevel.page);
    expect(raised, SurfaceLevel.card);
  });

  testWidgets('the nearest scope wins and the raised level steps from it', (
    tester,
  ) async {
    late SurfaceLevel seen;
    late SurfaceLevel raised;
    await tester.pumpWidget(
      MaterialApp(
        home: SurfaceScope(
          level: SurfaceLevel.card,
          child: SurfaceScope(
            level: SurfaceLevel.inset,
            child: Builder(
              builder: (context) {
                seen = context.surfaceLevel;
                raised = context.raisedSurfaceLevel;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(seen, SurfaceLevel.inset);
    expect(raised, SurfaceLevel.inset);
  });

  testWidgets('a dependent rebuilds when the level changes, not when it '
      'is restated', (tester) async {
    var builds = 0;
    late StateSetter setLevel;
    SurfaceLevel level = SurfaceLevel.card;
    final dependent = Builder(
      builder: (context) {
        SurfaceScope.of(context);
        builds++;
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setLevel = setState;
            return SurfaceScope(level: level, child: dependent);
          },
        ),
      ),
    );
    expect(builds, 1);
    setLevel(() => level = SurfaceLevel.block);
    await tester.pump();
    expect(builds, 2);
    setLevel(() {});
    await tester.pump();
    expect(builds, 2);
  });

  group('ElevatedSurfaceTheme', () {
    testWidgets('is absent until it wraps the tree', (tester) async {
      late bool inside;
      late bool outside;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              outside = ElevatedSurfaceTheme.isIn(context);
              return ElevatedSurfaceTheme(
                child: Builder(
                  builder: (context) {
                    inside = ElevatedSurfaceTheme.isIn(context);
                    return const SizedBox.shrink();
                  },
                ),
              );
            },
          ),
        ),
      );
      expect(outside, isFalse);
      expect(inside, isTrue);
    });

    testWidgets('presents the carried scheme inside the surface', (
      tester,
    ) async {
      final carried = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      late ColorScheme seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            extensions: [ElevatedColorScheme(carried)],
          ),
          home: ElevatedSurfaceTheme(
            child: Builder(
              builder: (context) {
                seen = Theme.of(context).colorScheme;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(seen, carried);
    });
  });

  group('ThemeData.elevated', () {
    test('returns the theme itself when no scheme is carried', () {
      final theme = ThemeData();
      expect(theme.elevated, same(theme));
    });

    test('swaps in the carried scheme and repaints the canvas from it', () {
      final carried = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      final theme = ThemeData(
        extensions: [ElevatedColorScheme(carried)],
      ).elevated;
      expect(theme.colorScheme, carried);
      expect(theme.canvasColor, carried.surface);
      expect(theme.scaffoldBackgroundColor, HaraPalette.dark.bg);
    });
  });

  group('withAppSurfaces', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.grey);
    final theme = ThemeData(colorScheme: scheme).withAppSurfaces;

    test('the scaffold stands on the field while cards and floats take '
        'their ladder colours', () {
      expect(theme.scaffoldBackgroundColor, HaraPalette.light.bg);
      expect(theme.cardTheme.color, SurfaceLevel.card.colorOf(scheme));
      expect(theme.cardTheme.elevation, 0);
      final floating = SurfaceLevel.floatingOf(scheme).colorOf(scheme);
      expect(theme.dialogTheme.backgroundColor, floating);
      expect(theme.popupMenuTheme.color, floating);
      expect(
        theme.menuTheme.style?.backgroundColor?.resolve(<WidgetState>{}),
        floating,
      );
    });

    test('sheets sit on the field, front and modal alike', () {
      final field = HaraPalette.light.bg;
      expect(theme.bottomSheetTheme.backgroundColor, field);
      expect(theme.bottomSheetTheme.modalBackgroundColor, field);
    });

    test('the divider is the on-surface colour at its settled alpha', () {
      expect(
        theme.dividerTheme.color,
        scheme.onSurface.withValues(alpha: 0.14),
      );
    });

    test('the navigation bar rides the chrome surface with a clear '
        'indicator', () {
      final nav = theme.navigationBarTheme;
      expect(nav.backgroundColor, scheme.chromeSurface);
      expect(nav.elevation, 0);
      expect(nav.indicatorColor, Colors.transparent);
      final icons = nav.iconTheme?.resolve(<WidgetState>{});
      expect(icons?.color, scheme.onSurfaceVariant.withValues(alpha: 0.72));
      final selected = nav.iconTheme?.resolve(<WidgetState>{
        WidgetState.selected,
      });
      expect(selected?.color, scheme.onSurface);
      final label = nav.labelTextStyle?.resolve(<WidgetState>{});
      expect(label?.fontSize, AppTextStyle.caption1.size);
      expect(label?.fontWeight, FontWeight.w500);
      final labelSelected = nav.labelTextStyle?.resolve(<WidgetState>{
        WidgetState.selected,
      });
      expect(labelSelected?.fontWeight, FontWeight.w600);
    });
  });

  group('the field colour', () {
    ThemeData themed(HaraPalette palette, Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.grey,
        brightness: brightness,
      ),
      extensions: [HaraTheme(palette)],
    ).withAppSurfaces;

    test('is white under the light palette, scaffold and sheets alike', () {
      final theme = themed(HaraPalette.light, Brightness.light);
      expect(theme.fieldColor, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFFFFFFFF));
      expect(
        theme.bottomSheetTheme.modalBackgroundColor,
        const Color(0xFFFFFFFF),
      );
    });

    test('is the dark ground under the dark palette', () {
      final theme = themed(HaraPalette.dark, Brightness.dark);
      expect(theme.fieldColor, const Color(0xFF101010));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF101010));
      expect(theme.bottomSheetTheme.backgroundColor, const Color(0xFF101010));
    });

    test('is black under the pure black palette', () {
      final theme = themed(
        HaraPalette.of(Brightness.dark, pureBlack: true),
        Brightness.dark,
      );
      expect(theme.fieldColor, const Color(0xFF000000));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    test('falls back to the brightness palette without an extension', () {
      final dark = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.dark,
        ),
      ).withAppSurfaces;
      expect(dark.fieldColor, const Color(0xFF101010));
      final light = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey),
      ).withAppSurfaces;
      expect(light.fieldColor, const Color(0xFFFFFFFF));
    });
  });
}
