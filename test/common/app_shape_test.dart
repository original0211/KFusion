import 'package:kfusion/ui/shape.dart';
import 'package:kfusion/ui/surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppCorner.fit', () {
    test('takes the largest tier a third of the side can hold', () {
      final cases = <double, double>{
        84: AppCorner.xxl,
        83.9: AppCorner.floating,
        78: AppCorner.floating,
        77.9: AppCorner.xl,
        66: AppCorner.xl,
        65.9: AppCorner.lg,
        60: AppCorner.lg,
        59.9: AppCorner.md,
        48: AppCorner.md,
        47.9: AppCorner.sm,
        24: AppCorner.sm,
        23.9: AppCorner.xs,
        12: AppCorner.xs,
        11.9: AppCorner.none,
        0: AppCorner.none,
      };
      for (final entry in cases.entries) {
        expect(
          AppCorner.fit(entry.key),
          entry.value,
          reason: 'side ${entry.key}',
        );
      }
    });

    test('never steps down as the side grows', () {
      var previous = AppCorner.fit(0);
      for (var side = 0.0; side <= 120; side += 0.5) {
        final corner = AppCorner.fit(side);
        expect(corner, greaterThanOrEqualTo(previous), reason: 'side $side');
        previous = corner;
      }
      expect(previous, AppCorner.xxl);
    });
  });

  group('radius and shape factories', () {
    test('all rounds every corner by the given value', () {
      expect(AppRadius.all(10), BorderRadius.circular(10));
      expect(AppShape.all(10).borderRadius, BorderRadius.circular(10));
    });

    test('top rounds only the top corners', () {
      final resolved = AppRadius.top(10).resolve(TextDirection.ltr);
      expect(resolved.topLeft, const Radius.circular(10));
      expect(resolved.topRight, const Radius.circular(10));
      expect(resolved.bottomLeft, Radius.zero);
      expect(resolved.bottomRight, Radius.zero);
      expect(AppShape.top(10).borderRadius, AppRadius.top(10));
    });

    test('vertical rounds each end by its own value', () {
      final resolved = AppRadius.vertical(
        top: 8,
        bottom: 4,
      ).resolve(TextDirection.ltr);
      expect(resolved.topLeft, const Radius.circular(8));
      expect(resolved.bottomLeft, const Radius.circular(4));
      expect(
        AppShape.vertical(top: 8, bottom: 4).borderRadius,
        AppRadius.vertical(top: 8, bottom: 4),
      );
    });

    test('of keeps the radius it is given', () {
      const radius = BorderRadius.all(Radius.circular(7));
      expect(AppShape.of(radius).borderRadius, radius);
    });

    test('the input shape is the app input border at the md radius', () {
      expect(AppShape.input, isA<AppInputBorder>());
      expect(AppShape.input.borderRadius, AppRadius.md);
      expect(AppShape.input.gapPadding, 4.0);
    });
  });

  group('AppInputBorder', () {
    test('its dimensions are the side width on every edge', () {
      expect(const AppInputBorder().dimensions, const EdgeInsets.all(1));
      const wide = AppInputBorder(borderSide: BorderSide(width: 3));
      expect(wide.dimensions, const EdgeInsets.all(3));
      expect(wide.isOutline, isTrue);
    });

    test('copyWith replaces only the named fields', () {
      const base = AppInputBorder();
      final changed = base.copyWith(gapPadding: 9);
      expect(changed.gapPadding, 9);
      expect(changed.borderSide, base.borderSide);
      expect(changed.borderRadius, base.borderRadius);
      expect(base.copyWith(), base);
    });

    test('scale multiplies the side, the radius and the gap', () {
      const base = AppInputBorder(
        borderSide: BorderSide(width: 2),
        borderRadius: AppRadius.lg,
        gapPadding: 3,
      );
      final scaled = base.scale(2);
      expect(scaled.borderSide.width, 4);
      expect(scaled.borderRadius, AppRadius.lg * 2);
      expect(scaled.gapPadding, 6);
    });

    test('lerping keeps the gap of the end it lands away from', () {
      const from = AppInputBorder(borderRadius: AppRadius.md, gapPadding: 2);
      const to = AppInputBorder(borderRadius: AppRadius.xl, gapPadding: 6);
      final fromLerp = to.lerpFrom(from, 0.5) as AppInputBorder;
      expect(fromLerp.borderRadius, BorderRadius.circular(19));
      expect(fromLerp.gapPadding, 2);
      final toLerp = from.lerpTo(to, 0.5) as AppInputBorder;
      expect(toLerp.borderRadius, BorderRadius.circular(19));
      expect(toLerp.gapPadding, 6);
    });

    test('equality and hashCode read every field', () {
      const base = AppInputBorder();
      expect(const AppInputBorder(), base);
      expect(const AppInputBorder().hashCode, base.hashCode);
      expect(base.copyWith(gapPadding: 5), isNot(base));
      expect(
        base.copyWith(borderSide: const BorderSide(width: 2)),
        isNot(base),
      );
      expect(base.copyWith(borderRadius: AppRadius.sm), isNot(base));
    });
  });

  group('withAppShapes', () {
    final theme = ThemeData(useMaterial3: true).withAppShapes;

    test('cards, dialogs and menus take their settled shapes', () {
      expect(theme.cardTheme.shape, AppShape.xl);
      final dialog = theme.dialogTheme.shape as RoundedSuperellipseBorder;
      expect(dialog.borderRadius, AppRadius.floating);
      expect(dialog.side, theme.colorScheme.cabinRimSide);
      final menu = theme.popupMenuTheme.shape as RoundedSuperellipseBorder;
      expect(menu.borderRadius, AppRadius.floating);
      expect(menu.side, theme.colorScheme.cabinRimSide);
    });

    test('sheets round only their top, at the floating radius', () {
      expect(theme.bottomSheetTheme.shape, AppShape.top(AppCorner.floating));
    });

    test('small surfaces take the small tiers', () {
      expect(theme.snackBarTheme.shape, AppShape.xs);
      expect(theme.chipTheme.shape, AppShape.sm);
      expect(theme.floatingActionButtonTheme.shape, AppShape.md);
    });

    test('fields, indicators and progress take the input and pill shapes', () {
      expect(theme.inputDecorationTheme.border, AppShape.input);
      expect(theme.navigationBarTheme.indicatorShape, AppShape.full);
      expect(theme.navigationRailTheme.indicatorShape, AppShape.full);
      expect(theme.progressIndicatorTheme.borderRadius, AppRadius.full);
    });
  });
}
