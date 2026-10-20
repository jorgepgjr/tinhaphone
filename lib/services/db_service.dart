import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/photo.dart';

/// Banco novo por conta. photo_vault.db do aplicativo antigo não é aberto.
class DbService {
  final String scope;
  final DatabaseFactory? factory;
  Database? _database;
  Future<Database>? _opening;
  DbService(this.scope, {this.factory}) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope)) {
      throw ArgumentError('Conta inválida');
    }
  }
  Future<Database> get database async =>
      _database ??= await (_opening ??= _open());
  Future<Database> _open() async {
    final selected = factory ?? databaseFactory;
    final path = join(
      await selected.getDatabasesPath(),
      'tinhakids_v1_$scope.db',
    );
    return selected.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute(
            "CREATE TABLE photos (id TEXT PRIMARY KEY,localPath TEXT NOT NULL,timestamp INTEGER NOT NULL,status TEXT NOT NULL,driveFileId TEXT,driveUploadError TEXT,prismaPhotoId INTEGER,uploadError TEXT,accountScope TEXT NOT NULL,ownerId TEXT NOT NULL,schoolId INTEGER NOT NULL,server TEXT NOT NULL,classId INTEGER NOT NULL,tagIds TEXT NOT NULL DEFAULT '[]',tagSyncPending INTEGER NOT NULL DEFAULT 0)",
          );
          await db.execute(
            'CREATE TABLE logs (id INTEGER PRIMARY KEY AUTOINCREMENT,timestamp INTEGER NOT NULL,message TEXT NOT NULL,details TEXT)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE photos ADD COLUMN driveUploadError TEXT',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              "ALTER TABLE photos ADD COLUMN tagIds TEXT NOT NULL DEFAULT '[]'",
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              'ALTER TABLE photos ADD COLUMN tagSyncPending INTEGER NOT NULL DEFAULT 0',
            );
          }
        },
      ),
    );
  }

  Future<void> savePhoto(Photo photo) async {
    if (photo.accountScope != scope ||
        photo.classId == null ||
        photo.ownerId == null ||
        photo.schoolId == null ||
        photo.server == null) {
      throw StateError('A foto não pertence a esta conta ou não possui turma.');
    }
    await (await database).insert(
      'photos',
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Photo>> getPhotos() async => (await (await database).query(
    'photos',
    where: 'accountScope = ?',
    whereArgs: [scope],
    orderBy: 'timestamp DESC',
  )).map(Photo.fromMap).toList();
  Future<void> recoverInterruptedUploads() async => (await database).update(
    'photos',
    {'status': 'pending'},
    where: 'accountScope = ? AND status = ?',
    whereArgs: [scope, 'syncing'],
  );
  Future<void> updatePhotoStatus(
    String id,
    SyncStatus status, {
    String? driveFileId,
    int? prismaPhotoId,
    String? uploadError,
  }) async {
    await (await database).update(
      'photos',
      {
        'status': status.name,
        'uploadError': uploadError,
        'driveFileId': ?driveFileId,
        'prismaPhotoId': ?prismaPhotoId,
      },
      where: 'id = ? AND accountScope = ?',
      whereArgs: [id, scope],
    );
  }

  Future<void> deletePhoto(String id) async => (await database).delete(
    'photos',
    where: 'id = ? AND accountScope = ?',
    whereArgs: [id, scope],
  );
  Future<void> movePhoto(String id, int classId) async =>
      (await database).update(
        'photos',
        {'classId': classId},
        where: 'id = ? AND accountScope = ?',
        whereArgs: [id, scope],
      );
  Future<void> saveTagIds(String id, List<int> ids) async =>
      (await database).update(
        'photos',
        {'tagIds': jsonEncode(ids)},
        where: 'id = ? AND accountScope = ?',
        whereArgs: [id, scope],
      );
  Future<void> setTagSyncPending(String id, bool value) async =>
      (await database).update(
        'photos',
        {'tagSyncPending': value ? 1 : 0},
        where: 'id = ? AND accountScope = ?',
        whereArgs: [id, scope],
      );
  Future<void> updateDriveUpload(
    String id, {
    String? driveFileId,
    String? error,
  }) async {
    await (await database).update(
      'photos',
      {'driveFileId': driveFileId, 'driveUploadError': error},
      where: 'id = ? AND accountScope = ?',
      whereArgs: [id, scope],
    );
  }

  Future<void> saveLog(String message, String? details) async =>
      (await database).insert('logs', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'message': message,
        'details': details,
      });
  Future<List<Map<String, dynamic>>> getLogs() async =>
      (await database).query('logs', orderBy: 'timestamp DESC');
  Future<void> clearLogs() async => (await database).delete('logs');
  Future<void> close() async {
    if (_opening != null) await _opening;
    await _database?.close();
  }
}
