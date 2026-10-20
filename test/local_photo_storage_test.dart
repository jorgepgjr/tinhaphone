import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinhaphone/models/photo.dart';
import 'package:tinhaphone/services/local_photo_storage.dart';
import 'package:tinhaphone/services/prisma_api_service.dart';
import 'support/session_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory documents;
  late Directory cache;
  late File original;
  late LocalPhotoStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tinhaphone_storage_test_');
    documents = await Directory(p.join(root.path, 'documents')).create();
    cache = await Directory(p.join(root.path, 'cache')).create();
    original = await File(
      p.join(root.path, 'gallery.png'),
    ).writeAsBytes([1, 2, 3]);
    storage = LocalPhotoStorage(
      documentsDirectory: () async => documents,
      temporaryDirectory: () async => cache,
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async => root.delete(recursive: true));

  test(
    'importa uma cópia sem alterar a galeria e preserva o formato',
    () async {
      final photo = await storage.importPhoto(original);
      expect(p.extension(photo.localPath), '.png');
      expect(await File(photo.localPath).readAsBytes(), [1, 2, 3]);
      expect(await original.exists(), isTrue);
      expect(photo.status, SyncStatus.pending);
    },
  );

  test('nomes únicos mesmo ao importar várias vezes a mesma imagem', () async {
    final one = await storage.importPhoto(original);
    final two = await storage.importPhoto(original);
    expect(one.localPath, isNot(two.localPath));
    expect(one.id, isNot(two.id));
  });

  for (final status in [
    SyncStatus.pending,
    SyncStatus.error,
    SyncStatus.syncing,
    SyncStatus.scheduled,
  ]) {
    test('não apaga foto com status ${status.name}', () async {
      final photo = await storage.importPhoto(original);
      photo.status = status;
      photo.prismaPhotoId = 42;
      expect(await storage.deleteSyncedCopy(photo), isFalse);
      expect(await File(photo.localPath).exists(), isTrue);
    });
  }

  test('não apaga sincronizada sem confirmação do Prisma', () async {
    final photo = await storage.importPhoto(original);
    photo.status = SyncStatus.synced;
    expect(await storage.deleteSyncedCopy(photo), isFalse);
    expect(await File(photo.localPath).exists(), isTrue);
  });

  test('libera a cópia confirmada e mantém o original', () async {
    final photo = await storage.importPhoto(original);
    photo.status = SyncStatus.synced;
    photo.prismaPhotoId = 42;
    expect(await storage.deleteSyncedCopy(photo), isTrue);
    expect(await File(photo.localPath).exists(), isFalse);
    expect(await original.exists(), isTrue);
    expect(await storage.deleteSyncedCopy(photo), isTrue);
  });

  test('recusa apagar foto fora da pasta privada do app', () async {
    final photo = Photo(
      id: 'external',
      localPath: original.path,
      timestamp: 1,
      status: SyncStatus.synced,
      prismaPhotoId: 42,
    );
    expect(await storage.deleteSyncedCopy(photo), isFalse);
    expect(await original.exists(), isTrue);
  });

  test('limpa apenas o arquivo temporário importado, não a galeria', () async {
    final temporary = await original.copy(p.join(cache.path, 'shared.png'));
    final photo = await storage.importPhoto(temporary);
    await storage.deleteTemporaryCopy(temporary);
    await storage.deleteTemporaryCopy(original);
    expect(await temporary.exists(), isFalse);
    expect(await File(photo.localPath).exists(), isTrue);
    expect(await original.exists(), isTrue);
  });

  test(
    'limpeza vem desligada e a escolha persiste com as configurações',
    () async {
      final api = PrismaApiService(teacherSession);
      expect((await api.loadConfig()).autoDeleteSynced, isFalse);
      await api.saveConfig(
        const PrismaConfig(classId: 3, autoDeleteSynced: true),
      );
      final config = await api.loadConfig();
      expect(config.autoDeleteSynced, isTrue);
      expect(config.classId, 3);
      await api.saveConfig(
        PrismaConfig(classId: config.classId, autoDeleteSynced: false),
      );
      expect((await api.loadConfig()).autoDeleteSynced, isFalse);
    },
  );
}
