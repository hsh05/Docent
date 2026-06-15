import 'dart:math';
import 'package:flutter/material.dart';

class AudioVisualizer extends StatefulWidget {
  final double currentDecibels;
  final bool isListening;

  const AudioVisualizer({
    Key? key,
    required this.currentDecibels,
    required this.isListening,
  });

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  double _normalizeDecibels(double db) {
    if (db < -60.0 || db.isInfinite) return 0.0;
    if (db > 0.0) return 1.0;
    return (db + 60.0)/ 60.0;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedLevel = _normalizeDecibels(widget.currentDecibels);

    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      alignment: Alignment.center,
      child: widget.isListening
          ? AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, 80),
                  painter: WavePainter(
                    amplitude: normalizedLevel,
                    phase: _animationController.value * 2 * pi,
                    waveColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
          )
        : _buildMutedLine(),
    );
  }

  Widget _buildMutedLine() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        30,
        (index) => Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: const BoxDecoration(
            color: Color(0xFF3A3550),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double amplitude;
  final double phase;
  final Color waveColor;

  WavePainter({
    required this.amplitude,
    required this.phase,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height / 2;

    final maxWaveHeight = midY * (amplitude > 0.1 ? amplitude : 0.1);

    for (double x = 0; x <= size.width; x += 2) {
      final scalingFactor = sin((x / size.width) * pi);
      final y = midY + sin((x * 0.05) + phase) * maxWaveHeight * scalingFactor;

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) {
    return oldDelegate.amplitude != amplitude || oldDelegate.phase != phase;
  }
}