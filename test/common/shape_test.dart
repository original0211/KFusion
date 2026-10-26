import 'package:kfusion/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

ShapeBorder? _shapeOf(WidgetTester tester, Finder button) => tester
    .widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    )
    .shape;

void main() {
  test('the declared main corner tiers keep their values', () {
    expect(AppCorner.xl, 22, reason: 'card');
    expect(AppCorner.lg, 20, reason: 'row card');
    expect(AppCorner.floating, 26, reason: 'dock, dialog and menu');
    expect(AppCorner.md, 16, reason: 'block');
    expect(AppCorner.sm, 8, reason: 'small mark or chip');
    expect(AppShape.xl.borderRadius, AppRadius.xl);
    expect(AppShape.floating.borderRadius, AppRadius.floating);
    expect(AppShape.md.borderRadius, AppRadius.md);
    expect(AppShape.sm.borderRadius, AppRadius.sm);
  });

  testWidgets('pill buttons take the superellipse capsule, not the stadium', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true).withAppShapes,
        home: Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('text')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              CommonMinFilledButtonTheme(
                child: FilledButton(
                  onPressed: () {},
                  child: const Text('filled'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    for (final type in [TextButton, OutlinedButton, FilledButton]) {
      expect(
        _shapeOf(tester, find.byType(type)),
        isA<RoundedSuperellipseBorder>().having(
          (shape) => shape.borderRadius,
          'borderRadius',
          AppRadius.full,
        ),
        reason: '$type',
      );
    }
  });

  testWidgets('tooltips keep Material colours on a superellipse', (
    tester,
  ) async {
    Future<Decoration?> shownWith(ThemeData theme) async {
      final tooltip = GlobalKey<TooltipState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: Tooltip(
              key: tooltip,
              message: 'tip',
              child: const Text('anchor'),
            ),
          ),
        ),
      );
      tooltip.currentState!.ensureTooltipVisible();
      await tester.pumpAndSettle();
      return tester
          .widget<Container>(
            find
                .ancestor(
                  of: find.text('tip'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration;
    }

    for (final brightness in Brightness.values) {
      final material = await shownWith(ThemeData(brightness: brightness));
      final app = await shownWith(
        ThemeData(brightness: brightness).withAppShapes,
      );
      expect(
        app,
        isA<ShapeDecoration>()
            .having((it) => it.shape, 'shape', AppShape.xs)
            .having(
              (it) => it.color,
              'color',
              (material! as BoxDecoration).color,
            ),
        reason: '$brightness',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
