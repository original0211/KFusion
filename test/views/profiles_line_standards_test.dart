import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/models/models.dart';
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
          child: const TestApp(child: ProfilesView(picker: true)),
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

  group('ProfilesView current profile marks', () {
    testWidgets('the current card carries the watermark and the in-use chip, '
        'the other card carries neither', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(
            () => TestProfiles(const [
              Profile(
                id: 1,
                label: 'Alpha',
                type: ProfileType.url,
                url: 'https://example.com/alpha',
                autoUpdateDuration: Duration.zero,
              ),
              Profile(
                id: 2,
                label: 'Beta',
                type: ProfileType.file,
                autoUpdateDuration: Duration.zero,
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
      globalState.container = container;
      container
          .read(viewSizeProvider.notifier)
          .update((_) => const Size(800, 600));
      container.read(currentProfileIdProvider.notifier).value = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const TestApp(child: ProfilesView(picker: true)),
        ),
      );
      await tester.pumpAndSettle();
      final currentCard = find.byWidgetPredicate(
        (widget) => widget is ProfileItem && widget.profile.id == 1,
      );
      final otherCard = find.byWidgetPredicate(
        (widget) => widget is ProfileItem && widget.profile.id == 2,
      );
      expect(
        find.descendant(
          of: currentCard,
          matching: find.byType(DashboardDiscMotif),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: otherCard,
          matching: find.byType(DashboardDiscMotif),
        ),
        findsNothing,
      );
      final chip = tester.widget<MetaChip>(
        find.descendant(of: currentCard, matching: find.byType(MetaChip)),
      );
      final context = tester.element(currentCard);
      expect(chip.label, 'In use');
      expect(chip.color, Theme.of(context).colorScheme.primary);
      expect(
        find.descendant(of: otherCard, matching: find.byType(MetaChip)),
        findsNothing,
      );
      expect(find.byType(SelectionBadge), findsNothing);
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

    Container actionUnderline(WidgetTester tester, String label) {
      final column = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      return tester.widget<Container>(
        find.descendant(
          of: column,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.color != null &&
                widget.constraints?.minHeight == 1.2,
          ),
        ),
      );
    }

    testWidgets('method actions sit on their rows as underlined text', (
      tester,
    ) async {
      await pumpView(tester);
      expect(find.byType(DashboardDiscMotif), findsNothing);
      expect(find.byType(TonalButton), findsNothing);
      for (final label in ['下载并解析', '选择文件', '解析文本']) {
        expect(find.text(label), findsOneWidget, reason: label);
        expect(
          actionUnderline(tester, label).color,
          const Color(0xFF1A1A1A),
          reason: label,
        );
      }
      final confirm = tester.widget<Text>(find.text('确认导入'));
      expect(confirm.style?.color, const Color(0xFFB4B4B0));
    });

    testWidgets('unparsable text surfaces an error as red text', (
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
      expect(find.byType(ErrorBanner), findsNothing);
      final context = tester.element(find.byType(UniversalImportView));
      final errorText = tester.widget<Text>(find.textContaining('未解析出任何节点'));
      expect(errorText.style?.color, Theme.of(context).colorScheme.error);
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
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      final confirm = tester.widget<Text>(find.text('确认导入'));
      expect(confirm.style?.color, const Color(0xFF1A1A1A));
      expect(actionUnderline(tester, '确认导入').color, const Color(0xFF1A1A1A));
      expect(find.text('导出 sing-box 配置'), findsOneWidget);
    });

    testWidgets('payload wells are framed by hairlines with no fill', (
      tester,
    ) async {
      await pumpView(tester);
      List<BoxDecoration> wells() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .where((decoration) => decoration.border != null)
          .toList();
      expect(wells(), hasLength(2));
      for (final decoration in wells()) {
        expect(decoration.color, isNull);
        final border = decoration.border! as Border;
        expect(border.top.width, 0.7);
        expect(border.top.color, const Color(0xFFE9E9E6));
      }
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
      expect(wells(), hasLength(3));
    });
  });
}
