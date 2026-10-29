import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/models/models.dart' hide FileInfo;
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

ColorScheme _schemeOf(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).colorScheme;
}

void main() {
  testWidgets('a pass rule target reads neutral, a direct one success', (
    tester,
  ) async {
    ColorScheme? scheme;
    Future<Color?> targetColor(String target) async {
      await tester.pumpWidget(
        TestApp(
          child: Material(
            child: RuleItem(
              isSelected: false,
              rule: Rule(content: 'example.com', ruleTarget: target),
              onSelected: () {},
              onEdit: (_) {},
            ),
          ),
        ),
      );
      scheme = _schemeOf(tester, find.byType(RuleItem));
      final text = tester.widget<Text>(find.text(target));
      return text.style?.color;
    }

    expect(await targetColor('PASS'), scheme!.onSurfaceVariant);
    expect(await targetColor('GLOBAL'), scheme!.onSurfaceVariant);
    expect(await targetColor('DIRECT'), scheme!.success);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preset raw rules read as neutral subtitles', (tester) async {
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RulePresetSheet(onAdd: (_) {}),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final raw = RulePreset.blockQuic.rawRules.single;
    final text = tester.widget<Text>(find.text(raw));
    final scheme = _schemeOf(tester, find.text(raw));
    expect(text.style?.color, scheme.onSurfaceVariant);
    expect(text.style?.color, isNot(scheme.tertiary));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
