class Baby {
  final String id;
  final String userId;
  final String? ownerId;
  final String name;
  final DateTime dateOfBirth;
  final String? gender;
  final String? photoUrl;
  final DateTime createdAt;

  Baby({
    required this.id,
    required this.userId,
    this.ownerId,
    required this.name,
    required this.dateOfBirth,
    this.gender,
    this.photoUrl,
    required this.createdAt,
  });

  int get ageDays => DateTime.now().difference(dateOfBirth).inDays;

  String get ageDisplay {
    final months = ageDays ~/ 30;
    final days = ageDays % 30;
    if (months > 0) return '$months mo${days > 0 ? ', $days d' : ''}';
    return '$days days';
  }

  factory Baby.fromJson(Map<String, dynamic> json) {
    return Baby(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      ownerId: json['owner_id'] as String?,
      name: json['name'] as String,
      dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
      gender: json['gender'] as String?,
      photoUrl: json['photo_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'owner_id': ownerId,
    'name': name,
    'date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
    'gender': gender,
    'photo_url': photoUrl,
  };

  Baby copyWith({
    String? name,
    DateTime? dateOfBirth,
    String? gender,
    String? photoUrl,
  }) {
    return Baby(
      id: id,
      userId: userId,
      ownerId: ownerId,
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt,
    );
  }
}
