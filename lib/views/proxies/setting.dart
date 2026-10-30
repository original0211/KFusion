import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProxiesSetting extends ConsumerWidget {
  const ProxiesSetting({super.key});

  static ConfigWriter<T> _writer<T>(
    ProxiesStyleProps Function(ProxiesStyleProps state, T value) update,
  ) {
    return (ref, value) => ref
        .read(proxiesStyleSettingProvider.notifier)
        .update((state) => update(state, value));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final isList = ref.watch(
      proxiesStyleSettingProvider.select(
        (state) => state.type == ProxiesType.list,
      ),
    );
    final sections = <Widget>[
      _HaraSection(
        title: appLocalizations.proxySettings,
        rows: [
          _HaraOptions<ProxiesType>(
            ConfigOptionsItem<ProxiesType>(
              title: (l) => l.style,
              options: ProxiesType.values,
              textBuilder: (type) => type.label,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.type,
              ),
              onChanged: _writer((state, value) => state.copyWith(type: value)),
            ),
          ),
          _HaraOptions<ProxiesSortType>(
            ConfigOptionsItem<ProxiesSortType>(
              title: (l) => l.sort,
              options: ProxiesSortType.values,
              textBuilder: (type) => switch (type) {
                ProxiesSortType.none => appLocalizations.defaultText,
                ProxiesSortType.delay => appLocalizations.delay,
                ProxiesSortType.name => appLocalizations.name,
              },
              selector: proxiesStyleSettingProvider.select(
                (state) => state.sortType,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(sortType: value),
              ),
            ),
          ),
          _HaraOptions<ProxiesLayout>(
            ConfigOptionsItem<ProxiesLayout>(
              title: (l) => l.layout,
              options: ProxiesLayout.values,
              textBuilder: (layout) => switch (layout) {
                ProxiesLayout.tight => appLocalizations.tight,
                ProxiesLayout.standard => appLocalizations.standard,
                ProxiesLayout.loose => appLocalizations.loose,
              },
              selector: proxiesStyleSettingProvider.select(
                (state) => state.layout,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(layout: value),
              ),
            ),
          ),
          _HaraOptions<ProxyCardType>(
            ConfigOptionsItem<ProxyCardType>(
              title: (l) => l.size,
              options: ProxyCardType.values,
              textBuilder: (type) => type.label,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.cardType,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(cardType: value),
              ),
            ),
          ),
          if (isList)
            _HaraOptions<ProxiesIconStyle>(
              ConfigOptionsItem<ProxiesIconStyle>(
                title: (l) => l.iconStyle,
                options: ProxiesIconStyle.values,
                textBuilder: (style) => switch (style) {
                  ProxiesIconStyle.filled => appLocalizations.iconStyleFilled,
                  ProxiesIconStyle.plain => appLocalizations.iconStylePlain,
                  ProxiesIconStyle.hidden => appLocalizations.iconStyleHidden,
                },
                selector: proxiesStyleSettingProvider.select(
                  (state) => state.iconStyle,
                ),
                onChanged: _writer(
                  (state, value) => state.copyWith(iconStyle: value),
                ),
              ),
            ),
        ],
      ),
      _HaraSection(
        title: appLocalizations.filter,
        footer: appLocalizations.hideTimeoutProxiesDesc,
        rows: [
          _HaraToggle(
            ConfigToggleItem(
              title: (l) => l.hideTimeoutProxies,
              selector: proxiesStyleSettingProvider.select(
                (state) => state.hideTimeoutProxies,
              ),
              onChanged: _writer(
                (state, value) => state.copyWith(hideTimeoutProxies: value),
              ),
            ),
          ),
        ],
      ),
    ];
    return Material(
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
