enum SyncStatus { pending, scheduled, syncing, synced, error }

class Photo {
  final String id;
  final String localPath;
  final int timestamp;
  SyncStatus status;
  String? driveFileId;
  int? prismaPhotoId;
  String? uploadError;

  Photo({
    required this.id,
    required this.localPath,
    required this.timestamp,
    this.status = SyncStatus.pending,
    this.driveFileId,
    this.prismaPhotoId,
    this.uploadError,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localPath': localPath,
      'timestamp': timestamp,
      'status': status.name,
      'driveFileId': driveFileId,
      'prismaPhotoId': prismaPhotoId,
      'uploadError': uploadError,
    };
  }

  factory Photo.fromMap(Map<String, dynamic> map) {
    return Photo(
      id: map['id'] as String,
      localPath: map['localPath'] as String,
      timestamp: map['timestamp'] as int,
      status: SyncStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SyncStatus.pending,
      ),
      driveFileId: map['driveFileId'] as String?,
      prismaPhotoId: map['prismaPhotoId'] as int?,
      uploadError: map['uploadError'] as String?,
    );
  }
}
