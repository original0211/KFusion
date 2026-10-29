import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kfusion/common/l10n_labels.dart';
import 'package:kfusion/common/request.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/about.dart';
import 'package:kfusion/views/config/rules.dart';
import 'package:kfusion/views/profiles/extend/standard.dart';
import 'package:kfusion/views/proxies/setting.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _PendingAdapter implements HttpClientAdapter {
  final response = Completer<ResponseBody>();
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests++;
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _TestGlobalRules extends GlobalRules {
  _TestGlobalRules(this.initial);

  final List<Rule> initial;

  @override
  Stream<List<Rule>> build() => Stream.value(initial);
}

class _TestProfileAddedRules extends ProfileRules {
  _TestProfileAddedRules(this.initial);

  final List<Rule> initial;

  @override
  Stream<List<Rule>> build(int profileId) => Stream.value(initial);

  @override
  void order(int oldIndex, int newIndex) {}
}

class _TestProfileDisabledRuleIds extends ProfileDisabledRuleIds {
  _TestProfileDisabledRuleIds(this.initial);

  final List<int> initial;

  @override
  Stream<List<int>> build(int profileId) => Stream.value(initial);
}

ProviderContainer _containerFor(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<Profile>? profiles,
  Size size = const Size(1400, 1000),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(
        profiles == null ? TestProfiles.new : () => TestProfiles(profiles),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

void main() {
  setUpAll(() {
    // AboutView reads globalState.packageInfo, which only the real app bootstrap
    // populates.
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: '0.0.0',
      buildNumber: '1',
    );
  });

  testWidgets('proxies setting picks its style from a menu', (tester) async {
    final container = _containerFor(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: ProxiesSetting())),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.current;

    expect(find.text(l10n.iconStyle), findsOneWidget);

    await tester.tap(find.text(l10n.style));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ProxiesType.tab.label));
    await tester.pumpAndSettle();

    expect(container.read(proxiesStyleSettingProvider).type, ProxiesType.tab);
    expect(find.text(l10n.iconStyle), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('proxies setting sorts by delay when selected', (tester) async {
    final container = _containerFor(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: Scaffold(body: ProxiesSetting())),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.current;

    await tester.tap(find.text(l10n.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.delay));
    await tester.pumpAndSettle();

    expect(
      container.read(proxiesStyleSettingProvider).sortType,
      ProxiesSortType.delay,
    );
    expect(find.byType(CommonPopupMenu), findsNothing);
  });

  testWidgets('about view renders version and link sections', (tester) async {
    final container = _containerFor(tester);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: AboutView()),
      ),
    );
    await tester.pump();

    expect(find.byType(AboutView), findsOneWidget);
    expect(find.text('github.com/original0211/KFusion'), findsOneWidget);
    expect(find.text('Telegram'), findsNothing);
    final hero = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_AboutHero',
    );
    expect(
      tester.getRect(hero).top,
      tester.getRect(find.byType(AppBar)).bottom + 12,
    );
    expect(tester.takeException(), null);

    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      for (var index = 0; index < 4; index++) {
        await tester.drag(scrollables.first, const Offset(0, -400));
        await tester.pump();
      }
    }
    expect(tester.takeException(), null);
  });

  testWidgets('about view shows progress while checking for updates', (
    tester,
  ) async {
    final container = _containerFor(tester);
    final originalAdapter = request.dio.httpClientAdapter;
    addTearDown(() => request.dio.httpClientAdapter = originalAdapter);
    final adapter = _PendingAdapter();
    request.dio.httpClientAdapter = adapter;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: AboutView()),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(adapter.requests, 1);

    adapter.response.complete(
      ResponseBody.fromString(
        jsonEncode({'tag_name': 'v0.0.0'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('The app is already up to date'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('standard extension renders added rules and selection state', (
    tester,
  ) async {
    final profile = Profile.normal();
    final addedRules = List.generate(
      6,
      (index) => Rule(
        id: 300 + index,
        content: 'added$index.com',
        ruleTarget: 'DIRECT',
        order: index.toString(),
      ),
    );
    final globalRules = List.generate(
      3,
      (index) => Rule(
        id: 400 + index,
        content: 'global$index.com',
        ruleTarget: 'DIRECT',
        order: index.toString(),
      ),
    );
    final container = _containerFor(
      tester,
      profiles: [profile],
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profileRulesProvider.overrideWith2(
          (_) => _TestProfileAddedRules(addedRules),
        ),
        globalRulesProvider.overrideWith(() => _TestGlobalRules(globalRules)),
        profileDisabledRuleIdsProvider.overrideWith2(
          (_) => _TestProfileDisabledRuleIds(const []),
        ),
        clashConfigProvider(
          profile.id,
        ).overrideWithValue(const AsyncData(ClashConfig())),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: ProfileIdProvider(
            profileId: profile.id,
            child: const Scaffold(
              body: CustomScrollView(slivers: [StandardContent()]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StandardContent), findsOneWidget);
    expect(find.text('added0.com'), findsOneWidget);
    expect(tester.takeException(), null);

    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isNotEmpty) {
      for (var index = 0; index < 4; index++) {
        await tester.drag(scrollables.first, const Offset(0, -400));
        await tester.pump();
      }
    }
    expect(tester.takeException(), null);
  });

  testWidgets('standard extension picks a MATCH-TARGET from the profile', (
    tester,
  ) async {
    final profile = Profile.normal();
    final container = _containerFor(
      tester,
      profiles: [profile],
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profileRulesProvider.overrideWith2(
          (_) => _TestProfileAddedRules(const []),
        ),
        globalRulesProvider.overrideWith(() => _TestGlobalRules(const [])),
        profileDisabledRuleIdsProvider.overrideWith2(
          (_) => _TestProfileDisabledRuleIds(const []),
        ),
        clashConfigProvider(profile.id).overrideWithValue(
          const AsyncData(
            ClashConfig(
              proxies: [Proxy(name: 'HK', type: 'ss')],
              proxyGroups: [
                ProxyGroup(id: 1, name: 'Proxy', type: GroupType.Selector),
              ],
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: ProfileIdProvider(
            profileId: profile.id,
            child: const Scaffold(
              body: CustomScrollView(slivers: [StandardContent()]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.current;
    expect(find.text(l10n.followProfile), findsOneWidget);

    await tester.tap(find.text(l10n.matchTarget));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionSheet<String>), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);

    await tester.tap(find.text('HK'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectionSheet<String>), findsNothing);
    expect(container.read(profilesProvider).first.matchTarget, 'HK');
    expect(find.text('HK'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('the global added rules page opens where they are added in a '
      'sheet over itself', (tester) async {
    final profile = Profile.normal();
    final container = _containerFor(
      tester,
      profiles: [profile],
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        profileRulesProvider.overrideWith2(
          (_) => _TestProfileAddedRules(const []),
        ),
        globalRulesProvider.overrideWith(() => _TestGlobalRules(const [])),
        profileDisabledRuleIdsProvider.overrideWith2(
          (_) => _TestProfileDisabledRuleIds(const []),
        ),
        clashConfigProvider(
          profile.id,
        ).overrideWithValue(const AsyncData(ClashConfig())),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: ProfileIdProvider(
            profileId: profile.id,
            child: const Scaffold(
              body: CustomScrollView(slivers: [StandardContent()]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final l10n = AppLocalizations.current;

    await tester.tap(find.text(l10n.controlGlobalAddedRules));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.goToConfigureAddedRules));
    await tester.pumpAndSettle();

    expect(find.byType(AddedRulesView), findsOneWidget);
    expect(find.text(l10n.editGlobalRules), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
