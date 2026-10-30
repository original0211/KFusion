import 'dart:math';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/providers/action.dart';
import 'package:kfusion/providers/config.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  List<Widget> _getDeveloperRows(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    return [
      _HaraRow(
        onTap: () async {
          final storeAction = ref.read(storeActionProvider.notifier);
          final res = await dialogs.showMessage(
            message: TextSpan(text: appLocalizations.confirmClearAllData),
            destructive: true,
            confirmText: appLocalizations.clearData,
          );
          if (res != true) {
            return;
          }
          await storeAction.handleClear();
        },
        child: Text(
          appLocalizations.clearData,
          style: HaraText.nodeName(
            context,
            context.haraPalette.ink,
            current: false,
          ),
        ),
      ),
      _HaraRow(
        onTap: () async {
          await ref.read(storeActionProvider.notifier).shakingStore();
        },
        child: Text(
          appLocalizations.pruneCache,
          style: HaraText.nodeName(
            context,
            context.haraPalette.ink,
            current: false,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context, ref) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    final enable = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return BaseScaffold(
      title: appLocalizations.developerMode,
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
                HaraHairline(color: palette.line),
                _HaraToggleRow(
                  label: appLocalizations.developerMode,
                  value: enable,
                  onTap: () {
                    ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(developerMode: !enable),
                        );
                  },
                ),
                const SizedBox(height: HaraSpace.groupGap),
                _HaraSection(
                  title: appLocalizations.options,
                  rows: _getDeveloperRows(context, ref),
                ),
              ],
            );
          },
        ),
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

/// A section of the page: a dim title, a hairline, and its rows.
class _HaraSection extends StatelessWidget {
  const _HaraSection({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: HaraText.sectionTitle(context, palette.dim)),
        const SizedBox(height: HaraSpace.sectionTitleGap),
        HaraHairline(color: palette.line),
        ...rows,
      ],
    );
  }
}

/// A toggle row: the row tap flips the value, the state reads as the
/// shared toggle mark at the row's end.
class _HaraToggleRow extends StatelessWidget {
  const _HaraToggleRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final appLocalizations = context.appLocalizations;
    return Semantics(
      toggled: value,
      child: _HaraRow(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
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
