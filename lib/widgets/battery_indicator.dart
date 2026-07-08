import 'dart:math';
import 'package:flutter/material.dart';
import '../app_colors.dart';

class BatteryIndicator extends StatefulWidget {
  final int level;
  final bool isCharging;

  const BatteryIndicator({
    super.key,
    required this.level,
    required this.isCharging,
  });

  @override
  State<BatteryIndicator> createState() => _BatteryIndicatorState();
}

class _BatteryIndicatorState extends State<BatteryIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isCharging) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BatteryIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCharging && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isCharging && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowValue = widget.isCharging ? _pulseController.value : 0.0;
        return Container(
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1 + (glowValue * 0.15)),
                blurRadius: 30 + (glowValue * 20),
                spreadRadius: 2,
              )
            ],
          ),
          child: CustomPaint(
            painter: BatteryPainter(
              level: widget.level,
              isCharging: widget.isCharging,
              glowValue: glowValue,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isCharging)
                    Icon(
                      Icons.flash_on,
                      color: AppColors.accent,
                      size: 28,
                      shadows: [
                        Shadow(
                          color: AppColors.accent.withValues(alpha: 0.8),
                          blurRadius: 10,
                        )
                      ],
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.level}%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    widget.isCharging ? 'CHARGING' : 'ON BATTERY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: widget.isCharging ? AppColors.primary : AppColors.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class BatteryPainter extends CustomPainter {
  final int level;
  final bool isCharging;
  final double glowValue;

  BatteryPainter({
    required this.level,
    required this.isCharging,
    required this.glowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2) - 10;
    
    // Outer Track Paint
    final trackPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Active Progress Paint
    final progressAngle = (level / 100) * 2 * pi;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // Gradient logic: from green to bright cyan (charging) or just green/yellow
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    Color progressColor;
    if (level < 20) {
      progressColor = AppColors.alert;
    } else {
      progressColor = AppColors.primary;
    }


    if (isCharging) {
      progressPaint.shader = SweepGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.5),
          AppColors.primary,
          AppColors.accent,
          AppColors.primary,
        ],
        stops: const [0.0, 0.5, 0.75, 1.0],
        transform: const GradientRotation(-pi / 2),
      ).createShader(rect);
    } else {
      progressPaint.color = progressColor;
    }

    // Glow Effect under progress arc
    if (glowValue > 0) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = (isCharging ? AppColors.accent : progressColor).withValues(alpha: 0.3 * glowValue)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progressAngle,
        false,
        glowPaint,
      );
    }

    // Draw main progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      progressAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant BatteryPainter oldDelegate) {
    return oldDelegate.level != level || 
           oldDelegate.isCharging != isCharging || 
           oldDelegate.glowValue != glowValue;
  }
}
