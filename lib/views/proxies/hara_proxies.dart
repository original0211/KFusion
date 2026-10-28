import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/card.dart';
import 'package:kfusion/views/proxies/setting.dart';
import 'package:material_ui/material_ui.dart';

// The Hara A reading of the proxies page: a page title, text actions, and
// hairline-separated single-line rows grouped under small section titles.
// The page reads the same providers as the tab and list readings and writes
// selections and delay tests through the same actions; only the composition
// is new. The single vermilion dot on the screen marks the current exit
// leaf: the selection of the GLOBAL group (or the first group) followed
// through nested groups to the leaf that actually carries the traffic.
class HaraProxiesView extends ConsumerStatefulWidget {
  const HaraProxiesView({super.key});

  @override
  ConsumerState<HaraProxiesView> createState() => _HaraProxiesViewState();
}

class _HaraProxiesViewState extends ConsumerState<HaraProxiesView> {
  final _searchController = TextEditingController();
  var _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _searchController.clear();
      ref.read(queryProvider(QueryTag.proxies).notifier).value = '';
    }
  }

  void _testAll(List<Group> groups) {
    final action = ref.read(proxiesActionProvider.notifier);
    for (final group in groups) {
      action.delayTestPageGroup(group.name);
    }
  }

  void _openSettings() {
    showSheet(
      context: context,
      builder: (_) {
        return CommonScaffold(
          body: const ProxiesSetting(),
          title: context.appLocalizations.settings,
        );
      },
    );
  }

  String? _exitLeafName(List<Group> groups) {
    if (groups.isEmpty) return null;
    final head = groups.where((group) => group.name == 'GLOBAL').firstOrNull;
    final start = ref.watch(
      selectedProxyNameProvider((head ?? groups.first).name),
    );
    if (start == null || start.isEmpty) return null;
    return ref.watch(realSelectedProxyStateProvider(start)).proxyName;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final groups = ref.watch(
      proxiesListStateProvider.select((state) => state.groups),
    );
    final exitName = _exitLeafName(groups);
    return Material(
      color: palette.bg,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(child: _header(groups)),
                      if (groups.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: _HaraProxiesEmpty(),
                        )
                      else
                        for (final (index, group) in groups.indexed)
                          _HaraGroupSection(
                            group: group,
                            exitName: exitName,
                            first: index == 0,
                          ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: HaraSpace.modeToNavGap),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(List<Group> groups) {
    final palette = context.haraPalette;
    final localizations = context.appLocalizations;
    Widget action(String label, VoidCallback onTap) {
      return InkWell(
        customBorder: AppShape.hara,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: HaraText.pageAction(context, palette.dim)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: HaraSpace.titleTopGap),
        Row(
          children: [
            Text(
              localizations.proxies,
              style: HaraText.pageTitle(context, palette.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    action(
                      localizations.actionDelayTest,
                      () => _testAll(groups),
                    ),
                    action(localizations.settings, _openSettings),
                    action(localizations.search, _toggleSearch),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_searching) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: palette.line, width: 0.7),
              ),
            ),
            child: TextField(
              controller: _searchController,
              autocorrect: false,
              decoration: InputDecoration.collapsed(
                hintText: localizations.search,
                hintStyle: HaraText.statusNode(context, palette.dim),
              ),
              style: HaraText.nodeName(context, palette.ink, current: false),
              onChanged: (value) {
                ref.read(queryProvider(QueryTag.proxies).notifier).value =
                    value;
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _HaraProxiesEmpty extends StatelessWidget {
  const _HaraProxiesEmpty();

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DiscRingMotif(size: 72, color: palette.dim),
          const SizedBox(height: 20),
          Text(
            context.appLocalizations.nullTip(context.appLocalizations.proxies),
            style: HaraText.statusNode(context, palette.sub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HaraGroupSection extends StatelessWidget {
  const _HaraGroupSection({
    required this.group,
    required this.exitName,
    required this.first,
  });

  final Group group;
  final String? exitName;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: first
                    ? HaraSpace.titleToFirstGroup
                    : HaraSpace.groupGap,
              ),
              EmojiText(
                group.name,
                style: HaraText.sectionTitle(context, palette.dim),
                maxLines: 1,
              ),
              const SizedBox(height: HaraSpace.sectionTitleGap),
              HaraHairline(color: palette.line),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: group.all.length,
          itemBuilder: (context, index) {
            final proxy = group.all[index];
            return _HaraProxyRow(
              group: group,
              proxy: proxy,
              isExit: proxy.name == exitName,
            );
          },
        ),
      ],
    );
  }
}

class _HaraProxyRow extends ConsumerWidget {
  const _HaraProxyRow({
    required this.group,
    required this.proxy,
    required this.isExit,
  });

  final Group group;
  final Proxy proxy;
  final bool isExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final selected = ref.watch(
      selectedProxyNameProvider(
        group.name,
      ).select((name) => name == proxy.name),
    );
    final isGroup = GroupType.values.any((type) => type.name == proxy.type);
    return InkWell(
      customBorder: AppShape.hara,
      onTap: () => selectGroupProxy(
        ref,
        groupName: group.name,
        groupType: group.type,
        proxyName: proxy.name,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.nodeRowVertical,
            ),
            child: Row(
              children: [
                if (isExit && selected) ...[
                  const HaraDot(size: HaraSpace.dotRow),
                  const SizedBox(width: HaraSpace.dotNameGap),
                ],
                Expanded(
                  child: EmojiText(
                    proxy.name,
                    style: HaraText.nodeName(
                      context,
                      palette.ink,
                      current: selected,
                    ),
                    maxLines: 1,
                  ),
                ),
                if (isGroup)
                  _HaraRealSelected(group: group, proxy: proxy)
                else
                  _HaraDelay(group: group, proxy: proxy),
              ],
            ),
          ),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }
}

class _HaraRealSelected extends ConsumerWidget {
  const _HaraRealSelected({required this.group, required this.proxy});

  final Group group;
  final Proxy proxy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final real = ref.watch(realSelectedProxyStateProvider(proxy.name));
    if (real.proxyName.isEmpty || real.proxyName == proxy.name) {
      return const SizedBox.shrink();
    }

    return Flexible(
      child: EmojiText(
        '→ ${real.proxyName}',
        style: HaraText.statusNode(context, palette.sub),
        maxLines: 1,
      ),
    );
  }
}

class _HaraDelay extends ConsumerWidget {
  const _HaraDelay({required this.group, required this.proxy});

  final Group group;
  final Proxy proxy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final delay = ref.watch(
      delayProvider(proxyName: proxy.name, testUrl: group.testUrl),
    );
    // Watched so the slot rebuilds when a test starts and lands.
    ref.watch(
      delayTestPhaseProvider(proxyName: proxy.name, testUrl: group.testUrl),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref
          .read(proxiesActionProvider.notifier)
          .proxyDelayTest(proxy, group.testUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: _content(context, palette, delay),
      ),
    );
  }

  Widget _content(BuildContext context, HaraPalette palette, int? delay) {
    if (delay == null) {
      return Text('—', style: HaraText.untested(context, palette.dim));
    }
    if (delay <= 0) {
      return Text(
        delayFailureText(delay, context.appLocalizations),
        style: HaraText.delay(context, palette.sub),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$delay', style: HaraText.delay(context, palette.sub)),
          TextSpan(
            text: ' ms',
            style: HaraText.delayUnit(context, palette.sub),
          ),
        ],
      ),
    );
  }
}
