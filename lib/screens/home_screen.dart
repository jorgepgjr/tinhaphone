import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/db_service.dart';
import '../services/drive_service.dart';
import '../models/photo.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';
import 'photo_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_handler/share_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DbService _dbService = DbService();
  final DriveService _driveService = DriveService();

  List<Photo> _photos = [];
  bool _isConnected = false;
  bool _isSyncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<SharedMedia>? _sharedMediaSubscription;
  
  Set<String> _selectedPhotoIds = {};
  bool get _isSelectionMode => _selectedPhotoIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedPhotoIds.contains(id)) {
        _selectedPhotoIds.remove(id);
      } else {
        _selectedPhotoIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPhotoIds.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPhotos();
    _checkDriveConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _initShareHandler();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _sharedMediaSubscription?.cancel();
    super.dispose();
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      _syncScheduled();
    }
  }

  Future<void> _syncScheduled() async {
    if (_isSyncing) return;
    
    await _loadPhotos();
    final scheduledPhotos = _photos.where((p) => p.status == SyncStatus.scheduled).toList();
    
    if (scheduledPhotos.isEmpty) return;

    setState(() {
      _isSyncing = true;
    });

    for (final photo in scheduledPhotos) {
      await _syncPhoto(photo);
    }

    setState(() {
      _isSyncing = false;
    });
  }

  Future<void> _initShareHandler() async {
    final handler = ShareHandlerPlatform.instance;
    
    final initialMedia = await handler.getInitialSharedMedia();
    if (initialMedia != null) {
      _processSharedMedia(initialMedia);
    }

    _sharedMediaSubscription = handler.sharedMediaStream.listen((SharedMedia media) {
      if (!mounted) return;
      _processSharedMedia(media);
    });
  }

  Future<void> _processSharedMedia(SharedMedia media) async {
    if (media.attachments == null || media.attachments!.isEmpty) return;

    final appDir = await getApplicationDocumentsDirectory();
    
    for (final attachment in media.attachments!) {
      if (attachment != null && attachment.path != null) {
        final sourceFile = File(attachment.path!);
        if (await sourceFile.exists()) {
          final String uuid = const Uuid().v4();
          final dt = DateTime.now();
          final timestamp = dt.millisecondsSinceEpoch;
          final String filename =
              '${dt.year}_${dt.month.toString().padLeft(2, '0')}_${dt.day.toString().padLeft(2, '0')}_${timestamp}_${uuid.substring(0, 4)}.jpg';
          final String localPath = '${appDir.path}/$filename';

          final savedFile = await sourceFile.copy(localPath);

          final photo = Photo(
            id: uuid,
            localPath: savedFile.path,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );

          await _dbService.savePhoto(photo);
        }
      }
    }
    
    await _loadPhotos();
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

  Future<void> _disconnectDrive() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar do Drive?'),
        content: const Text(
          'Tem certeza que deseja deslogar sua conta do Google Drive?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _driveService.signOut();
      if (mounted) {
        setState(() {
          _isConnected = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Desconectado do Google Drive com sucesso.')),
        );
      }
    }
  }

  Future<Photo> _handleCapture(XFile file) async {
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
    return photo;
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

    final prefs = await SharedPreferences.getInstance();
    final wifiOnlySync = prefs.getBool('wifi_only_sync') ?? false;

    if (wifiOnlySync) {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        final pendingPhotos = _photos.where((p) => p.status == SyncStatus.pending || p.status == SyncStatus.error).toList();
        for (final photo in pendingPhotos) {
          await _dbService.updatePhotoStatus(photo.id, SyncStatus.scheduled);
        }
        await _loadPhotos();
        if (mounted && pendingPhotos.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronização agendada para quando houver Wi-Fi.')),
          );
        }
        return;
      }
    }

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

  Future<void> _syncSelected() async {
    if (_isSyncing || _selectedPhotoIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final wifiOnlySync = prefs.getBool('wifi_only_sync') ?? false;

    final selectedPhotos = _photos
        .where((p) => _selectedPhotoIds.contains(p.id) && (p.status == SyncStatus.pending || p.status == SyncStatus.error || p.status == SyncStatus.scheduled))
        .toList();

    if (wifiOnlySync) {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.contains(ConnectivityResult.wifi)) {
        for (final photo in selectedPhotos) {
          if (photo.status != SyncStatus.scheduled) {
            await _dbService.updatePhotoStatus(photo.id, SyncStatus.scheduled);
          }
        }
        await _loadPhotos();
        if (mounted && selectedPhotos.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronização agendada para quando houver Wi-Fi.')),
          );
        }
        setState(() {
          _selectedPhotoIds.clear();
        });
        return;
      }
    }

    setState(() {
      _isSyncing = true;
    });

    final photosToSync = _photos
        .where((p) => _selectedPhotoIds.contains(p.id) && (p.status == SyncStatus.pending || p.status == SyncStatus.error))
        .toList();
        
    for (final photo in photosToSync) {
      await _syncPhoto(photo);
    }

    setState(() {
      _isSyncing = false;
      _selectedPhotoIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedPhotoIds.isEmpty) return;
    
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir Fotos Selecionadas?'),
        content: Text('Isso apagará permanentemente as ${_selectedPhotoIds.length} fotos selecionadas do seu dispositivo.'),
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
      for (final id in _selectedPhotoIds) {
        await _dbService.deletePhoto(id);
        final photo = _photos.firstWhere((p) => p.id == id);
        final file = File(photo.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
      setState(() {
        _selectedPhotoIds.clear();
      });
      await _loadPhotos();
    }
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TinhaPhone',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
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
                  ? GestureDetector(
                      onTap: _disconnectDrive,
                      child: Tooltip(
                        message: 'Conectado ao Drive (Toque para deslogar)',
                        child: Stack(
                          children: [
                            const Icon(
                              Icons.add_to_drive,
                              color: Colors.indigo,
                              size: 28,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade500,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                          isSelected: _selectedPhotoIds.contains(photo.id),
                          onSync: () => _syncPhoto(photo),
                          onDelete: () => _handleDelete(photo),
                          onTap: () async {
                            if (_isSelectionMode) {
                              _toggleSelection(photo.id);
                            } else {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PhotoViewerScreen(
                                    photos: _photos,
                                    initialIndex: index,
                                  ),
                                ),
                              );
                              _loadPhotos();
                            }
                          },
                          onLongPress: () {
                            _toggleSelection(photo.id);
                          },
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: _clearSelection,
                        child: const Icon(Icons.close, color: Colors.grey, size: 20),
                      ),
                    ),
                  Text(
                    _isSelectionMode 
                      ? '${_selectedPhotoIds.length} selecionadas'
                      : '${_photos.length} foto${_photos.length != 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isSelectionMode)
                      TextButton(
                        onPressed: _deleteSelected,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Excluir'),
                      ),
                    if (_isSelectionMode)
                      const SizedBox(width: 4),
                    Flexible(
                      child: ElevatedButton.icon(
                        onPressed: _isSelectionMode
                            ? (_isSyncing || !_photos.any((p) => _selectedPhotoIds.contains(p.id) && (p.status == SyncStatus.pending || p.status == SyncStatus.error || p.status == SyncStatus.scheduled)) ? null : _syncSelected)
                            : (_isSyncing || !_photos.any((p) => p.status == SyncStatus.pending || p.status == SyncStatus.error || p.status == SyncStatus.scheduled) ? null : _syncAllPending),
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync, size: 16),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_isSelectionMode ? 'Sinc. Selecionadas' : 'Sinc. Todas'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoCard extends StatelessWidget {
  final Photo photo;
  final VoidCallback onSync;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;

  const PhotoCard({
    super.key,
    required this.photo,
    required this.onSync,
    required this.onDelete,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
  });

  Color _getStatusColor() {
    switch (photo.status) {
      case SyncStatus.pending:
        return Colors.grey.shade600;
      case SyncStatus.scheduled:
        return Colors.orange.shade500;
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
      case SyncStatus.scheduled:
        return Icons.access_time;
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
                onTap: onTap,
                onLongPress: onLongPress,
              ),
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.blue.withOpacity(0.4),
                  child: const Center(
                    child: Icon(Icons.check_circle, color: Colors.white, size: 40),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
