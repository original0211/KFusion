import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/features/form/form.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/pages/editor.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef OverrideState<K extends OverrideKey, M> = ({M model, Set<K> keys});

abstract interface class OverrideModel<M> {
  ProviderListenable<T> selectModel<T>(T Function(M model) select);

  ConfigWriter<T> modelWriter<T>(M Function(M model, T value) update);

  bool get emptyCancels;
}

/// Where an override page keeps its model and the keys picked from it.
abstract class OverrideTarget<K extends OverrideKey, M>
    implements OverrideModel<M> {
  const OverrideTarget();

  ConfigLabel get description;

  ConfigLabel get entries;

  ConfigLabel get addEntry;

  ProviderListenable<List<CustomIssue>>? get issues => null;

  ProviderListenable<T> select<T>(T Function(OverrideState<K, M> state) select);

  OverrideState<K, M> read(WidgetRef ref);

  void update(
    WidgetRef ref,
    OverrideState<K, M> Function(OverrideState<K, M> state) update,
  );

  @override
  ProviderListenable<T> selectModel<T>(T Function(M model) select) =>
      this.select((state) => select(state.model));

  @override
  ConfigWriter<T> modelWriter<T>(M Function(M model, T value) update) =>
      (ref, value) => this.update(
        ref,
        (state) => (model: update(state.model, value), keys: state.keys),
      );

  @override
  bool get emptyCancels => true;
}

class PatchOverrideTarget<K extends OverrideKey, M>
    extends OverrideTarget<K, M> {
  const PatchOverrideTarget({
    required this.get,
    required this.set,
    required this.description,
  });

  final OverrideState<K, M> Function(PatchClashConfig config) get;
  final PatchClashConfig Function(
    PatchClashConfig config,
    OverrideState<K, M> state,
  )
  set;

  @override
  final ConfigLabel description;

  @override
  ConfigLabel get entries =>
      (l) => l.overrideEntries;

  @override
  ConfigLabel get addEntry =>
      (l) => l.addOverrideEntry;

  /// An emptied entry overrides the profile's own value with nothing.
  @override
  bool get emptyCancels => false;

  @override
  ProviderListenable<T> select<T>(
    T Function(OverrideState<K, M> state) select,
  ) => patchClashConfigProvider.select((config) => select(get(config)));

  @override
  OverrideState<K, M> read(WidgetRef ref) =>
      get(ref.read(patchClashConfigProvider));

  @override
  void update(
    WidgetRef ref,
    OverrideState<K, M> Function(OverrideState<K, M> state) update,
  ) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((config) => set(config, update(get(config))));
  }
}

abstract class OverrideField<M> {
  const OverrideField();

  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  });

  M reset(M model, M defaults);
}

abstract class ValueOverrideField<M, T> extends OverrideField<M> {
  const ValueOverrideField(this.select, this.update);

  final T Function(M model) select;
  final M Function(M model, T value) update;

  @override
  M reset(M model, M defaults) => update(model, select(defaults));
}

class ToggleOverrideField<M> extends ValueOverrideField<M, bool> {
  const ToggleOverrideField(super.select, super.update);

  @override
  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  }) {
    return _HaraToggle(
      ConfigToggleItem(
        leading: leading,
        title: title,
        selector: model.selectModel(select),
        onChanged: model.modelWriter(update),
      ),
    );
  }
}

class OptionsOverrideField<M, T extends Object>
    extends ValueOverrideField<M, T> {
  const OptionsOverrideField(
    this.options,
    super.select,
    super.update, {
    this.labelOf = _nameOf,
  });

  final List<T> options;
  final String Function(T value) labelOf;

  static String _nameOf(Object value) => value is Enum ? value.name : '$value';

  @override
  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  }) {
    return _HaraOptions(
      ConfigOptionsItem<T>(
        leading: leading,
        title: title,
        options: options,
        textBuilder: labelOf,
        selector: model.selectModel(select),
        onChanged: model.modelWriter(update),
      ),
    );
  }
}

class NumberOverrideField<M> extends ValueOverrideField<M, int> {
  const NumberOverrideField(
    super.select,
    super.update, {
    this.min = 0,
    this.max = 0x7fffffff,
    this.maxLength = TextInputLimits.number,
  });

  final int min;
  final int max;
  final int maxLength;

  String? _validate(String? value, ConfigLabel title) {
    final label = title(currentAppLocalizations);
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null) {
      return currentAppLocalizations.numberTip(label);
    }
    return number < min || number > max
        ? currentAppLocalizations.numberRangeTip(label, '$min', '$max')
        : null;
  }

  @override
  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  }) {
    return _HaraText(
      ConfigTextItem(
        leading: leading,
        title: title,
        selector: model.selectModel((model) => '${select(model)}'),
        onChanged: model.modelWriter<String>(
          (model, value) => update(model, int.parse(value)),
        ),
        maxLength: maxLength,
        keyboardType: TextInputType.number,
        normalize: (value) => value.trim(),
        validator: (value, _) => _validate(value, title),
        allowEmpty: model.emptyCancels,
      ),
    );
  }
}

class TextOverrideField<M> extends ValueOverrideField<M, String> {
  const TextOverrideField(
    super.select,
    super.update, {
    required this.maxLength,
    this.validator,
  });

  final int maxLength;
  final ConfigValidator? validator;

  @override
  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  }) {
    return _HaraText(
      ConfigTextItem(
        leading: leading,
        title: title,
        selector: model.selectModel(select),
        onChanged: model.modelWriter(update),
        maxLength: maxLength,
        normalize: (value) => value.trim(),
        validator: validator,
        allowEmpty: true,
      ),
    );
  }
}

class ListOverrideField<M> extends ValueOverrideField<M, List<String>> {
  const ListOverrideField(
    super.select,
    super.update, {
    required this.itemMaxLength,
    this.itemValidator,
  });

  final int itemMaxLength;
  final ConfigValidator? itemValidator;

  @override
  Widget build(
    OverrideModel<M> model, {
    required ConfigLabel title,
    required Widget leading,
  }) {
    return _HaraListEdit(
      ConfigListEditItem(
        leading: leading,
        title: title,
        selector: model.selectModel(select),
        onChanged: model.modelWriter(update),
        itemMaxLength: itemMaxLength,
        itemValidator: itemValidator,
      ),
    );
  }
}

abstract class OverrideSpec<K extends OverrideKey, M> {
  const OverrideSpec();

  OverrideTarget<K, M> get target;

  String title(AppLocalizations l);

  List<K> get values;

  NullStatusIllustration get illustration;

  /// What a newly added key starts from.
  M get defaults;

  String sectionOf(K key, AppLocalizations l) => l.options;

  String label(K key, AppLocalizations l);

  ConfigLabel? description(K key);

  OverrideField<M> fieldOf(K key);

  /// Also resets the values of [keys], so a profile with no keys is untouched.
  OverrideState<K, M> withoutKeys(OverrideState<K, M> state, Set<K> keys) {
    var model = state.model;
    for (final key in keys) {
      model = fieldOf(key).reset(model, defaults);
    }
    return (model: model, keys: state.keys.difference(keys));
  }

  String? footerOf(Iterable<K> keys, AppLocalizations l) {
    final lines = [for (final key in keys) ?description(key)?.call(l)];
    return lines.isEmpty ? null : lines.join('\n');
  }

  List<(String, List<K>)> sectionsOf(AppLocalizations l, Iterable<K> keys) {
    final sections = <String, List<K>>{};
    for (final key in keys) {
      sections.putIfAbsent(sectionOf(key, l), () => []).add(key);
    }
    return [
      for (final MapEntry(:key, :value) in sections.entries) (key, value),
    ];
  }
}

mixin OverrideQuickEdit<K extends OverrideKey, M> on OverrideSpec<K, M> {
  String overrideYaml(M model, Set<K> keys);

  /// Throws when [content] names a key outside [values] or a value the model
  /// cannot hold.
  OverrideState<K, M> applyOverrideYaml(M model, String content);

  EditorSchema get schema;
}

void showOverrideAddSheet<K extends OverrideKey, M>(
  BuildContext context,
  WidgetRef ref,
  OverrideSpec<K, M> spec,
) {
  final appLocalizations = context.appLocalizations;
  final added = spec.target.read(ref).keys;
  final remaining = spec.values.where((key) => !added.contains(key));
  showSheet<void>(
    context: context,
    builder: (_) => SelectionSheet<K>(
      title: spec.target.addEntry(appLocalizations),
      sections: [
        for (final (label, keys) in spec.sectionsOf(
          appLocalizations,
          remaining,
        ))
          SelectionSection(
            label: label,
            items: keys,
            subtitleBuilder: (context, key) =>
                spec.description(key)?.call(context.appLocalizations),
          ),
      ],
      labelBuilder: (key) => spec.label(key, appLocalizations),
      selectedOf: (_) => null,
      removeOnSelect: true,
      onSelected: (key) {
        if (!context.mounted) {
          return;
        }
        spec.target.update(
          ref,
          (state) => (
            model: spec.fieldOf(key).reset(state.model, spec.defaults),
            keys: {...state.keys, key},
          ),
        );
      },
    ),
  );
}

class OverrideView<K extends OverrideKey, M> extends ConsumerWidget {
  const OverrideView({super.key, required this.spec});

  final OverrideSpec<K, M> spec;

  void _handleAdd(BuildContext context, WidgetRef ref) =>
      showOverrideAddSheet(context, ref, spec);

  Future<void> _handleQuickEdit(
    BuildContext context,
    WidgetRef ref,
    OverrideQuickEdit<K, M> quickEdit,
  ) {
    final state = spec.target.read(ref);
    final raw = quickEdit.overrideYaml(state.model, state.keys);
    final page = EditorPage(
      title: spec.title(context.appLocalizations),
      content: raw,
      schema: quickEdit.schema,
      readOnly: false,
      onPop: (_, _, content) =>
          _handleQuickEditPop(ref, quickEdit, content, raw),
    );
    return sheetNavigatorOf(context).push(
      context.isMobileView
          ? CommonRoute(builder: (_) => page)
          : CommonDesktopRoute(builder: (_) => page),
    );
  }

  Future<bool> _handleQuickEditPop(
    WidgetRef ref,
    OverrideQuickEdit<K, M> quickEdit,
    String content,
    String raw,
  ) async {
    if (content == raw) {
      return true;
    }
    try {
      spec.target.update(ref, (state) {
        final listed = quickEdit.applyOverrideYaml(state.model, raw).keys;
        final next = readRelaxed(
          content,
          quickEdit.schema,
          (content) => quickEdit.applyOverrideYaml(state.model, content),
        );
        final stillSet = quickEdit
            .applyOverrideYaml(
              next.model,
              quickEdit.overrideYaml(next.model, next.keys),
            )
            .keys;
        return spec.withoutKeys((
          model: next.model,
          keys: {...next.keys, ...state.keys.difference(listed)},
        ), listed.difference(stillSet));
      });
      return true;
    } catch (error) {
      final res = await dialogs.showMessage(
        message: TextSpan(
          text:
              '${compactError(error)}\n\n'
              '${currentAppLocalizations.discardChanges}',
        ),
        destructive: true,
      );
      return res == true;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final spec = this.spec;
    final target = spec.target;
    final (:isEmpty, :canAdd) = ref.watch(
      target.select(
        (state) => (
          isEmpty: !spec.values.any(state.keys.contains),
          canAdd: spec.values.any((key) => !state.keys.contains(key)),
        ),
      ),
    );
    final addEntry = target.addEntry(appLocalizations);
    return CommonScaffold(
      title: spec.title(appLocalizations),
      iconActions: [
        if (!isEmpty)
          IconButtonData(
            glyph: AppGlyphs.addCircle,
            onPressed: canAdd ? () => _handleAdd(context, ref) : null,
            tooltip: addEntry,
          ),
        if (spec is OverrideQuickEdit<K, M>)
          IconButtonData(
            glyph: AppGlyphs.compose,
            onPressed: () => _handleQuickEdit(context, ref, spec),
            tooltip: appLocalizations.quickEdit,
          ),
      ],
      body: Material(
        color: palette.bg,
        child: NullStatusSwitcher(
          isEmpty: isEmpty,
          nullStatus: NullStatus(
            label: appLocalizations.nullTip(target.entries(appLocalizations)),
            description: target.description(appLocalizations),
            illustration: spec.illustration,
            action: TonalButton(
              size: TonalButtonSize.bar,
              glyph: AppGlyphs.addCircle,
              label: addEntry,
              onPressed: () => _handleAdd(context, ref),
            ),
          ),
          child: _OverrideList(spec: spec),
        ),
      ),
    );
  }
}

class _OverrideList<K extends OverrideKey, M> extends ConsumerWidget {
  const _OverrideList({required this.spec});

  final OverrideSpec<K, M> spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final keys = ref.watch(spec.target.select((state) => state.keys));
    final entries = spec.values.where(keys.contains);
    final sections = spec.sectionsOf(appLocalizations, entries);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = max(
          HaraSpace.pageInset,
          (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(side, context.appBarInset, side, 48),
          children: [
            if (spec.target.issues case final issues?)
              CustomIssuesBanner(issues: ref.watch(issues)),
            AnimatedEntries(
              children: [
                for (var i = 0; i < sections.length; i++)
                  KeyedSubtree(
                    key: ValueKey(sections[i].$1),
                    child: _HaraAnimatedSection(
                      title: sections[i].$1,
                      footer: spec.footerOf(sections[i].$2, appLocalizations),
                      topGap: i > 0,
                      children: [
                        for (final key in sections[i].$2)
                          OverrideEntry(
                            key: ValueKey(key),
                            spec: spec,
                            overrideKey: key,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: HaraSpace.groupGap),
            Text(
              spec.target.description(appLocalizations),
              style: HaraText.profileMeta(context, palette.dim),
            ),
          ],
        );
      },
    );
  }
}

/// A picked key's row, led by the button that takes it off the list.
class OverrideEntry<K extends OverrideKey, M> extends StatelessWidget {
  const OverrideEntry({
    super.key,
    required this.spec,
    required this.overrideKey,
  });

  final OverrideSpec<K, M> spec;
  final K overrideKey;

  @override
  Widget build(BuildContext context) {
    final field = spec.fieldOf(overrideKey);
    return field.build(
      field is ValueOverrideField && spec.target.emptyCancels
          ? _ListedValue(spec, overrideKey)
          : spec.target,
      title: (l) => spec.label(overrideKey, l),
      leading: _RemoveButton(spec: spec, overrideKey: overrideKey),
    );
  }
}

/// A key's own value; emptying it takes the key off the list.
class _ListedValue<K extends OverrideKey, M> implements OverrideModel<M> {
  const _ListedValue(this.spec, this.overrideKey);

  final OverrideSpec<K, M> spec;
  final K overrideKey;

  OverrideTarget<K, M> get target => spec.target;

  @override
  bool get emptyCancels => true;

  static bool _isEmpty(Object? value) => switch (value) {
    String() => value.isEmpty,
    Iterable() => value.isEmpty,
    Map() => value.isEmpty,
    _ => false,
  };

  @override
  ProviderListenable<T> selectModel<T>(T Function(M model) select) =>
      target.selectModel(select);

  @override
  ConfigWriter<T> modelWriter<T>(M Function(M model, T value) update) =>
      (ref, value) => target.update(
        ref,
        (state) => _isEmpty(value)
            ? spec.withoutKeys(state, {overrideKey})
            : (model: update(state.model, value), keys: state.keys),
      );
}

class _RemoveButton<K extends OverrideKey, M> extends ConsumerWidget {
  const _RemoveButton({required this.spec, required this.overrideKey});

  final OverrideSpec<K, M> spec;
  final K overrideKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EntryButton.remove(
      onPressed: () => spec.target.update(
        ref,
        (state) => spec.withoutKeys(state, {overrideKey}),
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

/// A section of the entries list: a dim title, a hairline, its rows
/// carried by the same entry transitions the section it replaces used,
/// and the section's footer note.
class _HaraAnimatedSection extends StatelessWidget {
  const _HaraAnimatedSection({
    this.title,
    required this.children,
    this.footer,
    this.topGap = false,
  });

  final String? title;
  final List<Widget> children;
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
        AnimatedEntries(grouped: true, children: children),
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

/// An options row: the row tap opens the menu out of its end value, as
/// the options row it replaces did.
class _HaraOptionsRow<T> extends StatelessWidget {
  const _HaraOptionsRow({
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
    return _HaraRow(
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
      subtitle: item.subtitle?.call(appLocalizations),
      leading: item.leading,
      options: item.options,
      value: value,
      textBuilder: item.textBuilder,
      onChanged: (value) => item.onChanged(ref, value),
    );
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
    return _HaraRow(
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
      leading: item.leading,
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

/// A list-edit row over an existing [ConfigListEditItem]: the item's own
/// selector and writer drive it; the summary under the label counts its
/// items the way its own row did.
class _HaraListEdit extends ConsumerWidget {
  const _HaraListEdit(this.item);

  final ConfigListEditItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final value = ref.watch(item.selector);
    final label = item.title(appLocalizations);
    final itemValidator = item.itemValidator;
    return _HaraOpenRow(
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
