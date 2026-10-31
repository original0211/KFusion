import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:kfusion/common/app_localizations.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/ui/disc_motif.dart';
import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/null_status.dart';
import 'package:kfusion/ui/paged_sheet.dart';
import 'package:kfusion/ui/sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _reducedMotion = MediaQueryData(disableAnimations: true);

Widget _switcher({
  required bool isEmpty,
  bool isLoading = false,
  bool isSearching = false,
  String? loadingLabel,
  String label = 'Nothing here',
  MediaQueryData? mediaQuery,
}) {
  final switcher = NullStatusSwitcher(
    isLoading: isLoading,
    isEmpty: isEmpty,
    isSearching: isSearching,
    loadingStatus: loadingLabel == null
        ? null
        : NullStatus(label: loadingLabel),
    nullStatus: NullStatus(label: label),
    child: const Text('content', key: ValueKey('content')),
  );
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      AppUiLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: mediaQuery == null
        ? switcher
        : MediaQuery(data: mediaQuery, child: switcher),
  );
}

void main() {
  testWidgets('renders every semantic illustration', (tester) async {
    for (final illustration in NullStatusIllustration.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: NullStatus(label: 'Nothing here', illustration: illustration),
        ),
      );
      await tester.pumpAndSettle();

      final background = find.byKey(ValueKey(illustration));
      expect(background, findsOneWidget);
      expect(tester.getSize(background), const Size.square(160));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reads each member as its own line glyph in the ink steps', (
    tester,
  ) async {
    const glyphs = <NullStatusIllustration, Glyph>{
      NullStatusIllustration.data: AppGlyphs.resources,
      NullStatusIllustration.logs: AppGlyphs.logs,
      NullStatusIllustration.dns: AppGlyphs.dns,
      NullStatusIllustration.tun: AppGlyphs.vpn,
      NullStatusIllustration.wifi: AppGlyphs.wifi,
      NullStatusIllustration.apps: AppGlyphs.appsList,
      NullStatusIllustration.permission: AppGlyphs.lock,
      NullStatusIllustration.camera: AppGlyphs.camera,
      NullStatusIllustration.error: AppGlyphs.error,
      NullStatusIllustration.search: AppGlyphs.search,
    };
    for (final type in NullStatusIllustration.values) {
      await tester.pumpWidget(
        MaterialApp(home: EmptyIllustration(type: type, dimension: 160)),
      );
      await tester.pump();

      final paint = tester.widget<CustomPaint>(find.byKey(ValueKey(type)));
      final painter = paint.painter as dynamic;
      expect(painter.glyph as Glyph, glyphs[type], reason: '$type');
      expect(painter.ruleColor as Color, HaraPalette.light.dim);
      if (type == NullStatusIllustration.error) {
        final scheme = Theme.of(
          tester.element(find.byType(EmptyIllustration)),
        ).colorScheme;
        expect(painter.glyphColor as Color, scheme.error);
        expect(painter.frameColor as Color, scheme.error);
      } else {
        expect(painter.glyphColor as Color, HaraPalette.light.ink);
        expect(painter.frameColor as Color, HaraPalette.light.sub);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the illustration runs no entrance animation of its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmptyIllustration(
          type: NullStatusIllustration.data,
          dimension: 160,
        ),
      ),
    );
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('paints no chromatic fill, and red only for the error member', (
    tester,
  ) async {
    Future<({int chromatic, int redDominant, int dark})> census(
      NullStatusIllustration type,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: Colors.white,
                child: EmptyIllustration(type: type, dimension: 160),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      late ByteData bytes;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      });
      var chromatic = 0, redDominant = 0, dark = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        final r = bytes.getUint8(i);
        final g = bytes.getUint8(i + 1);
        final b = bytes.getUint8(i + 2);
        final spread =
            math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
        if (spread > 24) {
          chromatic++;
          if (r > g && r > b && r - b > 12) redDominant++;
        }
        if (r < 100 && g < 100 && b < 100) dark++;
      }
      return (chromatic: chromatic, redDominant: redDominant, dark: dark);
    }

    final data = await census(NullStatusIllustration.data);
    expect(data.chromatic, 0);
    expect(data.dark, greaterThan(200));

    final error = await census(NullStatusIllustration.error);
    expect(error.chromatic, greaterThan(200));
    expect(error.redDominant, error.chromatic);
  });

  testWidgets('the brand variant stands the disc mark for the illustration', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NullStatus.brand(label: 'Nothing here')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DashboardDiscMotif), findsOneWidget);
    expect(find.byType(EmptyIllustration), findsNothing);
    expect(
      tester.getSize(find.byType(DashboardDiscMotif)),
      const Size.square(128),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shrinks the illustration on a short screen', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(home: NullStatus(label: 'Nothing here')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey(NullStatusIllustration.data))),
      const Size.square(120),
    );
  });

  testWidgets('scrolls instead of overflowing a short box', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 180,
            child: NullStatus(
              label: 'Nothing here',
              description: 'A description long enough to wrap onto more lines',
              action: FilledButton(
                onPressed: () {},
                child: const Text('Retry'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(NullStatus), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Retry').hitTestable(), findsOneWidget);
  });

  testWidgets('keeps data as the default illustration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NullStatus(label: 'Nothing here')),
    );

    expect(
      find.byKey(const ValueKey(NullStatusIllustration.data)),
      findsOneWidget,
    );
  });

  testWidgets('staggers its entrance when shown on its own', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NullStatus(label: 'Nothing here', action: Text('Retry')),
      ),
    );

    final fades = find.descendant(
      of: find.byType(NullStatus),
      matching: find.byType(FadeTransition),
    );
    expect(fades, findsNWidgets(3));
    for (final fade in tester.widgetList<FadeTransition>(fades)) {
      expect(fade.opacity.value, 0);
    }

    await tester.pumpAndSettle();
    for (final fade in tester.widgetList<FadeTransition>(fades)) {
      expect(fade.opacity.value, 1);
    }
  });

  testWidgets('staggers its entrance when hosted by a switcher', (
    tester,
  ) async {
    await tester.pumpWidget(_switcher(isEmpty: true));

    final fades = find.descendant(
      of: find.byType(NullStatus),
      matching: find.byType(FadeTransition),
    );
    expect(fades, findsNWidgets(2));

    await tester.pumpAndSettle();
    for (final fade in tester.widgetList<FadeTransition>(fades)) {
      expect(fade.opacity.value, 1);
    }
  });

  testWidgets('skips its own fade while the route is still animating in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NullStatus(label: 'Nothing here'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.descendant(
        of: find.byType(NullStatus),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('skips its own fade while its sheet is still sliding in', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestApp(
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 900)),
        ],
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSheet<void>(
              context: context,
              props: nestedPagedSheetProps,
              builder: (_) => NestedPagedSheet(
                builder: (_) => const NullStatus(label: 'Nothing here'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NullStatus), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NullStatus),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('skips the entrance fade under reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: _reducedMotion,
          child: NullStatus(label: 'Nothing here', action: Text('Retry')),
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(NullStatus),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('fades between the empty state and content', (tester) async {
    await tester.pumpWidget(_switcher(isEmpty: true));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byKey(const ValueKey('content')), findsNothing);

    await tester.pumpWidget(_switcher(isEmpty: false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
    expect(find.byType(ScaleTransition), findsNWidgets(2));

    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first load done within a route transition shows no status', (
    tester,
  ) async {
    await tester.pumpWidget(
      _switcher(isEmpty: true, isLoading: true, loadingLabel: 'Loading'),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(NullStatus), findsNothing);

    await tester.pumpWidget(_switcher(isEmpty: false, loadingLabel: 'Loading'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NullStatus), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });

  testWidgets('a first load that outlasts a route transition shows its '
      'loading status until the content arrives', (tester) async {
    await tester.pumpWidget(
      _switcher(isEmpty: true, isLoading: true, loadingLabel: 'Loading'),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Loading'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading'), findsOneWidget);
    expect(find.byKey(const ValueKey('content')), findsNothing);

    await tester.pumpWidget(_switcher(isEmpty: false, loadingLabel: 'Loading'));
    await tester.pumpAndSettle();
    expect(find.text('Loading'), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });

  testWidgets('a first load that finds nothing leaves the loading status for '
      'the empty one', (tester) async {
    await tester.pumpWidget(
      _switcher(isEmpty: true, isLoading: true, loadingLabel: 'Loading'),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Loading'), findsOneWidget);

    await tester.pumpWidget(_switcher(isEmpty: true, loadingLabel: 'Loading'));
    await tester.pumpAndSettle();
    expect(find.text('Loading'), findsNothing);
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('a search that matches nothing has its own empty state', (
    tester,
  ) async {
    await tester.pumpWidget(_switcher(isEmpty: true, isSearching: true));
    await tester.pumpAndSettle();

    expect(find.text(AppLocalizations.current.noSearchResults), findsOneWidget);
    expect(
      find.byKey(const ValueKey(NullStatusIllustration.search)),
      findsOneWidget,
    );
    expect(find.text('Nothing here'), findsNothing);

    await tester.pumpWidget(_switcher(isEmpty: false, isSearching: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('content')), findsOneWidget);

    await tester.pumpWidget(_switcher(isEmpty: true));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('exits the empty state faster than it enters', (tester) async {
    await tester.pumpWidget(_switcher(isEmpty: true));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_switcher(isEmpty: false));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump();

    expect(find.text('Nothing here'), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows neither side while the first load is pending', (
    tester,
  ) async {
    await tester.pumpWidget(_switcher(isEmpty: true, isLoading: true));
    await tester.pumpAndSettle();

    expect(find.byType(NullStatus), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsNothing);
  });

  testWidgets('reveals the first loaded content without a transition', (
    tester,
  ) async {
    await tester.pumpWidget(_switcher(isEmpty: true, isLoading: true));
    await tester.pump();

    await tester.pumpWidget(_switcher(isEmpty: false));
    await tester.pump();

    expect(find.byType(NullStatus), findsNothing);
    final fades = find.ancestor(
      of: find.byKey(const ValueKey('content')),
      matching: find.byType(FadeTransition),
    );
    for (final fade in tester.widgetList<FadeTransition>(fades)) {
      expect(fade.opacity.value, 1);
    }
  });

  testWidgets('keeps the shown side when a later load starts', (tester) async {
    await tester.pumpWidget(_switcher(isEmpty: false));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_switcher(isEmpty: false, isLoading: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });

  testWidgets('gives the content the full body size', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: NullStatusSwitcher(
              isEmpty: false,
              nullStatus: NullStatus(label: 'Nothing here'),
              child: ColoredBox(key: ValueKey('content'), color: Colors.red),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('content'))),
      const Size(300, 500),
    );
  });

  testWidgets('switches immediately under reduced motion', (tester) async {
    await tester.pumpWidget(
      _switcher(isEmpty: true, mediaQuery: _reducedMotion),
    );
    await tester.pump();

    await tester.pumpWidget(
      _switcher(isEmpty: false, mediaQuery: _reducedMotion),
    );
    await tester.pump();

    expect(find.text('Nothing here'), findsNothing);
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });
}
