import '../utils/date_utils.dart';
class BabyShare {
  final String id;
  final String babyId;
  final String userId;
  final String role; // owner, logger, viewer
  final DateTime createdAt;
  final String? userName;
  final String? userEmail;

  BabyShare({
    required this.id,
    required this.babyId,
    required this.userId,
    required this.role,
    required this.createdAt,
    this.userName,
    this.userEmail,
  });

  bool get isOwner => role == 'owner';
  bool get canLog => role == 'owner' || role == 'logger';
  bool get isViewer => role == 'viewer';

  factory BabyShare.fromJson(Map<String, dynamic> json) {
    return BabyShare(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      createdAt: parseDbTime(json['created_at'] as String),
      userName: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['display_name'] as String?
          : null,
      userEmail: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['email'] as String?
          : null,
    );
  }
}
