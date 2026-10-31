import 'package:kfusion/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
).withAppShapes.withAppSurfaces;

final _darkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  ),
).withAppShapes.withAppSurfaces;

ButtonStyle _styleOf(WidgetTester tester, Finder host) {
  final button = tester.widget<FilledButton>(
    find.descendant(of: host, matching: find.byType(FilledButton)).first,
  );
  return button.style!;
}

BorderRadiusGeometry _radiusOf(ButtonStyle style) =>
    (style.shape!.resolve({})! as RoundedSuperellipseBorder).borderRadius;

Color _backgroundOf(ButtonStyle style) => style.backgroundColor!.resolve({})!;

BorderSide _sideOf(ButtonStyle style) => style.side!.resolve({})!;

Future<void> _pumpSection(
  WidgetTester tester, {
  required ThemeData theme,
  required List<Widget> items,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Column(children: [generateSection(items: items)]),
      ),
    ),
  );
}

void main() {
  testWidgets('grouped rows stand flat on the field', (tester) async {
    await _pumpSection(
      tester,
      theme: _theme,
      items: const [
        DecorationListItem(title: Text('first')),
        DecorationListItem(title: Text('second')),
      ],
    );
    final rows = find.byType(DecorationListItem);
    expect(rows, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      final style = _styleOf(tester, rows.at(i));
      expect(_radiusOf(style), BorderRadius.zero);
      expect(_backgroundOf(style), Colors.transparent);
      expect(
        _sideOf(style),
        BorderSide(color: HaraPalette.light.line, width: HaraSpace.hairline),
      );
    }
  });

  testWidgets('grouped rows stand flat in the dark', (tester) async {
    await _pumpSection(
      tester,
      theme: _darkTheme,
      items: const [DecorationListItem(title: Text('only'))],
    );
    final style = _styleOf(tester, find.byType(DecorationListItem));
    expect(_radiusOf(style), BorderRadius.zero);
    expect(_backgroundOf(style), Colors.transparent);
    expect(
      _sideOf(style),
      BorderSide(color: HaraPalette.dark.line, width: HaraSpace.hairline),
    );
  });

  testWidgets('an invalid row keeps the error fill and no edge', (
    tester,
  ) async {
    await _pumpSection(
      tester,
      theme: _theme,
      items: const [DecorationListItem(title: Text('bad'), invalid: true)],
    );
    final style = _styleOf(tester, find.byType(DecorationListItem));
    expect(_backgroundOf(style), _theme.colorScheme.errorContainer);
    expect(_sideOf(style), BorderSide.none);
  });

  testWidgets('a flat card keeps the selection fill; a plain card keeps '
      'the cabin surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: const Scaffold(
          body: Column(
            children: [
              CommonCard(
                flat: true,
                isSelected: true,
                fillsSelection: true,
                child: Text('filled'),
              ),
              CommonCard(flat: true, child: Text('flat')),
              CommonCard(child: Text('plain')),
            ],
          ),
        ),
      ),
    );
    final cards = find.byType(CommonCard);
    expect(cards, findsNWidgets(3));
    final filled = _styleOf(tester, cards.at(0));
    expect(_backgroundOf(filled), _theme.colorScheme.primary);
    expect(_sideOf(filled), BorderSide.none);
    final flat = _styleOf(tester, cards.at(1));
    expect(_backgroundOf(flat), Colors.transparent);
    expect(
      _sideOf(flat),
      BorderSide(color: HaraPalette.light.line, width: HaraSpace.hairline),
    );
    final plain = _styleOf(tester, cards.at(2));
    expect(_backgroundOf(plain), SurfaceLevel.card.colorOf(_theme.colorScheme));
    expect(_sideOf(plain), _theme.colorScheme.cabinRimSide);
    expect(_radiusOf(plain), AppRadius.xl);
  });
}
