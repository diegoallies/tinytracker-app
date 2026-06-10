import '../utils/date_utils.dart';
class Growth {
  final String id;
  final String babyId;
  final String userId;
  final double? weightKg;
  final double? heightCm;
  final double? headCm;
  final DateTime measuredAt;
  final String? notes;
  final DateTime createdAt;

  Growth({
    required this.id,
    required this.babyId,
    required this.userId,
    this.weightKg,
    this.heightCm,
    this.headCm,
    required this.measuredAt,
    this.notes,
    required this.createdAt,
  });

  factory Growth.fromJson(Map<String, dynamic> json) {
    return Growth(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      headCm: (json['head_cm'] as num?)?.toDouble(),
      measuredAt: parseDbTime(json['measured_at'] as String),
      notes: json['notes'] as String?,
      createdAt: parseDbTime(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'weight_kg': weightKg,
    'height_cm': heightCm,
    'head_cm': headCm,
    'measured_at': measuredAt.toUtc().toIso8601String(),
    'notes': notes,
  };
}
