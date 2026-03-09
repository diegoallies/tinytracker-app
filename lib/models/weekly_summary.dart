enum TrendDirection { up, down, same }

class WeeklySummary {
  final int feedCount;
  final int diaperCount;
  final int sleepMinutes;
  final int feedCountLastWeek;
  final int diaperCountLastWeek;
  final int sleepMinutesLastWeek;

  WeeklySummary({
    required this.feedCount,
    required this.diaperCount,
    required this.sleepMinutes,
    required this.feedCountLastWeek,
    required this.diaperCountLastWeek,
    required this.sleepMinutesLastWeek,
  });

  double get avgDailySleepHours => sleepMinutes / 7 / 60;
  double get avgFeedsPerDay => feedCount / 7;
  double get avgDiapersPerDay => diaperCount / 7;

  TrendDirection get feedTrend => _trend(feedCount, feedCountLastWeek);
  TrendDirection get diaperTrend => _trend(diaperCount, diaperCountLastWeek);
  TrendDirection get sleepTrend => _trend(sleepMinutes, sleepMinutesLastWeek);

  int get feedChange => feedCount - feedCountLastWeek;
  int get diaperChange => diaperCount - diaperCountLastWeek;
  int get sleepChangeMinutes => sleepMinutes - sleepMinutesLastWeek;

  String get feedChangePercent => _percentChange(feedCount, feedCountLastWeek);
  String get diaperChangePercent => _percentChange(diaperCount, diaperCountLastWeek);
  String get sleepChangePercent => _percentChange(sleepMinutes, sleepMinutesLastWeek);

  static TrendDirection _trend(int current, int previous) {
    if (current > previous) return TrendDirection.up;
    if (current < previous) return TrendDirection.down;
    return TrendDirection.same;
  }

  static String _percentChange(int current, int previous) {
    if (previous == 0) return current > 0 ? '+100%' : '0%';
    final change = ((current - previous) / previous * 100).round();
    if (change > 0) return '+$change%';
    if (change < 0) return '$change%';
    return '0%';
  }
}
