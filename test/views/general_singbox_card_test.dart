import 'package:kfusion/common/common.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCard(
    WidgetTester tester, {
    String statusText = '未运行',
    bool showBinary = true,
    bool binaryChecked = true,
    String? binaryLabel,
    bool downloading = false,
    double? progress,
    String? downloadRoute,
    String? downloadError,
    bool showToggle = false,
    bool running = false,
    bool starting = false,
  }) async {
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        child: Scaffold(
          body: ItemPositionProvider(
            position: ItemPosition.startAndEnd,
            child: Builder(
              builder: (context) => SingBoxStatusCard(
                statusText: statusText,
                showBinary: showBinary,
                binaryChecked: binaryChecked,
                binaryLabel: binaryLabel,
                downloading: downloading,
                progress: progress,
                downloadRoute: downloadRoute,
                downloadError: downloadError,
                onDownload: () {},
                showToggle: showToggle,
                running: running,
                starting: starting,
                onToggle: () {},
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
  // the regression this guards is content spilling onto the page. The card
  // itself is a FilledButton (CommonCard), so it is part of the scan.
  void expectAllInsideCard(WidgetTester tester) {
    final cardRect = tester.getRect(find.byType(CommonCard));
    final inside = find.descendant(
      of: find.byType(SingBoxStatusCard),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text ||
            widget is FilledButton ||
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

  testWidgets('managed binary found: one start button, no download offer', (
    tester,
  ) async {
    await pumpCard(
      tester,
      binaryLabel: '应用托管的二进制（版本 1.14.4）：C:\\data\\singbox\\sing-box.exe',
      showToggle: true,
    );
    expect(find.text('sing-box 核心'), findsOneWidget);
    expect(find.text('未运行'), findsOneWidget);
    expect(find.textContaining('应用托管的二进制'), findsOneWidget);
    expect(find.text('启动 sing-box'), findsOneWidget);
    expect(find.text('下载 sing-box'), findsNothing);
    expectAllInsideCard(tester);
  });

  testWidgets('manual binary found reads as one clean line', (tester) async {
    await pumpCard(
      tester,
      binaryLabel: '二进制：D:\\tools\\sing-box.exe',
      showToggle: true,
    );
    expect(find.text('二进制：D:\\tools\\sing-box.exe'), findsOneWidget);
    expect(find.text('启动 sing-box'), findsOneWidget);
    expectAllInsideCard(tester);
  });

  testWidgets('running state offers stop and disables it while starting', (
    tester,
  ) async {
    await pumpCard(
      tester,
      statusText: '运行中',
      binaryLabel: '二进制：D:\\tools\\sing-box.exe',
      showToggle: true,
      running: true,
      starting: true,
    );
    // The card itself is a FilledButton holding the same text deeper in
    // its tree; the toggle is the one whose direct child is the label.
    final toggle = find.byWidgetPredicate(
      (widget) =>
          widget is FilledButton &&
          widget.child is Text &&
          (widget.child as Text).data == '停止 sing-box',
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<FilledButton>(toggle).onPressed, isNull);
    expectAllInsideCard(tester);
  });

  testWidgets('missing binary: download offer inside the card, no toggle', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('未找到 sing-box 二进制'), findsOneWidget);
    expect(find.textContaining('tools/singbox/README.md'), findsOneWidget);
    expect(find.text('下载 sing-box'), findsOneWidget);
    expect(find.text('启动 sing-box'), findsNothing);
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
    expect(find.text('启动 sing-box'), findsNothing);
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

  testWidgets('without a binary section the card holds title and toggle', (
    tester,
  ) async {
    await pumpCard(
      tester,
      statusText: 'Android sing-box VPN 运行时（真机待验）',
      showBinary: false,
      binaryChecked: false,
      showToggle: true,
    );
    expect(find.text('启动 sing-box'), findsOneWidget);
    expect(find.text('未找到 sing-box 二进制'), findsNothing);
    expectAllInsideCard(tester);
  });
}
