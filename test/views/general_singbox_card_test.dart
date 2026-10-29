import 'package:kfusion/common/common.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    String statusText = '未运行',
    bool statusIsFailure = false,
    bool showBinary = true,
    bool binaryChecked = true,
    String? binaryLabel,
    bool downloading = false,
    double? progress,
    String? downloadRoute,
    String? downloadError,
    bool showSwitch = false,
    CoreKind selectedCore = CoreKind.mihomo,
    bool mihomoRunning = true,
    bool singBoxRunning = false,
    String failureDetail = '',
    bool switching = false,
    ValueChanged<CoreKind>? onSelectCore,
  }) async {
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        child: Scaffold(
          body: ItemPositionProvider(
            position: ItemPosition.startAndEnd,
            child: Builder(
              builder: (context) => CoreSwitchCard(
                statusText: statusText,
                statusIsFailure: statusIsFailure,
                showBinary: showBinary,
                binaryChecked: binaryChecked,
                binaryLabel: binaryLabel,
                downloading: downloading,
                progress: progress,
                downloadRoute: downloadRoute,
                downloadError: downloadError,
                onDownload: () {},
                showSwitch: showSwitch,
                selectedCore: selectedCore,
                mihomoRunning: mihomoRunning,
                singBoxRunning: singBoxRunning,
                failureDetail: failureDetail,
                switching: switching,
                onSelectCore: onSelectCore ?? (_) {},
                localizations: context.appLocalizations,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // Every visible element of the card must sit inside the card's own rect:
  // the regression this guards is content spilling onto the page.
  void expectAllInsideCard(WidgetTester tester) {
    final cardRect = tester.getRect(find.byType(CoreSwitchCard));
    final inside = find.descendant(
      of: find.byType(CoreSwitchCard),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text ||
            widget is FilledButton ||
            widget is InkWell ||
            widget is LinearProgressIndicator,
      ),
    );
    expect(inside, findsWidgets);
    for (final element in inside.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(
        rect.left >= cardRect.left &&
            rect.right <= cardRect.right &&
            rect.top >= cardRect.top &&
            rect.bottom <= cardRect.bottom,
        isTrue,
        reason: '${element.widget} at $rect escapes the card at $cardRect',
      );
    }
  }

  testWidgets('managed binary found: core rows show, no download offer', (
    tester,
  ) async {
    await pumpCard(
      tester,
      binaryLabel: '应用托管的二进制（版本 1.14.4）：C:\\data\\singbox\\sing-box.exe',
      showSwitch: true,
    );
    expect(find.text('核心切换'), findsOneWidget);
    expect(find.text('未运行'), findsNWidgets(2));
    expect(find.text('运行中'), findsOneWidget);
    expect(find.textContaining('应用托管的二进制'), findsOneWidget);
    expect(find.text('mihomo'), findsOneWidget);
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.byType(SelectionCheck), findsOneWidget);
    // The card's mark reads in palette ink; the scheme primary stays the
    // default only for surfaces that do not pass a color.
    expect(
      tester.widget<SelectionCheck>(find.byType(SelectionCheck)).color,
      HaraPalette.light.ink,
    );
    expect(find.text('下载 sing-box'), findsNothing);
    expectAllInsideCard(tester);
  });

  testWidgets('manual binary found reads as one clean line', (tester) async {
    await pumpCard(tester, binaryLabel: '二进制：D:\\tools\\sing-box.exe');
    expect(find.text('二进制：D:\\tools\\sing-box.exe'), findsOneWidget);
    expectAllInsideCard(tester);
  });

  testWidgets('tapping the other core asks for a switch to it', (tester) async {
    CoreKind? requested;
    await pumpCard(
      tester,
      showSwitch: true,
      selectedCore: CoreKind.mihomo,
      onSelectCore: (target) => requested = target,
    );
    await tester.tap(find.text('sing-box'));
    await tester.pump();
    expect(requested, CoreKind.singbox);
    expectAllInsideCard(tester);
  });

  testWidgets('while switching the core rows are inert', (tester) async {
    CoreKind? requested;
    await pumpCard(
      tester,
      statusText: '正在停止当前核心…',
      showSwitch: true,
      selectedCore: CoreKind.singbox,
      switching: true,
      onSelectCore: (target) => requested = target,
    );
    for (final name in ['mihomo', 'sing-box']) {
      final row = tester
          .widgetList<InkWell>(
            find.ancestor(of: find.text(name), matching: find.byType(InkWell)),
          )
          .first;
      expect(row.onTap, isNull);
    }
    await tester.tap(find.text('mihomo'));
    await tester.pump();
    expect(requested, isNull);
    expect(find.text('正在停止当前核心…'), findsOneWidget);
    expectAllInsideCard(tester);
  });

  testWidgets('a failure detail renders under the failure sentence', (
    tester,
  ) async {
    await pumpCard(
      tester,
      statusText: 'sing-box 启动失败，已恢复使用 mihomo。请稍后重试。',
      statusIsFailure: true,
      failureDetail: 'FATAL[0000] unknown outbound type: block',
      showSwitch: true,
      selectedCore: CoreKind.mihomo,
    );
    expect(
      find.text('原始信息：FATAL[0000] unknown outbound type: block'),
      findsOneWidget,
    );
    expectAllInsideCard(tester);
  });

  testWidgets('a failure sentence renders in the error color', (tester) async {
    await pumpCard(
      tester,
      statusText: 'mihomo 启动失败，已恢复使用 sing-box。请稍后重试。',
      statusIsFailure: true,
      showSwitch: true,
      selectedCore: CoreKind.singbox,
    );
    final text = tester.widget<Text>(
      find.text('mihomo 启动失败，已恢复使用 sing-box。请稍后重试。'),
    );
    final context = tester.element(find.text('核心切换'));
    expect(text.style?.color, Theme.of(context).colorScheme.error);
    expectAllInsideCard(tester);
  });

  testWidgets('missing binary: download offer inside the card, no switch', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('未找到 sing-box 二进制'), findsOneWidget);
    expect(find.textContaining('tools/singbox/README.md'), findsOneWidget);
    expect(find.text('下载 sing-box'), findsOneWidget);
    expect(find.text('mihomo'), findsNothing);
    expect(find.text('sing-box'), findsNothing);
    expectAllInsideCard(tester);
  });

  testWidgets('downloading: progress and route share one row in the card', (
    tester,
  ) async {
    await pumpCard(
      tester,
      downloading: true,
      progress: 0.42,
      downloadRoute: '系统代理',
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('下载 sing-box'), findsNothing);
    final progressText = find.textContaining('系统代理');
    expect(progressText, findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
    final barRect = tester.getRect(find.byType(LinearProgressIndicator));
    final textRect = tester.getRect(progressText);
    expect((barRect.center.dy - textRect.center.dy).abs(), lessThan(2));
    expectAllInsideCard(tester);
  });

  testWidgets('failed download: the error and a retry stay in the card', (
    tester,
  ) async {
    await pumpCard(
      tester,
      downloadError: '下载 sing-box 失败：已依次尝试系统代理、直连，均未成功。请检查网络后重试。',
    );
    expect(find.textContaining('已依次尝试系统代理、直连'), findsOneWidget);
    expect(find.text('重试下载'), findsOneWidget);
    expectAllInsideCard(tester);
  });

  testWidgets('without a binary section the card holds title and core rows', (
    tester,
  ) async {
    await pumpCard(
      tester,
      statusText: 'Android sing-box VPN 运行时（真机待验）',
      showBinary: false,
      binaryChecked: false,
      showSwitch: true,
      selectedCore: CoreKind.singbox,
      mihomoRunning: false,
      singBoxRunning: true,
    );
    expect(find.text('核心切换'), findsOneWidget);
    expect(find.text('mihomo'), findsOneWidget);
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('未找到 sing-box 二进制'), findsNothing);
    expectAllInsideCard(tester);
  });

  group('coreSwitchSelectedCore', () {
    test('an in-flight switch selects its target', () {
      expect(
        coreSwitchSelectedCore(
          status: const SingBoxStatus(
            state: SingBoxState.starting,
            switchTarget: CoreKind.singbox,
          ),
          activeKind: CoreKind.mihomo,
          mihomoRunning: true,
        ),
        CoreKind.singbox,
      );
    });

    test('a running sing-box wins over the persisted kind', () {
      expect(
        coreSwitchSelectedCore(
          status: const SingBoxStatus(state: SingBoxState.running),
          activeKind: CoreKind.mihomo,
          mihomoRunning: false,
        ),
        CoreKind.singbox,
      );
    });

    test('a running mihomo wins when sing-box is idle', () {
      expect(
        coreSwitchSelectedCore(
          status: const SingBoxStatus(state: SingBoxState.idle),
          activeKind: CoreKind.singbox,
          mihomoRunning: true,
        ),
        CoreKind.mihomo,
      );
    });

    test('with nothing running the persisted kind shows', () {
      expect(
        coreSwitchSelectedCore(
          status: const SingBoxStatus(state: SingBoxState.idle),
          activeKind: CoreKind.singbox,
          mihomoRunning: false,
        ),
        CoreKind.singbox,
      );
    });
  });

  group('coreSwitchStageText', () {
    test('every stage names itself, with the target where it matters', () {
      SingBoxStatus at(CoreSwitchStage stage) => SingBoxStatus(
        state: SingBoxState.starting,
        switchStage: stage,
        switchTarget: CoreKind.singbox,
      );
      expect(
        coreSwitchStageText(l10n, at(CoreSwitchStage.stopping)),
        '正在停止当前核心…',
      );
      expect(
        coreSwitchStageText(l10n, at(CoreSwitchStage.starting)),
        '正在启动 sing-box…',
      );
      expect(
        coreSwitchStageText(l10n, at(CoreSwitchStage.applying)),
        '正在应用当前配置…',
      );
      expect(
        coreSwitchStageText(l10n, at(CoreSwitchStage.restoring)),
        '切换失败，正在恢复原核心…',
      );
    });

    test('stage detail rides along, as a download percent does', () {
      const status = SingBoxStatus(
        state: SingBoxState.starting,
        switchStage: CoreSwitchStage.starting,
        switchTarget: CoreKind.singbox,
        stageDetail: '42%',
      );
      expect(coreSwitchStageText(l10n, status), '正在启动 sing-box… 42%');
    });
  });

  group('coreSwitchFailureText', () {
    SingBoxStatus failed(
      CoreSwitchFailure failure, {
      bool restored = true,
      CoreSwitchStage? failedStage = CoreSwitchStage.starting,
      CoreKind? from = CoreKind.mihomo,
    }) {
      return SingBoxStatus(
        state: SingBoxState.idle,
        switchTarget: CoreKind.singbox,
        switchFrom: from,
        failure: failure,
        failedStage: failedStage,
        restored: restored,
      );
    }

    test('no failure sentence ever leaks a raw exception string', () {
      for (final failure in CoreSwitchFailure.values) {
        for (final restored in [true, false]) {
          final text = coreSwitchFailureText(
            l10n,
            failed(failure, restored: restored),
          );
          expect(text, isNotEmpty, reason: '$failure restored=$restored');
          expect(text, isNot(contains('StateError')), reason: '$failure');
          expect(text, isNot(contains('Bad state')), reason: '$failure');
          expect(text, isNot(contains('Exception')), reason: '$failure');
        }
      }
    });

    test('a preflight rejection is explained before anything moved', () {
      expect(
        coreSwitchFailureText(
          l10n,
          failed(CoreSwitchFailure.profileNotRenderable, failedStage: null),
        ),
        '当前配置无法转换为 sing-box 可用的配置，切换已取消。请调整配置后重试。',
      );
      expect(
        coreSwitchFailureText(
          l10n,
          failed(CoreSwitchFailure.noProfile, failedStage: null),
        ),
        '没有选中的配置。请先到配置页选择一个配置，再切换核心。',
      );
    });

    test('an unresponsive check does not blame the profile', () {
      expect(
        coreSwitchFailureText(
          l10n,
          failed(CoreSwitchFailure.checkUnresponsive, failedStage: null),
        ),
        'sing-box 服务未响应配置校验，切换已取消。这不代表配置无效，请稍候重试。',
      );
    });

    test('a restored start failure names both cores', () {
      expect(
        coreSwitchFailureText(l10n, failed(CoreSwitchFailure.startFailed)),
        'sing-box 启动失败，已恢复使用 mihomo。请稍后重试。',
      );
    });

    test('an unrestored failure points at the dashboard, whatever failed', () {
      expect(
        coreSwitchFailureText(
          l10n,
          failed(CoreSwitchFailure.startFailed, restored: false),
        ),
        '切换失败，且原核心也未能自动恢复。请到仪表盘手动启动核心。',
      );
      expect(
        coreSwitchFailureText(
          l10n,
          failed(CoreSwitchFailure.applyFailed, restored: false),
        ),
        '切换失败，且原核心也未能自动恢复。请到仪表盘手动启动核心。',
      );
    });

    test('a stop failure keeps the blame on the stop step', () {
      expect(
        coreSwitchFailureText(
          l10n,
          failed(
            CoreSwitchFailure.stopFailed,
            failedStage: CoreSwitchStage.stopping,
          ),
        ),
        '当前核心未能停止，切换已取消。请稍后重试，或先在仪表盘手动停止核心后再切换。',
      );
    });
  });
}
