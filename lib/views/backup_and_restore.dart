import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/action.dart';
import 'package:kfusion/providers/app.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/widgets/config_item.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BackupAndRestore extends ConsumerStatefulWidget {
  const BackupAndRestore({super.key});

  @override
  ConsumerState<BackupAndRestore> createState() => _BackupAndRestoreState();
}

class _BackupAndRestoreState extends ConsumerState<BackupAndRestore>
    with UniqueKeyStateMixin {
  Future<void> _run({
    required String title,
    required String successMessage,
    required Future<bool> Function() task,
  }) async {
    final res = await globalState.loadingRun<bool>(
      task,
      tag: LoadingTag.backup_restore,
      title: title,
    );
    if (res != true) return;
    unawaited(
      dialogs.showMessage(
        title: title,
        message: TextSpan(text: successMessage),
      ),
    );
  }

  Future<void> _backup(BackupDelivery deliver) {
    final appLocalizations = context.appLocalizations;
    return _run(
      title: appLocalizations.backup,
      successMessage: appLocalizations.backupSuccess,
      task: () => ref.read(backupActionProvider.notifier).backup(deliver),
    );
  }

  Future<void> _restore(RestoreOption option, BackupFetch fetch) {
    final appLocalizations = context.appLocalizations;
    return _run(
      title: appLocalizations.restore,
      successMessage: appLocalizations.restoreSuccess,
      task: () =>
          ref.read(backupActionProvider.notifier).restore(option, fetch),
    );
  }

  Future<RestoreOption?> _pickRestoreOption() {
    return dialogs.showCommonDialog<RestoreOption>(
      child: const RestoreOptionsDialog(),
    );
  }

  Future<void> _backupOnLocal() {
    return _backup((archivePath) async {
      final savedPath = await picker.saveFileWithPath(
        getBackupFileName(),
        archivePath,
      );
      return savedPath != null;
    });
  }

  Future<void> _restoreOnLocal() async {
    final option = await _pickRestoreOption();
    if (option == null || !mounted) return;
    final file = await picker.pickerFile();
    final path = file?.path;
    if (path == null || !mounted) return;
    await _restore(option, (_) async => path);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final isLoading = ref.watch(loadingProvider(LoadingTag.backup_restore));
    return CommonScaffold(
      isLoading: isLoading,
      title: appLocalizations.backupAndRestore,
      body: Material(
        color: palette.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(side, context.appBarInset, side, 48),
              children: [
                _section(
                  context,
                  appLocalizations.local,
                  rows: [
                    _HaraRow(
                      onTap: _backupOnLocal,
                      child: Text(
                        appLocalizations.backup,
                        style: HaraText.nodeName(
                          context,
                          palette.ink,
                          current: false,
                        ),
                      ),
                    ),
                    _HaraRow(
                      onTap: _restoreOnLocal,
                      child: Text(
                        appLocalizations.restore,
                        style: HaraText.nodeName(
                          context,
                          palette.ink,
                          current: false,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HaraSpace.groupGap),
                _section(
                  context,
                  appLocalizations.options,
                  rows: [
                    _HaraBoundOptions<RestoreStrategy>(
                      ConfigOptionsItem<RestoreStrategy>(
                        title: (l) => l.restoreStrategy,
                        options: RestoreStrategy.values,
                        textBuilder: (strategy) => strategy.label,
                        selector: appSettingProvider.select(
                          (state) => state.restoreStrategy,
                        ),
                        onChanged: (ref, value) => ref
                            .read(appSettingProvider.notifier)
                            .update(
                              (state) => state.copyWith(restoreStrategy: value),
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
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
    return _HaraRow(
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

class RestoreOptionsDialog extends StatefulWidget {
  const RestoreOptionsDialog({super.key});

  @override
  State<RestoreOptionsDialog> createState() => _RestoreOptionsDialogState();
}

class _RestoreOptionsDialogState extends State<RestoreOptionsDialog> {
  void _handleOnTab(RestoreOption? option) {
    if (option == null) return;
    Navigator.of(context).pop(option);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.restore,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Wrap(
        children: [
          ListItem(
            onTap: () {
              _handleOnTab(RestoreOption.onlyProfiles);
            },
            title: Text(appLocalizations.restoreOnlyConfig),
          ),
          ListItem(
            onTap: () {
              _handleOnTab(RestoreOption.all);
            },
            title: Text(appLocalizations.restoreAllData),
          ),
        ],
      ),
    );
  }
}
