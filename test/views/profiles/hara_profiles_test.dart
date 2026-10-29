import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/profiles/hara_profiles.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

class _RecordingProxiesAction extends ProxiesAction {
  static final List<String> tested = [];

  @override
  Future<void> delayTestPageGroup(
    String groupName, {
    bool matchSearch = true,
  }) async {
    tested.add(groupName);
  }
}

Group _group(String name, int count) => Group(
  type: GroupType.Selector,
  name: name,
  all: [for (var i = 0; i < count; i++) Proxy(name: '$name-$i', type: 'ss')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final profiles = [
    Profile(
      id: 1,
      label: 'Alpha',
      type: ProfileType.url,
      url: 'https://example.com/alpha',
      autoUpdateDuration: Duration.zero,
      lastUpdateDate: DateTime(2026, 10, 20),
      subscriptionInfo: const SubscriptionInfo(
        upload: 1073741824,
        download: 2147483648,
        total: 107374182400,
        expire: 1793000000,
      ),
    ),
    const Profile(
      id: 2,
      label: 'Beta',
      type: ProfileType.file,
      autoUpdateDuration: Duration.zero,
    ),
    const Profile(
      id: 3,
      label: 'Gamma',
      type: ProfileType.custom,
      autoUpdateDuration: Duration.zero,
    ),
  ];

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    List<Group>? testGroups,
  }) async {
    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(profiles)),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        if (testGroups != null) ...[
          proxiesActionProvider.overrideWith(_RecordingProxiesAction.new),
          currentGroupsStateProvider.overrideWithValue(
            GroupsState(value: testGroups),
          ),
        ],
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
        child: const TestApp(child: HaraProfilesView()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('rows render name over type and usage meta lines', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.textContaining('100GB'), findsOneWidget);
  });

  testWidgets('the only vermilion dot and the in-use word mark the current', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.byType(HaraDot), findsOneWidget);
    expect(find.text('In use'), findsOneWidget);
    final dotRow = find.ancestor(
      of: find.byType(HaraDot),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: dotRow, matching: find.text('Alpha')),
      findsOneWidget,
    );
  });

  testWidgets('the add section keeps the creation entries as text rows', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Import from link'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('tapping a row switches the current profile', (tester) async {
    final container = await pumpPage(tester);
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(container.read(currentProfileIdProvider), 2);
  });

  testWidgets('the page title carries the subscriptions screen name', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Subscriptions'), findsOneWidget);
    expect(find.text('Profiles'), findsNothing);
  });

  testWidgets('the header test-all entry delay-tests every listed group', (
    tester,
  ) async {
    _RecordingProxiesAction.tested.clear();
    await pumpPage(tester, testGroups: [_group('G0', 2), _group('G1', 1)]);
    expect(find.text('Test all delays'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Sort profiles'), findsOneWidget);
    await tester.tap(find.text('Test all delays'));
    await tester.pump();
    expect(_RecordingProxiesAction.tested, ['G0', 'G1']);
  });
}
