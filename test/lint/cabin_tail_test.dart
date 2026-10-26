import 'dart:io';

import 'package:test/test.dart';

Iterable<File> _dartFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File &&
        entity.path.endsWith('.dart') &&
        !entity.path.contains('/generated/')) {
      yield entity;
    }
  }
}

List<String> _hits(RegExp pattern) {
  final hits = <String>[];
  for (final file in _dartFiles()) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        hits.add('${file.path}:${i + 1}');
      }
    }
  }
  return hits;
}

void main() {
  test('dialogs open through the shared base in lib/ui/dialog.dart', () {
    final offenders = _hits(
      RegExp(r'\b(showDialog|showGeneralDialog|AlertDialog)\s*\('),
    ).where((hit) => !hit.startsWith('lib/ui/dialog.dart')).toList();
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('sheets never open through the bare Material route', () {
    final offenders = _hits(RegExp(r'\bshowModalBottomSheet\s*\('));
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('menus never open through the Material popup widgets', () {
    final offenders = _hits(
      RegExp(r'\b(PopupMenuButton|showMenu|DropdownMenu)\s*[<(]'),
    );
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the brand empty state stays on its two home screens', () {
    final files = _hits(RegExp(r'NullStatus\.brand\s*\('))
        .where((hit) => !hit.startsWith('lib/ui/null_status.dart'))
        .map((hit) => hit.split(':').first)
        .toSet();
    expect(files, {
      'lib/views/profiles/profiles.dart',
      'lib/views/dns_queries.dart',
    });
  });
}
