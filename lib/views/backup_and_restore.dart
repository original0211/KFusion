import 'dart:async';
import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/common/dav_client.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
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
  final _davConnection = DAVConnectionController();

  @override
  void initState() {
    super.initState();
    ref.listenManual(davSettingProvider, (_, _) {
      _updateDAVClient();
    }, fireImmediately: true);
  }

  void _updateDAVClient() {
    unawaited(_davConnection.update(ref.read(davSettingProvider)));
  }

  @override
  void dispose() {
    _davConnection.dispose();
    super.dispose();
  }

  Future<void> _showAddWebDAV(DAVProps? dav) async {
    await showFormSheet<void>(
      context: context,
      builder: (_) => WebDAVForm(dav: dav?.copyWith()),
    );
  }

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

  Future<void> _backupOnWebDAV() async {
    final client = _davConnection.client;
    if (client == null) return;
    await _backup((archivePath) async {
      await client.upload(archivePath);
      return true;
    });
  }

  Future<void> _restoreOnWebDAV() async {
    final client = _davConnection.client;
    if (client == null) return;
    final option = await _pickRestoreOption();
    if (option == null || !mounted) return;
    await _restore(option, (downloadPath) async {
      await client.download(downloadPath);
      return downloadPath;
    });
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

  void _handleChange(String? value, WidgetRef ref) {
    if (value == null) {
      return;
    }
    ref
        .read(davSettingProvider.notifier)
        .update((state) => state?.copyWith(fileName: value));
  }

  Future<void> _editFileName(BuildContext context, String value) async {
    final result = await showFloatingDialog<String>(
      context: Navigator.of(context, rootNavigator: true).context,
      child: InputDialog(
        title: context.appLocalizations.file,
        value: value,
        resetValue: defaultDavFileName,
        inputFormatters: TextInputLimits.limit(TextInputLimits.fileName),
      ),
    );
    _handleChange(result, ref);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final dav = ref.watch(davSettingProvider);
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
                  appLocalizations.remote,
                  rows: [
                    if (dav == null)
                      _HaraRow(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appLocalizations.noInfo,
                                    style: HaraText.nodeName(
                                      context,
                                      palette.ink,
                                      current: false,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: HaraSpace.profileMetaGap,
                                  ),
                                  Text(
                                    appLocalizations.pleaseBindWebDAV,
                                    style: HaraText.profileMeta(
                                      context,
                                      palette.sub,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _TextAction(
                              label: appLocalizations.bind,
                              onPressed: () => _showAddWebDAV(dav),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _HaraRow(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TooltipText(
                                    text: Text(
                                      dav.user,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: HaraText.nodeName(
                                        context,
                                        palette.ink,
                                        current: false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: HaraSpace.profileMetaGap,
                                  ),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        appLocalizations.connectivity,
                                        style: HaraText.profileMeta(
                                          context,
                                          palette.sub,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _DavConnectionIndicator(
                                        connection: _davConnection,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _TextAction(
                              label: appLocalizations.edit,
                              onPressed: () => _showAddWebDAV(dav),
                            ),
                          ],
                        ),
                      ),
                      _HaraRow(
                        onTap: () => _editFileName(context, dav.fileName),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizations.file,
                              style: HaraText.nodeName(
                                context,
                                palette.ink,
                                current: false,
                              ),
                            ),
                            const SizedBox(height: HaraSpace.profileMetaGap),
                            Text(
                              dav.fileName,
                              style: HaraText.payload(context, palette.sub),
                            ),
                          ],
                        ),
                      ),
                      _HaraRow(
                        onTap: _backupOnWebDAV,
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
                        onTap: _restoreOnWebDAV,
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
                  ],
                ),
                const SizedBox(height: HaraSpace.groupGap),
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

/// A text action in a row's trailing slot.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Semantics(
      button: true,
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: HaraText.action(context, palette.ink)),
        ),
      ),
    );
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

class _DavConnectionIndicator extends StatelessWidget {
  const _DavConnectionIndicator({required this.connection});

  final ValueNotifier<bool?> connection;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: connection,
      builder: (context, isConnected, _) {
        return Center(
          child: FadeThroughBox(
            child: isConnected == null
                ? const CommonCircleLoading(size: 12)
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !isConnected
                          ? context.colorScheme.error
                          : context.colorScheme.success,
                    ),
                    width: 12,
                    height: 12,
                  ),
          ),
        );
      },
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

enum _DavField { uri, user, password }

class WebDAVForm extends ConsumerStatefulWidget {
  final DAVProps? dav;

  const WebDAVForm({super.key, this.dav});

  @override
  ConsumerState<WebDAVForm> createState() => _WebDAVFormState();
}

class _WebDAVFormState extends ConsumerState<WebDAVForm> {
  late final TextEditingController _uriController;
  late final TextEditingController _userController;
  late final TextEditingController _passwordController;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _uriController = TextEditingController(text: widget.dav?.uri);
    _userController = TextEditingController(text: widget.dav?.user);
    _passwordController = TextEditingController(text: widget.dav?.password);
  }

  @override
  void dispose() {
    _uriController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ({_DavField field, String message})? _issue(
    AppLocalizations appLocalizations,
  ) {
    final uri = _uriController.text;
    if (uri.isEmpty || !uri.isUrl) {
      return (field: _DavField.uri, message: appLocalizations.addressTip);
    }
    if (_userController.text.isEmpty) {
      return (
        field: _DavField.user,
        message: appLocalizations.emptyTip(appLocalizations.account),
      );
    }
    if (_passwordController.text.isEmpty) {
      return (
        field: _DavField.password,
        message: appLocalizations.emptyTip(appLocalizations.password),
      );
    }
    return null;
  }

  void _handleChanged(String _) {
    if (_attempted) {
      setState(() {});
    }
  }

  void _submit() {
    if (_issue(context.appLocalizations) != null) {
      setState(() {
        _attempted = true;
      });
      return;
    }
    ref
        .read(davSettingProvider.notifier)
        .update(
          (_) => DAVProps(
            uri: _uriController.text,
            user: _userController.text,
            password: _passwordController.text,
            fileName: widget.dav?.fileName ?? defaultDavFileName,
          ),
        );
    Navigator.pop(context);
  }

  void _delete() {
    ref.read(davSettingProvider.notifier).update((_) => null);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final issue = _attempted ? _issue(appLocalizations) : null;
    return FormPage(
      title: appLocalizations.webDAVConfiguration,
      onSave: _submit,
      error: issue?.message,
      children: [
        generateSection(
          footer: appLocalizations.addressHelp,
          items: [
            FormRow(
              title: appLocalizations.address,
              invalid: issue?.field == _DavField.uri,
              trailing: FormRowTextField(
                controller: _uriController,
                hintText: appLocalizations.required,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(TextInputLimits.uri),
                onChanged: _handleChanged,
              ),
            ),
            FormRow(
              title: appLocalizations.account,
              invalid: issue?.field == _DavField.user,
              trailing: FormRowTextField(
                controller: _userController,
                hintText: appLocalizations.required,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(
                  TextInputLimits.userName,
                ),
                onChanged: _handleChanged,
              ),
            ),
            FormRow(
              title: appLocalizations.password,
              invalid: issue?.field == _DavField.password,
              trailing: FormRowSecretTextField(
                controller: _passwordController,
                hintText: appLocalizations.required,
                textInputAction: TextInputAction.done,
                inputFormatters: TextInputLimits.limit(
                  TextInputLimits.password,
                ),
                onChanged: _handleChanged,
                onFieldSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        if (widget.dav != null)
          generateSection(
            items: [
              FormRow(
                title: appLocalizations.delete,
                titleStyle: TextStyle(color: context.colorScheme.error),
                onPressed: _delete,
              ),
            ],
          ),
      ],
    );
  }
}
