import 'dart:math' as math;

import 'package:kfusion/ui/hara.dart';
import 'package:material_ui/material_ui.dart';

abstract final class DiscGeometry {
  // At 157 degrees on the ring's mid-line; diameter 0.16 of the outer radius.
  static const dotDirection = 157 * math.pi / 180;
  static const dotDiameterRatio = 0.16;

  static Path ringPath(Offset center, double radius) {
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  static Offset dotCenter(Offset center, double ringRadius) {
    return center + Offset.fromDirection(dotDirection, ringRadius);
  }

  static double dotRadius(double outerRadius) {
    return outerRadius * dotDiameterRatio / 2;
  }
}

class DashboardDiscMotif extends StatelessWidget {
  const DashboardDiscMotif({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DiscRingMotif(size: size, color: color);
  }
}

class DiscRingMotif extends StatelessWidget {
  const DiscRingMotif({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.3,
    this.lit = false,
  });

  final double size;
  final Color color;
  final double strokeWidth;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscRingPainter(
        color,
        strokeWidth,
        lit ? context.haraPalette.vermilion : null,
      ),
    );
  }
}

class _DiscRingPainter extends CustomPainter {
  const _DiscRingPainter(this.color, this.strokeWidth, this.dotColor);

  final Color color;
  final double strokeWidth;
  final Color? dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final ringRadius = radius - strokeWidth;
    canvas.drawPath(
      DiscGeometry.ringPath(center, ringRadius),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    final dot = dotColor;
    if (dot != null) {
      canvas.drawCircle(
        DiscGeometry.dotCenter(center, ringRadius),
        DiscGeometry.dotRadius(ringRadius + strokeWidth / 2),
        Paint()..color = dot,
      );
    }
  }

  @override
  bool shouldRepaint(_DiscRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dotColor != dotColor;
}
