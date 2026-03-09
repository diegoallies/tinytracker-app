class Feeding {
  final String id;
  final String babyId;
  final String userId;
  final String type; // breast_left, breast_right, bottle, solids
  final int? durationMinutes;
  final int? amountMl;
  final String? notes;
  final DateTime loggedAt;
  final DateTime createdAt;

  Feeding({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.type,
    this.durationMinutes,
    this.amountMl,
    this.notes,
    required this.loggedAt,
    required this.createdAt,
  });

  String get typeDisplay {
    switch (type) {
      case 'breast_left': return 'Left Breast';
      case 'breast_right': return 'Right Breast';
      case 'bottle': return 'Bottle';
      case 'solids': return 'Solids';
      default: return type;
    }
  }

  factory Feeding.fromJson(Map<String, dynamic> json) {
    return Feeding(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      durationMinutes: json['duration_minutes'] as int?,
      amountMl: json['amount_ml'] as int?,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'type': type,
    'duration_minutes': durationMinutes,
    'amount_ml': amountMl,
    'notes': notes,
    'logged_at': loggedAt.toIso8601String(),
  };
}
