import 'package:flutter/material.dart';

const tinhaNavy = Color(0xFF101E50);
const tinhaBlue = Color(0xFF245CF5);

class TinhaWordmark extends StatelessWidget {
  final double fontSize;
  const TinhaWordmark({super.key, this.fontSize = 28});

  @override
  Widget build(BuildContext context) => Text.rich(
    const TextSpan(
      children: [
        TextSpan(
          text: 'Tinha',
          style: TextStyle(color: tinhaNavy),
        ),
        TextSpan(
          text: 'Kids',
          style: TextStyle(color: tinhaBlue),
        ),
      ],
    ),
    semanticsLabel: 'TinhaKids',
    maxLines: 1,
    style: TextStyle(
      fontFamily: 'Nunito',
      fontSize: fontSize,
      height: 1.1,
      letterSpacing: -fontSize * .04,
      fontWeight: FontWeight.w900,
    ),
  );
}

class GraduationCap extends StatelessWidget {
  final double width;
  const GraduationCap({super.key, this.width = 36});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(width, width * 48 / 62),
      painter: const _CapPainter(),
    ),
  );
}

class _CapPainter extends CustomPainter {
  const _CapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 62, size.height / 48);
    final outline = Paint()
      ..color = tinhaNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(59, 17)
        ..lineTo(59, 35),
      Paint()
        ..color = tinhaBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 24)
        ..lineTo(14, 37)
        ..lineTo(30.5, 46)
        ..lineTo(47, 37)
        ..lineTo(47, 24),
      outline,
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, 17)
        ..lineTo(30.5, 3)
        ..lineTo(57, 17)
        ..lineTo(30.5, 31)
        ..close(),
      outline,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CapPainter oldDelegate) => false;
}
