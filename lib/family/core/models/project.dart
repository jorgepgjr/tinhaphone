class Project {
  final String id;
  final String childId;
  final String title;
  final String imageUrl;
  final List<String> imageUrls;
  final String completionDate;
  final List<String> pedagogicalObjectives;
  final String description;

  const Project({
    required this.id,
    required this.childId,
    required this.title,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.completionDate,
    required this.pedagogicalObjectives,
    required this.description,
  });

  factory Project.fromJson(
    Map<String, dynamic> json,
    String Function(String) resolveUrl,
  ) {
    final rawImages = (json['image_urls'] as List?)?.cast<String>() ?? const [];
    final images = rawImages.map(resolveUrl).toList();
    final fallbackImage = resolveUrl(json['image_url'] as String);
    return Project(
      id: json['id'] as String,
      childId: json['child_id'] as String,
      title: json['title'] as String,
      imageUrl: images.isEmpty ? fallbackImage : images.first,
      imageUrls: images.isEmpty ? [fallbackImage] : images,
      completionDate: DateTime.parse(
        json['completion_date'] as String,
      ).toLocal().toIso8601String(),
      pedagogicalObjectives: (json['pedagogical_objectives'] as List)
          .cast<String>(),
      description: json['description'] as String,
    );
  }
}
