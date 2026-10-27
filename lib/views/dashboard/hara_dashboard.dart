import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/service_probe.dart';
import 'package:kfusion/core/core.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/outbound_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/providers/routed_probe.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/profiles/universal_import.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'probe_start_hold.dart';
import 'widgets/core_status_button.dart';

const _pendingBudget = Duration(seconds: 45);
const _stickyExtent = 48.0;

/// The dashboard in the Hara A reading: one white field, the outline ring
/// as the switch, a fixed list of figures and a text mode row. It reads the
/// same providers the cabin core read and starts and stops the core through
/// the same action; only the presentation is new.
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
    required bool suspended,
    required ProbeEntry<IpInfo> entry,
  }) {
    if (!hasProfile) return _Phase.noProfile;
    if (_pending == true && !isStart) return _Phase.connecting;
    if (_pending == false && isStart) return _Phase.disconnecting;
    if (!isStart) return _Phase.disconnected;
    if (suspended) return _Phase.suspended;
    if (shownPhase(entry) == ProbePhase.failed && entry.value == null) {
      return _Phase.error;
    }
    return _Phase.connected;
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
    final phase = _phase(
      hasProfile: hasProfile,
      isStart: isStart,
      suspended: suspended,
      entry: entry,
    );
    final profile = ref.watch(currentProfileProvider);
    final ipInfo = entry.value;
    final nodeName = ipInfo == null ? null : entry.stamp?.chains.firstOrNull;
    final delay = nodeName == null
        ? null
        : ref.watch(delayProvider(proxyName: nodeName));
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: KeyedSubtree(
                        key: _heroKey,
                        child: _hero(
                          context,
                          phase: phase,
                          palette: palette,
                          profile: profile,
                          nodeName: nodeName,
                        ),
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      child: phase == _Phase.noProfile
                          ? const SizedBox.shrink()
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _dataList(
                                  context,
                                  phase: phase,
                                  palette: palette,
                                  ipInfo: ipInfo,
                                  delay: delay,
                                ),
                                const SizedBox(height: HaraSpace.listToModeGap),
                                _modeRow(context, palette),
                                const SizedBox(height: HaraSpace.modeToNavGap),
                              ],
                            ),
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
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: HaraSpace.brandTopGap),
          Row(
            children: [
              Text('KFUSION', style: HaraText.brand(context, palette.dim)),
              const Spacer(),
              if (coreLib == null) const CoreStatusButton(),
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
                  : _toggle,
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
                  const SizedBox(width: 10),
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
            Text('→', style: HaraText.addRow(context, palette.sub)),
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
  }) {
    final appLocalizations = context.appLocalizations;
    final showValues =
        phase == _Phase.connected ||
        phase == _Phase.suspended ||
        phase == _Phase.disconnecting;
    final hideIp = ref.watch(
      appSettingProvider.select((state) => state.hideIp),
    );
    final runTime = ref.watch(runTimeProvider);
    final latest = ref.watch(trafficsProvider).list.safeLast(const Traffic());
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
    final exitRow = valueOf(
      showValues && ipInfo != null,
      hideIp ? '*****' : (ipInfo?.ip ?? ''),
    );
    final elapsedRow = valueOf(showValues, getTimeText(runTime));
    final downShow = latest.down.traffic;
    final downRow = valueOf(showValues, downShow.value, '${downShow.unit}/s');
    final upShow = latest.up.traffic;
    final upRow = valueOf(showValues, upShow.value, '${upShow.unit}/s');
    final totalShow = (total.up + total.down).traffic;
    final sessionRow = valueOf(showValues, totalShow.value, totalShow.unit);
    final rows = <(String, (String, Color, String?))>[
      (appLocalizations.delay, delayRow),
      (appLocalizations.ipExit, exitRow),
      (appLocalizations.connected, elapsedRow),
      (appLocalizations.download, downRow),
      (appLocalizations.upload, upRow),
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
