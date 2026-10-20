import 'dart:convert';

enum SyncStatus { pending, scheduled, syncing, synced, error }

class Photo {
  final String id;
  final String localPath;
  final int timestamp;
  SyncStatus status;
  String? driveFileId;
  int? prismaPhotoId;
  String? uploadError;
  String? driveUploadError;
  final String? accountScope, ownerId, server;
  final int? schoolId;
  int? classId;
  List<int> tagIds;
  String? mediaUrl;
  bool tagSyncPending;

  Photo({
    required this.id,
    required this.localPath,
    required this.timestamp,
    this.status = SyncStatus.pending,
    this.driveFileId,
    this.prismaPhotoId,
    this.uploadError,
    this.driveUploadError,
    this.accountScope,
    this.ownerId,
    this.server,
    this.schoolId,
    this.classId,
    this.tagIds = const [],
    this.mediaUrl,
    this.tagSyncPending = false,
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
      'driveUploadError': driveUploadError,
      'accountScope': accountScope,
      'ownerId': ownerId,
      'server': server,
      'schoolId': schoolId,
      'classId': classId,
      'tagIds': jsonEncode(tagIds),
      'tagSyncPending': tagSyncPending ? 1 : 0,
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
      driveUploadError: map['driveUploadError'] as String?,
      accountScope: map['accountScope'] as String?,
      ownerId: map['ownerId'] as String?,
      server: map['server'] as String?,
      schoolId: map['schoolId'] as int?,
      classId: map['classId'] as int?,
      tagIds: map['tagIds'] == null
          ? []
          : (jsonDecode(map['tagIds'] as String) as List).cast<int>(),
      tagSyncPending: map['tagSyncPending'] == 1,
    );
  }
}
