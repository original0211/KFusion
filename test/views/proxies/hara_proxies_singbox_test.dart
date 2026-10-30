import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/hara_proxies.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: '', proxyName: ''),
    );
  });

  const parent = '⚡ CF前置';
  const child = '⚡ CF前置 · auto';

  const dualProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {parent: 'CF-02'},
    autoUpdateDuration: Duration.zero,
  );
  const dualGroups = [
    Group(
      name: parent,
      type: GroupType.URLTest,
      now: 'CF-01',
      all: [
        Proxy(name: 'CF-01', type: 'Http'),
        Proxy(name: 'CF-02', type: 'Shadowsocks'),
      ],
    ),
  ];
  const dualPanel = <String, SingBoxPanelGroup>{
    parent: (type: 'Selector', now: 'CF-02', all: [child, 'CF-01', 'CF-02']),
    child: (type: 'URLTest', now: 'CF-01', all: ['CF-01', 'CF-02']),
  };

  const nativeProfile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {},
    autoUpdateDuration: Duration.zero,
  );
  const nativeGroups = [
    Group(
      name: 'Native',
      type: GroupType.URLTest,
      now: 'N2',
      all: [
        Proxy(name: 'N1', type: 'Shadowsocks'),
        Proxy(name: 'N2', type: 'Shadowsocks'),
      ],
    ),
  ];
  const nativePanel = <String, SingBoxPanelGroup>{
    'Native': (type: 'URLTest', now: 'N2', all: ['N1', 'N2']),
  };

  Future<ProviderContainer> pumpSection(
    WidgetTester tester, {
    required Profile profile,
    required List<Group> groups,
    required Map<String, SingBoxPanelGroup> panel,
    required String? exitName,
  }) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = _MockCoreHandlerInterface();
    when(
      () => core.changeProxy(any()),
    ).thenAnswer((_) async => const ChangeProxyResult(changed: true));
    when(
      () => core.getProxies(),
    ).thenAnswer((_) async => const ProxiesData(proxies: {}, all: []));
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        groupsProvider.overrideWithValue(groups),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        singBoxPanelGroupsProvider.overrideWithValue(AsyncData(panel)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(412, 800));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('en'),
          child: Builder(
            builder: (context) => Material(
              color: context.haraPalette.bg,
              child: CustomScrollView(
                slivers: [
                  HaraProxyGroupSection(
                    group: groups.single,
                    exitName: exitName,
                    first: true,
                    exitMarker: HaraExitMarker.dot,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder dotRow() {
    return find.ancestor(of: find.byType(HaraDot), matching: find.byType(Row));
  }

  testWidgets(
    'a dual-layer group leads with a tappable auto row for the child',
    (tester) async {
      final container = await pumpSection(
        tester,
        profile: dualProfile,
        groups: dualGroups,
        panel: dualPanel,
        exitName: 'CF-01',
      );
      expect(find.text('Auto'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Auto')).dy,
        lessThan(tester.getTopLeft(find.text('CF-01')).dy),
      );
      // The pinned leaf holds the selection, so the exit dot starts on
      // the panel child's current leaf row.
      expect(find.byType(HaraDot), findsOneWidget);
      expect(
        find.descendant(of: dotRow(), matching: find.text('CF-01')),
        findsOneWidget,
      );

      await tester.tap(find.text('Auto'));
      await tester.pump();
      expect(container.read(selectedMapProvider)[parent], child);
      // The dot moves to the auto row, and nowhere else.
      expect(find.byType(HaraDot), findsOneWidget);
      expect(
        find.descendant(of: dotRow(), matching: find.text('Auto')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 15));

      // Member rows keep their legacy behaviour.
      await tester.tap(find.text('CF-02'));
      await tester.pump();
      expect(container.read(selectedMapProvider)[parent], 'CF-02');
      await tester.pump(const Duration(seconds: 15));
    },
  );

  testWidgets('a native URLTest group is labelled auto and locked', (
    tester,
  ) async {
    final container = await pumpSection(
      tester,
      profile: nativeProfile,
      groups: nativeGroups,
      panel: nativePanel,
      exitName: 'N2',
    );
    // The header carries the auto label; no synthetic row appears.
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('N1'), findsOneWidget);
    expect(find.text('N2'), findsOneWidget);
    // The panel's current member shows as the exit.
    expect(find.byType(HaraDot), findsOneWidget);
    expect(
      find.descendant(of: dotRow(), matching: find.text('N2')),
      findsOneWidget,
    );

    await tester.tap(find.text('N1'));
    await tester.pump();
    expect(container.read(selectedMapProvider), isEmpty);
    await tester.tap(find.text('N2'));
    await tester.pump();
    expect(container.read(selectedMapProvider), isEmpty);
    await tester.pump(const Duration(seconds: 15));
  });
}
