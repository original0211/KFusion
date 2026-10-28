import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/views/profiles/singbox_degradations.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Universal import: any Clash YAML, sing-box JSON, share-link list or
/// base64 subscription becomes one file profile of Clash YAML, optionally
/// under a routing template. Failures are shown, never silently imported.
class UniversalImportView extends ConsumerStatefulWidget {
  const UniversalImportView({super.key});

  @override
  ConsumerState<UniversalImportView> createState() =>
      _UniversalImportViewState();
}

class _UniversalImportViewState extends ConsumerState<UniversalImportView> {
  final _urlController = TextEditingController();
  final _pasteController = TextEditingController();
  final _labelController = TextEditingController(text: 'KFusion 导入');
  var _templateId = kfusionDefaultTemplate.id;
  IrParseResult? _preview;
  ConfigFormat? _format;
  String? _error;
  String? _exportMessage;
  var _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    _pasteController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _showPreview(String content) {
    setState(() {
      _error = null;
      try {
        _format = detectFormat(content);
        _preview = parseConfig(content);
        if (_preview!.profile.nodes.isEmpty) {
          _error = '未解析出任何节点，请检查内容格式。';
        }
      } catch (e) {
        _preview = null;
        _error = '无法解析：${compactError(e)}';
      }
    });
  }

  Future<void> _loadFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请先填写订阅链接。');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await request.getFileResponseForUrl(url);
      final bytes = decompressUnlabeled(response.data ?? Uint8List(0));
      _showPreview(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      setState(() {
        _preview = null;
        _error = '订阅下载失败：${compactError(e)}';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _loadFromFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    try {
      final bytes = await platformFile.readBytes();
      _showPreview(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      setState(() {
        _preview = null;
        _error = '文件读取失败：${compactError(e)}';
      });
    }
  }

  String _previewText(IrParseResult preview) {
    final unsupported = preview.unsupported.isEmpty
        ? ''
        : '，不支持：${preview.unsupported.join('、')}';
    final skipped = preview.skipped.isEmpty
        ? ''
        : '，跳过：${preview.skipped.join('、')}';
    return '检测到：${_format?.name ?? ''}，'
        '${preview.profile.nodes.length} 个节点$unsupported$skipped';
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null || preview.profile.nodes.isEmpty) {
      setState(() => _error = '没有可导入的节点。');
      return;
    }
    setState(() => _busy = true);
    try {
      final yamlText = yaml.encode(
        applyTemplate(preview.profile.toClashMap(), _templateId),
      );
      final label = _labelController.text.trim().isEmpty
          ? 'KFusion 导入'
          : _labelController.text.trim();
      final saved = await ref
          .read(profilesActionProvider.notifier)
          .addUniversalProfile(label, yamlText);
      if (!mounted) return;
      final degradations = await scanAndStoreSingBoxDegradations(
        ref.read(singBoxDegradationStoreProvider),
        saved.id,
      );
      ref.invalidate(profileDegradationsProvider(saved.id));
      var viewList = false;
      if (degradations.isNotEmpty && mounted) {
        viewList =
            await showSingBoxImportSummary(context, degradations.length) ??
            false;
      }
      if (!mounted) return;
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
      if (viewList) {
        final homeContext = globalState.navigatorKey.currentContext;
        if (homeContext != null && homeContext.mounted) {
          unawaited(
            BaseNavigator.push(
              homeContext,
              SingBoxDegradationsView(profile: saved),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _error = '导入失败：${compactError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSingBox() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _busy = true);
    try {
      final SingBoxRenderResult rendered = renderSingBox(
        preview.profile,
        secret: generateSingBoxSecret(),
      );
      final bytes = Uint8List.fromList(
        utf8.encode(json.encode(rendered.config)),
      );
      final uri = await picker.saveFile('kfusion-singbox.json', bytes);
      if (!mounted) return;
      setState(() {
        _exportMessage = uri == null
            ? '已取消导出。'
            : 'sing-box 配置已保存到 $uri'
                  '${rendered.unsupported.isEmpty ? '' : '，未翻译：${rendered.unsupported.join('、')}'}';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _exportMessage = '导出失败：${compactError(e)}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final preview = _preview;
    return CommonScaffold(
      title: '万能导入',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(
            HaraSpace.pageInset,
            (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
          );
          return ListView(
            padding: EdgeInsets.symmetric(
              horizontal: side,
            ).copyWith(top: context.contentTopPadding, bottom: 16),
            children: [
              Text('万能导入', style: HaraText.pageTitle(context, palette.ink)),
              const SizedBox(height: 6),
              Text(
                'Clash / sing-box / 分享链接 / 订阅，一次导入',
                style: HaraText.statusNode(context, palette.sub),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: HaraText.statusNode(
                    context,
                    context.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: HaraSpace.groupGap),
              _HaraSection(
                rows: [
                  _HaraSourceRow(
                    title: '从订阅链接导入',
                    subtitle: '支持 Clash / sing-box / 分享链接',
                    actionLabel: '下载并解析',
                    onTap: _busy ? null : _loadFromUrl,
                  ),
                  _HaraWell(
                    child: TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      style: HaraText.payload(context, palette.ink),
                      decoration: InputDecoration.collapsed(
                        border: const NoInputBorder(),
                        hintText: 'https://…',
                        hintStyle: HaraText.payload(context, palette.dim),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HaraSpace.groupGap),
              _HaraSection(
                rows: [
                  _HaraSourceRow(
                    title: '从文件导入',
                    subtitle: 'Clash YAML / sing-box JSON / 链接文本',
                    actionLabel: '选择文件',
                    onTap: _busy ? null : _loadFromFile,
                  ),
                ],
              ),
              const SizedBox(height: HaraSpace.groupGap),
              _HaraSection(
                rows: [
                  _HaraSourceRow(
                    title: '解析粘贴的文本',
                    subtitle: '粘贴内容后点「解析文本」',
                    actionLabel: '解析文本',
                    onTap: _busy
                        ? null
                        : () => _showPreview(_pasteController.text),
                  ),
                  _HaraWell(
                    child: TextField(
                      controller: _pasteController,
                      minLines: 4,
                      maxLines: null,
                      autocorrect: false,
                      style: HaraText.payload(context, palette.ink),
                      decoration: InputDecoration.collapsed(
                        border: const NoInputBorder(),
                        hintText: '粘贴配置文本…',
                        hintStyle: HaraText.payload(context, palette.dim),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HaraSpace.groupGap),
              _HaraSection(
                rows: [
                  _HaraFieldRow(
                    title: '配置名称',
                    child: FormRowTextField(
                      controller: _labelController,
                      hintText: 'KFusion 导入',
                    ),
                  ),
                  _HaraFieldRow(
                    title: '路由模板',
                    child: DropdownButton<String>(
                      value: _templateId,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      style: HaraText.nodeName(
                        context,
                        palette.ink,
                        current: false,
                      ),
                      items: [
                        for (final template in routingTemplates)
                          DropdownMenuItem(
                            value: template.id,
                            child: Text(
                              template.label,
                              textAlign: TextAlign.end,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _templateId = value);
                      },
                    ),
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: HaraSpace.groupGap),
                _HaraSection(
                  title: '解析结果',
                  rows: [
                    _HaraWell(
                      child: Text(
                        _previewText(preview),
                        style: HaraText.payload(context, palette.sub),
                      ),
                    ),
                    if (_exportMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Text(
                          _exportMessage!,
                          style: HaraText.statusNode(context, palette.sub),
                        ),
                      ),
                  ],
                ),
                if (system.isAndroid) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Android 由 sing-box VPN 运行时接管（真机待验）。',
                    style: HaraText.profileMeta(context, palette.dim),
                  ),
                ],
                const SizedBox(height: 30),
                _HaraPrimaryAction(
                  label: '确认导入',
                  onTap: _busy ? null : _confirm,
                ),
                const SizedBox(height: 18),
                _HaraTextAction(
                  label: '导出 sing-box 配置',
                  onTap: _busy ? null : _exportSingBox,
                ),
              ] else ...[
                const SizedBox(height: 30),
                Text('确认导入', style: HaraText.action(context, palette.dim)),
                const SizedBox(height: 8),
                Text(
                  '解析成功后可在此确认导入',
                  style: HaraText.profileMeta(context, palette.dim),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One import section: an optional small section title over hairline rows.
class _HaraSection extends StatelessWidget {
  const _HaraSection({this.title, required this.rows});

  final String? title;
  final List<Widget> rows;

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
        for (final (index, row) in rows.indexed) ...[
          row,
          if (index < rows.length - 1) HaraHairline(color: palette.line),
        ],
        HaraHairline(color: palette.line),
      ],
    );
  }
}

class _HaraSourceRow extends StatelessWidget {
  const _HaraSourceRow({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final enabled = onTap != null;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: HaraText.nodeName(
                      context,
                      palette.ink,
                      current: false,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: HaraText.profileMeta(context, palette.sub),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HaraUnderlinedAction(
              label: actionLabel,
              color: enabled ? palette.ink : palette.dim,
            ),
          ],
        ),
      ),
    );
  }
}

class _HaraFieldRow extends StatelessWidget {
  const _HaraFieldRow({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          Text(
            title,
            style: HaraText.nodeName(context, palette.ink, current: false),
          ),
          const SizedBox(width: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The primary action reading: ink text over a 1.2 ink underline.
class _HaraUnderlinedAction extends StatelessWidget {
  const _HaraUnderlinedAction({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: HaraText.action(context, color)),
          const SizedBox(height: 5),
          Container(height: 1.2, color: color),
        ],
      ),
    );
  }
}

class _HaraPrimaryAction extends StatelessWidget {
  const _HaraPrimaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _HaraUnderlinedAction(
            label: label,
            color: onTap == null ? palette.dim : palette.ink,
          ),
        ),
      ),
    );
  }
}

class _HaraTextAction extends StatelessWidget {
  const _HaraTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        customBorder: AppShape.hara,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            label,
            style: HaraText.action(
              context,
              onTap == null ? palette.dim : palette.sub,
            ),
          ),
        ),
      ),
    );
  }
}

/// A payload well: hairlines on all four sides, no fill, mono text inside.
class _HaraWell extends StatelessWidget {
  const _HaraWell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: palette.line, width: 0.7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: child,
        ),
      ),
    );
  }
}
