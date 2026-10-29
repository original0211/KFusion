// Guards for the Hara A surfaces (spec batches as they land). The scan set
// grows with each batch; the rules do not soften: radii come only from the
// A aliases, no shadows or gradients, color literals live only in the
// token layer, the vermilion is consumed only through HaraDot in the
// whitelisted files, and the disc bite geometry has exactly one home.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/ui/disc_motif.dart';

const aSurfaces = <String>[
  'lib/ui/hara.dart',
  'lib/ui/text_navigation.dart',
  'lib/views/dashboard/hara_dashboard.dart',
  'lib/views/proxies/hara_proxies.dart',
  'lib/views/profiles/hara_profiles.dart',
  'lib/views/profiles/singbox_degradations.dart',
  'lib/views/profiles/universal_import.dart',
  'lib/views/tools.dart',
];

const tokenLayer = 'lib/ui/hara.dart';

Iterable<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

String read(String path) => File(path).readAsStringSync();

void main() {
  group('Hara A standards', () {
    test('radii come only from the A aliases', () {
      final offenders = <String>[];
      for (final path in aSurfaces) {
        final source = read(path);
        for (final match in RegExp(r'BorderRadius\.\w+').allMatches(source)) {
          if (match.group(0) != 'BorderRadius.zero') {
            offenders.add('$path: ${match.group(0)}');
          }
        }
        for (final match in RegExp(r'AppRadius\.\w+').allMatches(source)) {
          if (match.group(0) != 'AppRadius.hara') {
            offenders.add('$path: ${match.group(0)}');
          }
        }
        for (final match in RegExp(r'AppCorner\.\w+').allMatches(source)) {
          if (match.group(0) != 'AppCorner.hara') {
            offenders.add('$path: ${match.group(0)}');
          }
        }
        for (final match in RegExp(r'AppShape\.\w+').allMatches(source)) {
          if (match.group(0) != 'AppShape.hara' &&
              match.group(0) != 'AppShape.circle') {
            offenders.add('$path: ${match.group(0)}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('no shadows and no gradients', () {
      final offenders = <String>[];
      for (final path in aSurfaces) {
        final source = read(path);
        for (final token in const [
          'BoxShadow',
          'LinearGradient',
          'RadialGradient',
          'SweepGradient',
        ]) {
          if (source.contains(token)) offenders.add('$path: $token');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('color literals live only in the token layer', () {
      final literal = RegExp(
        r'Color\(0x|Color\.fromARGB|Color\.fromRGBO|Colors\.\w+',
      );
      final offenders = <String>[];
      for (final path in aSurfaces) {
        if (path == tokenLayer) continue;
        for (final match in literal.allMatches(read(path))) {
          offenders.add('$path: ${match.group(0)}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the vermilion is read only in the token layer', () {
      final offenders = <String>[];
      for (final file in libFiles()) {
        if (file.path.endsWith(tokenLayer)) continue;
        if (file.readAsStringSync().contains('.vermilion')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('HaraDot is built only on whitelisted surfaces', () {
      const whitelist = <String>{
        tokenLayer,
        'lib/views/dashboard/hara_dashboard.dart',
        'lib/views/proxies/hara_proxies.dart',
        'lib/views/profiles/hara_profiles.dart',
      };
      final offenders = <String>[];
      for (final file in libFiles()) {
        if (whitelist.contains(file.path)) continue;
        if (file.readAsStringSync().contains('HaraDot(')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the disc bite geometry has exactly one home', () {
      final definitions = libFiles()
          .where(
            (file) => file.readAsStringSync().contains('class DiscGeometry'),
          )
          .map((file) => file.path)
          .toList();
      expect(definitions, ['lib/ui/disc_motif.dart']);
      final source = read('lib/ui/disc_motif.dart');
      for (final constant in const [
        'biteDirection =',
        'biteDistance =',
        'biteRadius =',
      ]) {
        expect(
          constant.allMatches(source).length,
          1,
          reason: '$constant must be declared exactly once',
        );
      }
    });

    test('the disc bite keeps its settled values', () {
      expect(DiscGeometry.biteDirection, closeTo(157 * math.pi / 180, 1e-12));
      expect(DiscGeometry.biteDistance, 1.28);
      expect(DiscGeometry.biteRadius, 0.67);
    });
  });
}
