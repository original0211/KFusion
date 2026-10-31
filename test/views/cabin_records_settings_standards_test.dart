import 'dart:io';

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/logs.dart';
import 'package:kfusion/views/resources.dart';
import 'package:kfusion/views/theme.dart';
import 'package:kfusion/views/theme_preview.dart';
import 'package:kfusion/views/tools.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../helpers/test_database_providers.dart';
import '../helpers/test_profiles.dart';

ProviderContainer _container(
  WidgetTester tester, {
  Size size = const Size(1400, 2400),
  List<Override> overrides = const [],
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(TestProfiles.new), ...overrides],
  );
  addTearDown(container.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

ShapeDecoration _shapeDecorationOf(WidgetTester tester, Finder finder) {
  final box = tester.widget<DecoratedBox>(finder);
  return box.decoration as ShapeDecoration;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final home = Directory.systemTemp.createTempSync('cabin4-standards-');
    await useAppPaths(home);
  });

  group('record row cards (cabin batch 4, shared)', () {
    Future<void> pumpItem(WidgetTester tester, Brightness brightness) async {
      final theme = ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        TestApp(
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.light,
          child: const Scaffold(
            body: RecordListItem(header: Text('header'), body: Text('body')),
          ),
        ),
      );
      await tester.pump();
    }

    for (final brightness in Brightness.values) {
      testWidgets('row card is a hairline plate on the page field in '
          '$brightness', (tester) async {
        await pumpItem(tester, brightness);
        final context = tester.element(find.byType(RecordListItem));
        final palette = context.haraPalette;
        final decoration = _shapeDecorationOf(
          tester,
          find.descendant(
            of: find.byType(RecordListItem),
            matching: find.byType(DecoratedBox),
          ),
        );
        final shape = decoration.shape as RoundedSuperellipseBorder;
        expect(shape.borderRadius, AppRadius.hara);
        expect(shape.side.color, palette.line);
        expect(shape.side.width, HaraSpace.hairline);
        expect(decoration.color, palette.bg);
      });
    }

    testWidgets('the wide table header and striped rows sit on the card step', (
      tester,
    ) async {
      final container = _container(tester, size: const Size(1200, 800));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: TestApp(
            child: Scaffold(
              body: RecordTableFrame<String>(
                tableId: 'cabin4-pin',
                items: const ['one', 'two'],
                columnsOf: (width) => [
                  RecordColumn<String>(
                    const TableColumn('name', 'Name', flex: 1),
                    cell: (_, item) => RecordCellText(item),
                  ),
                ],
                builder: (context, table, items) => ListView(
                  children: [
                    for (final (index, item) in items.indexed)
                      RecordTableRow(
                        table: table!,
                        striped: index.isEven,
                        cells: table.cellsOf(context, item),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(RecordTableFrame<String>));
      final scheme = Theme.of(context).colorScheme;
      final cardStep = SurfaceLevel.card.colorOf(scheme);
      final header = tester
          .widgetList<Material>(find.byType(Material))
          .where((material) => material.color == cardStep);
      expect(header, isNotEmpty);
      final striped = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (box) =>
                box.decoration is ShapeDecoration &&
                (box.decoration as ShapeDecoration).color == cardStep,
          );
      expect(striped, isNotEmpty);
    });
  });

  group('logs (cabin batch 4, #11)', () {
    Future<void> pumpLog(WidgetTester tester, Log log) async {
      await tester.pumpWidget(TestApp(child: LogItem(log: log)));
      await tester.pump();
    }

    testWidgets('the payload sits in a hairline well', (tester) async {
      await pumpLog(
        tester,
        const Log(payload: 'core started', dateTime: '2024-01-01 12:00:00'),
      );
      final context = tester.element(find.byType(LogItem));
      final palette = context.haraPalette;
      final boxes = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(LogItem),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((box) => box.decoration is ShapeDecoration)
          .toList();
      // The row plate and the payload well are the only two plates.
      expect(boxes, hasLength(2));
      final well = boxes.last;
      final decoration = well.decoration as ShapeDecoration;
      expect(decoration.color, isNull);
      final shape = decoration.shape as RoundedSuperellipseBorder;
      expect(shape.borderRadius, AppRadius.hara);
      expect(shape.side.color, palette.line);
      expect(shape.side.width, HaraSpace.hairline);
      expect(
        find.descendant(
          of: find.byWidget(well),
          matching: find.byType(SelectableText),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the level label carries its tone as text', (tester) async {
      await pumpLog(
        tester,
        const Log(
          logLevel: LogLevel.warning,
          payload: 'slow upstream',
          dateTime: '2024-01-01 12:00:00',
        ),
      );
      final context = tester.element(find.byType(LogItem));
      final scheme = Theme.of(context).colorScheme;
      expect(find.byType(TonalChip), findsNothing);
      final label = tester.widget<Text>(find.text('warning'));
      expect(label.style?.color, scheme.warning);
    });
  });

  group('theme (cabin batch 4, #12)', () {
    Future<void> pumpTheme(WidgetTester tester) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ThemeView()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the live preview pairs a light and a dark cabin', (
      tester,
    ) async {
      await pumpTheme(tester);
      final screens = tester
          .widgetList<MiniScreen>(
            find.descendant(
              of: find.byType(ThemeLivePreview),
              matching: find.byType(MiniScreen),
            ),
          )
          .toList();
      expect(screens, hasLength(2));
      expect(screens.map((screen) => screen.colorScheme.brightness).toSet(), {
        Brightness.light,
        Brightness.dark,
      });
    });

    testWidgets('the live preview sits flat on the page field', (tester) async {
      await pumpTheme(tester);
      final plates = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(ThemeLivePreview),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((box) => box.decoration is ShapeDecoration)
          .toList();
      expect(plates, isEmpty);
    });

    testWidgets('every swatch ring reads in the palette ink', (tester) async {
      await pumpTheme(tester);
      final context = tester.element(find.byType(ThemeView));
      final rings = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((box) {
            if (box.decoration is! ShapeDecoration) return false;
            final shape = (box.decoration as ShapeDecoration).shape;
            return shape is CircleBorder && shape.side.width == 2.5;
          })
          .toList();
      expect(rings, isNotEmpty);
      for (final ring in rings) {
        final shape =
            (ring.decoration as ShapeDecoration).shape as CircleBorder;
        expect(shape.side.color, context.haraPalette.ink);
      }
    });

    testWidgets('the cabin core compact switch is present exactly once', (
      tester,
    ) async {
      await pumpTheme(tester);
      expect(find.text('Compact cabin core'), findsOneWidget);
    });
  });

  group('tools and index pages (cabin batch 4, #6/#16/#17)', () {
    testWidgets('settings sections head the page rows', (tester) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ToolsView()),
        ),
      );
      await tester.pump();
      expect(find.text('Startup and background'), findsOneWidget);
      expect(find.byType(CoreSwitchItem), findsOneWidget);
      expect(find.byType(DecorationListItem), findsNothing);
    });

    testWidgets('the settings index lists network and dns cabin rows', (
      tester,
    ) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ToolsView()),
        ),
      );
      await tester.pump();
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('DNS'), findsOneWidget);
      expect(find.byType(DecorationListItem), findsNothing);
    });

    ;
  });

  group('resources (cabin batch 4, #10)', () {
    testWidgets('resource rows are shared hara rows under section heads', (
      tester,
    ) async {
      final container = _container(
        tester,
        overrides: [
          iconSetsProvider.overrideWith(() => TestIconSets(const [])),
          clashProvidersProvider.overrideWith(
            () => TestClashProviders(const []),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ResourcesView()),
        ),
      );
      // The view loads its providers and file infos off the fake-async loop.
      for (var round = 0; round < 50; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.byType(ContextMenuRegion).evaluate().isNotEmpty) break;
      }
      expect(find.text('Geo'), findsOneWidget);
      expect(find.byType(DecorationListItem), findsNothing);
      expect(find.byType(ContextMenuRegion), findsWidgets);
      expect(find.byType(TonalChip), findsNothing);
    });
  });
}
