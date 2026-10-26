import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/features.dart';
import 'package:kfusion/features/ip_quality/labels.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/dashboard/layout.dart';
import 'package:kfusion/views/dashboard/probe_start_hold.dart';
import 'package:kfusion/views/dashboard/style.dart';
import 'package:kfusion/views/logs.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

/// The cabin core's two resting heights (REDESIGN_CABIN_SPEC.md §1.3/§2.1):
/// the full disc zone and the compact bar the dashboard's scroll collapses
/// it into.
const cabinCoreFullExtent = 300.0;
const cabinCoreBarExtent = 76.0;

const _discSize = 262.0;
const _discRingInset = 13.0;
const _arcStart = -1.05;
const _arcSweep = 0.62;
const _pendingBudget = Duration(seconds: 45);
const _stateDuration = Duration(milliseconds: 240);

/// What the cabin core presents. The transitional two are the core's own
/// reading of a tap whose intent the shared running state has not landed
/// yet; they never outlive [_pendingBudget] or the state catching up.
enum CabinCorePhase {
  noProfile,
  disconnected,
  connecting,
  connected,
  disconnecting,
  suspended,
  error,
}

/// Only a settled tunnel may fold away; every other phase keeps the full
/// disc, which carries the connect guidance and the failure.
bool cabinCoreAllowsCompact(CabinCorePhase phase) =>
    phase == CabinCorePhase.connected || phase == CabinCorePhase.suspended;

const _builtinOutbounds = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS'};

bool isBuiltinOutbound(String name) => _builtinOutbounds.contains(name);

/// The dashboard's status zone as the cabin core: a disc that is itself the
/// start/stop control, folding into a bar once the tunnel is up. In place
/// it stands over [CabinExitPanel]; under the dashboard's scroll it is
/// lifted out and driven by [extent] instead.
class CabinCoreCard extends ConsumerStatefulWidget {
  const CabinCoreCard({
    super.key,
    this.extent,
    this.onBarTap,
    this.onCompactAllowed,
  });

  /// Overlay mode: the zone height the dashboard's scroll position
  /// dictates, from [cabinCoreFullExtent] down to [cabinCoreBarExtent].
  final ValueListenable<double>? extent;

  /// A tap on the folded bar, which only ever asks to unfold.
  final VoidCallback? onBarTap;

  /// Reports the phase's compact verdict as it changes, so the dashboard
  /// can hold the full height while a fold is not allowed.
  final ValueChanged<bool>? onCompactAllowed;

  @override
  ConsumerState<CabinCoreCard> createState() => _CabinCoreCardState();
}

class _CabinCoreCardState extends ConsumerState<CabinCoreCard>
    with ProbeStartHold<CabinCoreCard> {
  late final OutboundIpProbe _probe;

  /// The running state a tap is still waiting on, true for a start.
  bool? _pending;
  Timer? _pendingTimer;
  var _forceExpanded = false;
  bool? _reportedAllowed;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
    ref.listenManual(isStartProvider, (previous, next) {
      if (!mounted) return;
      if (previous != next) {
        setState(() {
          _forceExpanded = false;
          if (_pending == next) {
            _pending = null;
            _pendingTimer?.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  void _toggle() {
    setState(() => _pending = !ref.read(isStartProvider));
    _pendingTimer?.cancel();
    _pendingTimer = Timer(_pendingBudget, () {
      if (mounted) setState(() => _pending = null);
    });
    ref.read(commonActionProvider.notifier).toggleRunning();
  }

  CabinCorePhase _phase({
    required bool hasProfile,
    required bool isStart,
    required bool suspended,
    required ProbeEntry<IpInfo> entry,
  }) {
    if (!hasProfile) return CabinCorePhase.noProfile;
    if (_pending == true && !isStart) return CabinCorePhase.connecting;
    if (_pending == false && isStart) return CabinCorePhase.disconnecting;
    if (!isStart) return CabinCorePhase.disconnected;
    if (suspended) return CabinCorePhase.suspended;
    if (shownPhase(entry) == ProbePhase.failed && entry.value == null) {
      return CabinCorePhase.error;
    }
    return CabinCorePhase.connected;
  }

  void _reportAllowed(bool allowed) {
    final callback = widget.onCompactAllowed;
    if (callback == null || _reportedAllowed == allowed) return;
    _reportedAllowed = allowed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(allowed);
    });
  }

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final phase = _phase(
      hasProfile: hasProfile,
      isStart: isStart,
      suspended: suspended,
      entry: entry,
    );
    final ipInfo = entry.value;
    final nodeName = ipInfo == null ? null : entry.stamp?.chains.firstOrNull;
    final delay = nodeName == null
        ? null
        : ref.watch(delayProvider(proxyName: nodeName));
    if (density.isDesktop) {
      final shown = shownPhase(entry);
      final qualityState = ipInfo == null
          ? null
          : ref.watch(ipQualityProvider(ipInfo.ip));
      final quality = qualityState?.value;
      final qualityLoading =
          qualityState != null && quality == null && qualityState.isLoading;
      final failed = shown == ProbePhase.failed && ipInfo == null;
      return _DesktopCore(
        phase: phase,
        nodeName: nodeName,
        delay: delay,
        region: ipInfo?.countryCode,
        proxied: ref.watch(
          routeTrackerProvider.select((state) => state.proxied),
        ),
        enabled: hasProfile,
        onToggle: _toggle,
        exit: _ExitBlock(
          ipInfo: ipInfo,
          failed: failed,
          loading: ipInfo == null ? !failed : qualityLoading,
          checking: shown == ProbePhase.probing || qualityLoading,
          quality: quality,
          active: isStart,
          cellsActive: isStart && !suspended,
          onRefresh: () => _refresh(ipInfo?.ip),
          metrics: _ExitMetrics.desktop(density),
        ),
      );
    }
    final allowed = cabinCoreAllowsCompact(phase);
    _reportAllowed(allowed);
    final extent = widget.extent;
    if (extent != null) {
      return ValueListenableBuilder<double>(
        valueListenable: extent,
        builder: (context, height, _) {
          final collapse = allowed
              ? ((cabinCoreFullExtent - height) /
                        (cabinCoreFullExtent - cabinCoreBarExtent))
                    .clamp(0.0, 1.0)
              : 0.0;
          return _zone(
            context,
            phase: phase,
            nodeName: nodeName,
            delay: delay,
            region: ipInfo?.countryCode,
            height: height,
            collapse: collapse,
            onBarTap: widget.onBarTap,
          );
        },
      );
    }
    final preferCompact = ref.watch(
      appSettingProvider.select((state) => state.cabinCoreCompact),
    );
    final compact = allowed && !_forceExpanded && preferCompact;
    final gap = cardSpacingOf(context, ref.watch(viewModeProvider));
    return Column(
      spacing: gap,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: compact ? 1 : 0),
          duration: context.motionDuration(_stateDuration),
          builder: (context, collapse, _) => _zone(
            context,
            phase: phase,
            nodeName: nodeName,
            delay: delay,
            region: ipInfo?.countryCode,
            height:
                cabinCoreFullExtent -
                (cabinCoreFullExtent - cabinCoreBarExtent) * collapse,
            collapse: collapse,
            onBarTap: () => setState(() => _forceExpanded = true),
          ),
        ),
        const CabinExitPanel(),
      ],
    );
  }

  void _refresh(String? ip) {
    _probe.refresh(const [routedOutbound]);
    if (ip != null && ref.read(ipQualityProvider(ip)).hasError) {
      ref.invalidate(ipQualityProvider(ip));
    }
  }

  Widget _zone(
    BuildContext context, {
    required CabinCorePhase phase,
    required String? nodeName,
    required int? delay,
    required String? region,
    required double height,
    required double collapse,
    required VoidCallback? onBarTap,
  }) {
    final colorScheme = context.colorScheme;
    final discOpacity = (1 - collapse * 2).clamp(0.0, 1.0);
    final barOpacity = ((collapse - 0.5) * 2).clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (discOpacity > 0)
            Positioned.fill(
              child: Opacity(
                opacity: discOpacity,
                child: Transform.scale(
                  scale: 1 - 0.25 * collapse,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 330,
                        height: 330,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colorScheme.cabinHalo,
                              colorScheme.cabinHalo.withValues(alpha: 0),
                            ],
                            stops: const [0.35, 1],
                          ),
                        ),
                      ),
                      _CabinDisc(
                        phase: phase,
                        size: _discSize,
                        nodeName: nodeName,
                        delay: delay,
                        region: region,
                        enabled: phase != CabinCorePhase.noProfile,
                        onTap: _toggle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (barOpacity > 0)
            Opacity(
              opacity: barOpacity,
              child: IgnorePointer(
                ignoring: collapse < 0.5,
                child: _CabinBar(
                  phase: phase,
                  nodeName: nodeName,
                  delay: delay,
                  onTap: onBarTap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The desktop core: one cabin panel, the disc standing where the start
/// button stood, the status and the exit block in the column beside it.
class _DesktopCore extends StatelessWidget {
  const _DesktopCore({
    required this.phase,
    required this.nodeName,
    required this.delay,
    required this.region,
    required this.proxied,
    required this.enabled,
    required this.onToggle,
    required this.exit,
  });

  final CabinCorePhase phase;
  final String? nodeName;
  final int? delay;
  final String? region;
  final bool proxied;
  final bool enabled;
  final VoidCallback onToggle;
  final Widget exit;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    return DashboardCard(
      padding: EdgeInsets.zero,
      semanticLabel: appLocalizations.status,
      child: Padding(
        padding: dashboardCardPadding(density),
        child: Row(
          spacing: 16,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardCardHeader(
                    glyph: AppGlyphs.status,
                    title: _phaseText(appLocalizations, phase),
                    leading: [
                      if (nodeName != null)
                        Flexible(
                          child: Text(
                            nodeName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption1
                                .of(context)
                                .copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      if (phase == CabinCorePhase.connected &&
                          (delay != null || region != null))
                        _CabinPill(
                          text: _pillText(appLocalizations, delay, region),
                          color: colorScheme.primary,
                        ),
                      if (!proxied && phase != CabinCorePhase.noProfile)
                        _CabinPill(
                          text: appLocalizations.direct,
                          color: colorScheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  exit,
                ],
              ),
            ),
            Center(
              child: _CabinDisc(
                phase: phase,
                size: compact ? 84 : 104,
                nodeName: null,
                delay: null,
                region: null,
                enabled: enabled,
                onTap: onToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _phaseText(AppLocalizations appLocalizations, CabinCorePhase phase) =>
    switch (phase) {
      CabinCorePhase.noProfile ||
      CabinCorePhase.disconnected => appLocalizations.disconnected,
      CabinCorePhase.connecting => appLocalizations.connecting,
      CabinCorePhase.connected => appLocalizations.connected,
      CabinCorePhase.disconnecting => appLocalizations.disconnecting,
      CabinCorePhase.suspended => appLocalizations.suspended,
      CabinCorePhase.error => appLocalizations.connectionFailed,
    };

String _pillText(
  AppLocalizations appLocalizations,
  int? delay,
  String? region,
) {
  final parts = [
    if (delay != null && delay > 0) '${appLocalizations.delay} $delay ms',
    if (region != null) '${appLocalizations.ipExit} $region',
  ];
  return parts.join(' · ');
}

/// The disc itself: halo-free, carrying the motif, the phase and, at full
/// size, the node and the delay/exit pill. A tap anywhere on it asks for
/// the opposite running state through the shared action.
class _CabinDisc extends StatefulWidget {
  const _CabinDisc({
    required this.phase,
    required this.size,
    required this.nodeName,
    required this.delay,
    required this.region,
    required this.enabled,
    required this.onTap,
  });

  final CabinCorePhase phase;
  final double size;
  final String? nodeName;
  final int? delay;
  final String? region;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_CabinDisc> createState() => _CabinDiscState();
}

class _CabinDiscState extends State<_CabinDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  var _hovered = false;
  var _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runSweep();
  }

  @override
  void didUpdateWidget(_CabinDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _runSweep();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _runSweep() {
    if (widget.phase == CabinCorePhase.connecting &&
        !context.disableAnimations) {
      _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  Color _arcColor(BuildContext context) {
    final colorScheme = context.colorScheme;
    return switch (widget.phase) {
      CabinCorePhase.noProfile ||
      CabinCorePhase.disconnected ||
      CabinCorePhase.disconnecting => colorScheme.cabinRing,
      CabinCorePhase.connecting ||
      CabinCorePhase.connected => colorScheme.primary,
      CabinCorePhase.suspended => DashboardColors.of(context).warn,
      CabinCorePhase.error => colorScheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final size = widget.size;
    final full = size >= 200;
    final phase = widget.phase;
    final appLocalizations = context.appLocalizations;
    final tooltip = switch (phase) {
      CabinCorePhase.suspended => appLocalizations.suspended,
      CabinCorePhase.connected ||
      CabinCorePhase.connecting ||
      CabinCorePhase.error => appLocalizations.stop,
      _ => appLocalizations.start,
    };
    final overlay = !widget.enabled
        ? 0.0
        : _focused
        ? 0.1
        : _hovered
        ? 0.08
        : 0.0;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: tooltip,
        child: InkResponse(
          onTap: widget.enabled ? widget.onTap : null,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          customBorder: const CircleBorder(),
          child: ElasticPress(
            enabled: widget.enabled,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.alphaBlend(
                  colorScheme.onSurface.withValues(alpha: overlay),
                  colors.card,
                ),
                border: Border.all(
                  color: _focused
                      ? focusRingSide(colorScheme, standsOff: true).color
                      : colorScheme.cabinRim,
                ),
                boxShadow: colorScheme.cabinDiscShadows,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size - _discRingInset * 2,
                    height: size - _discRingInset * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.cabinRing),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _sweep,
                    builder: (context, _) => CustomPaint(
                      size: Size.square(size),
                      painter: _CabinArcPainter(
                        color: _arcColor(context),
                        rotation: _sweep.value * 2 * math.pi,
                      ),
                    ),
                  ),
                  if (full)
                    _DiscCenter(
                      phase: phase,
                      nodeName: widget.nodeName,
                      delay: widget.delay,
                      region: widget.region,
                    )
                  else
                    DashboardDiscMotif(
                      size: size * 0.42,
                      color: colorScheme.onSurface,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The full disc's centre column: motif, phase, node, and the one pill the
/// phase allows.
class _DiscCenter extends StatelessWidget {
  const _DiscCenter({
    required this.phase,
    required this.nodeName,
    required this.delay,
    required this.region,
  });

  final CabinCorePhase phase;
  final String? nodeName;
  final int? delay;
  final String? region;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final showNode =
        nodeName != null &&
        (phase == CabinCorePhase.connected ||
            phase == CabinCorePhase.connecting ||
            phase == CabinCorePhase.suspended ||
            phase == CabinCorePhase.error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DashboardDiscMotif(size: 74, color: colorScheme.onSurface),
        const SizedBox(height: 8),
        SizedBox(
          width: 210,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _phaseText(appLocalizations, phase),
              maxLines: 1,
              style: AppTextStyle.custom(
                context,
                size: 21,
                leading: 26,
                weight: FontWeight.w600,
              ).copyWith(color: colorScheme.onSurface, letterSpacing: 6.3),
            ),
          ),
        ),
        if (showNode) ...[
          const SizedBox(height: 7),
          SizedBox(
            width: 200,
            child: Text(
              nodeName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyle.custom(
                context,
                size: 12.5,
                leading: 16,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
        const SizedBox(height: 9),
        switch (phase) {
          CabinCorePhase.connected when delay != null || region != null =>
            _CabinPill(
              text: _pillText(appLocalizations, delay, region),
              color: colorScheme.primary,
            ),
          CabinCorePhase.disconnected => _CabinPill(
            text: appLocalizations.tapToConnect,
            color: colorScheme.onSurfaceVariant,
          ),
          CabinCorePhase.error => _CabinPill(
            text: appLocalizations.details(appLocalizations.log),
            color: colorScheme.error,
            onTap: () => BaseNavigator.push(context, const LogsView()),
          ),
          _ => const SizedBox.shrink(),
        },
      ],
    );
  }
}

/// The cabin pill: a block-step capsule with a ring edge, its text the only
/// color it carries.
class _CabinPill extends StatelessWidget {
  const _CabinPill({required this.text, required this.color, this.onTap});

  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: ShapeDecoration(
        color: DashboardColors.of(context).tone,
        shape: AppShape.full.copyWith(
          side: BorderSide(color: colorScheme.cabinRing),
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .toTabular
            .copyWith(color: color),
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) return pill;
    return FocusRing(
      shape: AppShape.full,
      standsOff: true,
      child: InkWell(customBorder: AppShape.full, onTap: onTap, child: pill),
    );
  }
}

/// The compact bar: motif and phase on the left, the delay and the live
/// rates on the right. Tapping it only ever unfolds the core.
class _CabinBar extends ConsumerWidget {
  const _CabinBar({
    required this.phase,
    required this.nodeName,
    required this.delay,
    required this.onTap,
  });

  final CabinCorePhase phase;
  final String? nodeName;
  final int? delay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final traffic = ref.watch(
      trafficsProvider.select((state) => state.list.safeLast(const Traffic())),
    );
    final dotColor = switch (phase) {
      CabinCorePhase.connected => colorScheme.primary,
      CabinCorePhase.suspended => DashboardColors.of(context).warn,
      CabinCorePhase.error => colorScheme.error,
      _ => colorScheme.onSurfaceVariant,
    };
    return DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      onTap: onTap,
      semanticLabel: appLocalizations.status,
      child: SizedBox(
        height: cabinCoreBarExtent - 32,
        child: Row(
          spacing: 12,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                DashboardDiscMotif(size: 40, color: colorScheme.onSurface),
                PositionedDirectional(
                  end: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(
                        color: DashboardColors.of(context).card,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _phaseText(appLocalizations, phase),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                  if (nodeName != null)
                    Text(
                      nodeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (delay != null && delay! > 0)
                  Text(
                    '$delay ms',
                    maxLines: 1,
                    style: AppTextStyle.caption1
                        .of(context, emphasized: true)
                        .toTabular,
                  ),
                Text(
                  '↓ ${dashboardTraffic(traffic.down)}/s'
                  '  ↑ ${dashboardTraffic(traffic.up)}/s',
                  maxLines: 1,
                  style: AppTextStyle.caption2
                      .of(context)
                      .toTabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CabinArcPainter extends CustomPainter {
  const _CabinArcPainter({required this.color, required this.rotation});

  final Color color;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(
      center: center,
      radius: size.width / 2 - _discRingInset,
    );
    canvas.drawArc(
      rect,
      _arcStart + rotation,
      _arcSweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CabinArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rotation != rotation;
}

const _ipMask = '*****';

class _ExitMetrics {
  const _ExitMetrics({
    required this.badgeSize,
    required this.ip,
    required this.cellGap,
    required this.large,
  });

  factory _ExitMetrics.desktop(DashboardDensity density) => switch (density) {
    DashboardDensity.standard => const _ExitMetrics(
      badgeSize: 48,
      ip: AppTextStyle.title1,
      cellGap: 28,
      large: false,
    ),
    DashboardDensity.compact => const _ExitMetrics(
      badgeSize: 40,
      ip: AppTextStyle.title2,
      cellGap: 22,
      large: false,
    ),
    DashboardDensity.mobile => mobile,
  };

  static const mobile = _ExitMetrics(
    badgeSize: 48,
    ip: AppTextStyle.title2,
    cellGap: 24,
    large: true,
  );

  final double badgeSize;
  final AppTextStyle ip;
  final double cellGap;
  final bool large;
}

/// The exit block the core and the panel share: the address the traffic
/// leaves by, its quality, and the run's figures.
class _ExitBlock extends StatelessWidget {
  const _ExitBlock({
    required this.ipInfo,
    required this.failed,
    required this.loading,
    required this.checking,
    required this.quality,
    required this.active,
    required this.cellsActive,
    required this.onRefresh,
    required this.metrics,
  });

  final IpInfo? ipInfo;
  final bool failed;
  final bool loading;
  final bool checking;
  final IpQuality? quality;
  final bool active;
  final bool cellsActive;
  final VoidCallback onRefresh;
  final _ExitMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExitRow(
          info: ipInfo,
          failed: failed,
          loading: loading,
          checking: checking,
          onRefresh: onRefresh,
          quality: quality,
          active: active,
          metrics: metrics,
        ),
        const SizedBox(height: 16),
        _Cells(
          quality: quality,
          loading: loading,
          active: cellsActive,
          gap: metrics.cellGap,
        ),
      ],
    );
  }
}

/// The connection detail under the cabin core on the phone: the old status
/// card's body, in its own cabin panel. It keeps its own probe watch; the
/// core and the panel are two watchers of the one routed probe.
class CabinExitPanel extends ConsumerStatefulWidget {
  const CabinExitPanel({super.key});

  @override
  ConsumerState<CabinExitPanel> createState() => _CabinExitPanelState();
}

class _CabinExitPanelState extends ConsumerState<CabinExitPanel>
    with ProbeStartHold<CabinExitPanel> {
  late final OutboundIpProbe _probe;

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
  }

  @override
  void dispose() {
    _probe.unwatch(routedOutbound);
    super.dispose();
  }

  void _refresh(String? ip) {
    _probe.refresh(const [routedOutbound]);
    if (ip != null && ref.read(ipQualityProvider(ip)).hasError) {
      ref.invalidate(ipQualityProvider(ip));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final proxied = ref.watch(
      routeTrackerProvider.select((state) => state.proxied),
    );
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final ipInfo = entry.value;
    final phase = shownPhase(entry);
    final failed = phase == ProbePhase.failed && ipInfo == null;
    final qualityState = ipInfo == null
        ? null
        : ref.watch(ipQualityProvider(ipInfo.ip));
    final quality = qualityState?.value;
    final qualityLoading =
        qualityState != null && quality == null && qualityState.isLoading;
    final loading = ipInfo == null ? !failed : qualityLoading;
    final appLocalizations = context.appLocalizations;
    final (chipLabel, chipTone) = suspended
        ? (appLocalizations.suspended, DashboardChipTone.warn)
        : isStart
        ? (appLocalizations.running, DashboardChipTone.ok)
        : (appLocalizations.notRunning, DashboardChipTone.idle);
    // The header has no room for a second chip at phone widths; the title
    // ellipsizes, so the direct route is named there instead.
    final headerTitle = proxied
        ? appLocalizations.status
        : '${appLocalizations.status} · ${appLocalizations.direct}';
    return DashboardCard(
      semanticLabel: appLocalizations.status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.status,
            title: headerTitle,
            leading: [
              DashboardChip(label: chipLabel, tone: chipTone, dot: isStart),
            ],
          ),
          const SizedBox(height: 12),
          _ExitBlock(
            ipInfo: ipInfo,
            failed: failed,
            loading: loading,
            checking: phase == ProbePhase.probing || qualityLoading,
            quality: quality,
            active: isStart,
            cellsActive: isStart && !suspended,
            onRefresh: () => _refresh(ipInfo?.ip),
            metrics: _ExitMetrics.mobile,
          ),
        ],
      ),
    );
  }
}

class _ExitRow extends StatelessWidget {
  const _ExitRow({
    required this.info,
    required this.failed,
    required this.loading,
    required this.checking,
    required this.onRefresh,
    required this.quality,
    required this.active,
    required this.metrics,
  });

  final IpInfo? info;
  final bool failed;
  final bool loading;
  final bool checking;
  final VoidCallback onRefresh;
  final IpQuality? quality;
  final bool active;
  final _ExitMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = DashboardText.figure(
      context,
      metrics.ip,
      color: active ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
    ).copyWith(letterSpacing: 0);
    final info = this.info;
    final appLocalizations = context.appLocalizations;
    final Widget ip = info != null
        ? Tooltip(
            message: appLocalizations.details(appLocalizations.outboundIp),
            child: FocusRing(
              shape: AppShape.xs,
              standsOff: true,
              child: InkWell(
                onTap: () => showIpQualitySheet(context, ip: info.ip),
                customBorder: AppShape.xs,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: _IpText(ip: info.ip, style: style),
              ),
            ),
          )
        : failed
        ? Text(
            appLocalizations.serviceFailed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(color: colorScheme.error),
          )
        : SkeletonText(width: 140, style: style);
    return Row(
      spacing: 12,
      children: [
        _CountryBadge(
          countryCode: info?.countryCode,
          size: metrics.badgeSize,
          active: active,
          checking: checking,
          onRefresh: onRefresh,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height:
                    metrics.ip.leading * DashboardDensityScope.scaleOf(context),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ip,
                ),
              ),
              const SizedBox(height: 4),
              if (failed)
                SizedBox(
                  height: _chipHeight(metrics.large),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      appLocalizations.tapIconToRetry,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardText.label(context),
                    ),
                  ),
                )
              else
                _IpChips(
                  quality: quality,
                  loading: loading,
                  large: metrics.large,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IpText extends ConsumerWidget {
  const _IpText({required this.ip, required this.style});

  final String ip;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    return DashboardFitText(hideIp ? _ipMask : ip, style: style);
  }
}

double _chipHeight(bool large) => large ? 28 : 24;

const _chipSkeletonWidths = [48.0, 72.0];

class _IpChips extends StatelessWidget {
  const _IpChips({
    required this.quality,
    required this.loading,
    required this.large,
  });

  final IpQuality? quality;
  final bool loading;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final quality = this.quality;
    final height = _chipHeight(large);
    // Chips that do not fit wrap onto a clipped second line; the details
    // sheet still lists them all.
    return SizedBox(
      height: height,
      child: ClipRect(
        child: Wrap(
          spacing: 6,
          runSpacing: height,
          children: switch (quality) {
            final quality? => [
              DashboardChip(label: quality.type.label(context), large: large),
              DashboardChip(
                label:
                    '${context.appLocalizations.ipQualityShort} ${quality.level.label(context)}',
                tone: switch (quality.level) {
                  IpQualityLevel.good => DashboardChipTone.ok,
                  IpQualityLevel.normal => DashboardChipTone.idle,
                  IpQualityLevel.risky => DashboardChipTone.warn,
                },
                large: large,
              ),
            ],
            null when loading => [
              for (final width in _chipSkeletonWidths)
                SkeletonPill(width: width, height: height),
            ],
            null => [
              DashboardChip(
                label: context.appLocalizations.ipTypeUnknown,
                large: large,
              ),
            ],
          },
        ),
      ),
    );
  }
}

const _spinPeriod = Duration(milliseconds: 1500);

/// The exit's country on a clover that checks the exit again when tapped and
/// turns while it is being checked.
class _CountryBadge extends StatefulWidget {
  const _CountryBadge({
    required this.countryCode,
    required this.size,
    required this.active,
    required this.checking,
    required this.onRefresh,
  });

  final String? countryCode;
  final double size;
  final bool active;
  final bool checking;
  final VoidCallback onRefresh;

  @override
  State<_CountryBadge> createState() => _CountryBadgeState();
}

class _CountryBadgeState extends State<_CountryBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );
  var _hovered = false;
  var _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin();
  }

  @override
  void didUpdateWidget(_CountryBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.checking != widget.checking) {
      _spin();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  void _spin() {
    if (context.disableAnimations) {
      _turns.value = 0;
    } else if (widget.checking) {
      _turns.repeat();
    } else {
      // A clover looks the same every quarter turn, so it stops on the next.
      final rest = (_turns.value * 4).ceil() / 4;
      _turns.animateTo(rest, duration: _spinPeriod * (rest - _turns.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final foreground = widget.active
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final enabled = !widget.checking;
    final size = widget.size;
    final code = widget.countryCode;
    final tooltip = context.appLocalizations.retry;
    final color = Color.alphaBlend(
      foreground.withValues(alpha: enabled && _hovered ? 0.08 : 0),
      DashboardColors.of(context).tone2,
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: InkResponse(
          onTap: enabled ? widget.onRefresh : null,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          child: ElasticPress(
            enabled: enabled,
            child: AnimatedBuilder(
              animation: _turns,
              builder: (_, child) => ShapeBadge(
                shape: MaterialShapes.clover4Leaf,
                color: color,
                size: size,
                rotation: _turns.value * 2 * math.pi,
                ring: _focused ? focusRingSide(colorScheme) : null,
                child: child,
              ),
              child: code == null || code.isEmpty
                  ? GlyphIcon(
                      AppGlyphs.proxies,
                      size: size * 0.42,
                      color: foreground,
                    )
                  : Text(
                      code.toUpperCase(),
                      maxLines: 1,
                      style: AppTextStyle.footnote
                          .of(context, emphasized: true)
                          .copyWith(
                            color: foreground,
                            letterSpacing: 0.04 * AppTextStyle.footnote.size,
                          ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cells extends StatelessWidget {
  const _Cells({
    required this.quality,
    required this.loading,
    required this.active,
    required this.gap,
  });

  final IpQuality? quality;
  final bool loading;
  final bool active;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final organization = switch (quality) {
      IpQuality(organization: final name?) when name.isNotEmpty => name,
      IpQuality(asn: final asn?) => 'AS$asn',
      _ => null,
    };
    return Row(
      spacing: gap,
      children: [
        _Cell(
          label: appLocalizations.runTime,
          value: active ? const _RunTimeValue() : const _Placeholder(),
        ),
        Flexible(
          child: _Cell(
            label: appLocalizations.ipOrganization,
            value: organization != null
                ? _CellText(organization)
                : loading
                ? SkeletonText(width: 96, style: _cellStyle(context))
                : const _Placeholder(),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        const SizedBox(height: 2),
        value,
      ],
    );
  }
}

TextStyle _cellStyle(BuildContext context) =>
    AppTextStyle.subheadline.of(context, emphasized: true).toTabular;

class _CellText extends StatelessWidget {
  const _CellText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _cellStyle(context),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Text('—', maxLines: 1, style: _cellStyle(context));
  }
}

class _RunTimeValue extends ConsumerWidget {
  const _RunTimeValue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CellText(getTimeText(ref.watch(runTimeProvider)));
  }
}
