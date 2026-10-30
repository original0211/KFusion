import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/singbox_action.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/views/proxies/card.dart';
import 'package:material_ui/material_ui.dart';

/// The main screen labels the exit leaf while connected (the status row owns the dot then); the proxies page always dots it.
enum HaraExitMarker { dot, label }

class HaraProxyGroupSection extends ConsumerWidget {
  const HaraProxyGroupSection({
    super.key,
    required this.group,
    required this.exitName,
    required this.first,
    required this.exitMarker,
  });

  final Group group;
  final String? exitName;
  final bool first;
  final HaraExitMarker exitMarker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final panel = ref.watch(singBoxPanelGroupsProvider).value ?? const {};
    final panelGroup = panel[group.name];
    final autoChild = panelGroup == null
        ? null
        : singBoxPanelAutoChild(panel, group.name);
    final nativeAuto = panelGroup?.type == 'URLTest';
    final saved = ref.watch(proxyNameProvider(group.name));
    final childNow = autoChild == null ? '' : panel[autoChild]?.now ?? '';
    final autoMarked =
        autoChild != null &&
        saved == autoChild &&
        exitName != null &&
        (exitName == autoChild || exitName == childNow);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: first
                    ? HaraSpace.titleToFirstGroup
                    : HaraSpace.groupGap,
              ),
              if (nativeAuto)
                Row(
                  children: [
                    Flexible(
                      child: EmojiText(
                        group.name,
                        style: HaraText.sectionTitle(context, palette.dim),
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: HaraSpace.dotNameGap),
                    Text(
                      context.appLocalizations.auto,
                      style: HaraText.inUse(context, palette.dim),
                    ),
                  ],
                )
              else
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
          itemCount: group.all.length + (autoChild != null ? 1 : 0),
          itemBuilder: (context, index) {
            if (autoChild != null && index == 0) {
              return _HaraAutoRow(
                group: group,
                childTag: autoChild,
                childNow: childNow,
                isExit: exitName == autoChild || exitName == childNow,
                exitMarker: exitMarker,
              );
            }
            final proxy = group.all[autoChild != null ? index - 1 : index];
            return _HaraProxyRow(
              group: group,
              proxy: proxy,
              isExit: proxy.name == exitName && !autoMarked,
              exitMarker: exitMarker,
              locked: nativeAuto,
              forceSelected: nativeAuto && proxy.name == panelGroup?.now,
            );
          },
        ),
      ],
    );
  }
}

class _HaraAutoRow extends ConsumerWidget {
  const _HaraAutoRow({
    required this.group,
    required this.childTag,
    required this.childNow,
    required this.isExit,
    required this.exitMarker,
  });

  final Group group;
  final String childTag;
  final String childNow;
  final bool isExit;
  final HaraExitMarker exitMarker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final selected = ref.watch(
      proxyNameProvider(group.name).select((name) => name == childTag),
    );
    final marked = isExit && selected;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: () => ref
          .read(proxiesActionProvider.notifier)
          .changeProxyDebounce(group.name, childTag),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.nodeRowVertical,
            ),
            child: Row(
              children: [
                if (marked && exitMarker == HaraExitMarker.dot) ...[
                  const HaraDot(size: HaraSpace.dotRow),
                  const SizedBox(width: HaraSpace.dotNameGap),
                ],
                Expanded(
                  child: Text(
                    context.appLocalizations.auto,
                    style: HaraText.nodeName(
                      context,
                      palette.ink,
                      current: selected,
                    ),
                    maxLines: 1,
                  ),
                ),
                if (marked && exitMarker == HaraExitMarker.label) ...[
                  Text(
                    context.appLocalizations.currentExit,
                    style: HaraText.inUse(context, palette.dim),
                  ),
                  const SizedBox(width: 16),
                ],
                if (childNow.isNotEmpty)
                  _HaraDelay(
                    group: group,
                    proxy: Proxy(name: childNow, type: 'URLTest'),
                  )
                else
                  Text('—', style: HaraText.untested(context, palette.dim)),
              ],
            ),
          ),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }
}

class _HaraProxyRow extends ConsumerWidget {
  const _HaraProxyRow({
    required this.group,
    required this.proxy,
    required this.isExit,
    required this.exitMarker,
    this.locked = false,
    this.forceSelected = false,
  });

  final Group group;
  final Proxy proxy;
  final bool isExit;
  final HaraExitMarker exitMarker;
  final bool locked;
  final bool forceSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final selected =
        forceSelected ||
        ref.watch(
          selectedProxyNameProvider(
            group.name,
          ).select((name) => name == proxy.name),
        );
    final isGroup = GroupType.values.any((type) => type.name == proxy.type);
    final marked = isExit && selected;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: locked
          ? null
          : () => selectGroupProxy(
              ref,
              groupName: group.name,
              groupType: group.type,
              proxyName: proxy.name,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.nodeRowVertical,
            ),
            child: Row(
              children: [
                if (marked && exitMarker == HaraExitMarker.dot) ...[
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
                if (marked && exitMarker == HaraExitMarker.label) ...[
                  Text(
                    context.appLocalizations.currentExit,
                    style: HaraText.inUse(context, palette.dim),
                  ),
                  const SizedBox(width: 16),
                ],
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
