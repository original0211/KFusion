import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/about.dart';
import 'package:kfusion/views/access.dart';
import 'package:kfusion/views/backup_and_restore.dart';
import 'package:kfusion/views/config/dns.dart';
import 'package:kfusion/views/config/general.dart';
import 'package:kfusion/views/config/network.dart';
import 'package:kfusion/views/config/on_demand.dart';
import 'package:kfusion/views/developer.dart';
import 'package:kfusion/views/logs.dart';
import 'package:kfusion/views/proxies/setting.dart';
import 'package:kfusion/views/resources.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'disclaimer.dart';
import 'theme.dart';

// The settings page in the Hara A reading: a white field, an in-body
// title, and hairline sections over the half page's own sections,
// bindings and destinations. The core switch card keeps its panel
// form — its corner档 and shadow are pinned by the cabin standards.
// Since the flattening (2026-10-31) every destination page sits on
// this index directly; there is no gate page behind it.
class ToolsView extends ConsumerStatefulWidget {
  const ToolsView({super.key});

  @override
  ConsumerState<ToolsView> createState() => _ToolViewState();
}

class _ToolViewState extends ConsumerState<ToolsView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text;
      if (query != _query) {
        setState(() => _query = query);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // The takeover masters; their detail rows stay on the network page.
  List<ConsumerWidget> _takeoverItems() {
    if (system.isAndroid) {
      return const [VPNItem(), VpnSystemProxyItem()];
    }
    if (system.isDesktop) {
      return const [SystemProxyItem(), TUNItem()];
    }
    return const [];
  }

  Widget _section({String? title, required List<Widget> rows, String? footer}) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title, style: HaraText.sectionTitle(context, palette.dim)),
          const SizedBox(height: HaraSpace.sectionTitleGap),
        ],
        HaraHairline(color: palette.line),
        ...rows,
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(footer, style: HaraText.profileMeta(context, palette.dim)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final takeover = _takeoverItems();
    // The index: daily destinations first, then configuration, then
    // maintenance, then the legal rows. Every entry is one tap from
    // this page.
    final daily = <_Destination>[
      _Destination(appLocalizations.language, const _LocaleRow()),
      _Destination(
        appLocalizations.theme,
        _HaraOpenRow(label: appLocalizations.theme, target: const ThemeView()),
      ),
      _Destination(
        appLocalizations.proxySettings,
        _HaraOpenRow(
          label: appLocalizations.proxySettings,
          target: BaseScaffold(
            title: appLocalizations.proxySettings,
            body: const ProxiesSetting(),
          ),
        ),
      ),
      _Destination(
        appLocalizations.backupAndRestore,
        _HaraOpenRow(
          label: appLocalizations.backupAndRestore,
          target: const BackupAndRestore(),
        ),
      ),
      if (system.isAndroid)
        _Destination(
          appLocalizations.accessControl,
          _HaraOpenRow(
            label: appLocalizations.accessControl,
            target: const AccessView(),
          ),
        ),
    ];
    final configuration = <_Destination>[
      _Destination(
        appLocalizations.general,
        _HaraOpenRow(
          label: appLocalizations.general,
          target: const GeneralView(),
        ),
      ),
      _Destination(
        appLocalizations.network,
        _HaraOpenRow(
          label: appLocalizations.network,
          target: BaseScaffold(
            title: appLocalizations.network,
            body: const NetworkListView(),
          ),
        ),
      ),
      const _Destination('DNS', _HaraOpenRow(label: 'DNS', target: DnsView())),
      _Destination(
        appLocalizations.onDemand,
        _HaraOpenRow(
          label: appLocalizations.onDemand,
          target: const OnDemandView(),
        ),
      ),
    ];
    final maintenance = <_Destination>[
      _Destination(
        appLocalizations.logs,
        _HaraOpenRow(label: appLocalizations.logs, target: const LogsView()),
      ),
      _Destination(
        appLocalizations.resources,
        _HaraOpenRow(
          label: appLocalizations.resources,
          target: const ResourcesView(),
        ),
      ),
      _Destination(
        appLocalizations.developerMode,
        _HaraOpenRow(
          label: appLocalizations.developerMode,
          target: const DeveloperView(),
        ),
      ),
    ];
    final legal = <_Destination>[
      _Destination(
        appLocalizations.disclaimer,
        _HaraOpenRow(
          label: appLocalizations.disclaimer,
          target: const DisclaimerView(),
        ),
      ),
      _Destination(
        appLocalizations.about,
        _HaraOpenRow(label: appLocalizations.about, target: const AboutView()),
      ),
    ];
    final destinations = [...daily, ...configuration, ...maintenance, ...legal];
    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final matches = searching
        ? destinations
              .where((item) => item.label.toLowerCase().contains(query))
              .toList()
        : const <_Destination>[];
    final sections = <Widget>[
      const ItemPositionProvider(
        position: ItemPosition.startAndEnd,
        child: CoreSwitchItem(),
      ),
      _SearchRow(controller: _searchController),
      if (!searching) ...[
        _section(
          title: appLocalizations.startupAndBackground,
          rows: [
            for (final item in startupSettingItems())
              _HaraToggle(item as ConfigToggleItem),
          ],
          footer: [
            if (system.isDesktop) appLocalizations.silentLaunchDesc,
            appLocalizations.autoRunDesc,
          ].join('\n'),
        ),
        if (takeover.isNotEmpty)
          _section(rows: [for (final item in takeover) _HaraBoundToggle(item)]),
        _section(rows: [for (final item in daily) item.row]),
        _section(rows: [for (final item in configuration) item.row]),
        _section(rows: [for (final item in maintenance) item.row]),
        _section(rows: [for (final item in legal) item.row]),
      ] else
        _section(
          rows: [
            if (matches.isEmpty)
              _HaraRow(
                child: Text(
                  appLocalizations.noData,
                  style: HaraText.profileMeta(context, palette.dim),
                ),
              )
            else
              for (final item in matches) item.row,
          ],
        ),
    ];
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
              key: toolsStoreKey,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: HaraSpace.titleTopGap),
                        Text(
                          appLocalizations.settings,
                          style: HaraText.pageTitle(context, palette.ink),
                        ),
                        const SizedBox(height: HaraSpace.titleToList),
                        for (var i = 0; i < sections.length; i++) ...[
                          if (i > 0) const SizedBox(height: HaraSpace.groupGap),
                          sections[i],
                        ],
                        const SizedBox(height: HaraSpace.modeToNavGap),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One hairline row of the page: content over a bottom hairline.
class _HaraRow extends StatelessWidget {
  const _HaraRow({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: HaraSpace.nodeRowVertical,
          ),
          child: child,
        ),
        HaraHairline(color: palette.line),
      ],
    );
    if (onTap == null) return content;
    return InkWell(customBorder: AppShape.hara, onTap: onTap, child: content);
  }
}

/// A toggle row over an existing [ConfigToggleItem]: the item's own
/// selector and writer drive it; the row tap flips the value.
class _HaraToggle extends ConsumerWidget {
  const _HaraToggle(this.item);

  final ConfigToggleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    return Semantics(
      toggled: value,
      child: _HaraRow(
        onTap: () => item.onChanged(ref, !value),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.title(appLocalizations),
                style: HaraText.nodeName(context, palette.ink, current: false),
              ),
            ),
            HaraToggleMark(
              value: value,
              word: value
                  ? appLocalizations.enabled
                  : appLocalizations.disabled,
            ),
          ],
        ),
      ),
    );
  }
}

// The takeover items belong to the gated network page; building one
// here only assembles its ConfigToggleItem (a selector and a writer),
// which the Hara row renders instead of the item's own Material row.
class _HaraBoundToggle extends ConsumerWidget {
  const _HaraBoundToggle(this.source);

  final ConsumerWidget source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _HaraToggle(source.build(context, ref) as ConfigToggleItem);
  }
}

/// A row that opens a page: an ink label and a sub arrow. The open
/// follows the list row it replaces — sheet push or open container.
class _HaraOpenRow extends StatelessWidget {
  const _HaraOpenRow({required this.label, required this.target});

  final String label;
  final Widget target;

  Widget _content(BuildContext context) {
    final palette = context.haraPalette;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: HaraText.nodeName(context, palette.ink, current: false),
          ),
        ),
        Text('→', style: HaraText.addRowArrow(context, palette.sub)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    if (!context.isMobileView) {
      return _HaraRow(
        onTap: () {
          showExtend<dynamic>(
            context,
            props: const ExtendProps(forceFull: true),
            builder: (_) => target,
          );
        },
        child: _content(context),
      );
    }
    return OpenContainer<dynamic>(
      clipBehavior: Clip.none,
      closedColor: palette.bg,
      closedShape: AppShape.hara,
      closedBuilder: (context, action) {
        return _HaraRow(onTap: action, child: _content(context));
      },
      openBuilder: (_, _) => target,
    );
  }
}

/// One destination of the settings index: the label the search row
/// matches on, and the row itself.
class _Destination {
  const _Destination(this.label, this.row);

  final String label;
  final Widget row;
}

/// The search row under the core switch card: typing filters the
/// index to the destinations whose label matches, so a long index
/// never has to be scrolled end to end.
class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: HaraSpace.nodeRowVertical,
          ),
          child: Row(
            children: [
              GlyphIcon(AppGlyphs.search, color: palette.sub),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: HaraText.nodeName(
                    context,
                    palette.ink,
                    current: false,
                  ),
                  cursorColor: palette.ink,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: appLocalizations.search,
                    hintStyle: HaraText.nodeName(
                      context,
                      palette.dim,
                      current: false,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        HaraHairline(color: palette.line),
      ],
    );
  }
}

/// The language row: its end value opens the options row's popup menu.
class _LocaleRow extends ConsumerWidget {
  const _LocaleRow();

  String _label(BuildContext context, Locale? locale) {
    if (locale == null) return context.appLocalizations.defaultText;
    return locale.label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final locale = ref.watch(
      appSettingProvider.select((state) => state.locale),
    );
    final currentLocale = getLocaleForString(locale);
    PopupOpen? openMenu;
    return _HaraRow(
      onTap: () => openMenu?.call(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              appLocalizations.language,
              style: HaraText.nodeName(context, palette.ink, current: false),
            ),
          ),
          CommonPopupBox(
            targetBuilder: (open) {
              openMenu = open;
              return InkWell(
                customBorder: AppShape.hara,
                onTap: open,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label(context, currentLocale),
                      style: HaraText.statusNode(context, palette.sub),
                    ),
                    const SizedBox(width: 4),
                    GlyphIcon(AppGlyphs.picker, color: palette.sub),
                  ],
                ),
              );
            },
            popupBuilder: (_) => CommonPopupMenu(
              items: [
                for (final option in [
                  null,
                  ...AppLocalizations.delegate.supportedLocales,
                ])
                  CommonPopupMenuItem(
                    label: _label(context, option),
                    checked: option == currentLocale,
                    onPressed: () {
                      ref
                          .read(appSettingProvider.notifier)
                          .update(
                            (state) =>
                                state.copyWith(locale: option?.toString()),
                          );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
