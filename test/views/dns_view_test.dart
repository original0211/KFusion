import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/providers/database.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _profileId = 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> pumpView(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          () => TestProfiles([
            const Profile(
              id: _profileId,
              type: ProfileType.custom,
              autoUpdateDuration: Duration.zero,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1200, 1000));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: DnsView()),
      ),
    );
    await tester.pump();
  }

  PatchClashConfig config() => container.read(patchClashConfigProvider);

  void setKeys(Set<DnsOverrideKey> keys) {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(dnsOverrideKeys: keys));
  }

  String emptyLabel() =>
      currentAppLocalizations.nullTip(currentAppLocalizations.overrideEntries);

  Finder inSheet(String title) => find.descendant(
    of: find.byType(SelectionSheet<DnsOverrideKey>),
    matching: find.text(title),
  );

  Future<void> openAddSheet(WidgetTester tester) async {
    final l = currentAppLocalizations;
    await tester.tap(find.text(l.addOverrideEntry));
    await tester.pumpAndSettle();
  }

  IconButton barButton(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

  testWidgets('a key picked from the sheet starts at its default', (
    tester,
  ) async {
    await pumpView(tester);
    expect(find.text(emptyLabel()), findsOneWidget);

    await openAddSheet(tester);
    expect(inSheet(currentAppLocalizations.addOverrideEntry), findsOneWidget);
    await tester.tap(find.text(currentAppLocalizations.listen));
    await tester.pumpAndSettle();

    expect(config().dnsOverrideKeys, {DnsOverrideKey.listen});
    expect(config().dns.listen, isEmpty);
    expect(find.text(emptyLabel()), findsNothing);
    expect(find.text(currentAppLocalizations.listen), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('a key added again starts over from its default', (tester) async {
    await pumpView(tester);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.dns(ipv6: true));

    await openAddSheet(tester);
    await tester.tap(find.text('IPv6'));
    await tester.pumpAndSettle();

    expect(config().dnsOverrideKeys, {DnsOverrideKey.ipv6});
    expect(config().dns.ipv6, defaultDns.ipv6);
  });

  testWidgets('the empty page says where the entries apply and adds from it', (
    tester,
  ) async {
    final l = currentAppLocalizations;
    await pumpView(tester);

    expect(find.text(l.dnsOverrideDesc), findsOneWidget);
    expect(find.byTooltip(l.addOverrideEntry), findsNothing);

    setKeys({DnsOverrideKey.ipv6});
    await tester.pumpAndSettle();

    expect(find.text(emptyLabel()), findsNothing);
    expect(find.text(l.dnsOverrideDesc), findsOneWidget);
    await tester.tap(find.byTooltip(l.addOverrideEntry));
    await tester.pumpAndSettle();
    expect(inSheet(l.addOverrideEntry), findsOneWidget);
    expect(inSheet('IPv6'), findsNothing);
  });

  testWidgets('the app-wide page offers only the normal profile keys', (
    tester,
  ) async {
    await pumpView(tester);

    await openAddSheet(tester);

    expect(find.text('Direct Nameserver'), findsOneWidget);
    expect(find.text(currentAppLocalizations.respectRules), findsNothing);
    expect(find.text('Nameserver Policy'), findsNothing);
    expect(find.text(currentAppLocalizations.fallbackFilter), findsNothing);
  });

  testWidgets('the app-wide page offers no quick edit', (tester) async {
    await pumpView(tester);
    setKeys({DnsOverrideKey.ipv6});
    await tester.pump();

    expect(find.byTooltip(currentAppLocalizations.quickEdit), findsNothing);
  });

  testWidgets('an options key is added without asking for its value', (
    tester,
  ) async {
    await pumpView(tester);

    await openAddSheet(tester);
    await tester.tap(find.text(currentAppLocalizations.dnsMode));
    await tester.pumpAndSettle();

    expect(find.byType(CommonPopupMenu), findsNothing);
    expect(config().dnsOverrideKeys, {DnsOverrideKey.enhancedMode});
    expect(config().dns.enhancedMode, defaultDns.enhancedMode);
    expect(defaultDns.enhancedMode, DnsMode.redirHost);
    expect(find.text('redir-host'), findsOneWidget);
  });

  testWidgets('a toggle entry writes its value and can be removed', (
    tester,
  ) async {
    await pumpView(tester);
    setKeys({DnsOverrideKey.ipv6});
    await tester.pump();

    expect(find.text('IPv6'), findsOneWidget);
    await tester.tap(find.text('IPv6'));
    await tester.pump();
    expect(config().dns.ipv6, isTrue);

    await tester.tap(find.byTooltip(currentAppLocalizations.remove));
    await tester.pumpAndSettle();
    expect(config().dnsOverrideKeys, isEmpty);
    expect(config().dns.ipv6, defaultDns.ipv6);
    expect(find.text('IPv6'), findsNothing);
    expect(find.text(emptyLabel()), findsOneWidget);
  });

  testWidgets('a list entry without a description summarises its items', (
    tester,
  ) async {
    await pumpView(tester);
    setKeys({DnsOverrideKey.nameserver, DnsOverrideKey.defaultNameserver});
    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith.dns(
            nameserver: ['1.1.1.1', '8.8.8.8'],
            defaultNameserver: [],
          ),
        );
    await tester.pump();

    expect(find.text(currentAppLocalizations.itemsCount(2)), findsOneWidget);
    expect(find.text(currentAppLocalizations.none), findsOneWidget);
  });

  testWidgets('an entry emptied on the app-wide page overrides with nothing', (
    tester,
  ) async {
    await pumpView(tester);
    setKeys({
      DnsOverrideKey.listen,
      DnsOverrideKey.nameserver,
      DnsOverrideKey.defaultNameserver,
    });
    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith.dns(
            listen: ':1053',
            nameserver: ['1.1.1.1'],
            defaultNameserver: ['223.5.5.5'],
          ),
        );
    await tester.pump();

    await tester.tap(find.text(currentAppLocalizations.listen));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text(currentAppLocalizations.submit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Default Nameserver'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    await tester.tap(find.byGlyph(AppGlyphs.delete));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, currentAppLocalizations.delete),
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(config().dnsOverrideKeys, hasLength(3));
    expect(
      config().dns.overrideJson(config().dnsOverrideKeys, keepEmpty: true),
      {
        'listen': '',
        'default-nameserver': <String>[],
        'nameserver': ['1.1.1.1'],
      },
    );
  });

  testWidgets('the DNS mode options read as mihomo writes them and leave '
      'out hosts', (tester) async {
    await pumpView(tester);
    setKeys({DnsOverrideKey.enhancedMode});
    await tester.pump();

    await tester.tap(find.text(currentAppLocalizations.dnsMode));
    await tester.pumpAndSettle();

    expect(find.text('normal'), findsOneWidget);
    expect(find.text('fake-ip'), findsOneWidget);
    expect(find.text('redir-host'), findsWidgets);
    expect(find.text(DnsMode.redirHost.name), findsNothing);
    expect(find.text(DnsMode.hosts.name), findsNothing);
  });

  testWidgets('the add button disables while every key is listed', (
    tester,
  ) async {
    await pumpView(tester);
    setKeys(DnsOverrideKey.normalProfileKeys);
    await tester.pump();

    final add = barButton(tester, currentAppLocalizations.addOverrideEntry);
    expect(add.onPressed, isNull);
  });
}
