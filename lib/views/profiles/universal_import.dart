import 'dart:convert';
import 'dart:typed_data';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/core/singbox/singbox_runner.dart';
import 'package:kfusion/features/config_hub/config_hub.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
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
      await ref
          .read(profilesActionProvider.notifier)
          .addUniversalProfile(label, yamlText);
      if (!mounted) return;
      globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
      ref.read(currentPageLabelProvider.notifier).toProfiles();
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
    final colorScheme = context.colorScheme;
    final preview = _preview;
    final sections = <Widget>[
      generateSection(
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.cloudDownload),
            title: const Text('从订阅链接导入'),
            subtitle: const Text('支持 Clash / sing-box / 分享链接'),
            trailing: TonalButton(
              label: '下载并解析',
              onPressed: _busy ? null : _loadFromUrl,
            ),
            onTap: _busy ? null : _loadFromUrl,
          ),
          DecorationListItem(
            title: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration.collapsed(
                border: NoInputBorder(),
                hintText: 'https://…',
              ),
            ),
          ),
        ],
      ),
      generateSection(
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.importFile),
            title: const Text('从文件导入'),
            subtitle: const Text('Clash YAML / sing-box JSON / 链接文本'),
            trailing: TonalButton(
              label: '选择文件',
              onPressed: _busy ? null : _loadFromFile,
            ),
            onTap: _busy ? null : _loadFromFile,
          ),
        ],
      ),
      generateSection(
        items: [
          ListItem(
            leading: const GlyphIcon(AppGlyphs.customize),
            title: const Text('解析粘贴的文本'),
            subtitle: const Text('粘贴内容后点「解析文本」'),
            trailing: TonalButton(
              label: '解析文本',
              onPressed: _busy
                  ? null
                  : () => _showPreview(_pasteController.text),
            ),
            onTap: _busy ? null : () => _showPreview(_pasteController.text),
          ),
          DecorationListItem(
            title: TextField(
              controller: _pasteController,
              minLines: 4,
              maxLines: null,
              autocorrect: false,
              decoration: const InputDecoration.collapsed(
                border: NoInputBorder(),
                hintText: '粘贴配置文本…',
              ),
            ),
          ),
        ],
      ),
      generateSection(
        items: [
          FormRow(
            title: '配置名称',
            trailing: FormRowTextField(
              controller: _labelController,
              hintText: 'KFusion 导入',
            ),
          ),
          FormRow(
            title: '路由模板',
            trailing: DropdownButton<String>(
              value: _templateId,
              items: [
                for (final template in routingTemplates)
                  DropdownMenuItem(
                    value: template.id,
                    child: Text(template.label),
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
        generateSection(
          title: '解析结果',
          footer: system.isAndroid
              ? 'Android 由 sing-box VPN 运行时接管（真机待验）。'
              : null,
          items: [
            DecorationListItem(title: Text(_previewText(preview))),
            if (_exportMessage != null)
              DecorationListItem(title: Text(_exportMessage!)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: const Text('确认导入'),
            ),
            FilledButton.tonal(
              onPressed: _busy ? null : _exportSingBox,
              child: const Text('导出 sing-box 配置'),
            ),
          ],
        ),
      ] else ...[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            const FilledButton(onPressed: null, child: Text('确认导入')),
            Text('解析成功后可在此确认导入', style: context.listCaptionStyle),
          ],
        ),
      ],
    ];
    return CommonScaffold(
      title: '万能导入',
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
        ).copyWith(top: context.contentTopPadding, bottom: 16),
        children: [
          Row(
            spacing: 16,
            children: [
              DashboardDiscMotif(size: 44, color: colorScheme.onSurface),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('万能导入', style: AppTextStyle.headline.of(context)),
                    const SizedBox(height: 2),
                    Text(
                      'Clash / sing-box / 分享链接 / 订阅，一次导入',
                      style: AppTextStyle.footnote.of(context).toLighter,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ErrorBanner(message: _error),
          ...sections.separated(const SizedBox(height: 24)),
        ],
      ),
    );
  }
}
