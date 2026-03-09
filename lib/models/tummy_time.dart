class TummyTime {
  final String id;
  final String babyId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMinutes;
  final String? notes;
  final DateTime createdAt;

  TummyTime({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.startTime,
    this.endTime,
    this.durationMinutes,
    this.notes,
    required this.createdAt,
  });

  bool get isActive => endTime == null;

  String get durationDisplay {
    final mins = durationMinutes ?? DateTime.now().difference(startTime).inMinutes;
    return '${mins}m';
  }

  factory TummyTime.fromJson(Map<String, dynamic> json) {
    return TummyTime(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      durationMinutes: json['duration_minutes'] as int?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'start_time': startTime.toIso8601String(),
  };
}
