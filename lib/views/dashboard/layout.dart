import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

const _minDesktopWidth = 640.0;
const _minFourColumnWidth = 860.0;
const _minStandardFourColumnWidth = 1040.0;
const _minStandardHeight = 824.0;
const _mobileMaxWidth = 560.0;

int dashboardColumnsOf(double width) => width < _minFourColumnWidth ? 2 : 4;

/// The mobile cards and their editor share one centered column.
double dashboardMobileSideOf(double width) =>
    math.max(16, (width - _mobileMaxWidth) / 2);

/// Spreads [total] columns over one grid row's cells in proportion to
/// their composed [spans], so the row fills its tier with the cards it has
/// left. A row already at [total] keeps its spans; the columns left over
/// by rounding go to the largest remainders, then to the widest cells.
List<int> dashboardFilledSpans(List<int> spans, int total) {
  final used = spans.fold(0, (sum, span) => sum + span);
  if (spans.isEmpty || used >= total) return List.of(spans);
  final filled = [for (final span in spans) span * total ~/ used];
  var left = total - filled.fold(0, (sum, span) => sum + span);
  final order = [for (var index = 0; index < spans.length; index++) index]
    ..sort((a, b) {
      final remainderA = spans[a] * total % used;
      final remainderB = spans[b] * total % used;
      if (remainderA != remainderB) return remainderB - remainderA;
      if (spans[a] != spans[b]) return spans[b] - spans[a];
      return a - b;
    });
  for (final index in order) {
    if (left == 0) break;
    filled[index]++;
    left--;
  }
  return filled;
}

/// [compact] shrinks type, the start button and tiles, and drops subtitles.
enum DashboardDensity {
  standard,
  compact,
  mobile;

  bool get isDesktop => this != mobile;

  bool get isCompact => this == compact;

  static DashboardDensity of(Size size) {
    if (size.width < _minDesktopWidth) {
      return mobile;
    }
    final narrowColumns =
        dashboardColumnsOf(size.width) == 4 &&
        size.width < _minStandardFourColumnWidth;
    return narrowColumns || size.height < _minStandardHeight
        ? compact
        : standard;
  }
}

/// Every fixed height on the dashboard grows by [scale] so its text fits.
class DashboardDensityScope extends InheritedWidget {
  const DashboardDensityScope({
    super.key,
    required this.density,
    required this.scale,
    required super.child,
  });

  final DashboardDensity density;
  final double scale;

  static DashboardDensityScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardDensityScope>();

  static DashboardDensity of(BuildContext context) =>
      _of(context)?.density ?? DashboardDensity.mobile;

  static double scaleOf(BuildContext context) => _of(context)?.scale ?? 1;

  @override
  bool updateShouldNotify(DashboardDensityScope oldWidget) =>
      density != oldWidget.density || scale != oldWidget.scale;
}
