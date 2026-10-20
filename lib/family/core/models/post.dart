class Post {
  final String id;
  final List<String> childIds;
  final String teacherName;
  final String teacherAvatarUrl;
  final String classroomName;
  final String imageUrl;
  final List<String> imageUrls;
  final String caption;
  final DateTime createdAt;
  final int likesCount;
  final bool isLiked;

  const Post({
    required this.id,
    required this.childIds,
    required this.teacherName,
    required this.teacherAvatarUrl,
    required this.classroomName,
    required this.imageUrl,
    this.imageUrls = const [],
    required this.caption,
    required this.createdAt,
    required this.likesCount,
    this.isLiked = false,
  });

  factory Post.fromJson(
    Map<String, dynamic> json,
    String childId,
    String Function(String) resolveUrl,
  ) {
    final rawImages = (json['image_urls'] as List?)?.cast<String>() ?? const [];
    final images = rawImages.map(resolveUrl).toList();
    final fallbackImage = resolveUrl(json['image_url'] as String);
    return Post(
      id: json['id'] as String,
      childIds: [childId],
      teacherName: json['teacher_name'] as String,
      teacherAvatarUrl: resolveUrl(
        (json['teacher_avatar_url'] as String?) ?? '',
      ),
      classroomName: json['classroom_name'] as String,
      imageUrl: images.isEmpty ? fallbackImage : images.first,
      imageUrls: images.isEmpty ? [fallbackImage] : images,
      caption: json['caption'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      likesCount: 0,
    );
  }

  Post copyWith({
    String? id,
    List<String>? childIds,
    String? teacherName,
    String? teacherAvatarUrl,
    String? classroomName,
    String? imageUrl,
    List<String>? imageUrls,
    String? caption,
    DateTime? createdAt,
    int? likesCount,
    bool? isLiked,
  }) {
    return Post(
      id: id ?? this.id,
      childIds: childIds ?? this.childIds,
      teacherName: teacherName ?? this.teacherName,
      teacherAvatarUrl: teacherAvatarUrl ?? this.teacherAvatarUrl,
      classroomName: classroomName ?? this.classroomName,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}
