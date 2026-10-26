import 'dart:io';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/profiles/edit.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';

class _NoopSetupAction extends SetupAction {
  @override
  void autoApplyProfile() {}
}

class _FakeCoreKinds extends CoreKindsNotifier {
  _FakeCoreKinds(Map<int, CoreKind> initial) : _current = Map.of(initial);

  Map<int, CoreKind> _current;
  final List<(int, CoreKind)> calls = [];

  @override
  Future<Map<int, CoreKind>> build() async => _current;

  @override
  Future<void> setKind(int profileId, CoreKind kind) async {
    calls.add((profileId, kind));
    _current = {..._current, profileId: kind};
    state = AsyncData(_current);
  }
}

void main() {
  group('cabin supplement: general core switch container', () {
    testWidgets('the card wears the cabin panel shadow at xl rounding', (
      tester,
    ) async {
      await tester.pumpWidget(
        TestApp(
          locale: const Locale('zh', 'CN'),
          child: Scaffold(
            body: ItemPositionProvider(
              position: ItemPosition.startAndEnd,
              child: Builder(
                builder: (context) => CoreSwitchCard(
                  statusText: 'mihomo 运行中',
                  statusIsFailure: false,
                  showBinary: false,
                  binaryChecked: false,
                  binaryLabel: null,
                  downloading: false,
                  progress: null,
                  downloadRoute: null,
                  downloadError: null,
                  onDownload: () {},
                  showSwitch: true,
                  selectedCore: CoreKind.mihomo,
                  mihomoRunning: true,
                  singBoxRunning: false,
                  failureDetail: '',
                  switching: false,
                  onSelectCore: (_) {},
                  localizations: context.appLocalizations,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CommonCard), findsOneWidget);
      final context = tester.element(find.byType(CoreSwitchCard));
      final colorScheme = Theme.of(context).colorScheme;
      final wrapped = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byType(CommonCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where(
            (box) =>
                box.decoration is ShapeDecoration &&
                (box.decoration as ShapeDecoration).shadows?.isNotEmpty == true,
          )
          .toList();
      expect(wrapped, hasLength(1));
      final decoration = wrapped.single.decoration as ShapeDecoration;
      expect(decoration.shadows, colorScheme.cabinPanelShadows);
      expect(
        (decoration.shape as RoundedSuperellipseBorder).borderRadius,
        AppRadius.xl,
      );
      final card = tester.widget<CommonCard>(find.byType(CommonCard));
      expect(
        (card.shape as RoundedSuperellipseBorder).borderRadius,
        AppRadius.xl,
      );
      expect(find.text('mihomo'), findsOneWidget);
      expect(find.text('sing-box'), findsOneWidget);
    });
  });

  group('cabin supplement: profile edit core kind selector', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('cabin_supp_test');
      await useAppPaths(tempDir);
    });

    tearDownAll(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<_FakeCoreKinds> pumpEdit(
      WidgetTester tester,
      Profile profile,
      Map<int, CoreKind> initial,
    ) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = _FakeCoreKinds(initial);
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(() => _NoopSetupAction()),
          coreKindsProvider.overrideWith(() => fake),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
      });
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1000, 1400);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: globalState.navigatorKey,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              AppUiLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.delegate.supportedLocales,
            builder: (context, child) => wrapAppScopes(context, child!),
            home: Scaffold(
              body: Navigator(
                pages: [
                  MaterialPage(
                    child: Scaffold(body: EditProfileView(profile: profile)),
                  ),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return fake;
    }

    DecoratedBox kindRowBox(WidgetTester tester, String name) {
      final boxes = tester.widgetList<DecoratedBox>(
        find.ancestor(of: find.text(name), matching: find.byType(DecoratedBox)),
      );
      return boxes.singleWhere((box) {
        final decoration = box.decoration;
        return decoration is ShapeDecoration &&
            decoration.shape is RoundedSuperellipseBorder &&
            (decoration.shape as RoundedSuperellipseBorder).borderRadius ==
                AppRadius.md;
      });
    }

    testWidgets('the selector reads like the switch card rows', (tester) async {
      final profile = Profile.normal(
        label: 'supp test',
        url: 'https://example.com/sub',
      );
      await pumpEdit(tester, profile, {profile.id: CoreKind.mihomo});

      expect(find.byType(DropdownButton<CoreKind>), findsNothing);
      expect(find.text('mihomo'), findsOneWidget);
      expect(find.text('sing-box'), findsOneWidget);
      expect(find.byType(DashboardDiscMotif), findsNWidgets(2));
      expect(find.byType(SelectionCheck), findsOneWidget);
      final fieldContext = tester.element(
        find.ancestor(of: find.text('运行核心'), matching: find.byType(CommonCard)),
      );
      final colorScheme = Theme.of(fieldContext).colorScheme;
      final rowBox = kindRowBox(tester, 'mihomo');
      final decoration = rowBox.decoration as ShapeDecoration;
      expect(
        decoration.color,
        fieldContext.raisedSurfaceLevel.colorOf(colorScheme),
      );
      final checkRect = tester.getRect(find.byType(SelectionCheck));
      final mihomoRowRect = tester.getRect(find.byWidget(rowBox));
      expect(mihomoRowRect.contains(checkRect.center), isTrue);
      expect(find.byTooltip('Save'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('tapping a kind row reuses the persisted setKind wiring', (
      tester,
    ) async {
      final profile = Profile.normal(
        label: 'supp test',
        url: 'https://example.com/sub',
      );
      final fake = await pumpEdit(tester, profile, {
        profile.id: CoreKind.mihomo,
      });

      await tester.tap(find.text('sing-box'));
      await tester.pump();
      expect(fake.calls, [(profile.id, CoreKind.singbox)]);
      expect(find.byType(SelectionCheck), findsOneWidget);
      final checkRect = tester.getRect(find.byType(SelectionCheck));
      final singBoxRowRect = tester.getRect(
        find.byWidget(kindRowBox(tester, 'sing-box')),
      );
      expect(singBoxRowRect.contains(checkRect.center), isTrue);

      await tester.tap(find.text('sing-box'));
      await tester.pump();
      expect(fake.calls, hasLength(1));
    });
  });
}
