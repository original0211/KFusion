import 'dart:io';

import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/advanced.dart';
import 'package:kfusion/views/config/custom_resources.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/dns_queries.dart';
import 'package:kfusion/views/hotkey.dart';
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
      testWidgets('row card is a rimmed lg plate in $brightness', (
        tester,
      ) async {
        await pumpItem(tester, brightness);
        final context = tester.element(find.byType(RecordListItem));
        final scheme = Theme.of(context).colorScheme;
        final decoration = _shapeDecorationOf(
          tester,
          find.descendant(
            of: find.byType(RecordListItem),
            matching: find.byType(DecoratedBox),
          ),
        );
        final shape = decoration.shape as RoundedSuperellipseBorder;
        expect(shape.borderRadius, AppRadius.lg);
        expect(shape.side.color, scheme.cabinRim);
        expect(decoration.color, SurfaceLevel.card.colorOf(scheme));
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

    testWidgets('the payload sits in a rimmed inset well', (tester) async {
      await pumpLog(
        tester,
        const Log(payload: 'core started', dateTime: '2024-01-01 12:00:00'),
      );
      final context = tester.element(find.byType(LogItem));
      final scheme = Theme.of(context).colorScheme;
      final wells = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where(
            (box) =>
                box.decoration is ShapeDecoration &&
                (box.decoration as ShapeDecoration).color ==
                    SurfaceLevel.inset.colorOf(scheme),
          )
          .toList();
      expect(wells, hasLength(1));
      final shape =
          (wells.single.decoration as ShapeDecoration).shape
              as RoundedSuperellipseBorder;
      expect(shape.borderRadius, AppRadius.md);
      expect(shape.side.color, scheme.cabinRim);
      expect(
        find.descendant(
          of: find.byWidget(wells.single),
          matching: find.byType(SelectableText),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the level label carries its tone container', (tester) async {
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
      final chip = tester.widget<TonalChip>(find.byType(TonalChip));
      expect(chip.label, 'warning');
      expect(chip.color, scheme.warningContainer);
      expect(chip.foregroundColor, scheme.onWarningContainer);
    });
  });

  group('dns queries (cabin batch 4, #9)', () {
    testWidgets('a failed query reads its summary in the error color', (
      tester,
    ) async {
      await tester.pumpWidget(
        TestApp(
          child: DnsQueryItem(
            dnsQuery: DnsQuery(
              domain: 'example.com',
              type: 'A',
              answers: const [],
              rcode: 'SERVFAIL',
              error: 'server failure',
              delay: 30,
              time: DateTime.utc(2026, 9, 18, 4, 30),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(DnsQueryItem));
      final summary = tester.widget<Text>(find.text('server failure'));
      expect(summary.style?.color, Theme.of(context).colorScheme.error);
    });

    testWidgets('the empty state is the brand variant', (tester) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: DnsQueriesView()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final status = tester.widget<NullStatus>(find.byType(NullStatus));
      expect(status.brandMark, isTrue);
      expect(find.byType(DashboardDiscMotif), findsOneWidget);
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

    testWidgets('the live preview plate carries the cabin rim', (tester) async {
      await pumpTheme(tester);
      final context = tester.element(find.byType(ThemeLivePreview));
      final scheme = Theme.of(context).colorScheme;
      final plate = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(ThemeLivePreview),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((box) => box.decoration is ShapeDecoration)
          .single;
      final shape =
          (plate.decoration as ShapeDecoration).shape
              as RoundedSuperellipseBorder;
      expect(shape.side.color, scheme.cabinRim);
    });

    testWidgets('every swatch ring reads in the primary color', (tester) async {
      await pumpTheme(tester);
      final context = tester.element(find.byType(ThemeView));
      final scheme = Theme.of(context).colorScheme;
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
        expect(shape.side.color, scheme.primary);
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
    testWidgets('settings sections head shared cabin rows', (tester) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ToolsView()),
        ),
      );
      await tester.pump();
      final headers = tester
          .widgetList<ListHeader>(find.byType(ListHeader))
          .map((header) => header.title)
          .toList();
      expect(headers, contains('Startup and background'));
      expect(find.byType(CoreSwitchItem), findsOneWidget);
      expect(find.byType(DecorationListItem), findsWidgets);
    });

    testWidgets('the advanced index lists four cabin rows', (tester) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: AdvancedConfigView()),
        ),
      );
      await tester.pump();
      expect(find.byType(DecorationListItem), findsNWidgets(4));
    });

    testWidgets('the custom resources index lists four cabin rows', (
      tester,
    ) async {
      final container = _container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: CustomResourcesView()),
        ),
      );
      await tester.pump();
      expect(find.byType(DecorationListItem), findsNWidgets(4));
    });
  });

  group('resources (cabin batch 4, #10)', () {
    testWidgets('resource rows are shared cabin rows under section heads', (
      tester,
    ) async {
      final container = _container(
        tester,
        overrides: [
          iconSetsProvider.overrideWith(() => TestIconSets(const [])),
          clashProvidersProvider.overrideWith(
            () => TestClashProviders(const []),
          ),
          scriptsProvider.overrideWith(() => TestScripts(const [])),
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
        if (find.byType(DecorationListItem).evaluate().isNotEmpty) break;
      }
      final headers = tester
          .widgetList<ListHeader>(find.byType(ListHeader))
          .map((header) => header.title)
          .toList();
      expect(headers, contains('Geo'));
      expect(find.byType(DecorationListItem), findsWidgets);
      for (final chip in tester.widgetList<TonalChip>(find.byType(TonalChip))) {
        final context = tester.element(find.byType(ResourcesView));
        final scheme = Theme.of(context).colorScheme;
        expect(chip.foregroundColor, scheme.onSurfaceVariant);
        expect(chip.color, isNot(scheme.primary));
      }
    });
  });

  group('hotkey (cabin batch 4, #14)', () {
    testWidgets('the intro plate carries the cabin rim', (tester) async {
      final container = _container(tester);
      final subscription = container.listen(
        hotKeyActionsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: HotKeyView()),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HotKeyView));
      final scheme = Theme.of(context).colorScheme;
      final plates = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((box) {
            if (box.decoration is! ShapeDecoration) return false;
            final shape = (box.decoration as ShapeDecoration).shape;
            return shape is RoundedSuperellipseBorder &&
                shape.borderRadius == AppRadius.xl &&
                shape.side.color == scheme.cabinRim;
          });
      expect(plates, isNotEmpty);
    });
  });
}
