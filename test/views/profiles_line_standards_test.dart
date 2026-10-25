import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/profiles/profiles.dart';
import 'package:kfusion/views/profiles/universal_import.dart';
import 'package:kfusion/widgets/widgets.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExpireChip', () {
    Future<void> pumpChip(WidgetTester tester, DateTime expire) async {
      await tester.pumpWidget(
        TestApp(
          child: Center(child: ExpireChip(expire: expire)),
        ),
      );
      await tester.pump();
    }

    ({Color background, Color foreground}) chipColors(WidgetTester tester) {
      final chip = find.byType(ExpireChip);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: chip, matching: find.byType(DecoratedBox)),
      );
      final text = tester.widget<Text>(
        find.descendant(of: chip, matching: find.byType(Text)),
      );
      return (
        background: (box.decoration as ShapeDecoration).color!,
        foreground: text.style!.color!,
      );
    }

    testWidgets('an unexpired date reads neutral', (tester) async {
      await pumpChip(tester, DateTime.now().add(const Duration(days: 30)));
      final context = tester.element(find.byType(ExpireChip));
      final colorScheme = Theme.of(context).colorScheme;
      final colors = chipColors(tester);
      expect(
        colors.background,
        context.raisedSurfaceLevel.colorOf(colorScheme),
      );
      expect(colors.foreground, colorScheme.onSurfaceVariant);
    });

    testWidgets('an expired date keeps the error colors', (tester) async {
      await pumpChip(tester, DateTime.now().subtract(const Duration(days: 1)));
      final context = tester.element(find.byType(ExpireChip));
      final colorScheme = Theme.of(context).colorScheme;
      final colors = chipColors(tester);
      expect(colors.background, colorScheme.error.opacity15);
      expect(colors.foreground, colorScheme.error);
    });
  });

  group('ProfilesView empty state', () {
    testWidgets('uses the brand disc mark', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [profilesProvider.overrideWith(() => TestProfiles())],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      globalState.container = container;
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 600));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ProfilesView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DashboardDiscMotif), findsOneWidget);
      expect(
        tester.widget<NullStatus>(find.byType(NullStatus)).brandMark,
        isTrue,
      );
    });
  });

  group('UniversalImportView', () {
    Future<void> pumpView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      globalState.container = container;
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 1000));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: UniversalImportView()),
        ),
      );
      await tester.pumpAndSettle();
    }

    FilledButton confirmButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'));

    testWidgets('method actions sit on their rows under a disc header', (
      tester,
    ) async {
      await pumpView(tester);
      expect(find.byType(DashboardDiscMotif), findsOneWidget);
      for (final label in ['下载并解析', '选择文件', '解析文本']) {
        expect(
          find.widgetWithText(TonalButton, label),
          findsOneWidget,
          reason: label,
        );
      }
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('unparsable text surfaces an error in the banner', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.enterText(
        find.byType(TextField).at(1),
        '这不是任何已知格式的配置 {{{ 乱码',
      );
      await tester.tap(find.text('解析文本'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未解析出任何节点'), findsOneWidget);
      expect(find.byType(ErrorBanner), findsOneWidget);
    });

    testWidgets('a parsed paste reports its nodes and enables confirm', (
      tester,
    ) async {
      await pumpView(tester);
      await tester.enterText(
        find.byType(TextField).at(1),
        'proxies:\n'
        '  - name: node-a\n'
        '    type: ss\n'
        '    server: example.com\n'
        '    port: 8388\n'
        '    cipher: aes-256-gcm\n'
        '    password: secret\n',
      );
      await tester.tap(find.text('解析文本'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 个节点'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNotNull);
    });
  });
}
