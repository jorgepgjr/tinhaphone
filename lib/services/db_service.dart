import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE photos (
            id TEXT PRIMARY KEY,
            localPath TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            status TEXT NOT NULL,
            driveFileId TEXT,
            prismaPhotoId INTEGER,
            uploadError TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            message TEXT NOT NULL,
            details TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              message TEXT NOT NULL,
              details TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE photos ADD COLUMN prismaPhotoId INTEGER',
          );
          await db.execute('ALTER TABLE photos ADD COLUMN uploadError TEXT');
        }
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

    final appDir = await getApplicationDocumentsDirectory();

    return List.generate(maps.length, (i) {
      final photo = Photo.fromMap(maps[i]);
      final filename = photo.localPath.split('/').last;
      final correctPath = '${appDir.path}/$filename';

      return Photo(
        id: photo.id,
        localPath: correctPath,
        timestamp: photo.timestamp,
        status: photo.status,
        driveFileId: photo.driveFileId,
        prismaPhotoId: photo.prismaPhotoId,
        uploadError: photo.uploadError,
      );
    });
  }

  Future<void> updatePhotoStatus(
    String id,
    SyncStatus status, {
    String? driveFileId,
    int? prismaPhotoId,
    String? uploadError,
  }) async {
    final db = await database;
    final Map<String, Object?> updates = {'status': status.name};
    if (driveFileId != null) {
      updates['driveFileId'] = driveFileId;
    }
    if (prismaPhotoId != null) updates['prismaPhotoId'] = prismaPhotoId;
    updates['uploadError'] = uploadError;
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

  Future<void> saveLog(String message, String? details) async {
    final db = await database;
    await db.insert('logs', {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'message': message,
      'details': details,
    });
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await database;
    return await db.query('logs', orderBy: 'timestamp DESC');
  }

  Future<void> clearLogs() async {
    final db = await database;
    await db.delete('logs');
  }
}
