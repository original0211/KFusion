import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/core/core.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/profiles/universal_import.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'edit.dart';
import 'layout.dart';
import 'style.dart';
import 'widget_registry.dart';
import 'widgets/card.dart';
import 'widgets/core_status_button.dart';
import 'widgets/widgets.dart';

// Narrower columns leave the service grid's cells too tight for a status, so
// the grid takes the memory card's column instead.
const _memoryColumnMin = 290.0;

/// The beginner home shows only what a first run needs; editing and the
/// full dashboard keep the rest of the saved list.
const _beginnerHomeWidgets = {
  DashboardWidget.currentOutbound,
  DashboardWidget.networkSpeed,
  DashboardWidget.profiles,
};

const _maxColumnWidth = 440.0;

class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, this.platform});

  /// The host's platform when null.
  final SupportPlatform? platform;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  var _editing = false;
  final _cardKeys = <DashboardWidget, GlobalKey>{};

  void _setEditing(bool editing) {
    setState(() => _editing = editing);
  }

  GlobalKey _cardKeyOf(DashboardWidget widget) =>
      _cardKeys.putIfAbsent(widget, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final platform = widget.platform ?? SupportPlatform.currentPlatform;
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final editing = _editing;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      backgroundColor: DashboardColors.of(context).page,
      title: editing
          ? appLocalizations.editDashboard
          : appLocalizations.dashboard,
      backAction: editing ? () => _setEditing(false) : null,
      actions: [if (!editing && coreLib == null) const CoreStatusButton()],
      confirmationAction: editing
          ? IconButtonData(
              glyph: AppGlyphs.check,
              tooltip: appLocalizations.done,
              onPressed: () => _setEditing(false),
            )
          : null,
      iconActions: [
        if (!editing)
          IconButtonData(
            glyph: AppGlyphs.edit,
            tooltip: appLocalizations.editDashboard,
            onPressed: () => _setEditing(true),
          ),
      ],
      // The providers learn a resize a frame late, too late for the cards.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final room = constraints.biggest / scale;
          final layout = DashboardDensity.of(room);
          return DashboardDensityScope(
            density: layout,
            scale: scale,
            child: layout.isDesktop
                ? _DesktopDashboard(
                    platform: platform,
                    columns: dashboardColumnsOf(room.width),
                    gap: gap,
                    editing: editing,
                    cardKeyOf: _cardKeyOf,
                    onDone: () => _setEditing(false),
                  )
                : _MobileDashboard(
                    platform: platform,
                    gap: gap,
                    editing: editing,
                    cardKeyOf: _cardKeyOf,
                    onDone: () => _setEditing(false),
                  ),
          );
        },
      ),
    );
  }
}

class _DesktopDashboard extends ConsumerWidget {
  const _DesktopDashboard({
    required this.platform,
    required this.columns,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;
  final int columns;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    final widgets = [
      for (final widget in saved)
        if (widget.platforms.contains(platform)) widget,
    ];
    if (editing) {
      return _DesktopEditor(
        platform: platform,
        widgets: widgets,
        gap: gap,
        cardKeyOf: cardKeyOf,
        onDone: onDone,
      );
    }
    return _DesktopGrid(columns: columns, gap: gap, shown: widgets.toSet());
  }
}

/// The phone editor's model at a desktop width: the same list, the same
/// saves, in a centred column wide enough for the desktop card forms.
class _DesktopEditor extends StatelessWidget {
  const _DesktopEditor({
    required this.platform,
    required this.widgets,
    required this.gap,
    required this.cardKeyOf,
    required this.onDone,
  });

  static const _columnMax = 880.0;

  final SupportPlatform platform;
  final List<DashboardWidget> widgets;
  final double gap;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 16;
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    // The editor's cards stand in a list of no fixed height, which is the
    // phone forms' shape; the desktop forms expect their grid rows.
    return DashboardDensityScope(
      density: DashboardDensity.mobile,
      scale: DashboardDensityScope.scaleOf(context),
      child: CustomScrollView(
        // A viewport per card lays them all out and holds the scroll end
        // still.
        scrollCacheExtent: ScrollCacheExtent.viewport(
          DashboardWidget.values.length.toDouble(),
        ),
        slivers: [
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final side = math.max(
                24.0,
                (constraints.crossAxisExtent - _columnMax) / 2,
              );
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Four columns fill the window, the tables taking what the rows above them
/// leave. A window too short for the tables, and every two column one, gets
/// the summary cards instead, so no list scrolls inside a page that scrolls.
///
/// The saved list decides which cards a tier holds; a tier keeps its
/// composed order and spans, so the grid's shape survives an edit while its
/// membership follows the one list the phone edits too.
class _DesktopGrid extends StatelessWidget {
  const _DesktopGrid({
    required this.columns,
    required this.gap,
    required this.shown,
  });

  final int columns;
  final double gap;
  final Set<DashboardWidget> shown;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      MediaQuery.paddingOf(context).top,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    );
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    final middleHeight = (compact ? 152 : 176) * scale;
    final tablesHeight = connectionsTableMinHeight(density, scale);
    final summaryHeight = (compact ? 112 : 120) * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth - base.horizontal - gap * (columns - 1);
        final column = math.min(room / columns, _maxColumnWidth * scale);
        final inset = (room - column * columns) / 2;
        final padding = base.copyWith(
          start: base.start + inset,
          end: base.end + inset,
        );
        double span(int columns) => column * columns + gap * (columns - 1);
        Widget row(List<(int, Widget)> cards) {
          final filled = dashboardFilledSpans([
            for (final (cellSpan, _) in cards) cellSpan,
          ], columns);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              for (var index = 0; index < cards.length; index++)
                SizedBox(
                  width: span(filled[index]),
                  child: RepaintBoundary(child: cards[index].$2),
                ),
            ],
          );
        }

        Widget sized(double height, Widget child) =>
            SizedBox(height: height, child: child);

        // Greedy packing of one tier's cells into rows of [columns].
        (List<Widget>, double) pack(double height, List<(int, Widget)> cells) {
          final rows = <Widget>[];
          var current = <(int, Widget)>[];
          var used = 0;
          void close() {
            if (current.isEmpty) return;
            rows.add(sized(height, row(current)));
            current = [];
            used = 0;
          }

          for (final cell in cells) {
            if (used + cell.$1 > columns) close();
            current.add(cell);
            used += cell.$1;
          }
          close();
          return (rows, rows.length * height);
        }

        final topCells = <(int, Widget)>[
          if (shown.contains(DashboardWidget.currentOutbound))
            (2, const CurrentOutboundCard()),
          if (shown.contains(DashboardWidget.networkSpeed)) ...[
            (1, const SpeedCard(direction: TrafficDirection.upload)),
            (1, const SpeedCard(direction: TrafficDirection.download)),
          ],
        ];
        final controlCells = <(int, Widget)>[
          if (shown.contains(DashboardWidget.outboundMode))
            (2, const OutboundModeBar()),
          if (shown.contains(DashboardWidget.networkTakeover)) ...[
            (1, const NetworkTakeoverTile(TakeoverSwitch.systemProxy)),
            (1, const NetworkTakeoverTile(TakeoverSwitch.tun)),
          ] else if (shown.contains(DashboardWidget.vpnButton))
            (2, const VpnTile()),
        ];
        final narrow = column < _memoryColumnMin * scale;
        final middleCells = <(int, Widget)>[
          if (shown.contains(DashboardWidget.intranetIp))
            (1, const IntranetIpCard()),
          if (shown.contains(DashboardWidget.profiles))
            (1, const ProfilesCard()),
          if (shown.contains(DashboardWidget.serviceStatus))
            (narrow ? 2 : 1, const ServiceStatusCard()),
          if (!narrow && shown.contains(DashboardWidget.memoryInfo))
            (1, const MemoryInfo()),
        ];
        final half = columns ~/ 2;
        final summaryCells = <(int, Widget)>[
          if (shown.contains(DashboardWidget.connectionStats))
            (half, const ConnectionStatsCard()),
          if (shown.contains(DashboardWidget.proxyGroups))
            (half, const ProxyGroupsSummaryCard()),
        ];
        final summaries = summaryCells.isEmpty ? null : row(summaryCells);
        final tables = shown.contains(DashboardWidget.proxyGroups)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: gap,
                children: const [
                  Expanded(
                    flex: 3,
                    child: RepaintBoundary(child: ConnectionsTableCard()),
                  ),
                  Expanded(
                    flex: 2,
                    child: RepaintBoundary(child: ProxyGroupsCard()),
                  ),
                ],
              )
            : null;

        final (topRows, topTotal) = pack(topHeight, topCells);
        final (controlRows, controlTotal) = pack(controlHeight, controlCells);
        final (middleRows, middleTotal) = pack(middleHeight, middleCells);
        final fixedRows = [...topRows, ...controlRows, ...middleRows];
        if (columns == 2) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            child: Column(
              spacing: gap,
              children: [
                ...fixedRows,
                if (summaries != null) sized(summaryHeight, summaries),
              ],
            ),
          );
        }
        final rowsHeight =
            padding.vertical +
            topTotal +
            controlTotal +
            middleTotal +
            gap * fixedRows.length;
        final tablesFit =
            tables != null &&
            constraints.maxHeight >= rowsHeight + tablesHeight;
        final fills =
            summaries != null &&
            constraints.maxHeight >= rowsHeight + summaryHeight;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: tablesFit || fills ? constraints.maxHeight : null,
            child: Padding(
              padding: padding,
              child: Column(
                spacing: gap,
                children: [
                  ...fixedRows,
                  if (tablesFit)
                    Expanded(child: tables)
                  else if (summaries != null)
                    fills
                        ? Expanded(child: summaries)
                        : sized(summaryHeight, summaries),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileDashboard extends ConsumerWidget {
  const _MobileDashboard({
    required this.platform,
    required this.gap,
    required this.editing,
    required this.cardKeyOf,
    required this.onDone,
  });

  final SupportPlatform platform;
  final double gap;
  final bool editing;
  final GlobalKey Function(DashboardWidget widget) cardKeyOf;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(
      dashboardStateProvider.select((state) => state.dashboardWidgets),
    );
    // Until the preference lands the saved list shows as it stands; the
    // narrowing is a preference, not a state worth hiding cards over.
    final beginner = ref
        .watch(beginnerModeProvider)
        .when(
          data: (value) => value,
          loading: () => false,
          error: (_, _) => false,
        );
    final noProfiles = ref.watch(
      profilesProvider.select((state) => state.isEmpty),
    );
    final top = MediaQuery.paddingOf(context).top + 4;
    final bottom = 16 + BottomInsetScope.of(context);
    return CustomScrollView(
      // A viewport per card lays them all out and holds the scroll end still.
      scrollCacheExtent: editing
          ? ScrollCacheExtent.viewport(DashboardWidget.values.length.toDouble())
          : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final side = dashboardMobileSideOf(constraints.crossAxisExtent);
            final widgets = [
              for (final widget in saved)
                if (widget.platforms.contains(platform) &&
                    (!beginner ||
                        editing ||
                        _beginnerHomeWidgets.contains(widget)))
                  widget,
            ];
            if (editing) {
              return DashboardEditor(
                platform: platform,
                widgets: widgets,
                cardKeyOf: cardKeyOf,
                padding: EdgeInsets.fromLTRB(side, top, side, bottom),
                gap: gap,
                onDone: onDone,
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, top, side, bottom),
              // A lazy list estimates the cards it has not laid out from the
              // ones it has; cards this uneven move the scroll end as it goes.
              sliver: SliverToBoxAdapter(
                child: Column(
                  spacing: gap,
                  children: [
                    for (final widget in widgets)
                      RepaintBoundary(
                        key: cardKeyOf(widget),
                        child: widget.card,
                      ),
                    if (beginner && noProfiles) const _BeginnerImportCard(),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The beginner home's way in when there is nothing to run yet: one card
/// that opens the universal import.
class _BeginnerImportCard extends StatelessWidget {
  const _BeginnerImportCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardCard(
      onTap: () => BaseNavigator.push(context, const UniversalImportView()),
      child: Row(
        spacing: 16,
        children: [
          DashboardDiscMotif(size: 44, color: colorScheme.onSurface),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '万能导入',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.mobileCardTitle(context),
                ),
                const SizedBox(height: 2),
                Text(
                  'Clash / sing-box / 分享链接 / 订阅，一次导入',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.chevronForward,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
