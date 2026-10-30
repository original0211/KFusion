import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:kfusion/ui/disc_motif.dart';
import 'package:kfusion/ui/hara.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = 216.0;
const _stroke = 1.3;

final _boundaryKey = GlobalKey();

Widget _harness({required Brightness brightness, required Widget child}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Center(
        child: RepaintBoundary(key: _boundaryKey, child: child),
      ),
    ),
  );
}

Future<ByteData> _capture(WidgetTester tester) async {
  await tester.pump();
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = boundary.toImageSync();
  late ByteData data;
  await tester.runAsync(() async {
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data;
}

(int, int, int) _pixel(ByteData data, int x, int y) {
  final offset = (y * _size.toInt() + x) * 4;
  return (
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

bool _near((int, int, int) pixel, Color color, {int tolerance = 4}) {
  return (pixel.$1 - color.red8).abs() <= tolerance &&
      (pixel.$2 - color.green8).abs() <= tolerance &&
      (pixel.$3 - color.blue8).abs() <= tolerance;
}

extension on Color {
  int get red8 => (r * 255).round();
  int get green8 => (g * 255).round();
  int get blue8 => (b * 255).round();
}

// The point's centre in motif coordinates, from the settled geometry.
(int, int) _dotSite() {
  final center = DiscGeometry.dotCenter(
    const Offset(_size / 2, _size / 2),
    _size / 2 - _stroke,
  );
  return (center.dx.round(), center.dy.round());
}

void main() {
  test('the mark geometry keeps its settled proportions', () {
    expect(DiscGeometry.dotDirection, closeTo(157 * math.pi / 180, 1e-12));
    expect(DiscGeometry.dotDiameterRatio, 0.16);
    expect(DiscGeometry.dotRadius(200), 16);
    final site = DiscGeometry.dotCenter(const Offset(100, 100), 90);
    final ray = site - const Offset(100, 100);
    expect(ray.distance, closeTo(90, 1e-9));
    expect(ray.dx, isNegative);
    expect(ray.dy, isPositive);
  });

  testWidgets('a lit ring paints the vermilion point, light field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        brightness: Brightness.light,
        child: DiscRingMotif(
          size: _size,
          color: HaraPalette.light.ink,
          strokeWidth: _stroke,
          lit: true,
        ),
      ),
    );
    final data = await _capture(tester);
    final (x, y) = _dotSite();
    expect(_near(_pixel(data, x, y), HaraPalette.light.vermilion), isTrue);
    // The ring itself keeps the caller's colour at its top point; the
    // hairline stroke anti-aliases against the field, hence the slack.
    expect(
      _near(_pixel(data, _size ~/ 2, 1), HaraPalette.light.ink, tolerance: 26),
      isTrue,
    );
  });

  testWidgets('an unlit ring leaves the point site empty', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        brightness: Brightness.light,
        child: DiscRingMotif(
          size: _size,
          color: HaraPalette.light.ink,
          strokeWidth: _stroke,
        ),
      ),
    );
    final data = await _capture(tester);
    final (x, y) = _dotSite();
    final site = _pixel(data, x, y);
    expect(_near(site, HaraPalette.light.vermilion), isFalse);
    // The point sits on the ring's mid-line, so the bare ring line is
    // what crosses the site when nothing is lit.
    expect(_near(site, HaraPalette.light.ink, tolerance: 26), isTrue);
  });

  testWidgets('a lit ring paints the dark-field vermilion point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        brightness: Brightness.dark,
        child: DiscRingMotif(
          size: _size,
          color: HaraPalette.dark.ink,
          strokeWidth: _stroke,
          lit: true,
        ),
      ),
    );
    final data = await _capture(tester);
    final (x, y) = _dotSite();
    expect(_near(_pixel(data, x, y), HaraPalette.dark.vermilion), isTrue);
  });

  testWidgets('the flat decoration renders the ring with no point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _harness(
        brightness: Brightness.light,
        child: DashboardDiscMotif(size: _size, color: HaraPalette.light.ink),
      ),
    );
    final ring = tester.widget<DiscRingMotif>(find.byType(DiscRingMotif));
    expect(ring.lit, isFalse);
    final data = await _capture(tester);
    final (x, y) = _dotSite();
    expect(_near(_pixel(data, x, y), HaraPalette.light.vermilion), isFalse);
  });
}
