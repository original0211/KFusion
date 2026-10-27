import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The settled disc geometry, shared by the filled brand mark and the
/// outline ring so the two readings never drift apart.
abstract final class DiscGeometry {
  // The master's bite: centred just past the rim at 157 degrees, it cuts the disc back to 0.61 of its radius along that ray.
  static const biteDirection = 157 * math.pi / 180;
  static const biteDistance = 1.28;
  static const biteRadius = 0.67;

  static Path path(Offset center, double radius) {
    final biteCenter =
        center + Offset.fromDirection(biteDirection, radius * biteDistance);
    return Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
      Path()..addOval(
        Rect.fromCircle(center: biteCenter, radius: radius * biteRadius),
      ),
    );
  }
}

/// The brand mark as a flat decoration: the logo's disc with its crescent bite, at the master's proportions.
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
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscMotifPainter(color),
    );
  }
}

/// The outline reading of the brand disc: the same geometry as a fine
/// stroke, its centre hollow.
class DiscRingMotif extends StatelessWidget {
  const DiscRingMotif({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 1.3,
  });

  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DiscRingPainter(color, strokeWidth),
    );
  }
}

class _DiscMotifPainter extends CustomPainter {
  const _DiscMotifPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    canvas.drawPath(
      DiscGeometry.path(Offset(radius, radius), radius),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DiscMotifPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _DiscRingPainter extends CustomPainter {
  const _DiscRingPainter(this.color, this.strokeWidth);

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    canvas.drawPath(
      DiscGeometry.path(Offset(radius, radius), radius - strokeWidth),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_DiscRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
