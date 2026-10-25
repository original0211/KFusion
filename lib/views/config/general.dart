import 'package:kfusion/common/common.dart';
import 'package:kfusion/core/singbox/singbox_binary.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/views/config/on_demand.dart';
import 'package:kfusion/views/config/user_agents.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'general/port_form.dart';

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
    final label = binaryLabel;
    if (label != null) {
      return Text(label, style: context.listSubtitleStyle);
    }
    final error = downloadError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.singBoxBinaryMissing,
          style: context.listSubtitleStyle,
        ),
        const SizedBox(height: 2),
        Text(
          localizations.singBoxDownloadHint,
          style: context.listSubtitleStyle,
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error,
            style: context.listSubtitleStyle.copyWith(
              color: context.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (downloading)
          Row(
            children: [
              Expanded(child: LinearProgressIndicator(value: progress)),
              const SizedBox(width: 12),
              Text(_downloadingText(), style: context.listSubtitleStyle),
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
    final colorScheme = context.colorScheme;
    const shape = AppShape.md;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: shape,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: shape,
          onTap: switching || selected ? null : () => onSelectCore(kind),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                DashboardDiscMotif(
                  size: 20,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    coreKindDisplayName(kind),
                    style: context.listTitleStyle,
                  ),
                ),
                Text(
                  running ? localizations.running : localizations.notRunning,
                  style: context.listSubtitleStyle,
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const SelectionCheck(),
                ],
              ],
            ),
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
    final isStart =
        position == ItemPosition.start || position == ItemPosition.startAndEnd;
    final isEnd =
        position == ItemPosition.end || position == ItemPosition.startAndEnd;
    final borderRadius = AppRadius.vertical(
      top: isStart ? AppCorner.xl : AppCorner.none,
      bottom: isEnd ? AppCorner.xl : AppCorner.none,
    );
    return CommonCard(
      shape: AppShape.of(borderRadius),
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Text(localizations.coreSwitchTitle, style: context.listTitleStyle),
            const SizedBox(height: 2),
            Text(
              statusText,
              style: statusIsFailure
                  ? context.listSubtitleStyle.copyWith(
                      color: context.colorScheme.error,
                    )
                  : context.listSubtitleStyle,
            ),
            if (statusIsFailure && failureDetail.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                localizations.coreSwitchFailureDetail(failureDetail),
                style: context.listSubtitleStyle.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
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
            if (!isEnd)
              Divider(
                height: 1,
                indent: 0,
                endIndent: 14,
                color:
                    DividerTheme.of(context).color ??
                    context.colorScheme.outlineVariant,
              ),
          ],
        ),
      ),
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
    return ListItem(
      title: const Text('运行核心'),
      subtitle: Text(profile?.realLabel ?? '未选择配置'),
      trailing: profile == null
          ? null
          : DropdownButton<CoreKind>(
              value: kind ?? CoreKind.mihomo,
              items: [
                for (final option in CoreKind.values)
                  DropdownMenuItem(value: option, child: Text(option.value)),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(coreKindsProvider.notifier)
                      .setKind(profile.id, value);
                }
              },
            ),
    );
  }
}

class UaItem extends ConsumerWidget {
  const UaItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final globalUa = ref.watch(
      patchClashConfigProvider.select((state) => state.globalUa),
    );
    return ListItem.open(
      title: Text(appLocalizations.userAgent),
      subtitle: Text(globalUa ?? appLocalizations.defaultText),
      widget: const UserAgentsView(),
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
    return ListItem.input(
      title: Text(appLocalizations.testUrl),
      subtitle: Text(testUrl),
      resetValue: defaultTestUrl,
      dialogTitle: appLocalizations.testUrl,
      value: testUrl,
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
  }
}

class PortItem extends ConsumerWidget {
  const PortItem({super.key});

  Future<void> handleShowPortForm(BuildContext context) async {
    await showFormSheet<void>(
      context: context,
      builder: (_) => const _PortForm(),
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final mixedPort = ref.watch(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    return ListItem(
      title: Text(appLocalizations.port),
      subtitle: Text('$mixedPort'),
      onTap: () {
        handleShowPortForm(context);
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
    return ListItem.open(
      title: const Text('Hosts'),
      subtitle: Text(
        hosts.isEmpty
            ? appLocalizations.none
            : appLocalizations.itemsCount(hosts.length),
      ),
      widget: MapEditView(
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

class AuthenticationItem extends ConsumerWidget {
  const AuthenticationItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.authentication,
      selector: networkSettingProvider.select(
        (state) => state.authentication.enable,
      ),
      onChanged: (ref, value) =>
          ref.read(networkSettingProvider.notifier).update((state) {
            var authentication = state.authentication.copyWith(enable: value);
            if (value && authentication.username.isEmpty) {
              authentication = authentication.copyWith(
                username: generateRandomSecret(8),
                password: generateRandomSecret(16),
              );
            }
            return state.copyWith(authentication: authentication);
          }),
    );
  }
}

class AuthenticationAccountItem extends ConsumerWidget {
  const AuthenticationAccountItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.account,
      maxLength: TextInputLimits.userName,
      selector: networkSettingProvider.select(
        (state) => state.authentication.username,
      ),
      // mihomo and the Dart proxy string both split user:pass on the first
      // colon, so a colon in the username breaks authentication.
      normalize: (value) => value.trim().replaceAll(':', ''),
      onChanged: (ref, value) => ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith.authentication(username: value)),
    );
  }
}

class AuthenticationPasswordItem extends ConsumerWidget {
  const AuthenticationPasswordItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.password,
      maxLength: TextInputLimits.password,
      selector: networkSettingProvider.select(
        (state) => state.authentication.password,
      ),
      normalize: (value) => value.trim(),
      onChanged: (ref, value) => ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith.authentication(password: value)),
    );
  }
}

class ExternalControllerSecretItem extends ConsumerWidget {
  const ExternalControllerSecretItem({super.key});

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.externalControllerSecret,
      maxLength: TextInputLimits.password,
      selector: patchClashConfigProvider.select((state) => state.secret),
      normalize: (value) => value.trim(),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(secret: value)),
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

class GeneralView extends ConsumerWidget {
  const GeneralView({super.key});

  List<Widget> _startupItems(AppLocalizations appLocalizations) {
    return [
      const CoreSwitchItem(),
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
      ListItem.open(
        title: Text(appLocalizations.onDemand),
        widget: const OnDemandView(),
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

  List<Widget> _inboundItems({
    required bool authentication,
    required bool externalController,
  }) {
    return [
      const PortItem(),
      _clashToggle(
        title: (l) => l.allowLan,
        select: (state) => state.allowLan,
        update: (state, value) => state.copyWith(allowLan: value),
      ),
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
      if (externalController) const ExternalControllerSecretItem(),
      const AuthenticationItem(),
      if (authentication) ...const [
        AuthenticationAccountItem(),
        AuthenticationPasswordItem(),
      ],
    ];
  }

  List<Widget> _connectionItems() {
    return [
      const TestUrlItem(),
      _clashToggle(
        title: (l) => l.unifiedDelay,
        select: (state) => state.unifiedDelay,
        update: (state, value) => state.copyWith(unifiedDelay: value),
      ),
      _clashToggle(
        title: (l) => l.tcpConcurrent,
        select: (state) => state.tcpConcurrent,
        update: (state, value) => state.copyWith(tcpConcurrent: value),
      ),
      _clashToggle(
        title: (l) => l.findProcessMode,
        select: (state) => state.findProcessMode == FindProcessMode.always,
        update: (state, value) => state.copyWith(
          findProcessMode: value ? FindProcessMode.always : FindProcessMode.off,
        ),
      ),
      _appSettingToggle(
        title: (l) => l.autoCloseConnections,
        select: (state) => state.closeConnections,
        update: (state, value) => state.copyWith(closeConnections: value),
      ),
      _appSettingToggle(
        title: (l) => l.onlyStatisticsProxy,
        select: (state) => state.onlyStatisticsProxy,
        update: (state, value) => state.copyWith(onlyStatisticsProxy: value),
      ),
    ];
  }

  List<Widget> _requestItems() {
    return [
      const UaItem(),
      _appSettingToggle(
        title: (l) => l.checkCertificate,
        select: (state) => state.checkCertificate,
        update: (state, value) => state.copyWith(checkCertificate: value),
      ),
      _appSettingToggle(
        title: (l) => l.autoCheckUpdate,
        select: (state) => state.autoCheckUpdate,
        update: (state, value) => state.copyWith(autoCheckUpdate: value),
      ),
    ];
  }

  List<Widget> _coreItems() {
    return [
      const CurrentProfileCoreKindItem(),
      _clashToggle(
        title: (l) => 'IPv6',
        select: (state) => state.ipv6,
        update: (state, value) => state.copyWith(ipv6: value),
      ),
      const HostsItem(),
      ConfigToggleItem(
        title: (l) => l.appendSystemDns,
        selector: networkSettingProvider.select(
          (state) => state.appendSystemDns,
        ),
        onChanged: (ref, value) => ref
            .read(networkSettingProvider.notifier)
            .update((state) => state.copyWith(appendSystemDns: value)),
      ),
      _clashToggle(
        title: (l) => l.geodataLoader,
        select: (state) => state.geodataLoader == GeodataLoader.memconservative,
        update: (state, value) => state.copyWith(
          geodataLoader: value
              ? GeodataLoader.memconservative
              : GeodataLoader.standard,
        ),
      ),
    ];
  }

  List<Widget> _logItems() {
    return [
      const LogLevelItem(),
      _appSettingToggle(
        title: (l) => l.logcat,
        select: (state) => state.openLogs,
        update: (state, value) => state.copyWith(openLogs: value),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final authentication = ref.watch(
      networkSettingProvider.select((state) => state.authentication.enable),
    );
    final externalController = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.externalController == ExternalControllerStatus.open,
      ),
    );
    return BaseScaffold(
      title: appLocalizations.general,
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.appBarInset, bottom: 16),
        children: [
          generateSection(
            title: appLocalizations.startupAndBackground,
            items: _startupItems(appLocalizations),
            footer: [
              if (system.isDesktop) appLocalizations.silentLaunchDesc,
              appLocalizations.autoRunDesc,
              appLocalizations.onDemandDesc,
            ].join('\n'),
          ),
          generateSection(
            title: appLocalizations.requestsAndUpdates,
            items: _requestItems(),
            footer: appLocalizations.checkCertificateDesc,
          ),
          generateSection(
            title: appLocalizations.inbound,
            items: _inboundItems(
              authentication: authentication,
              externalController: externalController,
            ),
            footer: [
              appLocalizations.externalControllerDesc,
              appLocalizations.authenticationDesc,
            ].join('\n'),
          ),
          generateSection(
            title: appLocalizations.connection,
            items: _connectionItems(),
            footer: appLocalizations.autoCloseConnectionsDesc,
          ),
          generateSection(
            title: appLocalizations.core,
            items: _coreItems(),
            footer: appLocalizations.ipv6Desc,
          ),
          generateSection(
            title: appLocalizations.logsAndDiagnostics,
            items: _logItems(),
            footer: appLocalizations.logcatDesc,
          ),
        ],
      ),
    );
  }
}
