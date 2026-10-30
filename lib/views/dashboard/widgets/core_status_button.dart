import 'dart:async';

import 'package:kfusion/common/common.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/providers/providers.dart';
import 'package:kfusion/state.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/ui.dart';
import 'package:kfusion/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoreStatusButton extends ConsumerStatefulWidget {
  const CoreStatusButton({super.key});

  @override
  ConsumerState<CoreStatusButton> createState() => _CoreStatusButtonState();
}

class _CoreStatusButtonState extends ConsumerState<CoreStatusButton> {
  static const _holdDuration = Duration(milliseconds: 600);

  Timer? _holdTimer;
  CoreStatus _status = CoreStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _status = ref.read(coreStatusProvider);
    ref.listenManual(coreStatusProvider, (_, next) {
      _onStatusChanged(next);
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onStatusChanged(CoreStatus next) {
    setState(() {
      _status = next;
      switch (next) {
        case CoreStatus.connecting:
          _holdTimer ??= Timer(_holdDuration, () {
            if (mounted) {
              setState(() {
                _holdTimer = null;
              });
            }
          });
          break;
        case CoreStatus.disconnected:
          _holdTimer?.cancel();
          _holdTimer = null;
          break;
        case CoreStatus.connected:
          break;
      }
    });
  }

  Future<void> _handleConnection() async {
    if (_holdTimer != null) {
      return;
    }
    final coreStatus = ref.read(coreStatusProvider);
    if (coreStatus == CoreStatus.connecting) {
      return;
    }
    final tip = coreStatus == CoreStatus.connected
        ? context.appLocalizations.forceRestartCoreTip
        : context.appLocalizations.restartCoreTip;
    final res = await dialogs.showMessage(message: TextSpan(text: tip));
    if (res != true || !mounted) {
      return;
    }
    try {
      await ref.read(coreActionProvider.notifier).restartCore();
    } catch (error) {
      dialogs.showNotifier(error.toString(), level: MessageLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coreStatus = _holdTimer != null ? CoreStatus.connecting : _status;
    final appLocalizations = context.appLocalizations;
    final palette = context.haraPalette;
    final hairline = BorderSide(color: palette.line, width: HaraSpace.hairline);
    return Tooltip(
      message: appLocalizations.coreStatus,
      child: FadeScaleBox(
        alignment: Alignment.centerRight,
        child: coreStatus == CoreStatus.connected
            ? IconButton.filled(
                style: ElasticPress.buttonStyle.merge(
                  IconButton.styleFrom(
                    backgroundColor: HaraPalette.transparent,
                    foregroundColor: palette.ink,
                    side: hairline,
                  ),
                ),
                onPressed: _handleConnection,
                icon: const GlyphIcon(AppGlyphs.check, fill: 1),
              )
            : FilledButton.icon(
                key: ValueKey(coreStatus),
                onPressed: _handleConnection,
                style: ElasticPress.buttonStyle.merge(
                  FilledButton.styleFrom(
                    backgroundColor: HaraPalette.transparent,
                    foregroundColor: coreStatus == CoreStatus.disconnected
                        ? palette.sub
                        : palette.ink,
                    side: hairline,
                  ),
                ),
                icon: SizedBox(
                  height: globalState.measure.textHeight(
                    AppTextStyle.subheadline,
                  ),
                  width: globalState.measure.textHeight(
                    AppTextStyle.subheadline,
                  ),
                  child: switch (coreStatus) {
                    CoreStatus.connecting => CommonCircleLoading(
                      color: palette.ink,
                    ),
                    CoreStatus.connected => const GlyphIcon(
                      AppGlyphs.check,
                      fill: 1,
                    ),
                    CoreStatus.disconnected => const GlyphIcon(
                      AppGlyphs.refresh,
                      fill: 1,
                    ),
                  },
                ),
                label: Text(switch (coreStatus) {
                  CoreStatus.connecting => appLocalizations.connecting,
                  CoreStatus.connected => appLocalizations.connected,
                  CoreStatus.disconnected => appLocalizations.disconnected,
                }),
              ),
      ),
    );
  }
}
