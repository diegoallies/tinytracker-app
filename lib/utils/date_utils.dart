import 'package:intl/intl.dart';

class AppDateUtils {
  static DateTime get todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime get todayEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  static DateTime get yesterdayStart {
    final d = todayStart.subtract(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day);
  }

  static DateTime get yesterdayEnd {
    final d = todayStart.subtract(const Duration(days: 1));
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  static DateTime daysAgoStart(int days) {
    final d = todayStart.subtract(Duration(days: days));
    return DateTime(d.year, d.month, d.day);
  }

  static DateTime weekAgoStart() => daysAgoStart(7);

  static String getCachePeriod() {
    final now = DateTime.now();
    final period = now.hour < 18 ? 'am' : 'pm';
    return '${DateFormat('yyyy-MM-dd').format(now)}-$period';
  }

  static String formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);
  static String formatDate(DateTime dt) => DateFormat('MMM d').format(dt);
  static String formatFull(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
  static String formatDateShort(DateTime dt) => DateFormat('M/d').format(dt);
  static String formatMonthYear(DateTime dt) => DateFormat('MMMM yyyy').format(dt);

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formatDate(dt);
  }

  static String formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static String formatElapsed(Duration d) {
    final clamped = d.isNegative ? Duration.zero : d;
    final h = clamped.inHours;
    final m = clamped.inMinutes % 60;
    final s = clamped.inSeconds % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static int getAgeInMonths(DateTime dob) {
    final now = DateTime.now();
    return (now.year - dob.year) * 12 + now.month - dob.month;
  }

  static double getAgeInMonthsDecimal(DateTime dob) {
    return DateTime.now().difference(dob).inDays / 30.44;
  }
}

/// Parses a database timestamp into LOCAL time. Supabase returns timestamptz
/// as ISO-8601 in UTC; bare DateTime.parse keeps it UTC, so every formatter
/// and day-bucket downstream silently shows UTC (2h off in SAST). Date-only
/// strings carry no zone, parse as local, and toLocal() is then a no-op,
/// so this is safe for both kinds of column.
DateTime parseDbTime(String s) => DateTime.parse(s).toLocal();

DateTime? tryParseDbTime(String? s) =>
    s == null ? null : DateTime.tryParse(s)?.toLocal();
