class Subject {
  final String code;
  final String name;
  final DateTime addedAt;

  const Subject({
    required this.code,
    required this.name,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        code: json['code'] as String,
        name: json['name'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}
