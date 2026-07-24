/// Age-based formula-feeding guideline data.
///
/// Single source of truth for the per-feed target volume + typical interval.
/// It AUTOMATICALLY adjusts as the baby gets older because it is looked up from
/// the baby's age in days every time — no manual updates needed.
///
/// Pure Dart on purpose (no Supabase/Flutter imports) so it is unit-testable
/// and reusable from any provider.
///
/// NOTE: general guidance only, not medical advice. Babies self-regulate; the
/// clinic/paediatrician has the final say based on weight and growth curve.
/// Volumes/intervals follow the typical formula-feeding ranges published by
/// the NHS (https://www.nhs.uk/conditions/baby/breastfeeding-and-bottle-feeding/)
/// and are used only to time reminders - amounts are never shown as advice.
library;

class FeedingTarget {
  final int targetMl; // standard "full feed" volume for this age
  final double intervalHours; // typical hours between feeds at this age
  final String ageLabel; // human-readable bracket

  const FeedingTarget({
    required this.targetMl,
    required this.intervalHours,
    required this.ageLabel,
  });
}

class _Bracket {
  final double minMonths;
  final int targetMl;
  final double intervalHours;
  final String label;
  const _Bracket(this.minMonths, this.targetMl, this.intervalHours, this.label);
}

class FeedingGuidelines {
  FeedingGuidelines._();

  /// 45-minute floor so a tiny top-up feed can't schedule the next feed absurdly soon.
  static const double minIntervalHours = 0.75;

  static const List<_Bracket> _brackets = [
    _Bracket(0, 90, 3, '0-1 months'),
    _Bracket(1, 120, 3, '1-2 months'),
    _Bracket(2, 150, 3, '2-3 months'),
    _Bracket(3, 180, 3, '3-5 months'),
    _Bracket(5, 210, 4, '5-7 months'),
    _Bracket(7, 240, 4, '7-12 months'),
    _Bracket(12, 240, 5, '12+ months'),
  ];

  static const double _daysPerMonth = 30.4375;

  /// Standard target + interval for the baby's current age (in days).
  static FeedingTarget targetForAgeDays(int ageDays) {
    final months = ageDays / _daysPerMonth;
    var chosen = _brackets.first;
    for (final b in _brackets) {
      if (months >= b.minMonths) chosen = b;
    }
    return FeedingTarget(
      targetMl: chosen.targetMl,
      intervalHours: chosen.intervalHours,
      ageLabel: chosen.label,
    );
  }

  /// Hours until the next feed, scaled by how much the baby actually drank.
  /// A full feed -> full interval; a small feed -> proportionally sooner.
  /// Clamped between [minIntervalHours] and the full interval.
  ///
  /// Returns the full interval when [lastAmountMl] is null/0 (e.g. breastfeeding
  /// with no recorded volume) so callers can fall back to pattern-based timing.
  static double nextIntervalHours(int? lastAmountMl, FeedingTarget target) {
    if (lastAmountMl == null || lastAmountMl <= 0) return target.intervalHours;
    final scaled = (lastAmountMl / target.targetMl) * target.intervalHours;
    return scaled.clamp(minIntervalHours, target.intervalHours);
  }
}
