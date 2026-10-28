import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/hara_proxies.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = Profile(
    id: 1,
    label: 'Test',
    type: ProfileType.url,
    url: 'https://example.com/sub',
    selectedMap: {'GLOBAL': 'Home', 'Home': 'JP-03', 'Auto': 'JP-03'},
    autoUpdateDuration: Duration.zero,
  );

  final groups = [
    const Group(
      name: 'GLOBAL',
      type: GroupType.Selector,
      all: [
        Proxy(name: 'Home', type: 'Selector'),
        Proxy(name: 'JP-03', type: 'Shadowsocks'),
        Proxy(name: 'DIRECT', type: 'Direct'),
      ],
    ),
    const Group(
      name: 'Home',
      type: GroupType.Selector,
      all: [
        Proxy(name: 'JP-03', type: 'Shadowsocks'),
        Proxy(name: 'HK-01', type: 'Shadowsocks'),
      ],
    ),
    // Off the GLOBAL chain but holding the same leaf as its pick: its JP-03
    // row must not take the dot.
    const Group(
      name: 'Auto',
      type: GroupType.URLTest,
      all: [
        Proxy(name: 'JP-03', type: 'Shadowsocks'),
        Proxy(name: 'HK-01', type: 'Shadowsocks'),
      ],
    ),
  ];

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(const [profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        groupsProvider.overrideWithValue(groups),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: groups),
        ),
        delayProvider(proxyName: 'JP-03', testUrl: null).overrideWithValue(58),
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
        child: const TestApp(child: HaraProxiesView()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder richTextContaining(String needle) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is Text && (widget.textSpan?.toPlainText() ?? '') == needle,
    );
  }

  testWidgets('groups render as titled hairline sections of single rows', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('JP-03'), findsNWidgets(3));
    expect(find.text('HK-01'), findsNWidgets(2));
    expect(richTextContaining('58 ms'), findsWidgets);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('the only vermilion dot sits on the current exit leaf row', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.byType(HaraDot), findsOneWidget);
    final dotRow = find.ancestor(
      of: find.byType(HaraDot),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: dotRow, matching: find.text('JP-03')),
      findsOneWidget,
    );
  });

  testWidgets('the group row on the path shows its real selected leaf', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('→ JP-03'), findsOneWidget);
  });

  testWidgets('tapping a row writes the selection through the same action', (
    tester,
  ) async {
    final container = await pumpPage(tester);
    await tester.tap(find.text('HK-01').first);
    await tester.pump();
    expect(container.read(selectedMapProvider)['Home'], 'HK-01');
    // Flush the debounced core sync chain the selection action schedules.
    await tester.pump(const Duration(seconds: 15));
  });
}
