class SleepSession {
  final String id;
  final String babyId;
  final String userId;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMinutes;
  final String? quality;
  final int? wakeCount;
  final String? notes;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final String? userName;

  SleepSession({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.startTime,
    this.endTime,
    this.durationMinutes,
    this.quality,
    this.wakeCount,
    this.notes,
    required this.createdAt,
    this.deletedAt,
    this.userName,
  });

  bool get isActive => endTime == null;

  String get durationDisplay {
    final mins = durationMinutes ?? DateTime.now().difference(startTime).inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  factory SleepSession.fromJson(Map<String, dynamic> json) {
    return SleepSession(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      durationMinutes: json['duration_minutes'] as int?,
      quality: json['quality'] as String?,
      wakeCount: json['wake_count'] as int?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      deletedAt: json.containsKey('deleted_at') && json['deleted_at'] != null
          ? DateTime.parse(json['deleted_at'] as String)
          : null,
      userName: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['display_name'] as String?
          : null,
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'start_time': startTime.toIso8601String(),
  };
}
