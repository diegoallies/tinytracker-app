import '../utils/date_utils.dart';
class BabyMedication {
  final String id;
  final String babyId;
  final String name;
  final String? defaultDosage;

  /// Scheduled meds: how many times a day (1 = once). Null for as-needed.
  final int? frequencyPerDay;

  /// Calpol/Panado style - only given when needed.
  final bool asNeeded;

  /// Minimum gap between doses, in hours (e.g. 4).
  final double? minIntervalHours;

  /// Human-readable regimen, e.g. 'Once a day'.
  final String? instructions;

  final DateTime createdAt;

  BabyMedication({
    required this.id,
    required this.babyId,
    required this.name,
    this.defaultDosage,
    this.frequencyPerDay,
    this.asNeeded = false,
    this.minIntervalHours,
    this.instructions,
    required this.createdAt,
  });

  factory BabyMedication.fromJson(Map<String, dynamic> json) {
    return BabyMedication(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      name: json['name'] as String,
      defaultDosage: json['default_dosage'] as String?,
      frequencyPerDay: (json['frequency_per_day'] as num?)?.toInt(),
      asNeeded: json['as_needed'] as bool? ?? false,
      minIntervalHours: _toDouble(json['min_interval_hours']),
      instructions: json['instructions'] as String?,
      createdAt: parseDbTime(json['created_at'] as String),
    );
  }

  // Postgres `numeric` can arrive as num or String depending on the driver.
  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
