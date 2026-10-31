// The shared Hara row family: the settings and index pages each used to
// carry byte-identical private copies of these rows (the U-series pages
// wrapped their items page-locally by convention). The slimming audit's
// class-B extraction gathers them here, one copy each, verbatim; pages
// keep only the variants that genuinely drifted.

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kfusion/common/common.dart';
import 'package:kfusion/ui/context.dart';
import 'package:kfusion/ui/dialog.dart';
import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/input.dart';
import 'package:kfusion/ui/open_container.dart';
import 'package:kfusion/ui/popup.dart';
import 'package:kfusion/ui/shape.dart';
import 'package:kfusion/ui/sheet.dart';
import 'config_item.dart';
import 'input.dart';
import 'package:material_ui/material_ui.dart';

/// One hairline row of a page: content over a bottom hairline.
class HaraRow extends StatelessWidget {
  const HaraRow({super.key, required this.child, this.onTap});

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

/// A titled section band: an optional title over a hairline, the rows,
/// and an optional footer note. [topGap] adds the group gap above the
/// band; it defaults to false, and the pages that historically opened
/// with the gap pass it explicitly.
class HaraSection extends StatelessWidget {
  const HaraSection({
    super.key,
    this.title,
    required this.rows,
    this.footer,
    this.topGap = false,
  });

  final String? title;
  final List<Widget> rows;
  final String? footer;
  final bool topGap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topGap) const SizedBox(height: HaraSpace.groupGap),
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

/// A row that opens its [target]: pushed as an extended page on wide
/// layouts, an open-container transition on mobile.
class HaraOpenRow extends StatelessWidget {
  const HaraOpenRow({
    super.key,
    required this.label,
    this.subtitle,
    this.leading,
    required this.target,
    this.onChanged,
  });

  final String label;
  final String? subtitle;
  final Widget? leading;
  final Widget target;
  final ValueChanged<dynamic>? onChanged;

  Widget _content(BuildContext context) {
    final palette = context.haraPalette;
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 16)],
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
      return HaraRow(
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
        return HaraRow(onTap: action, child: _content(context));
      },
      onClosed: onChanged,
      openBuilder: (_, _) => target,
    );
  }
}

/// A label/value row that opens an editor on tap.
class HaraInputRow extends StatelessWidget {
  const HaraInputRow({
    super.key,
    required this.label,
    required this.value,
    this.leading,
    required this.onTap,
  });

  final String label;
  final String value;
  final Widget? leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return HaraRow(
      onTap: onTap,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
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
                if (value.isNotEmpty) ...[
                  const SizedBox(height: HaraSpace.profileMetaGap),
                  Text(
                    value,
                    style: HaraText.profileMeta(context, palette.sub),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label row with a popup menu over [options]; a null [onChanged]
/// renders the row inert.
class HaraOptionsRow<T> extends StatelessWidget {
  const HaraOptionsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.leading,
    required this.options,
    required this.value,
    required this.textBuilder,
    required this.onChanged,
  });

  final String label;
  final String? subtitle;
  final Widget? leading;
  final List<T> options;
  final T value;
  final String Function(T value) textBuilder;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final onChanged = this.onChanged;
    PopupOpen? openMenu;
    return HaraRow(
      onTap: onChanged == null ? null : () => openMenu?.call(),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
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

/// The trailing add row of an editable list: a label and an arrow.
class HaraAddRow extends StatelessWidget {
  const HaraAddRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return InkWell(
      customBorder: AppShape.hara,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: HaraSpace.addRowVertical,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: HaraText.addRow(context, palette.sub),
                  ),
                ),
                Text('→', style: HaraText.addRowArrow(context, palette.sub)),
              ],
            ),
          ),
          HaraHairline(color: palette.line),
        ],
      ),
    );
  }
}

/// The input dialog an input row opens, with the same plumbing the list
/// row it replaces used: the floating dialog over the root navigator,
/// the length limit as formatters, and the result handed back as-is.
Future<void> showConfigInputDialog({
  required BuildContext context,
  required String title,
  required String value,
  String? resetValue,
  String? suffixText,
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
      suffixText: suffixText,
      inputFormatters: maxLength == null
          ? null
          : TextInputLimits.limit(maxLength),
      keyboardType: keyboardType,
      validator: validator,
    ),
  );
  onChanged(result);
}

String? normalizeConfigText(ConfigTextItem item, String? value) {
  if (value == null) {
    return null;
  }
  final normalize = item.normalize;
  return normalize == null ? value : normalize(value);
}

/// A toggle row over an existing [ConfigToggleItem]: the item's own
/// selector and writer drive it.
class HaraToggle extends ConsumerWidget {
  const HaraToggle(this.item, {super.key});

  final ConfigToggleItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    return Semantics(
      toggled: value,
      child: HaraRow(
        onTap: () => item.onChanged(ref, !value),
        child: Row(
          children: [
            if (item.leading != null) ...[
              item.leading!,
              const SizedBox(width: 16),
            ],
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

/// A toggle row over a [ConfigToggleItem] another widget assembles:
/// building the source only assembles the item (a selector and a
/// writer), which the Hara row renders instead of its own Material row.
class HaraBoundToggle extends ConsumerWidget {
  const HaraBoundToggle(this.source, {super.key});

  final ConsumerWidget source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HaraToggle(source.build(context, ref) as ConfigToggleItem);
  }
}

/// An options row over an existing [ConfigOptionsItem]: the item's own
/// selector, options and writer drive it.
class HaraOptions<T> extends ConsumerWidget {
  const HaraOptions(this.item, {super.key});

  final ConfigOptionsItem<T> item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    return HaraOptionsRow<T>(
      label: item.title(appLocalizations),
      subtitle: item.subtitle?.call(appLocalizations),
      leading: item.leading,
      options: item.options,
      value: value,
      textBuilder: item.textBuilder,
      onChanged: (value) => item.onChanged(ref, value),
    );
  }
}

/// An input row over an existing [ConfigTextItem]: the item's own
/// selector and writer drive it. (Named for its item: [HaraText] is
/// the typography scale.)
class HaraTextItem extends ConsumerWidget {
  const HaraTextItem(this.item, {super.key});

  final ConfigTextItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    final label = item.title(appLocalizations);
    return HaraInputRow(
      label: label,
      value: value,
      leading: item.leading,
      onTap: () {
        showConfigInputDialog(
          context: context,
          title: label,
          value: value,
          maxLength: item.maxLength,
          keyboardType: item.keyboardType,
          validator: (text) {
            final normalized = normalizeConfigText(item, text);
            if (normalized == null || normalized.isEmpty) {
              return item.allowEmpty ? null : appLocalizations.emptyTip(label);
            }
            return item.validator?.call(normalized, appLocalizations);
          },
          onChanged: (text) {
            final normalized = normalizeConfigText(item, text);
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

/// A list-edit row over an existing [ConfigListEditItem]: opens the
/// list editor and writes the result back through the item.
class HaraListEdit extends ConsumerWidget {
  const HaraListEdit(this.item, {super.key});

  final ConfigListEditItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    final label = item.title(appLocalizations);
    final itemValidator = item.itemValidator;
    return HaraOpenRow(
      label: label,
      subtitle:
          item.subtitle?.call(appLocalizations) ??
          (value.isEmpty
              ? appLocalizations.none
              : appLocalizations.itemsCount(value.length)),
      leading: item.leading,
      target: ListEditView(
        title: label,
        items: value,
        itemMaxLength: item.itemMaxLength,
        itemValidator: itemValidator == null
            ? null
            : (item) => itemValidator(item, appLocalizations),
        titleBuilder: (item) => Text(item),
      ),
      onChanged: (items) {
        final next = List<String>.from(items as List);
        if (!listEquals(next, value)) {
          item.onChanged(ref, next);
        }
      },
    );
  }
}
