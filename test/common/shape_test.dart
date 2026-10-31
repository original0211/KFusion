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

  testWidgets('buttons take the square corner, not the capsule', (
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
              ElevatedButton(onPressed: () {}, child: const Text('elevated')),
              IconButton(onPressed: () {}, icon: const Text('icon')),
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

    for (final type in [
      TextButton,
      OutlinedButton,
      ElevatedButton,
      FilledButton,
      IconButton,
    ]) {
      expect(
        _shapeOf(tester, find.byType(type)),
        isA<RoundedSuperellipseBorder>().having(
          (shape) => shape.borderRadius,
          'borderRadius',
          AppRadius.hara,
        ),
        reason: '$type',
      );
    }
  });

  testWidgets('bar buttons and their shared fills take the square corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true).withAppShapes.withAppSurfaces,
        home: Scaffold(
          body: Column(
            children: [
              TonalButtonTheme(
                child: Row(
                  children: [
                    IconButton(onPressed: () {}, icon: const Text('icon')),
                    FilledButton(onPressed: () {}, child: const Text('action')),
                  ],
                ),
              ),
              TonalButtonGroup(
                children: [
                  IconButton(onPressed: () {}, icon: const Text('one')),
                  IconButton(onPressed: () {}, icon: const Text('two')),
                ],
              ),
              TonalButton(label: 'labelled', onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    for (final type in [IconButton, FilledButton]) {
      expect(
        _shapeOf(tester, find.byType(type).first),
        isA<RoundedSuperellipseBorder>().having(
          (shape) => shape.borderRadius,
          'borderRadius',
          AppRadius.hara,
        ),
        reason: '$type',
      );
    }
    for (final host in [TonalButtonGroup, TonalButton]) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(host),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as ShapeDecoration;
      expect(
        decoration.shape,
        isA<RoundedSuperellipseBorder>().having(
          (shape) => shape.borderRadius,
          'borderRadius',
          AppRadius.hara,
        ),
        reason: '$host',
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
