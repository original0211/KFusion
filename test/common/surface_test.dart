import 'package:kfusion/ui/color.dart';
import 'package:kfusion/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Hct;
import 'package:material_ui/material_ui.dart';

const _surface = Color(0xFF101010);
const _container = Color(0xFF202020);
const _bright = Color(0xFF303030);
const _low = Color(0xFF404040);
const _high = Color(0xFF505050);
const _highest = Color(0xFF606060);

ColorScheme _sentinel(Brightness brightness) =>
    ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: brightness,
    ).copyWith(
      surface: _surface,
      surfaceContainer: _container,
      surfaceBright: _bright,
      surfaceContainerLow: _low,
      surfaceContainerHigh: _high,
      surfaceContainerHighest: _highest,
    );

void main() {
  group('SurfaceLevel', () {
    test('steps one deeper at a time and floors at inset', () {
      expect(SurfaceLevel.page.next, SurfaceLevel.card);
      expect(SurfaceLevel.card.next, SurfaceLevel.block);
      expect(SurfaceLevel.block.next, SurfaceLevel.inset);
      expect(SurfaceLevel.inset.next, SurfaceLevel.inset);
    });

    test('floats as a card in light and a block in dark', () {
      expect(
        SurfaceLevel.floatingOf(_sentinel(Brightness.light)),
        SurfaceLevel.card,
      );
      expect(
        SurfaceLevel.floatingOf(_sentinel(Brightness.dark)),
        SurfaceLevel.block,
      );
    });

    test('reads its colour from the ladder role of its brightness', () {
      final light = _sentinel(Brightness.light);
      expect(SurfaceLevel.page.colorOf(light), _container);
      expect(SurfaceLevel.card.colorOf(light), _bright);
      expect(SurfaceLevel.block.colorOf(light), _low);
      expect(SurfaceLevel.inset.colorOf(light), _highest);

      final dark = _sentinel(Brightness.dark);
      expect(SurfaceLevel.page.colorOf(dark), _surface);
      expect(SurfaceLevel.card.colorOf(dark), _container);
      expect(SurfaceLevel.block.colorOf(dark), _high);
      expect(SurfaceLevel.inset.colorOf(dark), _highest);
    });
  });

  group('chrome and cabin surfaces', () {
    test('chrome takes the low container in dark, the highest in light', () {
      expect(_sentinel(Brightness.dark).chromeSurface, _low);
      expect(_sentinel(Brightness.light).chromeSurface, _highest);
    });

    test('the rim is a faint white in dark and a faint ink in light', () {
      final dark = _sentinel(Brightness.dark);
      expect(dark.cabinRim, Colors.white.withValues(alpha: 0.07));
      expect(dark.cabinRimSide.color, dark.cabinRim);
      expect(dark.cabinRimSide.width, 1.0);

      final light = _sentinel(Brightness.light);
      expect(light.cabinRim, const Color(0xFF181818).withValues(alpha: 0.06));
    });

    test('the panel shadow deepens and shortens in dark', () {
      final dark = _sentinel(Brightness.dark).cabinPanelShadows.single;
      expect(dark.color, Colors.black.withValues(alpha: 0.4));
      expect(dark.blurRadius, 18);
      expect(dark.offset, const Offset(0, 8));

      final light = _sentinel(Brightness.light).cabinPanelShadows.single;
      expect(light.color, const Color(0xFF3C341E).withValues(alpha: 0.08));
      expect(light.blurRadius, 20);
      expect(light.offset, const Offset(0, 8));
    });

    test('the dock shadow is the panel shadow grown', () {
      final dark = _sentinel(Brightness.dark).cabinDockShadows.single;
      expect(dark.color, Colors.black.withValues(alpha: 0.45));
      expect(dark.blurRadius, 30);
      expect(dark.offset, const Offset(0, 16));

      final light = _sentinel(Brightness.light).cabinDockShadows.single;
      expect(light.color, const Color(0xFF3C341E).withValues(alpha: 0.13));
      expect(light.blurRadius, 30);
      expect(light.offset, const Offset(0, 16));
    });

    test('the halo drops out only on a pure black dark surface', () {
      expect(_sentinel(Brightness.light).cabinHalo, const Color(0xFFE7E2D4));
      expect(_sentinel(Brightness.dark).cabinHalo, const Color(0xFF131516));
      final black = _sentinel(Brightness.dark).copyWith(surface: Colors.black);
      expect(black.cabinHalo, Colors.transparent);
      expect(black.cabinRing, const Color(0xFF2A2D2E));
      expect(_sentinel(Brightness.light).cabinRing, const Color(0xFFE1DCCE));
    });

    test('the disc shadow drops further in dark', () {
      final dark = _sentinel(Brightness.dark).cabinDiscShadows.single;
      expect(dark.color, Colors.black.withValues(alpha: 0.5));
      expect(dark.blurRadius, 50);
      expect(dark.offset, const Offset(0, 24));

      final light = _sentinel(Brightness.light).cabinDiscShadows.single;
      expect(light.color, const Color(0xFF3C341E).withValues(alpha: 0.14));
      expect(light.blurRadius, 50);
      expect(light.offset, const Offset(0, 14));
    });
  });

  group('the elevated scheme', () {
    test('copies with a replaced scheme and lerps toward the other', () {
      final first = ElevatedColorScheme(_sentinel(Brightness.dark));
      final other = ElevatedColorScheme(_sentinel(Brightness.light));
      expect(first.copyWith().colorScheme, first.colorScheme);
      expect(
        first.copyWith(colorScheme: other.colorScheme).colorScheme,
        other.colorScheme,
      );
      expect(first.lerp(null, 0.5), same(first));
      expect(
        first.lerp(other, 0).colorScheme.surface,
        first.colorScheme.surface,
      );
      expect(
        first.lerp(other, 1).colorScheme.surface,
        other.colorScheme.surface,
      );
    });

    test('a light scheme is already elevated', () {
      final light = _sentinel(Brightness.light);
      expect(light.elevated, same(light));
    });

    test('a dark scheme lifts every surface role by the page-to-card step', () {
      Color atTone(double tone) => Color(Hct.from(260, 4, tone).toInt());
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.grey,
        brightness: Brightness.dark,
      ).copyWith(surface: atTone(6), surfaceContainer: atTone(12));
      final elevated = dark.elevated;
      expect(elevated.surface.tone, closeTo(12, 1.5));
      expect(
        elevated.surfaceContainerHighest.tone,
        closeTo(dark.surfaceContainerHighest.tone + 6, 1.5),
      );
      expect(elevated.primary, dark.primary);
      expect(elevated.onSurface, dark.onSurface);
    });
  });

  group('the focus ring', () {
    final scheme = _sentinel(Brightness.light);

    test('is the primary colour at the settled width, inside by default', () {
      final side = focusRingSide(scheme);
      expect(side.color, scheme.primary);
      expect(side.width, 2.0);
      expect(side.strokeAlign, BorderSide.strokeAlignInside);
    });

    test('stands off by the gap on both sides of the ring', () {
      expect(focusRingSide(scheme, standsOff: true).strokeAlign, 2.0);
    });

    test('the style answers only in the focused state', () {
      final style = focusRingStyle(scheme);
      expect(style.side?.resolve(<WidgetState>{}), isNull);
      expect(
        style.side?.resolve(<WidgetState>{WidgetState.focused}),
        focusRingSide(scheme),
      );
    });
  });
}
