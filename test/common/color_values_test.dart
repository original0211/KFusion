import 'package:kfusion/ui/color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Hct;
import 'package:material_ui/material_ui.dart';

void main() {
  group('Color values', () {
    test('hex prints the rgb channels upper case, without the alpha', () {
      expect(const Color(0xFF7F0019).hex, '#7F0019');
      expect(const Color(0xFFabcdef).hex, '#ABCDEF');
      expect(const Color(0xFF000000).hex, '#000000');
      expect(const Color(0x00FFFFFF).hex, '#FFFFFF');
    });

    test('tone reads the hct tone of the colour', () {
      expect(Colors.white.tone, closeTo(100, 0.6));
      expect(Colors.black.tone, closeTo(0, 0.6));
    });

    test('shiftTone moves the tone and clamps at both ends', () {
      const base = Color(0xFF777777);
      expect(base.shiftTone(10).tone, closeTo(base.tone + 10, 1.5));
      expect(base.shiftTone(-10).tone, closeTo(base.tone - 10, 1.5));
      expect(const Color(0xFFEEEEEE).shiftTone(30).tone, closeTo(100, 0.6));
      expect(const Color(0xFF111111).shiftTone(-30).tone, closeTo(0, 0.6));
    });

    test('shiftTone keeps the hue it started from', () {
      const seed = Color(0xFF3366CC);
      final shifted = seed.shiftTone(12);
      expect(
        (Hct.fromInt(shifted.toARGB32()).hue - Hct.fromInt(seed.toARGB32()).hue)
            .abs(),
        lessThan(1),
        reason: 'a tone shift is not a hue shift',
      );
    });
  });

  group('scheme scrims and the destructive colour', () {
    test('the modal scrim is the scrim at a third of its strength', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
      expect(scheme.modalScrim, scheme.scrim.withValues(alpha: 0.32));
    });

    test('the alert scrim dims further in dark', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.blue);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      expect(light.alertScrim, light.scrim.withValues(alpha: 0.2));
      expect(dark.alertScrim, dark.scrim.withValues(alpha: 0.48));
    });

    test('destructive is the system red of the brightness', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.blue);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      expect(light.destructive, const Color(0xFFFF383C));
      expect(dark.destructive, const Color(0xFFFF4245));
    });
  });

  group('delay colours at the boundaries', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);

    test('an untested delay has no colour', () {
      expect(scheme.delayColor(null), isNull);
    });

    test('the warning starts exactly at the settled threshold', () {
      expect(scheme.delayColor(0), scheme.success);
      expect(scheme.delayColor(599), scheme.success);
      expect(scheme.delayColor(600), scheme.warning);
      expect(scheme.delayColor(-1), scheme.error);
    });
  });

  group('toPureBlack', () {
    test('leaves a scheme alone unless it is dark and asked', () {
      final dark = seededColorScheme(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      expect(dark.toPureBlack(false), same(dark));
      final light = seededColorScheme(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      );
      expect(light.toPureBlack(true), same(light));
    });

    test('flattens the floor roles to black and lowers the rest by the '
        'surface tone', () {
      final dark = seededColorScheme(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      final black = dark.toPureBlack(true);
      expect(black.surface, Colors.black);
      expect(black.surfaceDim, Colors.black);
      expect(black.surfaceContainerLowest, Colors.black);
      final shift = dark.surface.tone;
      expect(
        black.surfaceContainer.tone,
        closeTo(dark.surfaceContainer.tone - shift, 2),
      );
      expect(
        black.surfaceBright.tone,
        closeTo(dark.surfaceBright.tone - shift, 2),
      );
      expect(black.primary, dark.primary);
      expect(black.onSurface, dark.onSurface);
    });
  });

  group('the softer styles', () {
    test('soft and monochrome take their primary from the material role, '
        'not the seed accent', () {
      for (final style in [ColorStyle.soft, ColorStyle.monochrome]) {
        final scheme = seededColorScheme(
          seedColor: const Color(0xFFCC2233),
          brightness: Brightness.light,
          style: style,
        );
        expect(
          scheme.primary,
          isNot(const Color(0xFFCC2233)),
          reason: '$style',
        );
      }
    });

    test('the primary container keeps the primary hue at the capped '
        'chroma', () {
      final scheme = seededColorScheme(
        seedColor: const Color(0xFF0057FF),
        brightness: Brightness.light,
      );
      expect(scheme.primaryContainer.tone, closeTo(90, 1.5));
      expect(scheme.onPrimaryContainer.tone, closeTo(30, 1.5));
      final dark = seededColorScheme(
        seedColor: const Color(0xFF0057FF),
        brightness: Brightness.dark,
      );
      expect(dark.primaryContainer.tone, closeTo(30, 1.5));
      expect(dark.onPrimaryContainer.tone, closeTo(90, 1.5));
    });
  });
}
