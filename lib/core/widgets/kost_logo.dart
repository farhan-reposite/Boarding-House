import 'package:flutter/material.dart';

/// The app's mark: a house with an arched door on a rounded badge. This is
/// the in-app twin of assets/icon/icon.png (see gen_icon.py) - same shape,
/// drawn as a vector so it stays crisp at any size. Colors default to the
/// current theme so it adapts to light and dark mode.
class KostLogo extends StatelessWidget {
  const KostLogo({super.key, this.size = 32, this.background, this.foreground});

  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.square(size),
      painter: _KostLogoPainter(
        background: background ?? scheme.primary,
        foreground: foreground ?? scheme.onPrimary,
      ),
    );
  }
}

class _KostLogoPainter extends CustomPainter {
  _KostLogoPainter({required this.background, required this.foreground});
  final Color background;
  final Color foreground;

  static const _house = <Offset>[
    Offset(0.50, 0.20),
    Offset(0.86, 0.50),
    Offset(0.76, 0.50),
    Offset(0.76, 0.80),
    Offset(0.24, 0.80),
    Offset(0.24, 0.50),
    Offset(0.14, 0.50),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.24)),
      Paint()..color = background,
    );

    final path = Path()..moveTo(_house[0].dx * s, _house[0].dy * s);
    for (final p in _house.skip(1)) {
      path.lineTo(p.dx * s, p.dy * s);
    }
    path.close();

    final paint = Paint()..color = foreground;
    canvas.drawPath(path, paint);
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.03
        ..strokeJoin = StrokeJoin.round,
    );

    // Arched door, cut out in the background color.
    final door = Path()
      ..moveTo(s * 0.425, s * 0.80)
      ..lineTo(s * 0.425, s * 0.62)
      ..arcToPoint(Offset(s * 0.575, s * 0.62),
          radius: Radius.circular(s * 0.075), clockwise: true)
      ..lineTo(s * 0.575, s * 0.80)
      ..close();
    canvas.drawPath(door, Paint()..color = background);
  }

  @override
  bool shouldRepaint(covariant _KostLogoPainter old) =>
      old.background != background || old.foreground != foreground;
}
