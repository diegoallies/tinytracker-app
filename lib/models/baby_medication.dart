class BabyMedication {
  final String id;
  final String babyId;
  final String name;
  final String? defaultDosage;
  final DateTime createdAt;

  BabyMedication({
    required this.id,
    required this.babyId,
    required this.name,
    this.defaultDosage,
    required this.createdAt,
  });

  factory BabyMedication.fromJson(Map<String, dynamic> json) {
    return BabyMedication(
      id: json['id'] as String,
      babyId: json['baby_id'] as String,
      name: json['name'] as String,
      defaultDosage: json['default_dosage'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
