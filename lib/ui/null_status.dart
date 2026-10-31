import 'dart:async';

import 'package:kfusion/ui/context.dart';
import 'package:kfusion/ui/disc_motif.dart';
import 'package:kfusion/ui/fade_box.dart';
import 'package:kfusion/ui/hara.dart';
import 'package:kfusion/ui/icons/icons.dart';
import 'package:kfusion/ui/inherited.dart';
import 'package:kfusion/ui/l10n.dart';
import 'package:kfusion/ui/metrics.dart';
import 'package:kfusion/ui/navigator.dart';
import 'package:kfusion/ui/typography.dart';
import 'package:material_ui/material_ui.dart';

enum NullStatusIllustration {
  data,
  logs,
  dns,
  tun,
  wifi,
  apps,
  permission,
  camera,
  error,
  search,
}

class NullStatusSwitcher extends StatefulWidget {
  /// Only the first load is held back; later loads keep what is on screen.
  final bool isLoading;
  final bool isEmpty;
  final bool isSearching;

  /// Shown in place of a first load still running after a route transition.
  final NullStatus? loadingStatus;
  final NullStatus? nullStatus;
  final Widget child;

  const NullStatusSwitcher({
    super.key,
    this.isLoading = false,
    this.isEmpty = false,
    this.isSearching = false,
    this.loadingStatus,
    this.nullStatus,
    required this.child,
  }) : assert(!isEmpty || nullStatus != null);

  @override
  State<NullStatusSwitcher> createState() => _NullStatusSwitcherState();
}

class _NullStatusSwitcherState extends State<NullStatusSwitcher> {
  static const _exitDuration = Duration(milliseconds: 150);
  static const _loadingStatusDelay = Duration(milliseconds: 400);

  late bool _loaded = !widget.isLoading;
  Timer? _loadingStatusTimer;
  var _showsLoadingStatus = false;

  @override
  void initState() {
    super.initState();
    if (!_loaded && widget.loadingStatus != null) {
      _loadingStatusTimer = Timer(
        _loadingStatusDelay,
        () => setState(() => _showsLoadingStatus = true),
      );
    }
  }

  @override
  void didUpdateWidget(covariant NullStatusSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loaded = _loaded || !widget.isLoading;
    if (_loaded) {
      _loadingStatusTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _loadingStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_showsLoadingStatus) {
      return const SizedBox.expand();
    }
    final slot = switch ((widget.isEmpty, widget.isSearching)) {
      _ when !_loaded => _NullStatusSlot.loading,
      (true, true) => _NullStatusSlot.noResults,
      (true, false) => _NullStatusSlot.empty,
      (false, _) => _NullStatusSlot.content,
    };
    return AnimatedSwitcher(
      duration: context.motionDuration(commonDuration),
      reverseDuration: context.motionDuration(_exitDuration),
      switchInCurve: Easing.emphasizedDecelerate,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Align(
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: <Widget>[...previousChildren, ?currentChild],
        ),
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: animation.drive(Tween(begin: 0.92, end: 1.0)),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(slot),
        child: switch (slot) {
          _NullStatusSlot.loading => widget.loadingStatus!,
          _NullStatusSlot.noResults => NullStatus(
            label: UiLocalizations.of(context).noSearchResults,
            illustration: NullStatusIllustration.search,
          ),
          _NullStatusSlot.empty => widget.nullStatus!,
          _NullStatusSlot.content => widget.child,
        },
      ),
    );
  }
}

enum _NullStatusSlot { loading, empty, noResults, content }

class NullStatus extends StatefulWidget {
  final String? label;
  final String? description;
  final Widget? action;
  final NullStatusIllustration illustration;
  final bool brandMark;

  const NullStatus({
    super.key,
    this.label,
    this.description,
    this.action,
    this.illustration = NullStatusIllustration.data,
  }) : brandMark = false;

  /// The brand variant, for a surface with nothing to enumerate yet: the disc mark stands where an illustration would, in the variant tone.
  const NullStatus.brand({super.key, this.label, this.description, this.action})
    : illustration = NullStatusIllustration.data,
      brandMark = true;

  @override
  State<NullStatus> createState() => _NullStatusState();
}

class _NullStatusState extends State<NullStatus> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = sheetScrollController(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NullStatus(:label, :description, :action, :illustration, :brandMark) =
        widget;
    final colorScheme = context.colorScheme;
    final compact = MediaQuery.sizeOf(context).height < _compactHeight;
    return Align(
      alignment: const Alignment(0.0, -0.2),
      child: SingleChildScrollView(
        controller: _controller,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnterItem(
                child: brandMark
                    ? DashboardDiscMotif(
                        size: compact ? 96 : 128,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : EmptyIllustration(
                        type: illustration,
                        dimension: compact ? 120 : 160,
                      ),
              ),
              if (label != null) ...[
                SizedBox(height: compact ? 12 : 16),
                _EnterItem(
                  delay: _staggerStep,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.headline
                        .of(context)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
              if (description != null) ...[
                const SizedBox(height: 8),
                _EnterItem(
                  delay: _staggerStep * 2,
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 24),
                _EnterItem(
                  delay: _staggerStep * (description != null ? 3 : 2),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(visualDensity: VisualDensity.standard),
                    child: action,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _compactHeight = 560.0;
const _staggerStep = Duration(milliseconds: 60);
const _enterRise = 12.0;

bool _skipsEntrance(BuildContext context) =>
    context.disableAnimations || isRouteArriving(context);

class _EnterItem extends StatefulWidget {
  final Duration delay;
  final Widget child;

  const _EnterItem({this.delay = Duration.zero, required this.child});

  @override
  State<_EnterItem> createState() => _EnterItemState();
}

class _EnterItemState extends State<_EnterItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool? _skipped;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: commonDuration + widget.delay,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipped != null) {
      return;
    }
    _skipped = _skipsEntrance(context);
    if (!_skipped!) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skipped = _skipped;
    if (skipped == null || skipped) {
      return widget.child;
    }
    final total = commonDuration + widget.delay;
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    final animation = start == 0
        ? _controller.view
        : _controller.drive(CurveTween(curve: Interval(start, 1)));
    return FadeSlideEnterTransition(
      animation: animation,
      distance: _enterRise,
      axis: Axis.vertical,
      child: widget.child,
    );
  }
}

/// The empty-state schematic: one line-drawn glyph inside a hairline
/// frame, read in the Hara ink steps. The glyph alone carries which
/// member this is; there is no fill, gradient or entrance motion.
class EmptyIllustration extends StatelessWidget {
  final NullStatusIllustration type;
  final double dimension;

  const EmptyIllustration({
    super.key,
    required this.type,
    required this.dimension,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.haraPalette;
    final error = type == NullStatusIllustration.error;
    final errorColor = context.colorScheme.error;
    return CustomPaint(
      key: ValueKey(type),
      painter: _SchematicPainter(
        glyph: _glyphOf(type),
        frameColor: error ? errorColor : palette.sub,
        glyphColor: error ? errorColor : palette.ink,
        ruleColor: palette.dim,
      ),
      child: SizedBox.square(dimension: dimension),
    );
  }

  static Glyph _glyphOf(NullStatusIllustration type) => switch (type) {
    NullStatusIllustration.data => AppGlyphs.resources,
    NullStatusIllustration.logs => AppGlyphs.logs,
    NullStatusIllustration.dns => AppGlyphs.dns,
    NullStatusIllustration.tun => AppGlyphs.vpn,
    NullStatusIllustration.wifi => AppGlyphs.wifi,
    NullStatusIllustration.apps => AppGlyphs.appsList,
    NullStatusIllustration.permission => AppGlyphs.lock,
    NullStatusIllustration.camera => AppGlyphs.camera,
    NullStatusIllustration.error => AppGlyphs.error,
    NullStatusIllustration.search => AppGlyphs.search,
  };
}

class _SchematicPainter extends CustomPainter {
  static const _hairline = 0.7;
  static const _frameExtent = 0.84;
  static const _glyphExtent = 0.4;
  static const _ruleExtent = 0.14;
  static const _ruleDrop = 0.3;

  final Glyph glyph;
  final Color frameColor;
  final Color glyphColor;
  final Color ruleColor;

  const _SchematicPainter({
    required this.glyph,
    required this.frameColor,
    required this.glyphColor,
    required this.ruleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: side * _frameExtent,
        height: side * _frameExtent,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _hairline
        ..color = frameColor,
    );
    final glyphSide = side * _glyphExtent;
    canvas.save();
    canvas.translate(center.dx - glyphSide / 2, center.dy - glyphSide / 2);
    GlyphPainter(
      glyph: glyph,
      fill: 0,
      color: glyphColor,
    ).paint(canvas, Size.square(glyphSide));
    canvas.restore();
    final ruleY = center.dy + side * _ruleDrop;
    canvas.drawLine(
      Offset(center.dx - side * _ruleExtent, ruleY),
      Offset(center.dx + side * _ruleExtent, ruleY),
      Paint()
        ..strokeWidth = _hairline
        ..color = ruleColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.frameColor != frameColor ||
      oldDelegate.glyphColor != glyphColor ||
      oldDelegate.ruleColor != ruleColor;
}
