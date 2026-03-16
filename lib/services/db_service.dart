import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/photo.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'photo_vault.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE photos (
            id TEXT PRIMARY KEY,
            localPath TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL,
            driveFileId TEXT
          )
        ''');
      },
    );
  }

  Future<void> savePhoto(Photo photo) async {
    final db = await database;
    await db.insert(
      'photos',
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Photo>> getPhotos() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'photos',
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) => Photo.fromMap(maps[i]));
  }

  Future<void> updatePhotoStatus(
    String id,
    SyncStatus status, {
    String? driveFileId,
  }) async {
    final db = await database;
    final updates = {'status': status.name};
    if (driveFileId != null) {
      updates['driveFileId'] = driveFileId;
    }
    await db.update('photos', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deletePhoto(String id) async {
    final db = await database;
    await db.delete('photos', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearSyncedPhotos() async {
    final db = await database;
    // We should delete the files also? Better handle it at logic level when clearSynced is called
    await db.delete(
      'photos',
      where: 'status = ?',
      whereArgs: [SyncStatus.synced.name],
    );
  }
}
