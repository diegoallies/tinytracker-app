class Diaper {
  final String id;
  final String babyId;
  final String userId;
  final String type; // wet, dirty, both
  final String? color; // yellow, green, brown, black, red, white
  final String? notes;
  final DateTime loggedAt;
  final DateTime createdAt;

  Diaper({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.type,
    this.color,
    this.notes,
    required this.loggedAt,
    required this.createdAt,
  });

  String get typeDisplay {
    switch (type) {
      case 'wet': return 'Wet';
      case 'dirty': return 'Dirty';
      case 'both': return 'Both';
      default: return type;
    }
  }

  factory Diaper.fromJson(Map<String, dynamic> json) {
    return Diaper(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      color: json['color'] as String?,
      notes: json['notes'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'type': type,
    'color': color,
    'notes': notes,
    'logged_at': loggedAt.toIso8601String(),
  };
}
