import 'dart:math' as math;

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/l10n/l10n.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

List<(String, List<HotAction>)> _sections(AppLocalizations appLocalizations) {
  return [
    (
      appLocalizations.general,
      const [HotAction.view, HotAction.start, HotAction.exit],
    ),
    (
      appLocalizations.outboundMode,
      const [
        HotAction.mode,
        HotAction.ruleMode,
        HotAction.globalMode,
        HotAction.directMode,
      ],
    ),
    (
      appLocalizations.network,
      const [HotAction.proxy, HotAction.tun, HotAction.copyEnv],
    ),
    (
      appLocalizations.proxies,
      const [HotAction.delayTest, HotAction.updateProfiles],
    ),
  ];
}

bool _sameCombination(HotKeyAction a, HotKeyAction b) {
  return a.key != null &&
      a.key == b.key &&
      keyboardModifierListEquality.equals(a.modifiers, b.modifiers);
}

HotKeyAction? _conflictOf(List<HotKeyAction> actions, HotKeyAction binding) {
  for (final item in actions) {
    if (item.action != binding.action && _sameCombination(item, binding)) {
      return item;
    }
  }
  return null;
}

/// Stores [binding] for its action, or clears the action when it has no key.
/// Another action holding the same combination loses it.
List<HotKeyAction> _withBinding(
  List<HotKeyAction> actions,
  HotKeyAction binding,
) {
  final isBound = binding.key != null;
  var isPlaced = false;
  final result = <HotKeyAction>[];
  for (final item in actions) {
    if (item.action == binding.action) {
      isPlaced = true;
      if (isBound) {
        result.add(binding);
      }
    } else if (!(isBound && _sameCombination(item, binding))) {
      result.add(item);
    }
  }
  if (isBound && !isPlaced) {
    result.add(binding);
  }
  return result;
}

void _saveBinding(WidgetRef ref, HotKeyAction binding) {
  final notifier = ref.read(hotKeyActionsProvider.notifier);
  notifier.value = _withBinding(notifier.value, binding);
}

class HotKeyView extends StatelessWidget {
  const HotKeyView({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final labels = ShortcutLabels.host();
    return BaseScaffold(
      title: appLocalizations.hotkeyManagement,
      body: Material(
        color: palette.bg,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.max(
              HaraSpace.pageInset,
              (constraints.maxWidth - HaraSpace.contentMaxWidth) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(
                side,
                context.contentTopPadding,
                side,
                48,
              ),
              children: [
                const _HotKeyIntro(),
                for (final (title, actions) in _sections(appLocalizations)) ...[
                  const SizedBox(height: HaraSpace.groupGap),
                  _section(
                    context,
                    title,
                    rows: [
                      for (final action in actions)
                        _HotKeyItem(action: action, labels: labels),
                    ],
                  ),
                ],
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

class _HotKeyIntro extends StatelessWidget {
  const _HotKeyIntro();

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        GlyphIcon(AppGlyphs.keyboard, color: palette.sub),
        Expanded(
          child: Text(
            context.appLocalizations.hotkeyDesc,
            style: HaraText.profileMeta(context, palette.sub),
          ),
        ),
      ],
    );
  }
}

class _HotKeyItem extends ConsumerWidget {
  const _HotKeyItem({required this.action, required this.labels});

  final HotAction action;
  final ShortcutLabels labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final hotKeyAction = ref.watch(getHotKeyActionProvider(action));
    final failure = ref.watch(
      hotKeyFailuresProvider.select((state) => state[action]),
    );
    final key = hotKeyAction.key;
    return _HaraRow(
      onTap: () {
        dialogs.showCommonDialog(
          child: HotKeyRecorder(hotKeyAction: hotKeyAction, labels: labels),
        );
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: HaraText.nodeName(
                    context,
                    palette.ink,
                    current: false,
                  ),
                ),
                if (failure != null) ...[
                  const SizedBox(height: HaraSpace.profileMetaGap),
                  Tooltip(
                    message: failure,
                    child: Text(
                      appLocalizations.hotkeyUnavailable,
                      style: HaraText.profileMeta(
                        context,
                        context.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (key == null)
            Text(
              appLocalizations.hotkeyNotSet,
              style: HaraText.statusNode(context, palette.dim),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                _KeyCaps(
                  parts: labels.parts(hotKeyAction.modifiers, key),
                  isError: failure != null,
                ),
                IconButton(
                  tooltip: appLocalizations.remove,
                  onPressed: () {
                    _saveBinding(ref, HotKeyAction(action: action));
                  },
                  icon: GlyphIcon(
                    AppGlyphs.close,
                    size: 20,
                    color: palette.sub,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _KeyCaps extends StatelessWidget {
  const _KeyCaps({
    required this.parts,
    this.isLarge = false,
    this.isError = false,
  });

  final List<String> parts;
  final bool isLarge;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: isLarge ? 8 : 4,
      runSpacing: isLarge ? 8 : 4,
      alignment: WrapAlignment.center,
      children: [
        for (final part in parts)
          _KeyCap(label: part, isLarge: isLarge, isError: isError),
      ],
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.label,
    this.isLarge = false,
    this.isError = false,
    this.isPlaceholder = false,
  });

  final String label;
  final bool isLarge;
  final bool isError;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final colorScheme = context.colorScheme;
    final side = isLarge ? 44.0 : 26.0;
    final foregroundColor = isError
        ? colorScheme.onErrorContainer
        : isPlaceholder
        ? palette.dim
        : palette.sub;
    final textStyle = isLarge
        ? HaraText.profileName(
            context,
            foregroundColor,
            current: false,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()])
        : HaraText.payload(context, foregroundColor);
    return Container(
      constraints: BoxConstraints(minWidth: side, minHeight: side),
      padding: EdgeInsets.symmetric(horizontal: isLarge ? 12 : 7),
      decoration: ShapeDecoration(
        color: isError ? colorScheme.errorContainer : HaraPalette.transparent,
        shape: AppShape.hara.copyWith(
          side: isError || isPlaceholder
              ? BorderSide.none
              : BorderSide(color: palette.line, width: HaraSpace.hairline),
        ),
      ),
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(label, style: textStyle),
      ),
    );
  }
}

class HotKeyRecorder extends ConsumerStatefulWidget {
  const HotKeyRecorder({
    super.key,
    required this.hotKeyAction,
    required this.labels,
  });

  final HotKeyAction hotKeyAction;
  final ShortcutLabels labels;

  @override
  ConsumerState<HotKeyRecorder> createState() => _HotKeyRecorderState();
}

class _HotKeyRecorderState extends ConsumerState<HotKeyRecorder> {
  late final HotKeyRecording _recording;
  Set<KeyboardModifier> _modifiers = const {};
  int? _key;

  HotKeyAction get _draft =>
      widget.hotKeyAction.copyWith(modifiers: _modifiers, key: _key);

  @override
  void initState() {
    super.initState();
    _recording = ref.read(hotKeyRecordingProvider.notifier);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recording.value = true;
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    final recording = _recording;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      recording.value = false;
    });
    super.dispose();
  }

  Set<KeyboardModifier> _heldModifiers({PhysicalKeyboardKey? except}) {
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    return {
      for (final modifier in KeyboardModifier.values)
        if (modifier.physicalKeys.any(pressed.contains) &&
            !modifier.physicalKeys.contains(except))
          modifier,
    };
  }

  bool _handleKeyEvent(KeyEvent event) {
    final physicalKey = event.physicalKey;
    if (isModifierKey(physicalKey)) {
      if (event is KeyDownEvent || (event is KeyUpEvent && _key == null)) {
        setState(() {
          _key = null;
          _modifiers = _heldModifiers();
        });
      }
      return false;
    }
    if (event is KeyUpEvent) {
      return false;
    }
    final modifiers = _heldModifiers(except: physicalKey);
    if (physicalKey == PhysicalKeyboardKey.escape && modifiers.isEmpty) {
      Navigator.of(context).pop();
      return false;
    }
    setState(() {
      _modifiers = modifiers;
      _key = physicalKey.usbHidUsage;
    });
    return false;
  }

  void _handleSave() {
    Navigator.of(context).pop();
    _saveBinding(ref, _draft);
  }

  void _handleRemove() {
    Navigator.of(context).pop();
    _saveBinding(ref, HotKeyAction(action: widget.hotKeyAction.action));
  }

  Widget _buildCapture(BuildContext context, {required bool isError}) {
    final colorScheme = context.colorScheme;
    final key = _key;
    final Widget content;
    if (key != null) {
      content = _KeyCaps(
        parts: widget.labels.parts(_modifiers, key),
        isLarge: true,
        isError: isError,
      );
    } else if (_modifiers.isNotEmpty) {
      content = Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final part in widget.labels.modifierParts(_modifiers))
            _KeyCap(label: part, isLarge: true),
          const _KeyCap(label: '…', isLarge: true, isPlaceholder: true),
        ],
      );
    } else {
      content = Text(
        context.appLocalizations.pressKeyboard,
        textAlign: TextAlign.center,
        style: HaraText.nodeName(
          context,
          context.haraPalette.sub,
          current: false,
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: AppShape.hara.copyWith(
          side: BorderSide(
            color: isError ? colorScheme.error : context.haraPalette.ink,
            width: 1.2,
          ),
        ),
      ),
      child: content,
    );
  }

  Widget? _buildStatus(
    BuildContext context, {
    required bool isInvalid,
    required HotKeyAction? conflict,
  }) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final (text, color) = switch ((isInvalid, conflict)) {
      (true, _) => (
        appLocalizations.hotkeyNeedsModifier(
          widget.labels
              .modifierParts(primaryHotKeyModifiers)
              .join(widget.labels.isMacOS ? ' ' : ', '),
        ),
        colorScheme.error,
      ),
      (false, final HotKeyAction conflict) => (
        appLocalizations.hotkeyConflictWith(conflict.action.label),
        colorScheme.warning,
      ),
      _ => (null, null),
    };
    if (text == null) {
      return null;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(text, style: HaraText.profileMeta(context, color!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final draft = _draft;
    final isComplete = draft.key != null;
    final isValid = isValidHotKey(draft.modifiers, draft.key);
    final isInvalid = isComplete && !isValid;
    final conflict = isValid
        ? _conflictOf(ref.watch(hotKeyActionsProvider), draft)
        : null;
    final status = _buildStatus(
      context,
      isInvalid: isInvalid,
      conflict: conflict,
    );
    return Focus(
      onKeyEvent: (_, _) {
        return KeyEventResult.handled;
      },
      autofocus: true,
      child: CommonDialog(
        title: widget.hotKeyAction.action.label,
        hasFields: true,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(appLocalizations.cancel),
          ),
          if (widget.hotKeyAction.key != null)
            TextButton(
              onPressed: _handleRemove,
              style: ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(
                  context.colorScheme.destructive,
                ),
              ),
              child: Text(appLocalizations.remove),
            ),
          TextButton(
            onPressed: isValid ? _handleSave : null,
            child: Text(appLocalizations.save),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCapture(context, isError: isInvalid),
            AnimatedSize(
              duration: commonDuration,
              alignment: Alignment.topCenter,
              child: status ?? const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
