class Profile {
  final String id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? phone;
  final String? bio;
  final DateTime createdAt;

  Profile({
    required this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.phone,
    this.bio,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      bio: json['bio'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toUpdateJson() => {
    'display_name': displayName,
    'phone': phone,
    'bio': bio,
    'avatar_url': avatarUrl,
  };
}
