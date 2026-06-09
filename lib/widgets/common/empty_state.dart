import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? illustrationType;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.illustrationType,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (illustrationType != null)
              _BabyIllustration(type: illustrationType!)
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.1, end: 0, duration: 500.ms, curve: Curves.easeOut)
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 48, color: AppColors.primary),
              ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: context.palette.text,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.muted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BabyIllustration extends StatelessWidget {
  final String type;

  const _BabyIllustration({required this.type});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _BabyIllustrationPainter(type: type),
      ),
    );
  }
}

class _BabyIllustrationPainter extends CustomPainter {
  final String type;

  _BabyIllustrationPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = AppColors.pastelPurple.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.45, bgPaint);

    // Soft inner glow
    final glowPaint = Paint()
      ..color = AppColors.pastelPurple.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.35, glowPaint);

    switch (type) {
      case 'feeding':
        _drawFeedingBaby(canvas, size, cx, cy);
        break;
      case 'diaper':
        _drawDiaperBaby(canvas, size, cx, cy);
        break;
      case 'sleep':
        _drawSleepingBaby(canvas, size, cx, cy);
        break;
      case 'tummy_time':
        _drawTummyBaby(canvas, size, cx, cy);
        break;
      case 'no_baby':
        _drawStork(canvas, size, cx, cy);
        break;
      case 'photos':
        _drawCameraBaby(canvas, size, cx, cy);
        break;
      case 'milestones':
        _drawStarBaby(canvas, size, cx, cy);
        break;
      case 'health':
        _drawHealthBaby(canvas, size, cx, cy);
        break;
      case 'growth':
        _drawGrowthBaby(canvas, size, cx, cy);
        break;
      default:
        _drawDefaultBaby(canvas, size, cx, cy);
    }
  }

  void _drawBabyHead(Canvas canvas, double cx, double cy, double radius) {
    // Head
    final skinPaint = Paint()
      ..color = const Color(0xFFFDD9B5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), radius, skinPaint);

    // Outline
    final outlinePaint = Paint()
      ..color = const Color(0xFFD4A88C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), radius, outlinePaint);

    // Eyes
    final eyePaint = Paint()
      ..color = const Color(0xFF2D2640)
      ..style = PaintingStyle.fill;
    final eyeR = radius * 0.12;
    canvas.drawCircle(Offset(cx - radius * 0.3, cy - radius * 0.1), eyeR, eyePaint);
    canvas.drawCircle(Offset(cx + radius * 0.3, cy - radius * 0.1), eyeR, eyePaint);

    // Eye shine
    final shinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(cx - radius * 0.3 + eyeR * 0.3, cy - radius * 0.1 - eyeR * 0.3),
        eyeR * 0.4, shinePaint);
    canvas.drawCircle(
        Offset(cx + radius * 0.3 + eyeR * 0.3, cy - radius * 0.1 - eyeR * 0.3),
        eyeR * 0.4, shinePaint);

    // Rosy cheeks
    final cheekPaint = Paint()
      ..color = const Color(0xFFFFB6C1).withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx - radius * 0.5, cy + radius * 0.15),
          width: radius * 0.3,
          height: radius * 0.2),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx + radius * 0.5, cy + radius * 0.15),
          width: radius * 0.3,
          height: radius * 0.2),
      cheekPaint,
    );
  }

  void _drawSmile(Canvas canvas, double cx, double cy, double radius) {
    final smilePaint = Paint()
      ..color = const Color(0xFFD4A88C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final smilePath = Path()
      ..moveTo(cx - radius * 0.2, cy + radius * 0.2)
      ..quadraticBezierTo(cx, cy + radius * 0.4, cx + radius * 0.2, cy + radius * 0.2);
    canvas.drawPath(smilePath, smilePaint);
  }

  void _drawClosedEyes(Canvas canvas, double cx, double cy, double radius) {
    final eyePaint = Paint()
      ..color = const Color(0xFF2D2640)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Left closed eye
    final leftEye = Path()
      ..moveTo(cx - radius * 0.42, cy - radius * 0.1)
      ..quadraticBezierTo(cx - radius * 0.3, cy - radius * 0.02, cx - radius * 0.18, cy - radius * 0.1);
    canvas.drawPath(leftEye, eyePaint);

    // Right closed eye
    final rightEye = Path()
      ..moveTo(cx + radius * 0.18, cy - radius * 0.1)
      ..quadraticBezierTo(cx + radius * 0.3, cy - radius * 0.02, cx + radius * 0.42, cy - radius * 0.1);
    canvas.drawPath(rightEye, eyePaint);
  }

  void _drawFeedingBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.22;
    _drawBabyHead(canvas, cx - 8, cy - 5, r);
    _drawSmile(canvas, cx - 8, cy - 5, r);

    // Bottle
    final bottlePaint = Paint()
      ..color = AppColors.pastelBlue
      ..style = PaintingStyle.fill;
    final bottleOutline = Paint()
      ..color = const Color(0xFF7BAFD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Bottle body
    final bottleRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + 25, cy + 5), width: 14, height: 30),
      const Radius.circular(4),
    );
    canvas.drawRRect(bottleRect, bottlePaint);
    canvas.drawRRect(bottleRect, bottleOutline);

    // Bottle nipple
    final nipplePath = Path()
      ..moveTo(cx + 20, cy - 10)
      ..lineTo(cx + 22, cy - 18)
      ..quadraticBezierTo(cx + 25, cy - 22, cx + 28, cy - 18)
      ..lineTo(cx + 30, cy - 10)
      ..close();
    canvas.drawPath(nipplePath, bottlePaint);
    canvas.drawPath(nipplePath, bottleOutline);

    // Milk level
    final milkPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 25, cy + 10), width: 10, height: 15),
        const Radius.circular(2),
      ),
      milkPaint,
    );
  }

  void _drawDiaperBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.22;
    _drawBabyHead(canvas, cx, cy - 10, r);
    _drawSmile(canvas, cx, cy - 10, r);

    // Diaper shape below
    final diaperPaint = Paint()
      ..color = AppColors.pastelPurple
      ..style = PaintingStyle.fill;
    final diaperOutline = Paint()
      ..color = AppColors.primaryLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final diaperPath = Path()
      ..moveTo(cx - 20, cy + 15)
      ..quadraticBezierTo(cx - 25, cy + 35, cx - 15, cy + 40)
      ..quadraticBezierTo(cx, cy + 45, cx + 15, cy + 40)
      ..quadraticBezierTo(cx + 25, cy + 35, cx + 20, cy + 15)
      ..close();
    canvas.drawPath(diaperPath, diaperPaint);
    canvas.drawPath(diaperPath, diaperOutline);

    // Star decoration on diaper
    _drawTinyStar(canvas, cx, cy + 28, 5, AppColors.primary.withValues(alpha: 0.5));
  }

  void _drawSleepingBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.22;

    // Head tilted
    final skinPaint = Paint()
      ..color = const Color(0xFFFDD9B5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r, skinPaint);
    final outlinePaint = Paint()
      ..color = const Color(0xFFD4A88C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r, outlinePaint);

    // Rosy cheeks
    final cheekPaint = Paint()
      ..color = const Color(0xFFFFB6C1).withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - r * 0.5, cy + r * 0.15), width: r * 0.3, height: r * 0.2),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + r * 0.5, cy + r * 0.15), width: r * 0.3, height: r * 0.2),
      cheekPaint,
    );

    // Closed eyes
    _drawClosedEyes(canvas, cx, cy, r);

    // Peaceful smile
    _drawSmile(canvas, cx, cy, r);

    // Z's
    final zPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    _drawZ(canvas, cx + r + 8, cy - r + 5, 8, zPaint);
    _drawZ(canvas, cx + r + 18, cy - r - 8, 10, zPaint..strokeWidth = 2.5);
    _drawZ(canvas, cx + r + 30, cy - r - 18, 7, zPaint..strokeWidth = 1.5);

    // Moon
    final moonPaint = Paint()
      ..color = const Color(0xFFFFF3B0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - r - 10, cy - r + 5), 8, moonPaint);
    // Cut out crescent
    final cutPaint = Paint()
      ..color = AppColors.pastelPurple.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - r - 7, cy - r + 2), 6, cutPaint);
  }

  void _drawZ(Canvas canvas, double x, double y, double s, Paint paint) {
    final path = Path()
      ..moveTo(x - s / 2, y - s / 2)
      ..lineTo(x + s / 2, y - s / 2)
      ..lineTo(x - s / 2, y + s / 2)
      ..lineTo(x + s / 2, y + s / 2);
    canvas.drawPath(path, paint);
  }

  void _drawTummyBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.2;

    // Body (oval on tummy)
    final bodyPaint = Paint()
      ..color = AppColors.pastelPink
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: r * 2.5, height: r * 1.2),
      bodyPaint,
    );

    // Head
    _drawBabyHead(canvas, cx - r * 0.6, cy - r * 0.3, r * 0.8);
    _drawSmile(canvas, cx - r * 0.6, cy - r * 0.3, r * 0.8);

    // Little arms
    final armPaint = Paint()
      ..color = const Color(0xFFFDD9B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - r * 0.1, cy + 2), Offset(cx + r * 0.3, cy - 8), armPaint);
    canvas.drawLine(Offset(cx + r * 0.8, cy + 2), Offset(cx + r * 1.1, cy - 5), armPaint);
  }

  void _drawStork(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.18;

    // Bundle
    final bundlePaint = Paint()
      ..color = AppColors.pastelPink
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy + 10), r, bundlePaint);

    // Bundle outline
    final bundleOutline = Paint()
      ..color = AppColors.primaryLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy + 10), r, bundleOutline);

    // Baby face in bundle
    _drawBabyHead(canvas, cx, cy + 5, r * 0.6);
    _drawSmile(canvas, cx, cy + 5, r * 0.6);

    // Heart above
    _drawHeart(canvas, cx, cy - r - 8, 10, AppColors.primary.withValues(alpha: 0.6));

    // Sparkles
    _drawTinyStar(canvas, cx - 25, cy - 15, 4, AppColors.primary.withValues(alpha: 0.4));
    _drawTinyStar(canvas, cx + 28, cy - 10, 5, AppColors.primary.withValues(alpha: 0.3));
  }

  void _drawCameraBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.2;
    _drawBabyHead(canvas, cx, cy + 5, r);
    _drawSmile(canvas, cx, cy + 5, r);

    // Camera
    final camPaint = Paint()
      ..color = AppColors.pastelBlue
      ..style = PaintingStyle.fill;
    final camOutline = Paint()
      ..color = const Color(0xFF7BAFD4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - r - 12), width: 30, height: 20),
        const Radius.circular(4),
      ),
      camPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - r - 12), width: 30, height: 20),
        const Radius.circular(4),
      ),
      camOutline,
    );

    // Lens
    canvas.drawCircle(Offset(cx, cy - r - 12), 6, camOutline);

    // Flash
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - 8, cy - r - 23), width: 10, height: 5),
        const Radius.circular(2),
      ),
      camPaint,
    );
  }

  void _drawStarBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.2;
    _drawBabyHead(canvas, cx, cy + 5, r);
    _drawSmile(canvas, cx, cy + 5, r);

    // Stars around
    _drawTinyStar(canvas, cx - r - 10, cy - 10, 8, const Color(0xFFFFD700));
    _drawTinyStar(canvas, cx + r + 12, cy - 5, 6, const Color(0xFFFFD700).withValues(alpha: 0.7));
    _drawTinyStar(canvas, cx - r, cy - r - 5, 5, const Color(0xFFFFD700).withValues(alpha: 0.5));
    _drawTinyStar(canvas, cx + r - 5, cy - r - 8, 7, const Color(0xFFFFD700).withValues(alpha: 0.8));
  }

  void _drawHealthBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.2;
    _drawBabyHead(canvas, cx, cy + 5, r);
    _drawSmile(canvas, cx, cy + 5, r);

    // Thermometer
    final thermPaint = Paint()
      ..color = AppColors.pastelPink
      ..style = PaintingStyle.fill;
    final thermOutline = Paint()
      ..color = const Color(0xFFE91E63).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + r + 10, cy), width: 8, height: 32),
        const Radius.circular(4),
      ),
      thermPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + r + 10, cy), width: 8, height: 32),
        const Radius.circular(4),
      ),
      thermOutline,
    );
    // Bulb
    canvas.drawCircle(Offset(cx + r + 10, cy + 18), 5, thermPaint);
    canvas.drawCircle(Offset(cx + r + 10, cy + 18), 5, thermOutline);

    // Heart
    _drawHeart(canvas, cx - r - 8, cy - 8, 8, Colors.red.withValues(alpha: 0.5));
  }

  void _drawGrowthBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.2;
    _drawBabyHead(canvas, cx - 5, cy + 5, r);
    _drawSmile(canvas, cx - 5, cy + 5, r);

    // Measuring ruler
    final rulerPaint = Paint()
      ..color = AppColors.pastelGreen
      ..style = PaintingStyle.fill;
    final rulerOutline = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + r + 12, cy), width: 10, height: 45),
        const Radius.circular(3),
      ),
      rulerPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + r + 12, cy), width: 10, height: 45),
        const Radius.circular(3),
      ),
      rulerOutline,
    );

    // Ruler marks
    for (var i = -3; i <= 3; i++) {
      final y = cy + i * 6.0;
      final w = i % 2 == 0 ? 4.0 : 2.5;
      canvas.drawLine(
        Offset(cx + r + 7, y),
        Offset(cx + r + 7 + w, y),
        rulerOutline,
      );
    }
  }

  void _drawDefaultBaby(Canvas canvas, Size size, double cx, double cy) {
    final r = size.width * 0.22;
    _drawBabyHead(canvas, cx, cy, r);
    _drawSmile(canvas, cx, cy, r);
  }

  void _drawTinyStar(Canvas canvas, double x, double y, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    for (var i = 0; i < 5; i++) {
      final angle = (i * 144 - 90) * 3.14159 / 180;
      final px = x + size * math.cos(angle);
      final py = y + size * math.sin(angle);
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawHeart(Canvas canvas, double x, double y, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(x, y + size * 0.3)
      ..cubicTo(x - size, y - size * 0.5, x - size * 0.5, y - size, x, y - size * 0.4)
      ..cubicTo(x + size * 0.5, y - size, x + size, y - size * 0.5, x, y + size * 0.3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BabyIllustrationPainter oldDelegate) =>
      oldDelegate.type != type;
}
