import 'dart:math' as math;
import 'dart:ui' show ClipOp, lerpDouble;

import 'package:kfusion/ui/surface.dart';
import 'package:material_ui/material_ui.dart';

/// Corner radii. A surface takes one of the main tiers — [xl] for a card,
/// [lg] for a row card, [floating] for the dock, dialogs and menus, [md]
/// for a block inside a card, [sm] for a small mark or chip, [full] for a
/// pill — rather than a step in between; [xs] and [xxl] serve the steps of
/// [AppCorner.fit] and sheets, and [alert] is a dialog's own.
abstract final class AppCorner {
  static const double none = 0;

  /// The Hara A tier declares its corners, and the declaration is zero.
  static const double hara = none;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 22;
  static const double floating = 26;
  static const double xxl = 28;

  /// UIAlertController's corner on iOS 27, rounder than a sheet's.
  static const double alert = 34;
  static const double full = 1000;

  static double fit(double shortestSide) {
    final limit = shortestSide / 3;
    if (limit >= xxl) return xxl;
    if (limit >= floating) return floating;
    if (limit >= xl) return xl;
    if (limit >= lg) return lg;
    if (limit >= md) return md;
    if (limit >= sm) return sm;
    if (limit >= xs) return xs;
    return none;
  }
}

abstract final class AppRadius {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius hara = none;
  static const BorderRadius xs = BorderRadius.all(
    Radius.circular(AppCorner.xs),
  );
  static const BorderRadius sm = BorderRadius.all(
    Radius.circular(AppCorner.sm),
  );
  static const BorderRadius md = BorderRadius.all(
    Radius.circular(AppCorner.md),
  );
  static const BorderRadius lg = BorderRadius.all(
    Radius.circular(AppCorner.lg),
  );
  static const BorderRadius xl = BorderRadius.all(
    Radius.circular(AppCorner.xl),
  );
  static const BorderRadius floating = BorderRadius.all(
    Radius.circular(AppCorner.floating),
  );
  static const BorderRadius xxl = BorderRadius.all(
    Radius.circular(AppCorner.xxl),
  );
  static const BorderRadius full = BorderRadius.all(
    Radius.circular(AppCorner.full),
  );

  static BorderRadius all(double corner) => BorderRadius.circular(corner);

  static BorderRadius top(double corner) =>
      BorderRadius.vertical(top: Radius.circular(corner));

  static BorderRadius vertical({
    double top = AppCorner.none,
    double bottom = AppCorner.none,
  }) => BorderRadius.vertical(
    top: Radius.circular(top),
    bottom: Radius.circular(bottom),
  );
}

abstract final class AppShape {
  static const RoundedSuperellipseBorder none = RoundedSuperellipseBorder();
  static const RoundedSuperellipseBorder hara = none;
  static const RoundedSuperellipseBorder xs = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xs,
  );
  static const RoundedSuperellipseBorder sm = RoundedSuperellipseBorder(
    borderRadius: AppRadius.sm,
  );
  static const RoundedSuperellipseBorder md = RoundedSuperellipseBorder(
    borderRadius: AppRadius.md,
  );
  static const RoundedSuperellipseBorder lg = RoundedSuperellipseBorder(
    borderRadius: AppRadius.lg,
  );
  static const RoundedSuperellipseBorder xl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xl,
  );
  static const RoundedSuperellipseBorder floating = RoundedSuperellipseBorder(
    borderRadius: AppRadius.floating,
  );
  static const RoundedSuperellipseBorder xxl = RoundedSuperellipseBorder(
    borderRadius: AppRadius.xxl,
  );
  static const RoundedSuperellipseBorder full = RoundedSuperellipseBorder(
    borderRadius: AppRadius.full,
  );
  static const CircleBorder circle = CircleBorder();
  static const AppInputBorder input = AppInputBorder();

  static RoundedSuperellipseBorder all(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.all(corner));

  static RoundedSuperellipseBorder top(double corner) =>
      RoundedSuperellipseBorder(borderRadius: AppRadius.top(corner));

  static RoundedSuperellipseBorder vertical({
    double top = AppCorner.none,
    double bottom = AppCorner.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: AppRadius.vertical(top: top, bottom: bottom),
  );

  static RoundedSuperellipseBorder of(BorderRadius borderRadius) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius);
}

class AppInputBorder extends InputBorder {
  const AppInputBorder({
    super.borderSide = const BorderSide(),
    this.borderRadius = AppRadius.md,
    this.gapPadding = 4.0,
  });

  final BorderRadius borderRadius;
  final double gapPadding;

  RoundedSuperellipseBorder get _shape =>
      RoundedSuperellipseBorder(borderRadius: borderRadius, side: borderSide);

  @override
  bool get isOutline => true;

  @override
  bool get preferPaintInterior => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  AppInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) {
    return AppInputBorder(
      borderSide: borderSide ?? this.borderSide,
      borderRadius: borderRadius ?? this.borderRadius,
      gapPadding: gapPadding ?? this.gapPadding,
    );
  }

  @override
  AppInputBorder scale(double t) {
    return AppInputBorder(
      borderSide: borderSide.scale(t),
      borderRadius: borderRadius * t,
      gapPadding: gapPadding * t,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _shape.paintInterior(canvas, rect, paint, textDirection: textDirection);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
        gapPadding: a.gapPadding,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is AppInputBorder) {
      return AppInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
        gapPadding: b.gapPadding,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    final outline = rect.deflate(borderSide.width / 2);
    if (gapStart == null || gapExtent <= 0.0 || gapPercentage == 0.0) {
      _shape.paint(canvas, rect, textDirection: textDirection);
      return;
    }
    final extent = lerpDouble(
      0.0,
      gapExtent + gapPadding * 2.0,
      gapPercentage,
    )!;
    final start = switch (textDirection ?? TextDirection.ltr) {
      TextDirection.rtl => gapStart + gapPadding - extent,
      TextDirection.ltr => gapStart - gapPadding,
    };
    final radii = borderRadius.resolve(textDirection);
    final left = outline.left + math.max(0.0, start);
    final depth =
        math.max(radii.topLeft.y, radii.topRight.y) + borderSide.width;
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTRB(
          left,
          outline.top - borderSide.width,
          left + extent,
          outline.top + depth,
        ),
        clipOp: ClipOp.difference,
      );
    _shape.paint(canvas, rect, textDirection: textDirection);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding;
  }

  @override
  int get hashCode => Object.hash(borderSide, borderRadius, gapPadding);
}

extension AppShapeThemeExt on ThemeData {
  ThemeData get withAppShapes => copyWith(
    cardTheme: cardTheme.copyWith(shape: AppShape.xl),
    dialogTheme: dialogTheme.copyWith(
      shape: AppShape.floating.copyWith(side: colorScheme.cabinRimSide),
    ),
    bottomSheetTheme: bottomSheetTheme.copyWith(
      shape: AppShape.top(AppCorner.floating),
    ),
    snackBarTheme: snackBarTheme.copyWith(shape: AppShape.xs),
    tooltipTheme: tooltipTheme.copyWith(
      // A decoration replaces Material's tooltip colours too, so restate them.
      decoration: ShapeDecoration(
        shape: AppShape.xs,
        color: switch (brightness) {
          Brightness.dark => Colors.white.withAlpha(230),
          Brightness.light => Colors.grey[700]!.withAlpha(230),
        },
      ),
    ),
    chipTheme: chipTheme.copyWith(shape: AppShape.sm),
    popupMenuTheme: popupMenuTheme.copyWith(
      shape: AppShape.floating.copyWith(side: colorScheme.cabinRimSide),
    ),
    menuTheme: MenuThemeData(
      style: (menuTheme.style ?? const MenuStyle()).copyWith(
        shape: WidgetStatePropertyAll(
          AppShape.floating.copyWith(side: colorScheme.cabinRimSide),
        ),
      ),
    ),
    inputDecorationTheme: inputDecorationTheme.copyWith(border: AppShape.input),
    floatingActionButtonTheme: floatingActionButtonTheme.copyWith(
      shape: AppShape.md,
    ),
    navigationBarTheme: navigationBarTheme.copyWith(
      indicatorShape: AppShape.full,
    ),
    navigationRailTheme: navigationRailTheme.copyWith(
      indicatorShape: AppShape.full,
    ),
    progressIndicatorTheme: progressIndicatorTheme.copyWith(
      borderRadius: AppRadius.full,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: filledButtonTheme.style?.merge(_squareButton) ?? _squareButton,
    ),
    textButtonTheme: TextButtonThemeData(
      style: textButtonTheme.style?.merge(_squareButton) ?? _squareButton,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: outlinedButtonTheme.style?.merge(_squareButton) ?? _squareButton,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: elevatedButtonTheme.style?.merge(_squareButton) ?? _squareButton,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: iconButtonTheme.style?.merge(_squareButton) ?? _squareButton,
    ),
  );
}

// Buttons take the family's square corner; a button's fill, outline or ink
// alone carries its kind, never a capsule silhouette.
const _squareButton = ButtonStyle(shape: WidgetStatePropertyAll(AppShape.hara));
