import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';

import '../models/photo.dart';
import '../services/db_service.dart';
import '../services/prisma_api_service.dart';
import '../services/local_photo_storage.dart';
import 'camera_screen.dart';
import 'photo_viewer_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _database = DbService();
  final _api = PrismaApiService();
  final _storage = LocalPhotoStorage();
  final Set<String> _uploading = {};
  StreamSubscription<SharedMedia>? _shareSubscription;
  Future<void> _shareQueue = Future.value();
  List<Photo> _photos = [];
  bool _syncingAll = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadPhotos();
    await _cleanSyncedPhotos();
    final configured = await _api.hasSavedConfig();
    if (!mounted) return;
    setState(() => _configured = configured);
    if (!configured) {
      await _openSettings(initialSetup: true);
    }
    if (mounted) await _initSharing();
  }

  Future<void> _loadPhotos() async {
    final photos = await _database.getPhotos();
    if (mounted) setState(() => _photos = photos);
  }

  Future<Photo> _saveLocalPhoto(File source) async {
    final photo = await _storage.importPhoto(source);
    await _database.savePhoto(photo);
    try {
      await _storage.deleteTemporaryCopy(source);
    } catch (error) {
      await _database.saveLog(
        'Não foi possível limpar o cache da foto',
        '$error',
      );
    }
    return photo;
  }

  Future<Photo?> _handleCapture(XFile capturedFile) async {
    final photo = await _saveLocalPhoto(File(capturedFile.path));
    await _loadPhotos();
    await _upload(photo);
    final remaining = await _database.getPhotos();
    return remaining.where((item) => item.id == photo.id).firstOrNull;
  }

  Future<void> _initSharing() async {
    try {
      final handler = ShareHandler.instance;
      _shareSubscription = handler.sharedMediaStream.listen(
        _queueSharedMedia,
        onError: (Object error) =>
            _database.saveLog('Falha no compartilhamento', '$error'),
      );
      final initial = await handler.getInitialSharedMedia();
      if (initial != null) {
        _queueSharedMedia(initial);
        await handler.resetInitialSharedMedia();
      }
    } catch (error) {
      await _database.saveLog(
        'Não foi possível iniciar o compartilhamento',
        '$error',
      );
    }
  }

  void _queueSharedMedia(SharedMedia media) {
    _shareQueue = _shareQueue.then((_) => _importSharedMedia(media)).catchError((
      Object error,
    ) async {
      await _database.saveLog(
        'Falha ao importar fotos compartilhadas',
        '$error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível importar as fotos. Os originais foram preservados.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _importSharedMedia(SharedMedia media) async {
    final paths = (media.attachments ?? [])
        .where((item) => item?.type == SharedAttachmentType.image)
        .map((item) => item!.path)
        .toSet();
    final imported = <Photo>[];
    var failed = 0;
    // Salva todas as imagens antes de iniciar a rede. Cada falha é independente.
    for (final path in paths) {
      try {
        imported.add(await _saveLocalPhoto(File(path)));
      } catch (error) {
        failed++;
        await _database.saveLog(
          'Falha ao importar uma foto compartilhada',
          '$error',
        );
      }
    }
    await _loadPhotos();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${imported.length} foto(s) recebida(s). ${_configured ? 'Enviando para a turma configurada.' : 'Configure o Prisma e toque em Enviar.'}${failed > 0 ? ' $failed foto(s) não puderam ser importadas.' : ''}',
          ),
        ),
      );
    }
    if (_configured) {
      for (final photo in imported) {
        await _upload(photo);
      }
    }
  }

  Future<void> _cleanSyncedPhotos() async {
    try {
      await _performSyncedCleanup();
    } catch (error) {
      await _database.saveLog(
        'Não foi possível iniciar a limpeza de espaço',
        '$error',
      );
    }
  }

  Future<void> _performSyncedCleanup() async {
    if (!(await _api.loadConfig()).autoDeleteSynced) return;
    for (final photo in await _database.getPhotos()) {
      try {
        if (await _storage.deleteSyncedCopy(photo)) {
          await _database.deletePhoto(photo.id);
        }
      } catch (error) {
        // Uma falha na limpeza nunca transforma um envio confirmado em erro.
        await _database.saveLog(
          'Foto enviada, mas não foi possível liberar espaço',
          '$error',
        );
      }
    }
    await _loadPhotos();
  }

  Future<void> _upload(Photo photo) async {
    if (!_uploading.add(photo.id)) return;
    try {
      await _database.updatePhotoStatus(photo.id, SyncStatus.syncing);
      await _loadPhotos();
      final remoteId = await _api.uploadPhoto(File(photo.localPath));
      await _database.updatePhotoStatus(
        photo.id,
        SyncStatus.synced,
        prismaPhotoId: remoteId,
      );
      await _cleanSyncedPhotos();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto enviada ao Prisma com sucesso.')),
        );
      }
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      await _database.updatePhotoStatus(
        photo.id,
        SyncStatus.error,
        uploadError: message,
      );
      await _database.saveLog('Falha no envio ao Prisma', message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A foto ficou salva. Tente enviar novamente: $message',
            ),
          ),
        );
      }
    } finally {
      _uploading.remove(photo.id);
      await _loadPhotos();
    }
  }

  Future<void> _syncPending() async {
    if (_syncingAll) return;
    setState(() => _syncingAll = true);
    for (final photo in _photos.where(
      (item) =>
          item.status == SyncStatus.pending || item.status == SyncStatus.error,
    )) {
      await _upload(photo);
    }
    if (mounted) setState(() => _syncingAll = false);
  }

  Future<void> _openCamera() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(onCapture: _handleCapture),
      ),
    );
    await _loadPhotos();
  }

  Future<void> _openSettings({bool initialSetup = false}) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialSetup: initialSetup,
          onSaved: _cleanSyncedPhotos,
        ),
      ),
    );
    if (mounted) {
      final configured = await _api.hasSavedConfig();
      if (mounted) setState(() => _configured = configured);
      await _cleanSyncedPhotos();
    }
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  void _openPhoto(int index) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                PhotoViewerScreen(photos: _photos, initialIndex: index),
          ),
        )
        .then((_) => _loadPhotos());
  }

  @override
  Widget build(BuildContext context) {
    final pending = _photos
        .where((item) => item.status != SyncStatus.synced)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tinhaphone', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              'Câmera escolar',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configurações',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPhotos,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: pending == 0
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        child: Icon(
                          pending == 0
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_upload_outlined,
                          color: pending == 0
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              !_configured
                                  ? 'Configure o acesso ao Prisma'
                                  : pending == 0
                                  ? 'Tudo enviado'
                                  : '$pending foto(s) aguardando envio',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              !_configured
                                  ? 'Informe a API, o usuário e a turma antes de fotografar.'
                                  : 'As fotos enviadas aparecem automaticamente no Prisma.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_configured)
                        TextButton(
                          onPressed: () => _openSettings(initialSetup: true),
                          child: const Text('Configurar'),
                        )
                      else if (pending > 0)
                        TextButton(
                          onPressed: _syncingAll ? null : _syncPending,
                          child: _syncingAll
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Enviar'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_photos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_camera_outlined,
                        size: 56,
                        color: Colors.black38,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Nenhuma foto ainda',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Use o botão abaixo para registrar a rotina escolar.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    final photo = _photos[index];
                    return InkWell(
                      onTap: () => _openPhoto(index),
                      borderRadius: BorderRadius.circular(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(photo.localPath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFFE2E8F0),
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: _StatusBadge(
                                photo: photo,
                                onRetry: () => _upload(photo),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _configured
            ? _openCamera
            : () => _openSettings(initialSetup: true),
        icon: const Icon(Icons.camera_alt_outlined),
        label: Text(_configured ? 'Tirar foto' : 'Configurar acesso'),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Photo photo;
  final VoidCallback onRetry;
  const _StatusBadge({required this.photo, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (photo.status == SyncStatus.syncing)
      return const CircleAvatar(
        radius: 14,
        backgroundColor: Colors.white,
        child: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    final sent = photo.status == SyncStatus.synced;
    return InkWell(
      onTap: sent ? null : onRetry,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: sent ? Colors.green.shade600 : Colors.red.shade600,
        child: Icon(
          sent ? Icons.check : Icons.refresh,
          size: 16,
          color: Colors.white,
        ),
      ),
    );
  }
}
