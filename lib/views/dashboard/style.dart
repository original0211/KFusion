import 'package:kfusion/common/common.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:material_ui/material_ui.dart';

export 'package:kfusion/ui/disc_motif.dart';

class DashboardColors {
  const DashboardColors._({
    required this.page,
    required this.card,
    required this.tone,
    required this.tone2,
    required this.track,
    required this.thumb,
    required this.series2,
    required this.ok,
    required this.okContainer,
    required this.onOkContainer,
    required this.warn,
    required this.warnContainer,
    required this.onWarnContainer,
  });

  factory DashboardColors.of(BuildContext context) {
    final colorScheme = context.colorScheme;
    final card = SurfaceLevel.card.colorOf(colorScheme);
    return DashboardColors._(
      page: SurfaceLevel.page.colorOf(colorScheme),
      card: card,
      tone: SurfaceLevel.block.colorOf(colorScheme),
      tone2: SurfaceLevel.inset.colorOf(colorScheme),
      track: colorScheme.surfaceContainerHighest,
      thumb: colorScheme.outline,
      series2: Color.alphaBlend(
        colorScheme.primary.withValues(alpha: 0.45),
        card,
      ),
      ok: colorScheme.success,
      okContainer: colorScheme.successContainer,
      onOkContainer: colorScheme.onSuccessContainer,
      warn: colorScheme.warning,
      warnContainer: colorScheme.warningContainer,
      onWarnContainer: colorScheme.onWarningContainer,
    );
  }

  final Color page;
  final Color card;

  final Color tone;

  final Color tone2;
  final Color track;
  final Color thumb;
  final Color series2;
  final Color ok;
  final Color okContainer;
  final Color onOkContainer;
  final Color warn;
  final Color warnContainer;
  final Color onWarnContainer;
}

/// The cabin corner tiers (REDESIGN_CABIN_SPEC.md §1.2) under the names the
/// dashboard already uses; a table header keeps its own step, which the
/// tier scale has no rung for.
abstract final class DashboardCorner {
  static const desktopCard = AppCorner.xl;
  static const mobileCard = AppCorner.xl;
  static const block = AppCorner.lg;
  static const mobileBlock = AppCorner.xl;
  static const tab = 16.0;
  static const tableHeader = 12.0;
  static const badge = AppCorner.md;
}

final _groupedFormat = NumberFormat.decimalPattern('en');

/// Grouped digits, as the design shows them, until they outgrow a third of a
/// phone's width.
String dashboardCount(int count) =>
    count < 100000 ? _groupedFormat.format(count) : count.compact;

String dashboardTraffic(num bytes) {
  final show = bytes.traffic;
  return '${show.value} ${show.unit}';
}

/// The dashboard's text roles; every figure reads in tabular digits.
abstract final class DashboardText {
  static TextStyle cardTitle(BuildContext context) => AppTextStyle.footnote
      .of(context, emphasized: true)
      .copyWith(color: context.colorScheme.onSurfaceVariant);

  static TextStyle mobileCardTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true);

  static TextStyle label(BuildContext context, {Color? color}) => AppTextStyle
      .caption1
      .of(context)
      .toTabular
      .copyWith(color: color ?? context.colorScheme.onSurfaceVariant);

  static TextStyle figure(
    BuildContext context,
    AppTextStyle style, {
    Color? color,
  }) => style
      .of(context, emphasized: true)
      .toTabular
      .copyWith(color: color, letterSpacing: -0.02 * style.size);

  static TextStyle unit(
    BuildContext context, [
    AppTextStyle style = AppTextStyle.subheadline,
  ]) => style
      .of(context, emphasized: true)
      .copyWith(color: context.colorScheme.onSurfaceVariant);

  static TextStyle rowTitle(BuildContext context) =>
      AppTextStyle.subheadline.of(context, emphasized: true);
}
