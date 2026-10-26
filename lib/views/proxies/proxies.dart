import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/node_ip.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/list.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'setting.dart';
import 'tab.dart';

class ProxiesView extends ConsumerStatefulWidget {
  const ProxiesView({super.key, this.picker = false});

  /// Leaves the bar only its search and delay test, for picking a proxy from a
  /// sheet.
  final bool picker;

  @override
  ConsumerState<ProxiesView> createState() => _ProxiesViewState();
}

class _ProxiesViewState extends ConsumerState<ProxiesView> {
  final GlobalKey<ProxiesTabViewState> _proxiesTabKey = GlobalKey();
  late final NodeIpSweeper _sweeper;

  // The same instance on every build, so the bar changing with the current
  // group or its delay test leaves the page alone.
  late final _tabView = ProxiesTabView(key: _proxiesTabKey);
  bool _isTab = false;
  List<Group>? _pendingSweep;
  bool _sweepScheduled = false;

  List<CommonPopupMenuItem> _buildMenuItems(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.sliders,
        label: appLocalizations.settings,
        onPressed: () {
          showSheet(
            context: context,
            builder: (_) {
              return CommonScaffold(
                body: const ProxiesSetting(),
                title: appLocalizations.settings,
              );
            },
          );
        },
      ),
    ];
  }

  IconButtonData? _buildPrimaryAction() {
    if (!_isTab) {
      return null;
    }
    final isDelayTesting = ref.watch(currentGroupDelayTestingProvider);
    return IconButtonData(
      glyph: AppGlyphs.bolt,
      onPressed: () {
        _proxiesTabKey.currentState?.delayTestCurrentGroup();
      },
      tooltip: context.appLocalizations.delayTest,
      isLoading: isDelayTesting,
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.proxies).notifier).value = value;
  }

  @override
  void initState() {
    super.initState();
    _sweeper = ref.read(nodeIpSweeperProvider.notifier);
    ref.listenManual(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.tab,
      ),
      (prev, next) {
        if (prev != next) {
          setState(() {
            _isTab = next;
          });
        }
      },
      fireImmediately: true,
    );
    ref.listenManual(groupsProvider, (_, groups) {
      _pendingSweep = groups;
      if (_sweepScheduled) return;
      _sweepScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sweepScheduled = false;
        final pending = _pendingSweep;
        _pendingSweep = null;
        if (!mounted || pending == null) return;
        _sweeper.sweep([
          for (final group in pending)
            for (final proxy in group.all)
              if (!GroupType.values.any((type) => type.name == proxy.type) &&
                  proxy.name != 'REJECT')
                proxy.name,
        ]);
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sweeper.cancelSweep();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proxiesType = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.type),
    );
    final isLoading = ref.watch(loadingProvider(LoadingTag.proxies));
    final picker = widget.picker;
    final primaryAction = _buildPrimaryAction();
    return CommonScaffold(
      isLoading: isLoading,
      resizeToAvoidBottomInset: false,
      primaryAction: primaryAction,
      searchActions: [?primaryAction],
      iconActions: [
        if (_isTab && !picker)
          IconButtonData(
            glyph: AppGlyphs.locate,
            onPressed: () {
              _proxiesTabKey.currentState?.scrollToGroupSelected();
            },
            tooltip: context.appLocalizations.scrollToSelected,
          ),
      ],
      menuItems: picker ? const [] : _buildMenuItems(context),
      title: context.appLocalizations.proxies,
      searchState: AppBarSearchState(onSearch: _onSearch),
      body: Column(
        children: [
          if (!picker) const _IpProbeNotice(),
          Expanded(
            child: switch (proxiesType) {
              ProxiesType.tab => _tabView,
              ProxiesType.list => const ProxiesListView(),
            },
          ),
        ],
      ),
    );
  }
}

/// One-time note under the bar: the type marks come from probing each
/// node's real exit IP, so they fill in gradually on the first visit.
class _IpProbeNotice extends ConsumerStatefulWidget {
  const _IpProbeNotice();

  @override
  ConsumerState<_IpProbeNotice> createState() => _IpProbeNoticeState();
}

class _IpProbeNoticeState extends ConsumerState<_IpProbeNotice> {
  bool _loaded = false;
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    Preferences().getNodeIpNoticeSeen().then((seen) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _seen = seen;
      });
    });
  }

  void _dismiss() {
    setState(() => _seen = true);
    Preferences().setNodeIpNoticeSeen();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      appSettingProvider.select((state) => state.probeNodeIpType),
    );
    if (!_loaded || _seen || !enabled) return const SizedBox.shrink();
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.raisedSurfaceLevel.colorOf(colorScheme),
          shape: AppShape.lg.copyWith(side: colorScheme.cabinRimSide),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Text(
                  context.appLocalizations.ipProbeNotice,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            IconButton(
              tooltip: context.appLocalizations.close,
              onPressed: _dismiss,
              icon: const GlyphIcon(AppGlyphs.close, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}
