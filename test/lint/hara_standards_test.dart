// Guards for the Hara A surfaces (spec batches as they land). The scan set
// grows with each batch; the rules do not soften: radii come only from the
// A aliases, no shadows or gradients, color literals live only in the
// token layer, the vermilion is consumed only through HaraDot in the
// whitelisted files and through the mark's point in disc_motif, and the
// disc mark geometry has exactly one home.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/ui/disc_motif.dart';

const aSurfaces = <String>[
  'lib/ui/hara.dart',
  'lib/ui/text_navigation.dart',
  'lib/views/dashboard/hara_dashboard.dart',
  'lib/views/proxies/hara_proxies.dart',
  'lib/views/proxies/setting.dart',
  'lib/views/profiles/hara_profiles.dart',
  'lib/views/profiles/singbox_degradations.dart',
  'lib/views/profiles/universal_import.dart',
  'lib/views/profiles/add.dart',
  'lib/views/tools.dart',
  'lib/views/config/general.dart',
  'lib/views/config/on_demand.dart',
  'lib/views/config/network.dart',
  'lib/views/config/dns.dart',
  'lib/views/config/override.dart',
  'lib/views/resources.dart',
  'lib/views/logs.dart',
  'lib/views/developer.dart',
  'lib/views/about.dart',
  'lib/views/access.dart',
  'lib/views/backup_and_restore.dart',
  'lib/views/disclaimer.dart',
  'lib/views/theme.dart',
  'lib/views/theme_preview.dart',
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
        r'Color\(0x|Color\.fromARGB|Color\.fromRGBO|\bColors\.\w+',
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

    test('the vermilion is read only in the token layer and the mark', () {
      final offenders = <String>[];
      for (final file in libFiles()) {
        if (file.path.endsWith(tokenLayer)) continue;
        if (file.path.endsWith('lib/ui/disc_motif.dart')) continue;
        if (file.readAsStringSync().contains('.vermilion')) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('HaraDot is built only on whitelisted surfaces', () {
      const whitelist = <String>{
        tokenLayer,
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

    test('the disc mark geometry has exactly one home', () {
      final definitions = libFiles()
          .where(
            (file) => file.readAsStringSync().contains('class DiscGeometry'),
          )
          .map((file) => file.path)
          .toList();
      expect(definitions, ['lib/ui/disc_motif.dart']);
      final source = read('lib/ui/disc_motif.dart');
      for (final constant in const ['dotDirection =', 'dotDiameterRatio =']) {
        expect(
          constant.allMatches(source).length,
          1,
          reason: '$constant must be declared exactly once',
        );
      }
    });

    // The dialog layer is a shared component: held by this pin, not aSurfaces.
    test('the dialog layer stays off the glass and the pill', () {
      final source = read('lib/ui/dialog.dart');
      for (final token in const [
        '_AlertGlass',
        'LiquidGlassStyle',
        'LiquidGlassRim',
        'glassFillOf',
        'glassMenuShadows',
        'AppCorner.alert',
        'AppShape.full',
        'BoxShadow',
      ]) {
        expect(source.contains(token), isFalse, reason: 'dialog.dart: $token');
      }
      expect(source, contains('AppShape.hara'));
      expect(source, contains('HaraHairline'));
    });

    // The sheet layer is a shared component family: held by this pin, not aSurfaces.
    test('the sheet layer keeps square corners and a square handle', () {
      final snap = read('lib/ui/snap_sheet.dart');
      expect(
        snap.contains('AppCorner.floating'),
        isFalse,
        reason: 'snap_sheet.dart: AppCorner.floating',
      );
      expect(snap, contains('AppRadius.top(AppCorner.hara)'));
      final paged = read('lib/ui/paged_sheet.dart');
      expect(
        paged.contains('AppCorner.floating'),
        isFalse,
        reason: 'paged_sheet.dart: AppCorner.floating',
      );
      expect(paged, contains('AppShape.top(AppCorner.hara)'));
      final form = read('lib/ui/form_sheet.dart');
      for (final token in const ['AppShape.xxl', 'dialogTheme.shape']) {
        expect(
          form.contains(token),
          isFalse,
          reason: 'form_sheet.dart: $token',
        );
      }
      expect(form, contains('AppShape.hara'));
      expect(form, contains('HaraSpace.hairline'));
      final scaffold = read('lib/ui/scaffold.dart');
      expect(
        scaffold.contains('AppCorner.xxl'),
        isFalse,
        reason: 'scaffold.dart: AppCorner.xxl',
      );
      expect(scaffold, contains('AppRadius.top(AppCorner.hara)'));
      final header = read('lib/ui/sheet_header.dart');
      expect(
        header.contains('AppShape.all'),
        isFalse,
        reason: 'sheet_header.dart: AppShape.all',
      );
      expect(header, contains('AppShape.hara'));
    });

    test('the disc mark keeps its settled values', () {
      expect(DiscGeometry.dotDirection, closeTo(157 * math.pi / 180, 1e-12));
      expect(DiscGeometry.dotDiameterRatio, 0.16);
      expect(DiscGeometry.dotRadius(216), closeTo(17.28, 1e-9));
      final center = DiscGeometry.dotCenter(const Offset(108, 108), 106.7);
      expect((center - const Offset(108, 108)).distance, closeTo(106.7, 1e-9));
    });
  });
}
