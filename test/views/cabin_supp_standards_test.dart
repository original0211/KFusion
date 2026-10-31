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
  group('hara reading: general core switch container', () {
    testWidgets('the card wears no panel: no card fill, no shadow', (
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

      final card = find.byType(CoreSwitchCard);
      expect(
        find.descendant(of: card, matching: find.byType(CommonCard)),
        findsNothing,
      );
      final shadowed = tester
          .widgetList<DecoratedBox>(
            find.ancestor(of: card, matching: find.byType(DecoratedBox)),
          )
          .where(
            (box) =>
                box.decoration is ShapeDecoration &&
                (box.decoration as ShapeDecoration).shadows?.isNotEmpty == true,
          )
          .toList();
      expect(shadowed, isEmpty);
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

    Container kindUnderline(WidgetTester tester, String name) {
      final column = find
          .ancestor(of: find.text(name), matching: find.byType(Column))
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

    testWidgets(
      'the selector reads as text with an ink underline on the current core',
      (tester) async {
        final profile = Profile.normal(
          label: 'supp test',
          url: 'https://example.com/sub',
        );
        await pumpEdit(tester, profile, {profile.id: CoreKind.mihomo});

        expect(find.byType(DropdownButton<CoreKind>), findsNothing);
        expect(find.text('mihomo'), findsOneWidget);
        expect(find.text('sing-box'), findsOneWidget);
        final field = find.ancestor(
          of: find.text('运行核心'),
          matching: find.byType(CommonCard),
        );
        expect(
          find.descendant(of: field, matching: find.byType(DashboardDiscMotif)),
          findsNothing,
        );
        expect(
          find.descendant(of: field, matching: find.byType(SelectionCheck)),
          findsNothing,
        );
        final card = tester.widget<CommonCard>(field);
        expect(card.flat, isTrue);
        expect(card.shape, AppShape.hara);
        final cardStyle = tester
            .widget<FilledButton>(
              find.descendant(of: field, matching: find.byType(FilledButton)),
            )
            .style!;
        expect(
          (cardStyle.shape!.resolve({})! as RoundedSuperellipseBorder)
              .borderRadius,
          BorderRadius.zero,
        );
        expect(cardStyle.backgroundColor!.resolve({}), Colors.transparent);
        expect(
          cardStyle.side!.resolve({}),
          BorderSide(color: HaraPalette.light.line, width: HaraSpace.hairline),
        );
        expect(kindUnderline(tester, 'mihomo').color, const Color(0xFF1A1A1A));
        expect(kindUnderline(tester, 'sing-box').color, Colors.transparent);
        expect(
          tester.widget<Text>(find.text('mihomo')).style?.fontWeight,
          FontWeight.w500,
        );
        expect(
          tester.widget<Text>(find.text('sing-box')).style?.fontWeight,
          FontWeight.w400,
        );
        expect(find.byTooltip('Save'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

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
      expect(kindUnderline(tester, 'sing-box').color, const Color(0xFF1A1A1A));
      expect(kindUnderline(tester, 'mihomo').color, Colors.transparent);

      await tester.tap(find.text('sing-box'));
      await tester.pump();
      expect(fake.calls, hasLength(1));
    });
  });
}
