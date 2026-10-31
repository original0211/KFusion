import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/plugins/app.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccessView extends ConsumerStatefulWidget {
  const AccessView({super.key});

  @override
  ConsumerState<AccessView> createState() => _AccessViewState();
}

class _AccessViewState extends ConsumerState<AccessView>
    with RouteSettledMixin<AccessView> {
  late ScrollController _controller;
  List<String>? _pinedList;
  bool _isInit = false;
  bool _installedAppsPermissionGranted = true;

  final _completer = Completer();

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
    final accessControl = ref
        .read(vpnSettingProvider.select((state) => state.accessControlProps))
        .copyWith();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(accessControlStateProvider.notifier).value = accessControl;
      _isInit = true;
      _pinList();
    });
    ref.listenManual(
      accessControlStateProvider.select((state) => state.mode),
      (_, _) => _pinList(),
    );
    _completer.complete(_loadPackages());
  }

  @override
  void didSettleRoute() => setState(() {});

  Future<void> _loadPackages() async {
    final action = ref.read(systemActionProvider.notifier);
    final packages = await action.getPackages();
    final granted =
        packages.isNotEmpty || await action.isInstalledAppsPermissionGranted();
    if (!mounted || granted == _installedAppsPermissionGranted) {
      return;
    }
    setState(() {
      _installedAppsPermissionGranted = granted;
    });
  }

  Future<void> _handleGrantInstalledAppsPermission() async {
    final appLocalizations = context.appLocalizations;
    final granted = await ref
        .read(systemActionProvider.notifier)
        .requestInstalledAppsPermission();
    if (!mounted) {
      return;
    }
    if (!granted) {
      final res = await dialogs.showMessage(
        message: TextSpan(
          text: appLocalizations.installedAppsPermissionDeniedMessage,
        ),
        confirmText: appLocalizations.settings,
      );
      if (res == true) {
        await app?.openAppSettings();
      }
      return;
    }
    await globalState.loadingRun(_loadPackages, tag: LoadingTag.access);
  }

  void _pinList() {
    if (!_isInit || !mounted) {
      return;
    }
    setState(() {
      _pinedList = ref.read(accessControlStateProvider).currentList;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconButtonData _buildSelectAllAction({
    required bool isSelectedAll,
    required List<String> allValueList,
  }) {
    void onPressed() {
      ref.read(accessControlStateProvider.notifier).update((state) {
        final newSet = Set<String>.from(state.currentList);
        final isSelectedAll = newSet.containsAll(allValueList);
        if (isSelectedAll) {
          newSet.removeAll(allValueList);
        } else {
          newSet.addAll(allValueList);
        }
        return state.copyWithNewList(newSet.toList());
      });
    }

    final appLocalizations = context.appLocalizations;
    return isSelectedAll
        ? IconButtonData(
            glyph: AppGlyphs.deselect,
            tooltip: appLocalizations.cancelSelectAll,
            onPressed: onPressed,
          )
        : IconButtonData(
            glyph: AppGlyphs.selectAll,
            tooltip: appLocalizations.selectAll,
            onPressed: onPressed,
          );
  }

  Future<void> _intelligentSelected() async {
    final packageNames = ref.read(
      packagesProvider.select((state) => state.map((item) => item.packageName)),
    );
    if (packageNames.isEmpty) {
      return;
    }
    final selectedPackageNames =
        (await globalState.loadingRun<List<String>>(() async {
          return await app?.getChinaPackageNames() ?? [];
        }, tag: LoadingTag.access))?.toSet() ??
        {};
    final acceptList = packageNames
        .where((item) => !selectedPackageNames.contains(item))
        .toList();
    final rejectList = packageNames
        .where((item) => selectedPackageNames.contains(item))
        .toList();
    ref
        .read(accessControlStateProvider.notifier)
        .update(
          (state) =>
              state.copyWith(acceptList: acceptList, rejectList: rejectList),
        );
  }

  Future<void> _handleToSetting() async {
    await showSheet<int>(
      context: context,
      builder: (context) {
        final appLocalizations = context.appLocalizations;
        return CommonScaffold(
          body: const AccessControlPanel(),
          title: appLocalizations.accessControlSettings,
        );
      },
    );
  }

  void _handleSelected(String packageName) {
    ref.read(accessControlStateProvider.notifier).update((state) {
      final newSet = Set<String>.from(state.currentList)
        ..addOrRemove(packageName);
      return state.copyWithNewList(newSet.toList());
    });
  }

  void _handleEnable(bool enable) {
    ref.read(accessControlStateProvider.notifier).update((state) {
      return state.copyWith(enable: enable);
    });
  }

  Future<void> _handleBack() async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.saveChanges),
    );
    if (res == null) {
      return;
    }
    if (res) {
      _handleSave();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  AccessControlProps _getRealAccessControlProps(
    AccessControlProps accessControl,
  ) {
    final packages = ref.read(packagesProvider);
    if (packages.isEmpty) {
      return accessControl;
    }
    final viewPackageNames = packages
        .whereVisible(
          isFilterSystemApp: accessControl.isFilterSystemApp,
          isFilterNonInternetApp: accessControl.isFilterNonInternetApp,
        )
        .map((item) => item.packageName)
        .toSet();
    return accessControl.copyWithNewList(
      accessControl.currentList
          .where((item) => viewPackageNames.contains(item))
          .toList()
        ..sort(),
    );
  }

  void _handleSave() {
    final accessControl = ref.read(accessControlStateProvider);
    ref
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            accessControlProps: _getRealAccessControlProps(accessControl),
          ),
        );
  }

  Future<void> _exportToClipboard() async {
    await globalState.safeRun(() {
      final currentList = ref.read(
        accessControlStateProvider.select((state) => state.currentList),
      );
      Clipboard.setData(ClipboardData(text: currentList.join('\n')));
    });
  }

  Future<void> _importFormClipboard() async {
    await globalState.safeRun(() async {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text == null) return;
      final list = text.split('\n');
      ref
          .read(accessControlStateProvider.notifier)
          .update((state) => state.copyWithNewList(list.toSet().toList()));
    });
  }

  List<CommonPopupMenuItem> _buildMenuItems(
    BuildContext context, {
    required bool enable,
  }) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.toggle,
        label: appLocalizations.accessControl,
        subItems: [
          CommonPopupMenuItem(
            label: appLocalizations.turnOn,
            checked: enable,
            onPressed: () => _handleEnable(true),
          ),
          CommonPopupMenuItem(
            label: appLocalizations.turnOff,
            checked: !enable,
            onPressed: () => _handleEnable(false),
          ),
        ],
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.sliders,
        label: appLocalizations.settings,
        onPressed: _handleToSetting,
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.moreCircle,
        label: appLocalizations.action,
        subItems: [
          CommonPopupMenuItem(
            glyph: AppGlyphs.sparkle,
            label: appLocalizations.intelligentSelected,
            onPressed: _intelligentSelected,
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.copy,
            label: appLocalizations.clipboardExport,
            onPressed: _exportToClipboard,
          ),
          CommonPopupMenuItem(
            glyph: AppGlyphs.paste,
            label: appLocalizations.clipboardImport,
            onPressed: _importFormClipboard,
          ),
        ],
      ),
    ];
  }

  Widget _buildContent({
    required List<Package> packages,
    required Set<String> selected,
    required bool isSearching,
    required double side,
  }) {
    return FutureBuilder(
      future: _completer.future,
      builder: (context, snapshot) {
        final appLocalizations = context.appLocalizations;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CommonCircleLoading.page());
        }
        return NullStatusSwitcher(
          isEmpty: packages.isEmpty,
          isSearching: isSearching,
          nullStatus: NullStatus(
            label: appLocalizations.noData,
            illustration: NullStatusIllustration.apps,
          ),
          child: CommonScrollBar(
            controller: _controller,
            child: ListView.builder(
              controller: _controller,
              padding: EdgeInsets.fromLTRB(
                side,
                0,
                side,
                BottomInsetScope.of(context),
              ),
              scrollCacheExtent: arrivalScrollCacheExtent(routeSettled),
              itemCount: packages.length,
              itemExtent: 72,
              itemBuilder: (_, index) {
                final package = packages[index];
                return PackageListItem(
                  key: Key(package.packageName),
                  package: package,
                  value: selected.contains(package.packageName),
                  onChanged: (value) {
                    _handleSelected(package.packageName);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstalledAppsPermissionStatus() {
    final appLocalizations = context.appLocalizations;
    return NullStatus(
      label: appLocalizations.installedAppsPermissionRequired,
      description: appLocalizations.installedAppsPermissionDesc,
      illustration: NullStatusIllustration.permission,
      action: TonalButton(
        size: TonalButtonSize.bar,
        glyph: AppGlyphs.lockOpen,
        label: appLocalizations.authorize,
        onPressed: _handleGrantInstalledAppsPermission,
      ),
    );
  }

  Widget _buildBannerBar({
    required bool enable,
    required AccessControlMode mode,
    required int count,
    required double side,
  }) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final Widget row;
    if (!enable) {
      row = Row(
        children: [
          Expanded(
            child: Text(
              appLocalizations.accessControlDisabledDesc,
              style: HaraText.profileMeta(context, palette.sub),
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            button: true,
            child: InkWell(
              customBorder: AppShape.hara,
              onTap: () => _handleEnable(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  appLocalizations.turnOn,
                  style: HaraText.action(context, palette.ink),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      final describe = mode == AccessControlMode.acceptSelected
          ? appLocalizations.accessControlAllowDesc
          : appLocalizations.accessControlNotAllowDesc;
      row = Row(
        children: [
          Expanded(
            child: Text(
              describe,
              style: HaraText.profileMeta(context, palette.sub),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            appLocalizations.selected,
            style: HaraText.statusNode(context, palette.sub),
          ),
          const SizedBox(width: 4),
          Text('$count', style: HaraText.dataValue(context, palette.ink)),
        ],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        side,
        HaraSpace.nodeRowVertical,
        side,
        HaraSpace.nodeRowVertical,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          const SizedBox(height: HaraSpace.nodeRowVertical),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }

  void _onSearch(String value) {
    ref.read(queryProvider(QueryTag.access).notifier).value = value;
    _pinList();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(loadingProvider(LoadingTag.access));
    final query = SearchQuery(ref.watch(queryProvider(QueryTag.access)));
    final packages = ref.watch(packagesProvider);
    final accessControl = ref.watch(accessControlStateProvider);
    final viewPackages = packages
        .getViewList(
          pinedList: _pinedList ?? [],
          sortType: accessControl.sort,
          isFilterNonInternetApp: accessControl.isFilterNonInternetApp,
          isFilterSystemApp: accessControl.isFilterSystemApp,
        )
        .whereMatches(query, (package) => [package.label, package.packageName])
        .toList();
    final mode = accessControl.mode;
    final currentList = accessControl.currentList;
    final viewPackageNameList = viewPackages.map((e) => e.packageName).toList();
    final valueList = currentList.intersection(viewPackageNameList);
    final needsInstalledAppsPermission =
        packages.isEmpty && !_installedAppsPermissionGranted;
    final selectAllAction =
        accessControl.enable &&
            !needsInstalledAppsPermission &&
            viewPackageNameList.isNotEmpty
        ? _buildSelectAllAction(
            isSelectedAll: valueList.length == viewPackageNameList.length,
            allValueList: viewPackageNameList,
          )
        : null;
    final hasChanges = ref.watch(
      vpnSettingProvider.select(
        (state) =>
            _getRealAccessControlProps(state.accessControlProps) !=
            _getRealAccessControlProps(accessControl),
      ),
    );
    return CommonPopScope(
      onPop: hasChanges
          ? (_) {
              _handleBack();
              return false;
            }
          : null,
      child: CommonScaffold(
        isLoading: isLoading,
        searchState: AppBarSearchState(onSearch: _onSearch),
        searchActions: [?selectAllAction],
        title: context.appLocalizations.appAccessControl,
        confirmationAction: hasChanges
            ? IconButtonData(
                glyph: AppGlyphs.check,
                onPressed: _handleSave,
                tooltip: context.appLocalizations.save,
              )
            : null,
        menuItems: [
          ..._buildMenuItems(context, enable: accessControl.enable),
          if (selectAllAction != null)
            CommonPopupMenuItem(
              glyph: selectAllAction.glyph,
              label: selectAllAction.tooltip!,
              onPressed: selectAllAction.onPressed,
            ),
        ],
        body: AppBarClearance(
          child: Material(
            color: context.haraPalette.bg,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = math.max(
                  HaraSpace.pageInset,
                  (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBannerBar(
                      enable: accessControl.enable,
                      mode: mode,
                      count: valueList.length,
                      side: side,
                    ),
                    Expanded(
                      child: needsInstalledAppsPermission
                          ? _buildInstalledAppsPermissionStatus()
                          : DisabledMask(
                              status: !accessControl.enable,
                              child: _buildContent(
                                packages: viewPackages,
                                selected: valueList.toSet(),
                                isSearching: query.isNotEmpty,
                                side: side,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class PackageListItem extends StatelessWidget {
  final Package package;
  final bool value;
  final void Function(bool?) onChanged;

  const PackageListItem({
    super.key,
    required this.package,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Semantics(
      toggled: value,
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: [
                    PackageIcon(packageName: package.packageName, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package.label,
                            style: HaraText.nodeName(
                              context,
                              palette.ink,
                              current: value,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: HaraSpace.profileMetaGap),
                          Text(
                            package.packageName,
                            style: HaraText.payload(context, palette.sub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (value) SelectionCheck(color: palette.ink),
                  ],
                ),
              ),
              HaraHairline(color: palette.line),
            ],
          ),
        ),
      ),
    );
  }
}

class AccessControlPanel extends StatelessWidget {
  const AccessControlPanel({super.key});

  static ConfigWriter<T> _writer<T>(
    AccessControlProps Function(AccessControlProps state, T value) update,
  ) {
    return (ref, value) => ref
        .read(accessControlStateProvider.notifier)
        .update((state) => update(state, value));
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    return Material(
      color: palette.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            HaraSpace.pageInset,
            (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
          );
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              side,
              context.contentTopPadding,
              side,
              32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HaraHairline(color: palette.line),
                _HaraBoundOptions<AccessControlMode>(
                  ConfigOptionsItem<AccessControlMode>(
                    title: (l) => l.mode,
                    options: AccessControlMode.values,
                    textBuilder: (mode) => switch (mode) {
                      AccessControlMode.acceptSelected =>
                        appLocalizations.whitelistMode,
                      AccessControlMode.rejectSelected =>
                        appLocalizations.blacklistMode,
                    },
                    selector: accessControlStateProvider.select(
                      (state) => state.mode,
                    ),
                    onChanged: _writer(
                      (state, value) => state.copyWith(mode: value),
                    ),
                  ),
                ),
                _HaraBoundOptions<AccessSortType>(
                  ConfigOptionsItem<AccessSortType>(
                    title: (l) => l.sort,
                    options: AccessSortType.values,
                    textBuilder: (type) => switch (type) {
                      AccessSortType.none => appLocalizations.defaultText,
                      AccessSortType.name => appLocalizations.name,
                      AccessSortType.time => appLocalizations.time,
                    },
                    selector: accessControlStateProvider.select(
                      (state) => state.sort,
                    ),
                    onChanged: _writer(
                      (state, value) => state.copyWith(sort: value),
                    ),
                  ),
                ),
                const SizedBox(height: HaraSpace.groupGap),
                _section(
                  context,
                  appLocalizations.source,
                  rows: [
                    HaraToggle(
                      ConfigToggleItem(
                        title: (l) => l.systemApp,
                        selector: accessControlStateProvider.select(
                          (state) => !state.isFilterSystemApp,
                        ),
                        onChanged: _writer(
                          (state, value) =>
                              state.copyWith(isFilterSystemApp: !value),
                        ),
                      ),
                    ),
                    HaraToggle(
                      ConfigToggleItem(
                        title: (l) => l.noNetworkApp,
                        selector: accessControlStateProvider.select(
                          (state) => !state.isFilterNonInternetApp,
                        ),
                        onChanged: _writer(
                          (state, value) =>
                              state.copyWith(isFilterNonInternetApp: !value),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Widget _section(
  BuildContext context,
  String title, {
  required List<Widget> rows,
}) {
  final palette = context.haraPalette;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: HaraText.sectionTitle(context, palette.sub)),
      const SizedBox(height: HaraSpace.sectionTitleGap),
      HaraHairline(color: palette.line),
      ...rows,
    ],
  );
}

/// An options row over an existing [ConfigOptionsItem]: the item's own
/// selector, options and writer drive it; the row tap opens the popup
/// menu out of its end value, as the options row it replaces did.
class _HaraBoundOptions<T> extends ConsumerWidget {
  const _HaraBoundOptions(this.item);

  final ConfigOptionsItem<T> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    PopupOpen? openMenu;
    return HaraRow(
      onTap: () => openMenu?.call(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.title(appLocalizations),
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
                      item.textBuilder(value),
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
                for (final option in item.options)
                  CommonPopupMenuItem(
                    label: item.textBuilder(option),
                    checked: option == value,
                    onPressed: () => item.onChanged(ref, option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
