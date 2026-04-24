import 'dart:math';

import 'package:flutter/material.dart';

class SimpleLineChart extends StatelessWidget {
  final List<double> values;
  final double height;
  final String? title;
  final List<String>? xLabels;

  const SimpleLineChart({
    super.key,
    required this.values,
    this.height = 160,
    this.title,
    this.xLabels,
  });

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No data')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LinePainter(values: values, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        if (xLabels != null && xLabels!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  xLabels!.first,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
              ),
              if (xLabels!.length > 2)
                Expanded(
                  child: Text(
                    xLabels![xLabels!.length ~/ 2],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                )
              else
                const Spacer(),
              Expanded(
                child: Text(
                  xLabels!.last,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _LinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 10.0;
    final w = max(0.0, size.width - padding * 2);
    final h = max(0.0, size.height - padding * 2);

    final minV = values.reduce(min);
    final maxV = values.reduce(max);
    final span = (maxV - minV).abs() < 0.000001 ? 1.0 : (maxV - minV);

    final bgPaint = Paint()
      ..color = color.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final pointStrokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Light grid
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (h * i / 4.0);
      canvas.drawLine(Offset(padding, y), Offset(padding + w, y), gridPaint);
    }

    final path = Path();
    final points = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = padding + (values.length == 1 ? w / 2 : (w * i / (values.length - 1)));
      final yNorm = (values[i] - minV) / span;
      final y = padding + h - (h * yNorm);
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Fill area under curve
    final fill = Path.from(path)
      ..lineTo(padding + w, padding + h)
      ..lineTo(padding, padding + h)
      ..close();
    canvas.drawPath(fill, bgPaint);

    canvas.drawPath(path, linePaint);
    for (final point in points) {
      canvas.drawCircle(point, 4.5, pointPaint);
      canvas.drawCircle(point, 4.5, pointStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
