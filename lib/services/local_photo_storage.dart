import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/photo.dart';

/// Apenas arquivos privados do app são elegíveis para limpeza automática.
class LocalPhotoStorage {
  final Future<Directory> Function() documentsDirectory;
  final Future<Directory> Function() temporaryDirectory;

  LocalPhotoStorage({
    this.documentsDirectory = getApplicationDocumentsDirectory,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  Future<Photo> importPhoto(File source) async {
    final directory = await documentsDirectory();
    final id = const Uuid().v4();
    final extension = p.extension(source.path);
    final saved = await source.copy(
      p.join(directory.path, 'foto_$id$extension'),
    );
    return Photo(
      id: id,
      localPath: saved.path,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> deleteSyncedCopy(Photo photo) async {
    if (photo.status != SyncStatus.synced || photo.prismaPhotoId == null) {
      return false;
    }
    final directory = await documentsDirectory();
    final file = File(photo.localPath);
    if (!p.isWithin(directory.absolute.path, file.absolute.path)) return false;
    if (await file.exists()) {
      // Também recusa links simbólicos apontando para fora da pasta do app.
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(await directory.resolveSymbolicLinks(), resolved)) {
        return false;
      }
      await file.delete();
    }
    return true;
  }

  /// Descarta o cache de captura/compartilhamento somente após salvar uma cópia.
  /// Nunca remove o original recebido de uma galeria ou pasta externa.
  Future<void> deleteTemporaryCopy(File source) async {
    final directory = await temporaryDirectory();
    if (!p.isWithin(directory.absolute.path, source.absolute.path)) return;
    if (await source.exists() &&
        p.isWithin(
          await directory.resolveSymbolicLinks(),
          await source.resolveSymbolicLinks(),
        )) {
      await source.delete();
    }
  }
}
