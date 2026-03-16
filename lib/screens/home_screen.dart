import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../services/db_service.dart';
import '../services/drive_service.dart';
import '../models/photo.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DbService _dbService = DbService();
  final DriveService _driveService = DriveService();

  List<Photo> _photos = [];
  bool _isConnected = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _checkDriveConnection();
  }

  Future<void> _loadPhotos() async {
    final photos = await _dbService.getPhotos();
    setState(() {
      _photos = photos;
    });
  }

  Future<void> _checkDriveConnection() async {
    await _driveService.signInSilently();
    final isConnected = await _driveService.isSignedIn;
    setState(() {
      _isConnected = isConnected;
    });
  }

  Future<void> _connectDrive() async {
    try {
      await _driveService.signIn();
      setState(() {
        _isConnected = true;
      });
      // We no longer prompt for folder immediately, as the user can set it in Settings.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao conectar no Google Drive: $e')),
      );
    }
  }

  Future<void> _handleCapture(XFile file) async {
    // Save to local directory
    final appDir = await getApplicationDocumentsDirectory();
    final String uuid = const Uuid().v4();

    final dt = DateTime.now();
    final timestamp = dt.millisecondsSinceEpoch;
    final String filename =
        '${dt.year}_${dt.month.toString().padLeft(2, '0')}_${dt.day.toString().padLeft(2, '0')}_$timestamp.jpg';

    final String localPath = '${appDir.path}/$filename';

    final savedFile = await File(file.path).copy(localPath);

    final photo = Photo(
      id: uuid,
      localPath: savedFile.path,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await _dbService.savePhoto(photo);
    await _loadPhotos();
  }

  Future<void> _syncPhoto(Photo photo) async {
    if (!_isConnected) {
      await _connectDrive();
      if (!_isConnected) return;
    }

    try {
      await _dbService.updatePhotoStatus(photo.id, SyncStatus.syncing);
      await _loadPhotos();

      final file = File(photo.localPath);
      final dt = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final filename =
          '${dt.year}_${dt.month.toString().padLeft(2, '0')}_${dt.day.toString().padLeft(2, '0')}_${photo.timestamp}.jpg';

      final driveId = await _driveService.uploadFile(file, filename);

      final prefs = await SharedPreferences.getInstance();
      final bool autoDelete = prefs.getBool('auto_delete') ?? false;

      if (autoDelete) {
        await _dbService.deletePhoto(photo.id);
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await _dbService.updatePhotoStatus(
          photo.id,
          SyncStatus.synced,
          driveFileId: driveId,
        );
      }
    } catch (e) {
      print('Sync Error: $e');
      await _dbService.updatePhotoStatus(photo.id, SyncStatus.error);
    } finally {
      await _loadPhotos();
    }
  }

  Future<void> _syncAllPending() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    final pendingPhotos = _photos
        .where(
          (p) => p.status == SyncStatus.pending || p.status == SyncStatus.error,
        )
        .toList();
    for (final photo in pendingPhotos) {
      await _syncPhoto(photo);
    }

    setState(() {
      _isSyncing = false;
    });
  }

  Future<void> _handleDelete(Photo photo) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Foto?'),
        content: const Text(
          'Isso apagará permanentemente a foto do seu dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbService.deletePhoto(photo.id);
      final file = File(photo.localPath);
      if (await file.exists()) {
        await file.delete();
      }
      await _loadPhotos();
    }
  }

  Future<void> _clearSynced() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar Fotos Sincronizadas?'),
        content: const Text(
          'Isso apagará todas as fotos já sincronizadas do seu dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final syncedPhotos = _photos
          .where((p) => p.status == SyncStatus.synced)
          .toList();
      for (final photo in syncedPhotos) {
        final file = File(photo.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      await _dbService.clearSyncedPhotos();
      await _loadPhotos();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.cloud, color: Colors.indigo),
            const SizedBox(width: 8),
            const Text(
              'Tinha Phone',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ).then((_) {
                  // refresh in case connection or folder changed
                  _checkDriveConnection();
                  setState(() {});
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: _isConnected
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Conectado',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _connectDrive,
                      icon: const Icon(Icons.cloud_upload, size: 16),
                      label: const Text('Conectar Drive'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_photos.length} foto${_photos.length != 1 ? 's' : ''} local${_photos.length != 1 ? 'is' : ''}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed:
                            _photos.any((p) => p.status == SyncStatus.synced)
                            ? _clearSynced
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Limpar Sinc.'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed:
                            (_isSyncing ||
                                !_photos.any(
                                  (p) =>
                                      p.status == SyncStatus.pending ||
                                      p.status == SyncStatus.error,
                                ))
                            ? null
                            : _syncAllPending,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync, size: 16),
                        label: const Text('Sinc. Todas'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _photos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Nenhuma foto no cofre.',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          const Text(
                            'Toque no botão abaixo para capturar.',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: _photos.length,
                      itemBuilder: (context, index) {
                        final photo = _photos[index];
                        return PhotoCard(
                          photo: photo,
                          onSync: () => _syncPhoto(photo),
                          onDelete: () => _handleDelete(photo),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CameraScreen(onCapture: _handleCapture),
              fullscreenDialog: true,
            ),
          );
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
    );
  }
}

class PhotoCard extends StatelessWidget {
  final Photo photo;
  final VoidCallback onSync;
  final VoidCallback onDelete;

  const PhotoCard({
    Key? key,
    required this.photo,
    required this.onSync,
    required this.onDelete,
  }) : super(key: key);

  Color _getStatusColor() {
    switch (photo.status) {
      case SyncStatus.pending:
        return Colors.grey.shade600;
      case SyncStatus.syncing:
        return Colors.blue.shade500;
      case SyncStatus.synced:
        return Colors.green.shade500;
      case SyncStatus.error:
        return Colors.red.shade500;
    }
  }

  IconData _getStatusIcon() {
    switch (photo.status) {
      case SyncStatus.pending:
        return Icons.cloud_off;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.synced:
        return Icons.cloud_done;
      case SyncStatus.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(photo.localPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getStatusColor().withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(_getStatusIcon(), size: 12, color: Colors.white),
            ),
          ),
          // Hover actions (visible on tap in mobile)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (photo.status == SyncStatus.pending ||
                              photo.status == SyncStatus.error)
                            ListTile(
                              leading: const Icon(
                                Icons.cloud_upload,
                                color: Colors.indigo,
                              ),
                              title: const Text('Tentar Sincronizar'),
                              onTap: () {
                                Navigator.pop(context);
                                onSync();
                              },
                            ),
                          ListTile(
                            leading: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                            title: const Text(
                              'Excluir Foto',
                              style: TextStyle(color: Colors.red),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              onDelete();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
