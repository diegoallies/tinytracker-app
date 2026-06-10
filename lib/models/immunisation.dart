/// Model for public.immunisations - one row per (baby, vaccine) marking a
/// dose from the SA EPI schedule (lib/utils/immunisation_data.dart) as given.
library;

import '../utils/date_utils.dart';

class Immunisation {
  final String id;
  final String babyId;
  final String userId;

  /// Stable key from ImmunisationData.schedule (e.g. 'bcg', 'hexa1').
  final String vaccineKey;

  /// Date the dose was administered (date-only column).
  final DateTime givenOn;

  final String? notes;
  final DateTime createdAt;

  const Immunisation({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.vaccineKey,
    required this.givenOn,
    this.notes,
    required this.createdAt,
  });

  factory Immunisation.fromJson(Map<String, dynamic> json) {
    return Immunisation(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      vaccineKey: json['vaccine_key'] as String,
      // Column is enforced NOT NULL, but stay defensive about legacy rows.
      givenOn: parseDbTime(
          (json['given_on'] ?? json['created_at']) as String),
      notes: json['notes'] as String?,
      createdAt: parseDbTime(json['created_at'] as String),
    );
  }
}
