import 'package:kfusion/ui/motion.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('the tab fade keeps its settled duration and curve', () {
    expect(fadeTabDuration, const Duration(milliseconds: 220));
    expect(fadeTabCurve, same(Curves.easeInOut));
  });

  group('SpringCurve', () {
    const spring = SpringDescription(mass: 1, stiffness: 100, damping: 10);

    test('starts at zero and lands exactly on one', () {
      final curve = SpringCurve(spring, seconds: 0.5);
      expect(curve.transform(0), 0);
      expect(curve.transform(1), closeTo(1, 1e-9));
    });

    test('pays the residual back linearly over the run', () {
      final curve = SpringCurve(spring, seconds: 0.5);
      final raw = SpringSimulation(spring, 0, 1, 0);
      final residual = 1 - raw.x(0.5);
      for (final t in [0.25, 0.5, 0.75]) {
        expect(
          curve.transform(t),
          closeTo(raw.x(t * 0.5) + residual * t, 1e-9),
          reason: 't $t',
        );
      }
    });

    test('an underdamped spring overshoots before it settles', () {
      final curve = SpringCurve(spring, seconds: 1);
      var peak = 0.0;
      for (var t = 0.0; t <= 1; t += 0.01) {
        final value = curve.transform(t);
        if (value > peak) peak = value;
      }
      expect(peak, greaterThan(1.05));
    });

    test('an overdamped spring approaches without overshooting', () {
      final curve = SpringCurve(
        const SpringDescription(mass: 1, stiffness: 100, damping: 30),
        seconds: 1,
      );
      var previous = 0.0;
      for (var t = 0.0; t <= 1; t += 0.02) {
        final value = curve.transform(t);
        expect(value, lessThanOrEqualTo(1 + 1e-9), reason: 't $t');
        expect(value, greaterThanOrEqualTo(previous), reason: 't $t');
        previous = value;
      }
    });
  });
}
