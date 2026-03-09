import 'package:flutter/material.dart';

class CountUpText extends StatelessWidget {
  final int targetValue;
  final TextStyle? style;
  final String suffix;
  final Duration duration;

  const CountUpText({
    super.key,
    required this.targetValue,
    this.style,
    this.suffix = '',
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: targetValue),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, _) {
        return Text('$value$suffix', style: style);
      },
    );
  }
}

class CountUpDuration extends StatelessWidget {
  final int totalMinutes;
  final TextStyle? style;
  final Duration duration;

  const CountUpDuration({
    super.key,
    required this.totalMinutes,
    this.style,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: totalMinutes),
      duration: duration,
      curve: Curves.easeOut,
      builder: (context, value, _) {
        final h = value ~/ 60;
        final m = value % 60;
        return Text('${h}h ${m}m', style: style);
      },
    );
  }
}
