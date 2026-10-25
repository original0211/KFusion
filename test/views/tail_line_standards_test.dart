import 'package:kfusion/core/controller.dart';
import 'package:kfusion/core/interface.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart' hide FileInfo;
import 'package:kfusion/providers/action.dart';
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/providers/core.dart';
import 'package:kfusion/providers/database.dart';
import 'package:kfusion/providers/state.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/profiles/custom/groups.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _TestProxyGroups extends ProxyGroups {
  _TestProxyGroups(this.initial);

  final List<ProxyGroup> initial;

  @override
  Stream<List<ProxyGroup>> build(int profileId) => Stream.value(initial);

  @override
  void order(int oldIndex, int newIndex) {}

  @override
  void delAll(Iterable<int> proxyGroupIds) {}
}

class _MockCore extends Mock implements CoreHandlerInterface {}

class _GroupsInUse extends ProfilesAction {
  @override
  Future<Set<String>> groupsInUse(int profileId, Set<int> groupIds) async =>
      const {};
}

ColorScheme _schemeOf(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).colorScheme;
}

void main() {
  testWidgets('the filter regex text reads as a neutral subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const TestApp(child: Material(child: FilterRegexText('HK.*'))),
    );
    final text = tester.widget<Text>(find.text('HK.*'));
    final scheme = _schemeOf(tester, find.text('HK.*'));
    expect(text.style?.color, scheme.onSurfaceVariant);
    expect(text.style?.color, isNot(scheme.tertiary));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pass rule target reads neutral, a direct one success', (
    tester,
  ) async {
    ColorScheme? scheme;
    Future<Color?> targetColor(String target) async {
      await tester.pumpWidget(
        TestApp(
          child: Material(
            child: RuleItem(
              isSelected: false,
              rule: Rule(content: 'example.com', ruleTarget: target),
              onSelected: () {},
              onEdit: (_) {},
            ),
          ),
        ),
      );
      scheme = _schemeOf(tester, find.byType(RuleItem));
      final text = tester.widget<Text>(find.text(target));
      return text.style?.color;
    }

    expect(await targetColor('PASS'), scheme!.onSurfaceVariant);
    expect(await targetColor('GLOBAL'), scheme!.onSurfaceVariant);
    expect(await targetColor('DIRECT'), scheme!.success);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('preset raw rules read as neutral subtitles', (tester) async {
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RulePresetSheet(onAdd: (_) {}),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final raw = RulePreset.blockQuic.rawRules.single;
    final text = tester.widget<Text>(find.text(raw));
    final scheme = _schemeOf(tester, find.text(raw));
    expect(text.style?.color, scheme.onSurfaceVariant);
    expect(text.style?.color, isNot(scheme.tertiary));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('member kind chips sit neutral, the exclude chip on error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final profile = Profile.custom();
    final group = ProxyGroup(
      id: 100,
      profileId: profile.id,
      name: 'Group 0',
      type: GroupType.Selector,
      proxies: const ['DIRECT'],
      filter: 'HK',
      excludeFilter: 'bad',
    );
    registerFallbackValue(<String>[]);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        coreHandlerProvider.overrideWithValue(
          CoreController.scoped(_MockCore()),
        ),
        proxyGroupsProvider.overrideWith2((_) => _TestProxyGroups([group])),
        profilesActionProvider.overrideWith(() => _GroupsInUse()),
        customProfileDataProvider(profile.id).overrideWithValue(
          CustomProfileData(
            proxyGroups: [group],
            ruleTargets: {...RuleTarget.baseTargets, 'Group 0'},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container
        .read(viewSizeProvider.notifier)
        .update((_) => const Size(1400, 1000));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: CommonScaffold(
            title: 'Groups',
            body: CustomScrollView(
              slivers: [CustomProxyGroupsSection(profile.id)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Group 0'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.current;
    TonalChip chipWith(String label) =>
        tester.widget<TonalChip>(find.widgetWithText(TonalChip, label));
    final filterChip = chipWith(l10n.filters);
    final rowElement = tester.element(
      find.ancestor(
        of: find.widgetWithText(TonalChip, l10n.filters),
        matching: find.byType(DecorationListItem),
      ),
    );
    final scheme = _schemeOf(
      tester,
      find.widgetWithText(TonalChip, l10n.filters),
    );
    expect(filterChip.foregroundColor, scheme.onSurfaceVariant);
    expect(filterChip.color, rowElement.raisedSurfaceLevel.colorOf(scheme));
    expect(filterChip.color, isNot(scheme.tertiaryContainer));
    expect(filterChip.color, isNot(scheme.secondaryContainer));
    final excludeChip = chipWith(l10n.excludeFilter);
    expect(excludeChip.color, scheme.errorContainer);
    expect(excludeChip.foregroundColor, scheme.onErrorContainer);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
