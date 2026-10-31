// Widget-level standards for the empty-state schematic, kept outside
// aSurfaces under the D14/D15 shared-component precedent.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/ui/null_status.dart').readAsStringSync();

  group('null status schematic standards', () {
    test('leaves the shape-fill illustration behind', () {
      expect(source, isNot(contains('MaterialShapes')));
      expect(source, isNot(contains('_IllustrationPalette')));
      expect(source, isNot(contains('_Entrance')));
      expect(source, isNot(contains('primaryContainer')));
      expect(source, isNot(contains('tertiary')));
    });

    test('runs no random entrance choreography', () {
      expect(source, isNot(contains('Random')));
      expect(source, isNot(contains('milliseconds: 900')));
    });

    test('never spends the vermilion on an empty state', () {
      expect(source, isNot(contains('vermilion')));
    });

    test('reads the schematic in the Hara ink steps', () {
      expect(source, contains('palette.ink'));
      expect(source, contains('palette.sub'));
      expect(source, contains('palette.dim'));
      expect(source, contains('colorScheme.error'));
    });

    test('keeps one line glyph per member', () {
      const members = <String, String>{
        'data': 'AppGlyphs.resources',
        'logs': 'AppGlyphs.logs',
        'dns': 'AppGlyphs.dns',
        'tun': 'AppGlyphs.vpn',
        'wifi': 'AppGlyphs.wifi',
        'apps': 'AppGlyphs.appsList',
        'permission': 'AppGlyphs.lock',
        'camera': 'AppGlyphs.camera',
        'error': 'AppGlyphs.error',
        'search': 'AppGlyphs.search',
      };
      for (final entry in members.entries) {
        expect(
          source,
          contains('NullStatusIllustration.${entry.key} => ${entry.value}'),
          reason: entry.key,
        );
      }
    });
  });
}
