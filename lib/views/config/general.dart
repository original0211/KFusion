import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/core/singbox/singbox_binary.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/views/config/on_demand.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LogLevelItem extends ConsumerWidget {
  const LogLevelItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<LogLevel>(
      title: (l) => l.logLevel,
      options: LogLevel.values,
      textBuilder: (logLevel) => logLevel.name,
      selector: patchClashConfigProvider.select((state) => state.logLevel),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(logLevel: value)),
    );
  }
}

/// The core the card presents as current: switch target first, then the running core, then the persisted kind.
CoreKind coreSwitchSelectedCore({
  required SingBoxStatus status,
  required CoreKind activeKind,
  required bool mihomoRunning,
}) {
  final target = status.switchTarget;
  if (status.state == SingBoxState.starting && target != null) {
    return target;
  }
  if (status.state == SingBoxState.running) {
    return CoreKind.singbox;
  }
  if (mihomoRunning) {
    return CoreKind.mihomo;
  }
  return activeKind;
}

/// The name a core goes by in sentences; the persisted sing-box value drops its hyphen.
String coreKindDisplayName(CoreKind kind) {
  return switch (kind) {
    CoreKind.mihomo => 'mihomo',
    CoreKind.singbox => 'sing-box',
  };
}

String coreSwitchStageText(AppLocalizations l10n, SingBoxStatus status) {
  final target = status.switchTarget;
  final base = switch (status.switchStage) {
    CoreSwitchStage.stopping => l10n.coreSwitchStopping,
    CoreSwitchStage.starting => l10n.coreSwitchStarting(
      target == null ? '' : coreKindDisplayName(target),
    ),
    CoreSwitchStage.applying => l10n.coreSwitchApplying,
    CoreSwitchStage.restoring => l10n.coreSwitchRestoring,
    null => status.message,
  };
  final detail = status.stageDetail;
  return detail.isEmpty ? base : '$base $detail';
}

/// The one sentence a failed switch shows; raw exception text never reaches it.
String coreSwitchFailureText(AppLocalizations l10n, SingBoxStatus status) {
  final failure = status.failure ?? CoreSwitchFailure.unknown;
  if (status.failedStage != null && !status.restored) {
    return l10n.coreSwitchRollbackFailed;
  }
  final targetKind = status.switchTarget;
  final target = targetKind == null ? '' : coreKindDisplayName(targetKind);
  final from = status.switchFrom;
  return switch (failure) {
    CoreSwitchFailure.noProfile => l10n.coreSwitchNoProfile,
    CoreSwitchFailure.profileUnreadable => l10n.coreSwitchProfileUnreadable,
    CoreSwitchFailure.profileNotRenderable => l10n.coreSwitchNotRenderable(
      target,
    ),
    CoreSwitchFailure.checkUnresponsive => l10n.coreSwitchCheckUnresponsive,
    CoreSwitchFailure.stopFailed => l10n.coreSwitchStopFailed,
    CoreSwitchFailure.startFailed =>
      status.restored && from != null
          ? l10n.coreSwitchStartFailedRestored(
              target,
              coreKindDisplayName(from),
            )
          : l10n.coreSwitchStartFailed(target),
    CoreSwitchFailure.applyFailed =>
      status.restored && from != null
          ? l10n.coreSwitchApplyFailedRestored(coreKindDisplayName(from))
          : l10n.coreSwitchApplyFailed,
    CoreSwitchFailure.binaryUnavailable => l10n.coreSwitchBinaryUnavailable,
    CoreSwitchFailure.adminRequired => l10n.coreSwitchAdminRequired,
    CoreSwitchFailure.channelUnavailable => l10n.coreSwitchChannelUnavailable,
    CoreSwitchFailure.platformUnsupported => l10n.coreSwitchPlatformUnsupported,
    CoreSwitchFailure.unknown => l10n.coreSwitchFailed,
  };
}

class CoreSwitchItem extends ConsumerStatefulWidget {
  const CoreSwitchItem({super.key});

  @override
  ConsumerState<CoreSwitchItem> createState() => _CoreSwitchItemState();
}

class _CoreSwitchItemState extends ConsumerState<CoreSwitchItem> {
  String? _binary;
  String? _managedPath;
  var _binaryChecked = false;
  var _downloading = false;
  double? _progress;
  String? _downloadError;
  String? _downloadRoute;

  @override
  void initState() {
    super.initState();
    _refreshBinary();
  }

  Future<void> _refreshBinary() async {
    final homeDir = await appPath.homeDirPath;
    final stored = await Preferences().getSingBoxBinaryPath();
    final binary = findSingBoxBinary(
      singBoxCandidates(
        executableDir: appPath.executableDirPath,
        homeDir: homeDir,
        storedPath: stored,
      ),
    );
    if (!mounted) return;
    setState(() {
      _binary = binary;
      _managedPath = singBoxManagedPath(homeDir);
      _binaryChecked = true;
    });
  }

  Future<void> _downloadBinary() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _downloadError = null;
      _downloadRoute = null;
    });
    try {
      final homeDir = await appPath.homeDirPath;
      final stored = await Preferences().getSingBoxBinaryPath();
      final path = await singBoxBinaryManager.ensure(
        executableDir: appPath.executableDirPath,
        homeDir: homeDir,
        storedPath: stored,
        appProxyRoute: (url) =>
            FlClashHttpOverrides.findProxyForReader(ref.read, url),
        onRoute: (label) {
          if (!mounted) return;
          setState(() => _downloadRoute = label);
        },
        onProgress: (received, total) {
          if (!mounted || total == null) return;
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _binary = path;
        _managedPath = singBoxManagedPath(homeDir);
        _binaryChecked = true;
        _downloading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status =
        ref.watch(singBoxActionProvider).value ??
        const SingBoxStatus(state: SingBoxState.idle);
    final switching = status.state == SingBoxState.starting;
    // A switch can fetch the binary itself; rescan once it settles.
    ref.listen(singBoxActionProvider, (previous, next) {
      final settled = next.value?.state;
      if (settled == SingBoxState.running ||
          settled == SingBoxState.idle ||
          settled == SingBoxState.error) {
        _refreshBinary();
      }
    });
    final l10n = context.appLocalizations;
    final binary = _binary;
    final failure = status.failure;
    final String statusText;
    if (failure != null) {
      statusText = coreSwitchFailureText(l10n, status);
    } else if (switching && status.switchStage != null) {
      statusText = coreSwitchStageText(l10n, status);
    } else {
      statusText = status.message.isEmpty
          ? (system.isAndroid ? 'Android sing-box VPN 运行时（真机待验）' : '未运行')
          : status.message;
    }
    final mihomoRunning = ref.watch(isStartProvider);
    return CoreSwitchCard(
      statusText: statusText,
      statusIsFailure: failure != null,
      showBinary: system.isWindows,
      binaryChecked: _binaryChecked,
      binaryLabel: binary == null
          ? null
          : (binary == _managedPath
                ? l10n.singBoxManagedBinary(singBoxPinnedVersion, binary)
                : '二进制：$binary'),
      downloading: _downloading,
      progress: _progress,
      downloadRoute: _downloadRoute,
      downloadError: _downloadError,
      onDownload: _downloadBinary,
      showSwitch: system.isAndroid || (system.isWindows && binary != null),
      selectedCore: coreSwitchSelectedCore(
        status: status,
        activeKind: ref.watch(activeCoreKindProvider).value ?? CoreKind.mihomo,
        mihomoRunning: mihomoRunning,
      ),
      mihomoRunning: mihomoRunning,
      singBoxRunning: status.state == SingBoxState.running,
      failureDetail: status.failureDetail,
      switching: switching || _downloading,
      onSelectCore: (target) {
        ref.read(singBoxActionProvider.notifier).switchCore(target);
      },
      localizations: l10n,
    );
  }
}

/// The core switch settings row as one card, shaped like its section neighbours.
class CoreSwitchCard extends StatelessWidget {
  const CoreSwitchCard({
    super.key,
    required this.statusText,
    required this.statusIsFailure,
    required this.showBinary,
    required this.binaryChecked,
    required this.binaryLabel,
    required this.downloading,
    required this.progress,
    required this.downloadRoute,
    required this.downloadError,
    required this.onDownload,
    required this.showSwitch,
    required this.selectedCore,
    required this.mihomoRunning,
    required this.singBoxRunning,
    required this.failureDetail,
    required this.switching,
    required this.onSelectCore,
    required this.localizations,
  });

  final String statusText;

  /// Failure sentences render in the error color; other sentences stay neutral.
  final bool statusIsFailure;
  final bool showBinary;

  /// False until the first binary scan lands; the section stays empty.
  final bool binaryChecked;

  /// The found-binary line (managed or manual); null while it is missing.
  final String? binaryLabel;
  final bool downloading;
  final double? progress;

  /// Label of the download route in use, e.g. 系统代理; null before the
  /// first attempt reports one.
  final String? downloadRoute;
  final String? downloadError;
  final VoidCallback onDownload;
  final bool showSwitch;
  final CoreKind selectedCore;
  final bool mihomoRunning;
  final bool singBoxRunning;

  /// The native message under a failure sentence; empty when none arrived.
  final String failureDetail;
  final bool switching;
  final ValueChanged<CoreKind> onSelectCore;
  final AppLocalizations localizations;

  Widget _binaryContent(BuildContext context) {
    final palette = context.haraPalette;
    final label = binaryLabel;
    if (label != null) {
      return Text(label, style: HaraText.profileMeta(context, palette.sub));
    }
    final error = downloadError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.singBoxBinaryMissing,
          style: HaraText.profileMeta(context, palette.sub),
        ),
        const SizedBox(height: 2),
        Text(
          localizations.singBoxDownloadHint,
          style: HaraText.profileMeta(context, palette.sub),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: HaraText.profileMeta(context, context.colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        if (downloading)
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              const SizedBox(width: 12),
              Text(
                _downloadingText(),
                style: HaraText.profileMeta(context, palette.sub),
              ),
            ],
          )
        else
          FilledButton(
            onPressed: onDownload,
            child: Text(
              error == null
                  ? localizations.singBoxDownload
                  : localizations.singBoxDownloadRetry,
            ),
          ),
      ],
    );
  }

  Widget _coreRow(BuildContext context, CoreKind kind) {
    final selected = kind == selectedCore;
    final running = kind == CoreKind.mihomo ? mihomoRunning : singBoxRunning;
    final palette = context.haraPalette;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: switching || selected ? null : () => onSelectCore(kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              DashboardDiscMotif(
                size: 20,
                color: selected ? palette.ink : palette.sub,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  coreKindDisplayName(kind),
                  style: HaraText.nodeName(
                    context,
                    palette.ink,
                    current: selected,
                  ),
                ),
              ),
              Text(
                running ? localizations.running : localizations.notRunning,
                style: HaraText.statusNode(
                  context,
                  running ? palette.sub : palette.dim,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                SelectionCheck(color: palette.ink),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _downloadingText() {
    final percent = progress;
    final base = percent == null
        ? '正在下载 sing-box…'
        : localizations.singBoxDownloading((percent * 100).round());
    final route = downloadRoute;
    return route == null ? base : '$base（经$route）';
  }

  @override
  Widget build(BuildContext context) {
    final position = ItemPositionProvider.of(context)?.position;
    final isEnd =
        position == ItemPosition.end || position == ItemPosition.startAndEnd;
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          localizations.coreSwitchTitle,
          style: HaraText.nodeName(context, palette.ink, current: true),
        ),
        const SizedBox(height: 2),
        Text(
          statusText,
          style: HaraText.statusNode(
            context,
            statusIsFailure ? context.colorScheme.error : palette.sub,
          ),
        ),
        if (statusIsFailure && failureDetail.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            localizations.coreSwitchFailureDetail(failureDetail),
            style: HaraText.profileMeta(context, palette.dim),
          ),
        ],
        if (showBinary && binaryChecked) ...[
          const SizedBox(height: 8),
          _binaryContent(context),
        ],
        if (showSwitch) ...[
          const SizedBox(height: 12),
          _coreRow(context, CoreKind.mihomo),
          const SizedBox(height: 8),
          _coreRow(context, CoreKind.singbox),
        ],
        const SizedBox(height: 12),
        if (!isEnd) HaraHairline(color: palette.line),
      ],
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

/// A section of the page: a dim title, a hairline, its rows, and the
/// section's footer note.
class _HaraSection extends StatelessWidget {
  const _HaraSection({this.title, required this.rows, this.footer});

  final String? title;
  final List<Widget> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: HaraText.sectionTitle(context, palette.dim)),
          const SizedBox(height: HaraSpace.sectionTitleGap),
        ],
        HaraHairline(color: palette.line),
        ...rows,
        if (footer != null) ...[
          const SizedBox(height: 8),
          Text(footer!, style: HaraText.profileMeta(context, palette.dim)),
        ],
      ],
    );
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

/// An options row: the row tap opens the menu out of its end value, as
/// the options row it replaces did.
class _HaraOptionsRow<T> extends StatelessWidget {
  const _HaraOptionsRow({
    required this.label,
    this.subtitle,
    required this.options,
    required this.value,
    required this.textBuilder,
    required this.onChanged,
  });

  final String label;
  final String? subtitle;
  final List<T> options;
  final T value;
  final String Function(T value) textBuilder;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final onChanged = this.onChanged;
    PopupOpen? openMenu;
    return _HaraRow(
      onTap: onChanged == null ? null : () => openMenu?.call(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: HaraText.nodeName(
                    context,
                    palette.ink,
                    current: false,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: HaraSpace.profileMetaGap),
                  Text(
                    subtitle!,
                    style: HaraText.profileMeta(context, palette.sub),
                  ),
                ],
              ],
            ),
          ),
          if (onChanged != null)
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
                        textBuilder(value),
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
                  for (final option in options)
                    CommonPopupMenuItem(
                      label: textBuilder(option),
                      checked: option == value,
                      onPressed: () => onChanged(option),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An options row over an existing [ConfigOptionsItem]: the item's own
/// selector, options and writer drive it.
class _HaraOptions<T> extends ConsumerWidget {
  const _HaraOptions(this.item);

  final ConfigOptionsItem<T> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    return _HaraOptionsRow<T>(
      label: item.title(appLocalizations),
      options: item.options,
      value: value,
      textBuilder: item.textBuilder,
      onChanged: (value) => item.onChanged(ref, value),
    );
  }
}

/// An options row over a [ConfigOptionsItem] another widget assembles:
/// building the source only assembles the item (a selector, options and
/// a writer), which the Hara row renders instead of its own Material row.
class _HaraBoundOptions<T> extends ConsumerWidget {
  const _HaraBoundOptions(this.source);

  final ConsumerWidget source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _HaraOptions<T>(source.build(context, ref) as ConfigOptionsItem<T>);
  }
}

/// The input dialog an input row opens, with the same plumbing the list
/// row it replaces used: the floating dialog over the root navigator,
/// the length limit as formatters, and the result handed back as-is.
Future<void> _showConfigInputDialog({
  required BuildContext context,
  required String title,
  required String value,
  String? resetValue,
  int? maxLength,
  TextInputType? keyboardType,
  FormFieldValidator<String>? validator,
  required ValueChanged<String?> onChanged,
}) async {
  final result = await showFloatingDialog<String>(
    context: Navigator.of(context, rootNavigator: true).context,
    child: InputDialog(
      title: title,
      value: value,
      resetValue: resetValue,
      inputFormatters: maxLength == null
          ? null
          : TextInputLimits.limit(maxLength),
      keyboardType: keyboardType,
      validator: validator,
    ),
  );
  onChanged(result);
}

/// An input row: the label, its value under it, and the input dialog on
/// tap.
class _HaraInputRow extends StatelessWidget {
  const _HaraInputRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return _HaraRow(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: HaraText.nodeName(context, palette.ink, current: false),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(height: HaraSpace.profileMetaGap),
            Text(value, style: HaraText.profileMeta(context, palette.sub)),
          ],
        ],
      ),
    );
  }
}

String? _normalizeConfigText(ConfigTextItem item, String? value) {
  if (value == null) {
    return null;
  }
  final normalize = item.normalize;
  return normalize == null ? value : normalize(value);
}

/// An input row over an existing [ConfigTextItem]: the item's selector,
/// normalization, validation and writer drive it, through the same
/// input dialog its own row opened.
class _HaraText extends ConsumerWidget {
  const _HaraText(this.item);

  final ConfigTextItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    final label = item.title(appLocalizations);
    return _HaraInputRow(
      label: label,
      value: value,
      onTap: () {
        _showConfigInputDialog(
          context: context,
          title: label,
          value: value,
          maxLength: item.maxLength,
          keyboardType: item.keyboardType,
          validator: (text) {
            final normalized = _normalizeConfigText(item, text);
            if (normalized == null || normalized.isEmpty) {
              return item.allowEmpty ? null : appLocalizations.emptyTip(label);
            }
            return item.validator?.call(normalized, appLocalizations);
          },
          onChanged: (text) {
            final normalized = _normalizeConfigText(item, text);
            if (normalized == null || normalized == value) {
              return;
            }
            item.onChanged(ref, normalized);
          },
        );
      },
    );
  }
}

/// A row that opens a page: an ink label, its value under it when it has
/// one, and a sub arrow. The open follows the list row it replaces —
/// sheet push or open container — and the result reaches [onChanged]
/// the same way.
class _HaraOpenRow extends StatelessWidget {
  const _HaraOpenRow({
    required this.label,
    this.subtitle,
    required this.target,
    this.onChanged,
  });

  final String label;
  final String? subtitle;
  final Widget target;
  final ValueChanged<dynamic>? onChanged;

  Widget _content(BuildContext context) {
    final palette = context.haraPalette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: HaraText.nodeName(context, palette.ink, current: false),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: HaraSpace.profileMetaGap),
                Text(
                  subtitle!,
                  style: HaraText.profileMeta(context, palette.sub),
                ),
              ],
            ],
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
        onTap: () async {
          final result = await showExtend<dynamic>(
            context,
            props: const ExtendProps(forceFull: true),
            builder: (_) => target,
          );
          onChanged?.call(result);
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
      onClosed: onChanged,
      openBuilder: (_, _) => target,
    );
  }
}

/// The current profile's core kind, mirrored from the profile edit page.
class CurrentProfileCoreKindItem extends ConsumerWidget {
  const CurrentProfileCoreKindItem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    final kind = profile == null
        ? null
        : ref.watch(coreKindsProvider).value?[profile.id];
    return _HaraOptionsRow<CoreKind>(
      label: '运行核心',
      subtitle: profile?.realLabel ?? '未选择配置',
      options: CoreKind.values,
      value: kind ?? CoreKind.mihomo,
      textBuilder: (option) => option.value,
      onChanged: profile == null
          ? null
          : (value) {
              ref.read(coreKindsProvider.notifier).setKind(profile.id, value);
            },
    );
  }
}

class TestUrlItem extends ConsumerWidget {
  const TestUrlItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final testUrl = ref.watch(
      appSettingProvider.select((state) => state.testUrl),
    );
    return _HaraInputRow(
      label: appLocalizations.testUrl,
      value: testUrl,
      onTap: () {
        _showConfigInputDialog(
          context: context,
          title: appLocalizations.testUrl,
          value: testUrl,
          resetValue: defaultTestUrl,
          maxLength: TextInputLimits.url,
          validator: (String? value) {
            if (value == null || value.isEmpty) {
              return appLocalizations.emptyTip(appLocalizations.testUrl);
            }
            if (!value.isUrl) {
              return appLocalizations.urlTip(appLocalizations.testUrl);
            }
            return null;
          },
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            ref
                .read(appSettingProvider.notifier)
                .update((state) => state.copyWith(testUrl: value));
          },
        );
      },
    );
  }
}

class HostsItem extends ConsumerWidget {
  const HostsItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final hosts = ref.watch(
      patchClashConfigProvider.select((state) => state.hosts),
    );
    return _HaraOpenRow(
      label: 'Hosts',
      subtitle: hosts.isEmpty
          ? appLocalizations.none
          : appLocalizations.itemsCount(hosts.length),
      target: MapEditView(
        title: 'Hosts',
        entries: hosts,
        keyMaxLength: TextInputLimits.domain,
        valueMaxLength: TextInputLimits.hostValue,
        titleBuilder: (item) => Text(item.key),
        subtitleBuilder: (item) => Text(item.value),
      ),
      onChanged: (value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(hosts: value));
      },
    );
  }
}

class ExternalControllerSecretItem extends ConsumerWidget {
  const ExternalControllerSecretItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return _HaraText(
      ConfigTextItem(
        title: (l) => l.externalControllerSecret,
        maxLength: TextInputLimits.password,
        selector: patchClashConfigProvider.select((state) => state.secret),
        normalize: (value) => value.trim(),
        onChanged: (ref, value) => ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(secret: value)),
      ),
    );
  }
}

ConfigToggleItem _clashToggle({
  required ConfigLabel title,
  required bool Function(PatchClashConfig state) select,
  required PatchClashConfig Function(PatchClashConfig state, bool value) update,
}) {
  return ConfigToggleItem(
    title: title,
    selector: patchClashConfigProvider.select(select),
    onChanged: (ref, value) => ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => update(state, value)),
  );
}

ConfigToggleItem _appSettingToggle({
  required ConfigLabel title,
  required bool Function(AppSettingProps state) select,
  required AppSettingProps Function(AppSettingProps state, bool value) update,
}) {
  return ConfigToggleItem(
    title: title,
    selector: appSettingProvider.select(select),
    onChanged: (ref, value) => ref
        .read(appSettingProvider.notifier)
        .update((state) => update(state, value)),
  );
}

/// The startup toggles the settings page heads with.
List<Widget> startupSettingItems() {
  return [
    if (system.isDesktop) ...[
      _appSettingToggle(
        title: (l) => l.autoLaunch,
        select: (state) => state.autoLaunch,
        update: (state, value) => state.copyWith(autoLaunch: value),
      ),
      _appSettingToggle(
        title: (l) => l.silentLaunch,
        select: (state) => state.silentLaunch,
        update: (state, value) => state.copyWith(silentLaunch: value),
      ),
    ],
    _appSettingToggle(
      title: (l) => l.autoRun,
      select: (state) => state.autoRun,
      update: (state, value) => state.copyWith(autoRun: value),
    ),
    _appSettingToggle(
      title: (l) => l.minimizeOnExit,
      select: (state) => state.minimizeOnExit,
      update: (state, value) => state.copyWith(minimizeOnExit: value),
    ),
    if (system.isAndroid) ...[
      _appSettingToggle(
        title: (l) => l.exclude,
        select: (state) => state.hidden,
        update: (state, value) => state.copyWith(hidden: value),
      ),
      _appSettingToggle(
        title: (l) => l.showNotificationStopAction,
        select: (state) => state.showNotificationStopAction,
        update: (state, value) =>
            state.copyWith(showNotificationStopAction: value),
      ),
    ],
  ];
}

class GeneralView extends ConsumerWidget {
  const GeneralView({super.key});

  List<Widget> _startupItems(AppLocalizations appLocalizations) {
    return [
      _HaraOpenRow(
        label: appLocalizations.onDemand,
        target: const OnDemandView(),
      ),
    ];
  }

  List<Widget> _inboundItems({required bool externalController}) {
    return [
      _HaraToggle(
        _clashToggle(
          title: (l) => l.allowLan,
          select: (state) => state.allowLan,
          update: (state, value) => state.copyWith(allowLan: value),
        ),
      ),
      _HaraToggle(
        _clashToggle(
          title: (l) => l.externalController,
          select: (state) =>
              state.externalController == ExternalControllerStatus.open,
          update: (state, value) => state
              .copyWith(
                externalController: value
                    ? ExternalControllerStatus.open
                    : ExternalControllerStatus.close,
              )
              .ensureControllerSecret(),
        ),
      ),
      if (externalController) const ExternalControllerSecretItem(),
    ];
  }

  List<Widget> _connectionItems() {
    return [
      const TestUrlItem(),
      _HaraToggle(
        _clashToggle(
          title: (l) => l.unifiedDelay,
          select: (state) => state.unifiedDelay,
          update: (state, value) => state.copyWith(unifiedDelay: value),
        ),
      ),
      _HaraToggle(
        _clashToggle(
          title: (l) => l.tcpConcurrent,
          select: (state) => state.tcpConcurrent,
          update: (state, value) => state.copyWith(tcpConcurrent: value),
        ),
      ),
      _HaraToggle(
        _clashToggle(
          title: (l) => l.findProcessMode,
          select: (state) => state.findProcessMode == FindProcessMode.always,
          update: (state, value) => state.copyWith(
            findProcessMode: value
                ? FindProcessMode.always
                : FindProcessMode.off,
          ),
        ),
      ),
      _HaraToggle(
        _appSettingToggle(
          title: (l) => l.autoCloseConnections,
          select: (state) => state.closeConnections,
          update: (state, value) => state.copyWith(closeConnections: value),
        ),
      ),
      _HaraToggle(
        _appSettingToggle(
          title: (l) => l.onlyStatisticsProxy,
          select: (state) => state.onlyStatisticsProxy,
          update: (state, value) => state.copyWith(onlyStatisticsProxy: value),
        ),
      ),
    ];
  }

  List<Widget> _requestItems() {
    return [
      _HaraToggle(
        _appSettingToggle(
          title: (l) => l.checkCertificate,
          select: (state) => state.checkCertificate,
          update: (state, value) => state.copyWith(checkCertificate: value),
        ),
      ),
      _HaraToggle(
        _appSettingToggle(
          title: (l) => l.autoCheckUpdate,
          select: (state) => state.autoCheckUpdate,
          update: (state, value) => state.copyWith(autoCheckUpdate: value),
        ),
      ),
    ];
  }

  List<Widget> _coreItems() {
    return [
      const CurrentProfileCoreKindItem(),
      _HaraToggle(
        _clashToggle(
          title: (l) => 'IPv6',
          select: (state) => state.ipv6,
          update: (state, value) => state.copyWith(ipv6: value),
        ),
      ),
      const HostsItem(),
      _HaraToggle(
        ConfigToggleItem(
          title: (l) => l.appendSystemDns,
          selector: networkSettingProvider.select(
            (state) => state.appendSystemDns,
          ),
          onChanged: (ref, value) => ref
              .read(networkSettingProvider.notifier)
              .update((state) => state.copyWith(appendSystemDns: value)),
        ),
      ),
      _HaraToggle(
        _clashToggle(
          title: (l) => l.geodataLoader,
          select: (state) =>
              state.geodataLoader == GeodataLoader.memconservative,
          update: (state, value) => state.copyWith(
            geodataLoader: value
                ? GeodataLoader.memconservative
                : GeodataLoader.standard,
          ),
        ),
      ),
    ];
  }

  List<Widget> _logItems() {
    return [
      const _HaraBoundOptions<LogLevel>(LogLevelItem()),
      _HaraToggle(
        _appSettingToggle(
          title: (l) => l.logcat,
          select: (state) => state.openLogs,
          update: (state, value) => state.copyWith(openLogs: value),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final externalController = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.externalController == ExternalControllerStatus.open,
      ),
    );
    final sections = <Widget>[
      _HaraSection(
        title: appLocalizations.startupAndBackground,
        rows: _startupItems(appLocalizations),
        footer: appLocalizations.onDemandDesc,
      ),
      _HaraSection(
        title: appLocalizations.requestsAndUpdates,
        rows: _requestItems(),
        footer: appLocalizations.checkCertificateDesc,
      ),
      _HaraSection(
        title: appLocalizations.inbound,
        rows: _inboundItems(externalController: externalController),
        footer: appLocalizations.externalControllerDesc,
      ),
      _HaraSection(
        title: appLocalizations.connection,
        rows: _connectionItems(),
        footer: appLocalizations.autoCloseConnectionsDesc,
      ),
      _HaraSection(
        title: appLocalizations.core,
        rows: _coreItems(),
        footer: appLocalizations.ipv6Desc,
      ),
      _HaraSection(
        title: appLocalizations.logsAndDiagnostics,
        rows: _logItems(),
        footer: appLocalizations.logcatDesc,
      ),
    ];
    return BaseScaffold(
      title: appLocalizations.general,
      body: Material(
        color: palette.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(side, context.appBarInset, side, 48),
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: HaraSpace.groupGap),
                  sections[i],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
