import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/views/views.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpLogItem(WidgetTester tester, Log log) async {
    await tester.pumpWidget(TestApp(child: LogItem(log: log)));
    await tester.pump();
  }

  List<TextSpan> flattenSpans(InlineSpan root) {
    final spans = <TextSpan>[];
    root.visitChildren((span) {
      if (span is TextSpan) {
        spans.add(span);
      }
      return true;
    });
    return spans;
  }

  TextSpan spanWithText(WidgetTester tester, String text) {
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    return flattenSpans(
      selectable.textSpan!,
    ).singleWhere((span) => span.text == text);
  }

  const routedLog = Log(
    payload:
        '[TCP] 192.168.1.2:1234 --> example.com:443 '
        'match DomainSuffix(example.com) using NodeA',
    dateTime: '2024-01-01 12:00:00',
  );

  testWidgets('a routed log line keeps the proxy name off the primary color', (
    tester,
  ) async {
    await pumpLogItem(tester, routedLog);
    final context = tester.element(find.byType(LogItem));
    final colorScheme = Theme.of(context).colorScheme;
    final proxy = spanWithText(tester, 'NodeA');
    expect(proxy.style!.color, colorScheme.onSurface);
    expect(proxy.style!.color, isNot(colorScheme.primary));
  });

  testWidgets('a routed log line sets its payload in the mono face', (
    tester,
  ) async {
    await pumpLogItem(tester, routedLog);
    for (final text in [
      'example.com:443',
      'DomainSuffix(example.com)',
      'NodeA',
      '\nTCP  ·  192.168.1.2:1234',
    ]) {
      expect(spanWithText(tester, text).style!.fontFamily, 'JetBrainsMono');
    }
  });

  testWidgets('a plain log line sets its message in the mono face', (
    tester,
  ) async {
    await pumpLogItem(
      tester,
      const Log(
        payload: 'core started, all listeners up',
        dateTime: '2024-01-01 12:00:00',
      ),
    );
    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.data, 'core started, all listeners up');
    expect(selectable.style!.fontFamily, 'JetBrainsMono');
  });

  testWidgets('a dial failure keeps the error accent on the error text', (
    tester,
  ) async {
    await pumpLogItem(
      tester,
      const Log(
        logLevel: LogLevel.error,
        payload:
            '[TCP] dial NodeA (match DomainSuffix(example.com)) '
            '192.168.1.2:1234 --> example.com:443 '
            'error: dial tcp: connection refused',
        dateTime: '2024-01-01 12:00:00',
      ),
    );
    final context = tester.element(find.byType(LogItem));
    final error = spanWithText(tester, '\ndial tcp: connection refused');
    expect(error.style!.color, Theme.of(context).colorScheme.error);
    expect(error.style!.fontFamily, 'JetBrainsMono');
  });
}
