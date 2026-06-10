import '../utils/date_utils.dart';
class Photo {
  final String id;
  final String babyId;
  final String userId;
  final String url;
  final String? caption;
  final DateTime? takenAt;
  final DateTime createdAt;

  Photo({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.url,
    this.caption,
    this.takenAt,
    required this.createdAt,
  });

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      url: json['url'] as String,
      caption: json['caption'] as String?,
      takenAt: json['taken_at'] != null
          ? parseDbTime(json['taken_at'] as String)
          : null,
      createdAt: parseDbTime(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
    'baby_id': babyId,
    'user_id': userId,
    'url': url,
    'caption': caption,
    'taken_at': (takenAt ?? DateTime.now()).toUtc().toIso8601String(),
  };
}
