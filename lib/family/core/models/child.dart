class Child {
  final String id;
  final String name;
  final String avatarUrl;
  final String classroom;

  const Child({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.classroom,
  });

  factory Child.fromJson(
    Map<String, dynamic> json,
    String Function(String) resolveUrl,
  ) {
    return Child(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: resolveUrl(json['avatar_url'] as String),
      classroom: json['classroom'] as String,
    );
  }
}
