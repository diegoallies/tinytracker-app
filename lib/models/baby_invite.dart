class BabyInvite {
  final String id;
  final String babyId;
  final String? invitedBy;
  final String token;
  final String role;
  final DateTime? expiresAt;
  final String? usedBy;
  final DateTime createdAt;

  BabyInvite({
    required this.id,
    required this.babyId,
    this.invitedBy,
    required this.token,
    required this.role,
    this.expiresAt,
    this.usedBy,
    required this.createdAt,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isUsed => usedBy != null;
  bool get isValid => !isExpired && !isUsed;

  factory BabyInvite.fromJson(Map<String, dynamic> json) {
    return BabyInvite(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      invitedBy: json['invited_by'] as String?,
      token: json['token'] as String,
      role: json['role'] as String,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      usedBy: json['used_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
