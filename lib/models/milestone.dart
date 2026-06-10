import '../utils/date_utils.dart';
class Milestone {
  final String id;
  final String babyId;
  final String userId;
  final String category; // Motor, Social, Language, Cognitive
  final String title;
  final String? description;
  final bool achieved;
  final DateTime? achievedAt;
  final int expectedAgeMonths;
  final String? photoUrl;
  final DateTime createdAt;

  Milestone({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.category,
    required this.title,
    this.description,
    required this.achieved,
    this.achievedAt,
    required this.expectedAgeMonths,
    this.photoUrl,
    required this.createdAt,
  });

  factory Milestone.fromJson(Map<String, dynamic> json) {
    return Milestone(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      achieved: json['achieved'] as bool? ?? false,
      achievedAt: json['achieved_at'] != null
          ? parseDbTime(json['achieved_at'] as String)
          : null,
      expectedAgeMonths: json['expected_age_months'] as int? ?? 0,
      photoUrl: json['photo_url'] as String?,
      createdAt: parseDbTime(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'category': category,
    'title': title,
    'description': description,
    'expected_age_months': expectedAgeMonths,
    'achieved': achieved,
    'achieved_at': achievedAt?.toUtc().toIso8601String(),
  };

  Milestone copyWith({
    bool? achieved,
    DateTime? achievedAt,
    String? photoUrl,
  }) {
    return Milestone(
      id: id,
      babyId: babyId,
      userId: userId,
      category: category,
      title: title,
      description: description,
      achieved: achieved ?? this.achieved,
      achievedAt: achievedAt ?? this.achievedAt,
      expectedAgeMonths: expectedAgeMonths,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt,
    );
  }
}
