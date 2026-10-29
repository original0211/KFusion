import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/core/core.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/core_kind.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/features/ip_quality/labels.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/ip_quality.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/profiles/universal_import.dart';
import 'package:kfusion/views/proxies/hara_proxies.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'probe_start_hold.dart';
import 'widgets/core_status_button.dart';

const _pendingBudget = Duration(seconds: 45);
const _stickyExtent = 48.0;

String _coreName(CoreKind kind) {
  return switch (kind) {
    CoreKind.mihomo => 'mihomo',
    CoreKind.singbox => 'sing-box',
  };
}

/// The main screen in the Hara A reading: the ring, status row, figures
/// and mode row over the proxies reading's grouped node list, on one
/// scroll surface. A running sing-box core is presented, not controlled.
class HaraDashboard extends ConsumerStatefulWidget {
  const HaraDashboard({super.key});

  @override
  ConsumerState<HaraDashboard> createState() => _HaraDashboardState();
}

enum _Phase {
  noProfile,
  disconnected,
  connecting,
  connected,
  disconnecting,
  suspended,
  error,
}

class _HaraDashboardState extends ConsumerState<HaraDashboard>
    with ProbeStartHold<HaraDashboard> {
  late final OutboundIpProbe _probe;
  bool? _pending;
  Timer? _pendingTimer;
  late final ScrollController _scrollController;
  final _sticky = ValueNotifier<bool>(false);
  final _heroKey = GlobalKey();
  double? _heroExtent;

  @override
  void initState() {
    super.initState();
    _scrollController = sheetScrollController(context);
    _probe = ref.read(outboundIpProbeProvider.notifier)..watch(routedOutbound);
    ref.listenManual(isStartProvider, (previous, next) {
      if (!mounted) return;
      if (previous != next && _pending == next) {
        setState(() {
          _pending = null;
          _pendingTimer?.cancel();
        });
      }
    });
    _scrollController.addListener(_updateSticky);
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _probe.unwatch(routedOutbound);
    _scrollController.dispose();
    _sticky.dispose();
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

  void _updateSticky() {
    final extent = _heroExtent;
    if (extent == null || !_scrollController.hasClients) return;
    final show = _scrollController.offset >= extent - _stickyExtent;
    if (show != _sticky.value) _sticky.value = show;
  }

  _Phase _phase({
    required bool hasProfile,
    required bool isStart,
    required bool singBoxRunning,
    required bool suspended,
    required ProbeEntry<IpInfo> entry,
  }) {
    if (!hasProfile) return _Phase.noProfile;
    if (_pending == true && !isStart) return _Phase.connecting;
    if (_pending == false && isStart) return _Phase.disconnecting;
    if (singBoxRunning && !isStart) return _Phase.connected;
    if (!isStart) return _Phase.disconnected;
    if (suspended) return _Phase.suspended;
    if (shownPhase(entry) == ProbePhase.failed && entry.value == null) {
      return _Phase.error;
    }
    return _Phase.connected;
  }

  // The exit chain: follow group selections from GLOBAL (or the first
  // group) down to the leaf that actually carries the traffic.
  ({String group, String leaf})? _exitLeaf(List<Group> groups) {
    if (groups.isEmpty) return null;
    final byName = {for (final group in groups) group.name: group};
    var current = byName['GLOBAL'] ?? groups.first;
    final visited = <String>{};
    while (visited.add(current.name)) {
      final selected = ref.watch(selectedProxyNameProvider(current.name));
      if (selected == null || selected.isEmpty) return null;
      final next = byName[selected];
      if (next == null) {
        return (group: current.name, leaf: selected);
      }
      current = next;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final hasProfile = ref.watch(
      profilesProvider.select((state) => state.isNotEmpty),
    );
    final isStart = ref.watch(isStartProvider);
    final suspended = isStart && ref.watch(suspendProvider);
    final entry = ref.watch(
      outboundIpProbeProvider.select((state) => state.entryOf(routedOutbound)),
    );
    final singBoxRunning =
        ref.watch(singBoxActionProvider).value?.state == SingBoxState.running;
    final runningCore = singBoxRunning
        ? CoreKind.singbox
        : (isStart ? CoreKind.mihomo : null);
    final activeKind =
        ref.watch(activeCoreKindProvider).value ?? CoreKind.mihomo;
    final phase = _phase(
      hasProfile: hasProfile,
      isStart: isStart,
      singBoxRunning: singBoxRunning,
      suspended: suspended,
      entry: entry,
    );
    final profile = ref.watch(currentProfileProvider);
    final ipInfo = entry.value;
    final nodeName = ipInfo == null ? null : entry.stamp?.chains.firstOrNull;
    final delay = nodeName == null
        ? null
        : ref.watch(delayProvider(proxyName: nodeName));
    final groups = ref.watch(
      proxiesListStateProvider.select((state) => state.groups),
    );
    final exit = _exitLeaf(groups);
    final pinAllowed = phase == _Phase.connected || phase == _Phase.suspended;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _heroKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) _heroExtent = box.size.height;
    });
    return Material(
      color: palette.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            HaraSpace.pageInset,
            (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
          );
          return Stack(
            children: [
              CustomScrollView(
                controller: _scrollController,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: side),
                    sliver: SliverMainAxisGroup(
                      slivers: [
                        SliverToBoxAdapter(
                          child: KeyedSubtree(
                            key: _heroKey,
                            child: _hero(
                              context,
                              phase: phase,
                              palette: palette,
                              profile: profile,
                              nodeName: nodeName,
                              runningCore: runningCore,
                            ),
                          ),
                        ),
                        if (phase != _Phase.noProfile) ...[
                          SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _dataList(
                                  context,
                                  phase: phase,
                                  palette: palette,
                                  ipInfo: ipInfo,
                                  delay: delay,
                                  runningCore: runningCore,
                                  activeKind: activeKind,
                                ),
                                const SizedBox(height: HaraSpace.listToModeGap),
                                _modeRow(context, palette),
                              ],
                            ),
                          ),
                          for (final group in groups)
                            HaraProxyGroupSection(
                              group: group,
                              exitName: exit != null && exit.group == group.name
                                  ? exit.leaf
                                  : null,
                              first: false,
                              exitMarker: pinAllowed
                                  ? HaraExitMarker.label
                                  : HaraExitMarker.dot,
                            ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: HaraSpace.modeToNavGap),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (pinAllowed)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _sticky,
                    builder: (context, show, _) {
                      if (!show) return const SizedBox.shrink();
                      return _stickyBar(
                        context,
                        phase: phase,
                        palette: palette,
                        nodeName: nodeName,
                        side: side,
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(
    BuildContext context, {
    required _Phase phase,
    required HaraPalette palette,
    required Profile? profile,
    required String? nodeName,
    required CoreKind? runningCore,
  }) {
    final appLocalizations = context.appLocalizations;
    final ringColor = switch (phase) {
      _Phase.noProfile || _Phase.disconnected => palette.dim,
      _Phase.connected ||
      _Phase.suspended => palette.ink.withValues(alpha: 0.78),
      _ => palette.ink,
    };
    final statusText = switch (phase) {
      _Phase.noProfile => appLocalizations.addProfile,
      _Phase.disconnected => appLocalizations.disconnected,
      _Phase.connecting => appLocalizations.connecting,
      _Phase.connected => appLocalizations.connected,
      _Phase.disconnecting => appLocalizations.disconnecting,
      _Phase.suspended => appLocalizations.suspended,
      _Phase.error => appLocalizations.connectionFailed,
    };
    final statusColor = switch (phase) {
      _Phase.error => context.colorScheme.error,
      _Phase.disconnected || _Phase.disconnecting => palette.sub,
      _Phase.noProfile => palette.sub,
      _ => palette.ink,
    };
    final shownNode = switch (phase) {
      _Phase.disconnected || _Phase.noProfile => profile?.realLabel,
      _ => nodeName ?? profile?.realLabel,
    };
    final idleCore = switch (runningCore) {
      CoreKind.mihomo => CoreKind.singbox,
      CoreKind.singbox => CoreKind.mihomo,
      null => null,
    };
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: HaraSpace.brandTopGap),
          Row(
            children: [
              Text('KFUSION', style: HaraText.brand(context, palette.dim)),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (idleCore != null) ...[
                      Flexible(
                        child: Text(
                          appLocalizations.coreNotRunning(_coreName(idleCore)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: HaraText.statusNode(context, palette.dim),
                        ),
                      ),
                      if (coreLib == null) const SizedBox(width: 12),
                    ],
                    if (coreLib == null) const CoreStatusButton(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HaraSpace.ringTopGap),
          Semantics(
            button: true,
            label: statusText,
            child: InkWell(
              customBorder: AppShape.circle,
              onTap: phase == _Phase.noProfile
                  ? () =>
                        BaseNavigator.push(context, const UniversalImportView())
                  : (runningCore == CoreKind.singbox ? null : _toggle),
              child: DiscRingMotif(
                size: HaraSpace.ringSize,
                color: ringColor,
                strokeWidth: HaraSpace.ringStroke,
              ),
            ),
          ),
          const SizedBox(height: HaraSpace.statusTopGap),
          if (phase == _Phase.noProfile)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                statusText,
                textAlign: TextAlign.center,
                style: HaraText.statusNode(context, palette.sub),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (phase == _Phase.connected || phase == _Phase.suspended)
                  const HaraDot(size: HaraSpace.dotStatus),
                if (phase == _Phase.connected || phase == _Phase.suspended)
                  const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HaraText.status(context, statusColor),
                  ),
                ),
              ],
            ),
          if (phase == _Phase.error) ...[
            const SizedBox(height: 8),
            Text(
              appLocalizations.serviceFailed,
              textAlign: TextAlign.center,
              style: HaraText.statusNode(context, palette.sub),
            ),
          ],
          if (phase != _Phase.noProfile) ...[
            const SizedBox(height: HaraSpace.nodeTopGap),
            Text(
              shownNode ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: HaraText.statusNode(context, palette.sub),
            ),
          ],
          if (phase == _Phase.noProfile) ...[
            const SizedBox(height: 34),
            _importRow(context, palette),
          ],
        ],
      ),
    );
  }

  Widget _importRow(BuildContext context, HaraPalette palette) {
    final appLocalizations = context.appLocalizations;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: () => BaseNavigator.push(context, const UniversalImportView()),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              appLocalizations.addProfile,
              style: HaraText.addRow(context, palette.sub),
            ),
            const SizedBox(width: 8),
            Text('→', style: HaraText.addRowArrow(context, palette.sub)),
          ],
        ),
      ),
    );
  }

  Widget _stickyBar(
    BuildContext context, {
    required _Phase phase,
    required HaraPalette palette,
    required String? nodeName,
    required double side,
  }) {
    final appLocalizations = context.appLocalizations;
    final statusText = phase == _Phase.suspended
        ? appLocalizations.suspended
        : appLocalizations.connected;
    return Material(
      color: palette.bg,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: side),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _stickyExtent - HaraSpace.hairline,
              child: Row(
                children: [
                  DiscRingMotif(
                    size: HaraSpace.ringCompact,
                    color: palette.ink.withValues(alpha: 0.78),
                    strokeWidth: HaraSpace.ringStroke,
                  ),
                  const SizedBox(width: 10),
                  const HaraDot(size: HaraSpace.dotRow),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: HaraText.statusNode(context, palette.ink),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nodeName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HaraText.statusNode(context, palette.sub),
                    ),
                  ),
                ],
              ),
            ),
            const HaraHairline(),
          ],
        ),
      ),
    );
  }

  Widget _dataList(
    BuildContext context, {
    required _Phase phase,
    required HaraPalette palette,
    required IpInfo? ipInfo,
    required int? delay,
    required CoreKind? runningCore,
    required CoreKind activeKind,
  }) {
    final appLocalizations = context.appLocalizations;
    final showValues =
        phase == _Phase.connected ||
        phase == _Phase.suspended ||
        phase == _Phase.disconnecting;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final total = ref.watch(totalTrafficProvider);
    final dash = ('—', palette.dim, null as String?);
    (String, Color, String?) valueOf(bool ok, String value, [String? unit]) {
      return ok ? (value, palette.ink, unit) : dash;
    }

    final delayRow = valueOf(
      showValues && delay != null && delay > 0,
      '$delay',
      'ms',
    );
    final exitIp = showValues && !hideIp ? ipInfo?.ip : null;
    final exitType = exitIp == null
        ? null
        : ref.watch(ipQualityProvider(exitIp)).value?.type;
    // The country rides the same probe answer as the address itself, so
    // it resolves locally and lands with the IP, unlike the type.
    final exitCountry = exitIp == null
        ? null
        : countryName(ipInfo!.countryCode, Localizations.localeOf(context));
    final shownIp = hideIp ? '*****' : (ipInfo?.ip ?? '');
    final exitRow = valueOf(
      showValues && ipInfo != null,
      [
        shownIp,
        ?exitCountry,
        if (exitType != null) exitType.label(context),
      ].join(' · '),
    );
    final kernelRow = valueOf(showValues, _coreName(runningCore ?? activeKind));
    // The counters are mihomo-fed; under sing-box they would misreport zero.
    final totalShow = (total.up + total.down).traffic;
    final sessionRow = valueOf(
      showValues && runningCore != CoreKind.singbox,
      totalShow.value,
      totalShow.unit,
    );
    final rows = <(String, (String, Color, String?))>[
      (appLocalizations.delay, delayRow),
      (appLocalizations.ipExit, exitRow),
      (appLocalizations.core, kernelRow),
      (appLocalizations.totalTraffic, sessionRow),
    ];
    return Column(
      children: [
        for (final (label, value) in rows) ...[
          const HaraHairline(),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.dataRowVertical,
            ),
            child: Row(
              children: [
                Text(label, style: HaraText.dataKey(context, palette.sub)),
                const Spacer(),
                Text(value.$1, style: HaraText.dataValue(context, value.$2)),
                if (value.$3 != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    value.$3!,
                    style: HaraText.dataUnit(context, palette.sub),
                  ),
                ],
              ],
            ),
          ),
        ],
        const HaraHairline(),
      ],
    );
  }

  Widget _modeRow(BuildContext context, HaraPalette palette) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    return Row(
      children: [
        for (final (index, item) in Mode.values.indexed) ...[
          if (index > 0) const SizedBox(width: HaraSpace.modeItemGap),
          InkWell(
            customBorder: AppShape.hara,
            onTap: () {
              if (mode == item) return;
              ref.read(setupActionProvider.notifier).changeMode(item);
            },
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.label,
                    style: HaraText.mode(
                      context,
                      item == mode ? palette.ink : palette.dim,
                      selected: item == mode,
                    ),
                  ),
                  const SizedBox(height: HaraSpace.modeUnderlineGap),
                  Container(
                    height: HaraSpace.modeUnderline,
                    color: item == mode ? palette.ink : HaraPalette.transparent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
