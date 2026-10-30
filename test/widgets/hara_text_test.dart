import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/metrics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Future<BuildContext> _context(
  WidgetTester tester, {
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return context;
}

void main() {
  testWidgets('the text scale keeps its sizes, weights and tracking', (
    tester,
  ) async {
    final context = await _context(tester);
    const color = Color(0xFF222222);
    void check(
      TextStyle style, {
      required double size,
      FontWeight weight = FontWeight.w400,
      double? letterSpacing,
      bool mono = false,
    }) {
      expect(style.fontSize, size);
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, letterSpacing);
      expect(style.color, color);
      expect(
        style.fontFeatures,
        mono ? const [FontFeature.tabularFigures()] : isNull,
      );
    }

    check(HaraText.brand(context, color), size: 10, letterSpacing: 3.4);
    check(HaraText.pageTitle(context, color), size: 20);
    check(
      HaraText.status(context, color),
      size: 15,
      weight: FontWeight.w500,
      letterSpacing: 6,
    );
    check(HaraText.statusNode(context, color), size: 12.5);
    check(HaraText.dataKey(context, color), size: 11.5, letterSpacing: 2.2);
    check(
      HaraText.dataValue(context, color),
      size: 13,
      weight: FontWeight.w500,
      mono: true,
    );
    check(HaraText.dataUnit(context, color), size: 11.5);
    check(
      HaraText.mode(context, color, selected: true),
      size: 13.5,
      weight: FontWeight.w500,
    );
    check(HaraText.mode(context, color, selected: false), size: 13.5);
    check(HaraText.sectionTitle(context, color), size: 11, letterSpacing: 3);
    check(
      HaraText.nodeName(context, color, current: true),
      size: 15,
      weight: FontWeight.w600,
    );
    check(HaraText.nodeName(context, color, current: false), size: 15);
    check(
      HaraText.delay(context, color),
      size: 12.5,
      weight: FontWeight.w500,
      mono: true,
    );
    check(HaraText.delayUnit(context, color), size: 12);
    check(HaraText.untested(context, color), size: 12);
    check(
      HaraText.profileName(context, color, current: true),
      size: 17,
      weight: FontWeight.w600,
    );
    check(HaraText.profileName(context, color, current: false), size: 17);
    check(HaraText.profileMeta(context, color), size: 12);
    check(HaraText.inUse(context, color), size: 11, letterSpacing: 2);
    check(HaraText.addRow(context, color), size: 14.5);
    check(HaraText.addRowArrow(context, color), size: 14);
    check(
      HaraText.navLabel(context, color, current: true),
      size: 12.5,
      weight: FontWeight.w500,
    );
    check(HaraText.navLabel(context, color, current: false), size: 12.5);
    check(HaraText.pageAction(context, color), size: 12.5);
    check(HaraText.action(context, color), size: 13.5, weight: FontWeight.w500);
    check(HaraText.payload(context, color), size: 12.5, mono: true);
  });

  test('the space scale keeps its settled measurements', () {
    const expected = <double>[
      HaraSpace.hairline,
      HaraSpace.pageInset,
      HaraSpace.navHeight,
      HaraSpace.navTopPadding,
      HaraSpace.navUnderlineGap,
      HaraSpace.navUnderlineWidth,
      HaraSpace.navUnderlineHeight,
      HaraSpace.railWidth,
      HaraSpace.contentMaxWidth,
      HaraSpace.wideContentMaxWidth,
      HaraSpace.ringSize,
      HaraSpace.ringStroke,
      HaraSpace.ringEmpty,
      HaraSpace.ringCompact,
      HaraSpace.dotStatus,
      HaraSpace.dotRow,
      HaraSpace.dotNameGap,
      HaraSpace.modeUnderline,
      HaraSpace.modeUnderlineGap,
      HaraSpace.modeItemGap,
      HaraSpace.brandTopGap,
      HaraSpace.ringTopGap,
      HaraSpace.statusTopGap,
      HaraSpace.nodeTopGap,
      HaraSpace.dataRowVertical,
      HaraSpace.listToModeGap,
      HaraSpace.modeToNavGap,
      HaraSpace.titleTopGap,
      HaraSpace.titleToFirstGroup,
      HaraSpace.groupGap,
      HaraSpace.sectionTitleGap,
      HaraSpace.nodeRowVertical,
      HaraSpace.titleToList,
      HaraSpace.profileRowVertical,
      HaraSpace.profileNameToMeta,
      HaraSpace.profileMetaGap,
      HaraSpace.listToAddGap,
      HaraSpace.addRowVertical,
    ];
    expect(expected, [
      0.7,
      28,
      64,
      15,
      6,
      18,
      2,
      200,
      720,
      960,
      216,
      1.3,
      72,
      28,
      7,
      6,
      9,
      1.2,
      5,
      30,
      12,
      58,
      32,
      11,
      13.5,
      34,
      30,
      24,
      42,
      36,
      8,
      14.5,
      38,
      20,
      8,
      3,
      46,
      15,
    ]);
  });

  testWidgets('the hairline is one palette line at the settled height', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HaraHairline())),
    );
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(HaraHairline),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.color, HaraPalette.light.line);
    expect(tester.getSize(find.byType(HaraHairline)).height, 0.7);
  });

  testWidgets('the hairline takes an override colour when given one', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HaraHairline(color: Color(0xFF123456))),
      ),
    );
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(HaraHairline),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(box.color, const Color(0xFF123456));
  });

  testWidgets('the dot is a vermilion circle of the given size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: HaraDot(size: 7)),
      ),
    );
    expect(tester.getSize(find.byType(HaraDot)), const Size(7, 7));
    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, HaraPalette.dark.vermilion);
    expect(decoration.shape, BoxShape.circle);
  });

  testWidgets('the toggle mark shows an ink dot and word when on, and a '
      'dim word with an empty slot when off', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HaraToggleMark(value: true, word: 'on')),
      ),
    );
    expect(find.text('on'), findsOneWidget);
    var word = tester.widget<Text>(find.text('on'));
    expect(word.style?.color, HaraPalette.light.ink);
    expect(
      find.descendant(
        of: find.byType(HaraToggleMark),
        matching: find.byType(Container),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HaraToggleMark(value: false, word: 'off')),
      ),
    );
    word = tester.widget<Text>(find.text('off'));
    expect(word.style?.color, HaraPalette.light.dim);
    expect(
      find.descendant(
        of: find.byType(HaraToggleMark),
        matching: find.byType(Container),
      ),
      findsNothing,
    );
  });

  group('adaptive sizes', () {
    testWidgets('grow at half the text scale rate', (tester) async {
      final context = await _context(
        tester,
        textScaler: const TextScaler.linear(2),
      );
      expect(10.ap(context), 15);
    });

    testWidgets('never grow past the raw size, but shrink with the text', (
      tester,
    ) async {
      var context = await _context(
        tester,
        textScaler: const TextScaler.linear(2),
      );
      expect(10.mAp(context), 10);
      context = await _context(
        tester,
        textScaler: const TextScaler.linear(0.5),
      );
      expect(10.ap(context), 7.5);
      expect(10.mAp(context), 7.5);
    });

    testWidgets('the shared insets follow the capped scale', (tester) async {
      var context = await _context(tester);
      expect(baseInfoEdgeInsetsOf(context), const EdgeInsets.all(16));
      expect(
        listHeaderPaddingOf(context),
        const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      );
      context = await _context(
        tester,
        textScaler: const TextScaler.linear(0.5),
      );
      expect(baseInfoEdgeInsetsOf(context), const EdgeInsets.all(12));
      expect(
        listHeaderPaddingOf(context),
        const EdgeInsets.only(left: 12, right: 12, top: 18, bottom: 6),
      );
    });
  });
}
