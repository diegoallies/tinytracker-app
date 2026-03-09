class HealthLog {
  final String id;
  final String babyId;
  final String userId;
  final double? temperatureC;
  final String? medication;
  final String? dosage;
  final String? symptoms;
  final String? notes;
  final DateTime loggedAt;
  final DateTime createdAt;

  HealthLog({
    required this.id,
    required this.babyId,
    required this.userId,
    this.temperatureC,
    this.medication,
    this.dosage,
    this.symptoms,
    this.notes,
    required this.loggedAt,
    required this.createdAt,
  });

  String get tempStatus {
    if (temperatureC == null) return '';
    if (temperatureC! < 36) return 'Low';
    if (temperatureC! <= 37.5) return 'Normal';
    if (temperatureC! <= 38.5) return 'Fever';
    return 'High Fever';
  }

  factory HealthLog.fromJson(Map<String, dynamic> json) {
    return HealthLog(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      temperatureC: (json['temperature_c'] as num?)?.toDouble(),
      medication: json['medication'] as String?,
      dosage: json['dosage'] as String?,
      symptoms: json['symptoms'] as String?,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'temperature_c': temperatureC,
    'medication': medication,
    'dosage': dosage,
    'symptoms': symptoms,
    'notes': notes,
    'logged_at': loggedAt.toIso8601String(),
  };
}
