import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../widgets/tinha_brand.dart';
import '../auth/mobile_session.dart';
import '../models/photo.dart';
import '../services/db_service.dart';
import '../services/drive_service.dart';
import '../services/prisma_api_service.dart';
import '../services/local_photo_storage.dart';
import 'camera_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final MobileSession session;
  final SessionController controller;
  final DbService? database;
  const HomeScreen({
    super.key,
    required this.session,
    required this.controller,
    this.database,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _database = widget.database ?? DbService(widget.session.scope);
  late final _api = PrismaApiService(
    widget.session,
    onUnauthorized: () => widget.controller.invalidate(widget.session),
    client: widget.controller.api.client,
  );
  late final _storage = LocalPhotoStorage.forAccount(widget.session.scope);
  late final _drive = DriveService(widget.session.scope);
  final Set<String> _uploading = {};
  final Set<String> _driveUploading = {};
  StreamSubscription<SharedMedia>? _shareSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Map<String, int> _automaticAttempts = {};
  bool _offline = false;
  Future<void> _shareQueue = Future.value();
  List<Photo> _photos = [];
  List<Map<String, dynamic>> _classes = [];
  PrismaConfig _config = const PrismaConfig();
  bool _syncingAll = false, _loadingClasses = true;
  bool _driveConnected = false, _driveBusy = false, _driveSyncingAll = false;
  bool _driveAutoDelete = false;
  String? _classError;
  String _statusFilter = 'Todas';
  String _dateFilter = 'Todas';
  DateTimeRange? _customRange;
  final Set<int> _tagFilter = {};
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _tags = [];
  bool get _alive => mounted && widget.controller.owns(widget.session);
  bool get _configured => _classes.any((item) => item['id'] == _config.classId);
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  void _feedback(String message) {
    if (_alive) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _bootstrap() async {
    try {
      await _database.recoverInterruptedUploads();
      _config = await _api.loadConfig();
      await _loadPhotos();
      await _loadClasses();
      await _loadPhotos();
      await _loadTags();
      if (!_alive) return;
      try {
        await _drive.signInSilently();
        _driveConnected = await _drive.isSignedIn;
        _driveAutoDelete = _drive.autoDeleteAfterUpload;
        if (_alive) setState(() {});
      } catch (error) {
        await _database.saveLog('Drive indisponível', '$error');
      }
      if (!_alive) return;
      await _retryPendingTags();
      await _cleanSyncedPhotos();
      if (_alive) await _initSharing();
      if (_alive) _watchConnection();
    } catch (_) {
      if (_alive) {
        setState(() {
          _loadingClasses = false;
          _classError =
              'Não foi possível abrir os dados locais. Tente novamente.';
        });
      }
    }
  }

  Future<void> _loadClasses() async {
    if (_alive) {
      setState(() {
        _loadingClasses = true;
        _classError = null;
      });
    }
    try {
      final classes = await _api.getClasses();
      if (!_alive) return;
      setState(() => _classes = classes);
      if (!_configured) {
        _config = PrismaConfig(autoDeleteSynced: _config.autoDeleteSynced);
        await _api.saveConfig(_config);
      }
    } catch (error) {
      if (_alive) {
        setState(() {
          _classes = [];
          _classError =
              'Não foi possível carregar suas turmas. Confira a conexão e atualize.';
        });
      }
    } finally {
      if (_alive) setState(() => _loadingClasses = false);
    }
  }

  Future<void> _refresh() async {
    await _loadClasses();
    if (_alive) await _loadPhotos();
    if (_alive) await _loadTags();
  }

  void _watchConnection() {
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        if (!_alive) return;
        final offline = results.every(
          (value) => value == ConnectivityResult.none,
        );
        final wasOffline = _offline;
        setState(() => _offline = offline);
        if (wasOffline && !offline) _resumePending();
      });
    } catch (_) {
      /* O envio manual continua disponível. */
    }
  }

  Future<void> _resumePending() async {
    if (!_alive || _syncingAll) return;
    await _retryPendingTags();
    await _cleanSyncedPhotos();
    for (final photo in await _database.getPhotos()) {
      if (!_alive || _offline) break;
      if (photo.status != SyncStatus.pending &&
          photo.status != SyncStatus.error)
        continue;
      final attempts = _automaticAttempts[photo.id] ?? 0;
      if (attempts >= 3) continue;
      _automaticAttempts[photo.id] = attempts + 1;
      await _upload(photo);
    }
  }

  Future<void> _loadTags() async {
    try {
      final tags = await _api.getTags();
      if (_alive) setState(() => _tags = tags);
    } catch (_) {
      /* O catálogo permanece disponível após falha temporária. */
    }
  }

  Future<void> _retryPendingTags() async {
    for (final photo in await _database.getPhotos()) {
      if (!_alive) return;
      if (!photo.tagSyncPending ||
          photo.prismaPhotoId == null ||
          photo.tagIds.isEmpty)
        continue;
      try {
        await _api.updateTags([photo.prismaPhotoId!], photo.tagIds);
        await _database.setTagSyncPending(photo.id, false);
      } catch (_) {
        /* Associação permanece pendente para a próxima conexão. */
      }
    }
  }

  Future<void> _selectClass(int? id) async {
    if (!_alive || widget.controller.busy) return;
    _config = PrismaConfig(
      classId: id,
      autoDeleteSynced: _config.autoDeleteSynced,
    );
    await _api.saveConfig(_config);
    _selected.clear();
    _tagFilter.clear();
    if (_alive) await _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final local = await _database.getPhotos();
    final photos = local
        .where((photo) => photo.classId == _config.classId)
        .toList();
    if (_configured) {
      try {
        final remote = await _api.getClassPhotos(_config.classId!);
        final localRemoteIds = local.map((item) => item.prismaPhotoId).toSet();
        for (final item in remote) {
          final id = item['id'] as int;
          if (localRemoteIds.contains(id)) continue;
          photos.add(
            Photo(
              id: 'remote_$id',
              localPath: '',
              timestamp: DateTime.parse(
                item['created_at'] as String,
              ).millisecondsSinceEpoch,
              status: SyncStatus.synced,
              prismaPhotoId: id,
              accountScope: widget.session.scope,
              ownerId: widget.session.account.id,
              schoolId: widget.session.account.schoolId,
              server: widget.session.baseUrl,
              classId: _config.classId,
              mediaUrl: item['media_url'] == null
                  ? null
                  : Uri.parse(
                      widget.session.baseUrl,
                    ).resolve(item['media_url'] as String).toString(),
              tagIds: ((item['tags'] as List?) ?? [])
                  .map((tag) => (tag as Map)['id'] as int)
                  .toList(),
            ),
          );
        }
      } catch (_) {
        /* A fila local continua visível sem conexão. */
      }
    }
    photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (_alive) setState(() => _photos = photos);
  }

  Future<Photo> _saveLocalPhoto(File source, int classId) async {
    final photo = await _storage.importPhoto(
      source,
      session: widget.session,
      classId: classId,
    );
    await _database.savePhoto(photo);
    try {
      await _storage.deleteTemporaryCopy(source);
    } catch (error) {
      await _database.saveLog('Falha ao limpar cache', '$error');
    }
    return photo;
  }

  Future<Photo?> _handleCapture(XFile file) async {
    if (!_configured || !widget.controller.beginWork(widget.session)) {
      return null;
    }
    final classId = _config.classId!;
    try {
      final photo = await _saveLocalPhoto(File(file.path), classId);
      await _loadPhotos();
      if (_alive) await _upload(photo);
      final remaining = await _database.getPhotos();
      return remaining.where((item) => item.id == photo.id).firstOrNull;
    } finally {
      await widget.controller.endWork();
    }
  }

  Future<void> _initSharing() async {
    try {
      final handler = ShareHandler.instance;
      _shareSubscription = handler.sharedMediaStream.listen(
        _queueSharedMedia,
        onError: (Object e) =>
            _database.saveLog('Falha no compartilhamento', '$e'),
      );
      final initial = await handler.getInitialSharedMedia();
      if (initial != null && _alive) {
        _queueSharedMedia(initial);
        await handler.resetInitialSharedMedia();
      }
    } catch (error) {
      await _database.saveLog('Compartilhamento indisponível', '$error');
    }
  }

  void _queueSharedMedia(SharedMedia media) {
    final destination = _config.classId;
    _shareQueue = _shareQueue
        .then((_) async {
          if (!_alive) return;
          if (destination == null ||
              !_classes.any((item) => item['id'] == destination)) {
            _feedback(
              'Selecione uma turma antes de compartilhar as fotos novamente. Os originais foram preservados.',
            );
            return;
          }
          if (!widget.controller.beginWork(widget.session)) return;
          try {
            final paths = (media.attachments ?? [])
                .where((item) => item?.type == SharedAttachmentType.image)
                .map((item) => item!.path)
                .toSet();
            final imported = <Photo>[];
            for (final path in paths) {
              try {
                final photo = await _saveLocalPhoto(File(path), destination);
                imported.add(photo);
              } catch (error) {
                await _database.saveLog('Falha ao importar foto', '$error');
              }
            }
            for (final photo in imported) {
              if (!_alive) break;
              await _upload(photo);
            }
            await _loadPhotos();
            _feedback(
              '${imported.length} foto(s) recebida(s). Os originais da galeria foram preservados.',
            );
          } finally {
            await widget.controller.endWork();
          }
        })
        .catchError(
          (Object error) => _feedback(
            'Não foi possível importar as fotos. Os originais foram preservados.',
          ),
        );
  }

  Future<void> _cleanSyncedPhotos() async {
    try {
      await _performSyncedCleanup();
    } catch (error) {
      // Falha de limpeza nunca transforma um envio confirmado em pendência.
      try {
        await _database.saveLog(
          'Envio preservado; limpeza não concluída',
          '$error',
        );
      } catch (_) {}
      _feedback(
        'As fotos enviadas estão no Prisma, mas não foi possível concluir a limpeza local.',
      );
    }
  }

  Future<void> _performSyncedCleanup() async {
    if (!_config.autoDeleteSynced && !_driveAutoDelete) return;
    for (final photo in await _database.getPhotos()) {
      try {
        final prismaConfirmed = photo.status == SyncStatus.synced;
        final driveConfirmed = photo.driveFileId != null;
        final shouldDelete =
            prismaConfirmed &&
            (_driveAutoDelete ? driveConfirmed : _config.autoDeleteSynced);
        if (shouldDelete &&
            !photo.tagSyncPending &&
            _api.owns(photo) &&
            await _storage.deleteSyncedCopy(photo)) {
          await _database.deletePhoto(photo.id);
        }
      } catch (error) {
        await _database.saveLog(
          'Foto enviada; não foi possível liberar espaço',
          '$error',
        );
      }
    }
    await _loadPhotos();
  }

  Future<void> _upload(Photo photo) async {
    if (!_alive ||
        !_api.owns(photo) ||
        _uploading.contains(photo.id) ||
        !widget.controller.beginWork(widget.session)) {
      return;
    }
    _uploading.add(photo.id);
    try {
      await _database.updatePhotoStatus(photo.id, SyncStatus.syncing);
      await _loadPhotos();
      final id = await _api.uploadPhoto(photo);
      await _database.updatePhotoStatus(
        photo.id,
        SyncStatus.synced,
        prismaPhotoId: id,
      );
      if (photo.tagIds.isNotEmpty) {
        try {
          await _api.updateTags([id], photo.tagIds);
        } catch (error) {
          await _database.setTagSyncPending(photo.id, true);
          await _database.saveLog(
            'Foto enviada; tags pendentes de atualização',
            '$error',
          );
        }
      }
      await _cleanSyncedPhotos();
      _feedback('Foto enviada ao Prisma com sucesso.');
    } catch (error) {
      await _database.updatePhotoStatus(
        photo.id,
        SyncStatus.error,
        uploadError: '$error',
      );
      await _database.saveLog('Falha no envio ao Prisma', '$error');
      _feedback('A foto ficou salva. Tente enviar novamente.');
    } finally {
      _uploading.remove(photo.id);
      try {
        await _loadPhotos();
      } finally {
        await widget.controller.endWork();
      }
    }
  }

  Future<void> _syncPending() async {
    if (_syncingAll || !widget.controller.beginWork(widget.session)) return;
    setState(() => _syncingAll = true);
    try {
      for (final photo in List<Photo>.of(_photos).where(
        (p) => p.status == SyncStatus.pending || p.status == SyncStatus.error,
      )) {
        if (!_alive) break;
        await _upload(photo);
      }
    } finally {
      if (mounted) setState(() => _syncingAll = false);
      await widget.controller.endWork();
    }
  }

  Future<bool> _connectDrive() async {
    if (!_alive) return false;
    if (_driveConnected && await _drive.isSignedIn) return true;
    if (_driveBusy) return false;
    setState(() {
      _driveBusy = true;
    });
    try {
      await _drive.signIn();
      if (!_alive) return false;
      setState(() => _driveConnected = true);
      return true;
    } catch (_) {
      _feedback(
        'Não foi possível conectar ao Google Drive. Confira a conta e tente novamente.',
      );
      return false;
    } finally {
      if (_alive) setState(() => _driveBusy = false);
    }
  }

  String _driveFilename(Photo photo) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final extension = p.extension(photo.localPath);
    return '${date.year}_${date.month.toString().padLeft(2, '0')}_${date.day.toString().padLeft(2, '0')}_${photo.timestamp}${extension.isEmpty ? '.jpg' : extension}';
  }

  Future<void> _backupToDrive(Photo photo) async {
    if (!_alive ||
        !_api.owns(photo) ||
        photo.driveFileId != null ||
        _driveUploading.contains(photo.id)) {
      return;
    }
    if (!widget.controller.beginWork(widget.session)) return;
    _driveUploading.add(photo.id);
    if (_alive) setState(() {});
    try {
      if (!await _connectDrive()) return;
      if (!_alive || !_api.owns(photo)) return;
      final id = await _drive.uploadFile(
        File(photo.localPath),
        _driveFilename(photo),
      );
      if (!_alive) return;
      await _database.updateDriveUpload(photo.id, driveFileId: id);
      await _cleanSyncedPhotos();
      await _loadPhotos();
      _feedback('Foto salva no Google Drive.');
    } catch (error) {
      try {
        await _database.updateDriveUpload(photo.id, error: '$error');
        await _database.saveLog(
          'Falha ao enviar foto para o Google Drive',
          '$error',
        );
      } catch (_) {}
      _feedback(
        'Não foi possível salvar no Google Drive. A foto foi mantida no app.',
      );
    } finally {
      _driveUploading.remove(photo.id);
      try {
        if (_alive) await _loadPhotos();
      } finally {
        await widget.controller.endWork();
      }
    }
  }

  Future<void> _backupPendingToDrive() async {
    if (_driveSyncingAll || !_alive || !_configured) return;
    final connected = await _connectDrive();
    if (!connected || !_alive) return;
    setState(() => _driveSyncingAll = true);
    try {
      final pending = (await _database.getPhotos())
          .where((photo) => photo.driveFileId == null)
          .toList();
      for (final photo in pending) {
        if (!_alive) break;
        await _backupToDrive(photo);
      }
    } finally {
      if (_alive) setState(() => _driveSyncingAll = false);
    }
  }

  Future<void> _openCamera() async {
    if (!_configured || !_alive) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CameraScreen(onCapture: _handleCapture, database: _database),
      ),
    );
    if (_alive) await _loadPhotos();
  }

  Future<void> _importGallery() async {
    if (!_configured || !_alive) return;
    final destination = _config.classId!;
    try {
      final images = await ImagePicker().pickMultiImage(imageQuality: 92);
      if (images.isEmpty ||
          !_alive ||
          !widget.controller.beginWork(widget.session))
        return;
      try {
        final imported = <Photo>[];
        for (final image in images) {
          if (!_alive) break;
          imported.add(await _saveLocalPhoto(File(image.path), destination));
        }
        await _loadPhotos();
        for (final photo in imported) {
          if (!_alive) break;
          await _upload(photo);
        }
        _feedback('${imported.length} foto(s) importada(s).');
      } finally {
        await widget.controller.endWork();
      }
    } catch (error) {
      _feedback(
        'Não foi possível importar as fotos. Verifique a permissão da galeria.',
      );
    }
  }

  Future<void> _addPhotos() async {
    if (_loadingClasses) {
      _feedback('Aguarde o carregamento das turmas.');
      return;
    }
    if (_classError != null) {
      _feedback(
        'Não foi possível carregar as turmas. Atualize e tente novamente.',
      );
      return;
    }
    if (_classes.isEmpty) {
      _feedback('Você ainda não tem turmas. Peça o vínculo à coordenação.');
      return;
    }
    if (!_configured) {
      await _chooseClass();
      if (!_alive || !_configured) return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adicionar fotos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tirar foto'),
                subtitle: const Text('Abrir a câmera do celular'),
                onTap: () {
                  Navigator.pop(sheet);
                  _openCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Escolher da galeria'),
                subtitle: const Text('Importar fotos do celular'),
                onTap: () {
                  Navigator.pop(sheet);
                  _importGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseClass() async {
    final id = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Selecionar turma',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            for (final item in _classes)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                title: Text(item['name'] as String),
                subtitle: Text(widget.session.account.schoolName ?? ''),
                trailing: item['id'] == _config.classId
                    ? const Icon(Icons.check_circle, color: tinhaBlue)
                    : null,
                onTap: () => Navigator.pop(sheet, item['id'] as int),
              ),
          ],
        ),
      ),
    );
    if (id != null && _alive) await _selectClass(id);
  }

  List<Photo> get _visiblePhotos {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    return _photos.where((photo) {
      if (_statusFilter == 'Enviando' &&
          photo.status != SyncStatus.syncing &&
          photo.status != SyncStatus.scheduled &&
          photo.status != SyncStatus.pending)
        return false;
      if (_statusFilter == 'Enviadas' && photo.status != SyncStatus.synced)
        return false;
      if (_statusFilter == 'Erro' && photo.status != SyncStatus.error)
        return false;
      final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      if (_dateFilter == 'Hoje' && date.isBefore(startToday)) return false;
      if (_dateFilter == 'Últimos 7 dias' &&
          date.isBefore(startToday.subtract(const Duration(days: 6))))
        return false;
      if (_dateFilter == 'Este mês' &&
          (date.year != now.year || date.month != now.month))
        return false;
      if (_dateFilter == 'Personalizado' &&
          _customRange != null &&
          (date.isBefore(_customRange!.start) ||
              date.isAfter(_customRange!.end.add(const Duration(days: 1)))))
        return false;
      if (_tagFilter.isNotEmpty && !_tagFilter.every(photo.tagIds.contains))
        return false;
      return true;
    }).toList();
  }

  void _showFilters() {
    var status = _statusFilter;
    var date = _dateFilter;
    final selectedTags = Set<int>.of(_tagFilter);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filtros',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          status = 'Todas';
                          date = 'Todas';
                          selectedTags.clear();
                        }),
                        child: const Text('Limpar tudo'),
                      ),
                    ],
                  ),
                  const Text('Status'),
                  Wrap(
                    spacing: 8,
                    children: ['Todas', 'Enviando', 'Enviadas', 'Erro']
                        .map(
                          (value) => ChoiceChip(
                            label: Text(value),
                            selected: status == value,
                            onSelected: (_) => update(() => status = value),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Data'),
                  Wrap(
                    spacing: 8,
                    children:
                        [
                              'Todas',
                              'Hoje',
                              'Últimos 7 dias',
                              'Este mês',
                              'Personalizado',
                            ]
                            .map(
                              (value) => ChoiceChip(
                                label: Text(value),
                                selected: date == value,
                                onSelected: (_) async {
                                  if (value == 'Personalizado') {
                                    final range = await showDateRangePicker(
                                      context: sheet,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                    );
                                    if (range == null) return;
                                    _customRange = range;
                                  }
                                  update(() => date = value);
                                },
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Tags'),
                  if (_tags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Nenhuma tag cadastrada.'),
                    ),
                  Wrap(
                    spacing: 8,
                    children: _tags.map((tag) {
                      final id = tag['id'] as int;
                      return FilterChip(
                        label: Text(tag['name'] as String),
                        selected: selectedTags.contains(id),
                        onSelected: (yes) => update(() {
                          if (yes) {
                            selectedTags.add(id);
                          } else {
                            selectedTags.remove(id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _statusFilter = status;
                          _dateFilter = date;
                          _tagFilter
                            ..clear()
                            ..addAll(selectedTags);
                        });
                        Navigator.pop(sheet);
                      },
                      child: const Text('Aplicar filtros'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Photo> get _selectedPhotos =>
      _photos.where((photo) => _selected.contains(photo.id)).toList();
  void _toggleSelection(Photo photo) => setState(() {
    if (!_selected.add(photo.id)) _selected.remove(photo.id);
  });

  Future<void> _moveSelected() async {
    final photos = _selectedPhotos;
    if (photos.any((p) => p.status == SyncStatus.syncing)) {
      _feedback('Aguarde o envio terminar.');
      return;
    }
    final destination = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Mover ${photos.length} foto(s) para outra turma',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final item in _classes.where(
              (item) => item['id'] != _config.classId,
            ))
              ListTile(
                title: Text(item['name'] as String),
                onTap: () => Navigator.pop(sheet, item['id'] as int),
              ),
          ],
        ),
      ),
    );
    if (destination == null || !_alive) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mover fotos?'),
        content: Text('${photos.length} foto(s) serão movidas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var moved = 0;
    for (final photo in photos) {
      try {
        if (photo.prismaPhotoId != null)
          await _api.movePhoto(photo.prismaPhotoId!, destination);
        if (!photo.id.startsWith('remote_'))
          await _database.movePhoto(photo.id, destination);
        moved++;
      } catch (_) {
        /* Contabiliza falhas para feedback parcial. */
      }
    }
    _selected.clear();
    await _loadPhotos();
    _feedback('$moved de ${photos.length} foto(s) movida(s).');
  }

  Future<void> _deleteSelected() async {
    final photos = _selectedPhotos;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Excluir ${photos.length} foto(s)?'),
        content: const Text(
          'A cópia local remove apenas arquivos gerenciados pelo app. Excluir do servidor remove o registro remoto quando permitido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'local'),
            child: const Text('Cópia local'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'remote'),
            child: const Text('Do servidor'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    var deleted = 0;
    for (final photo in photos) {
      if (photo.status == SyncStatus.syncing) continue;
      try {
        if (choice == 'remote') {
          if (photo.prismaPhotoId == null) continue;
          await _api.deleteRemotePhoto(photo.prismaPhotoId!);
        }
        if (photo.localPath.isNotEmpty &&
            await _storage.deleteManagedCopy(photo))
          await _database.deletePhoto(photo.id);
        if (photo.id.startsWith('remote_') && choice == 'local') continue;
        deleted++;
      } catch (_) {
        /* Falha parcial é informada ao final. */
      }
    }
    _selected.clear();
    await _loadPhotos();
    _feedback('$deleted de ${photos.length} foto(s) excluída(s).');
  }

  Future<void> _editTags(List<Photo> photos) async {
    if (photos.isEmpty) return;
    final chosen = <int>{};
    final search = TextEditingController();
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(sheet).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tags · ${photos.length} foto(s)',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Pesquisar ou criar tag',
                  ),
                  onChanged: (text) => update(() => query = text.trim()),
                ),
                if (query.isNotEmpty &&
                    !_tags.any(
                      (tag) =>
                          (tag['name'] as String).toLowerCase() ==
                          query.toLowerCase(),
                    ))
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Criar "$query"'),
                    onPressed: () async {
                      try {
                        final tag = await _api.createTag(query);
                        await _loadTags();
                        update(() {
                          chosen.add(tag['id'] as int);
                          query = '';
                          search.clear();
                        });
                      } catch (_) {
                        _feedback('Não foi possível criar a tag.');
                      }
                    },
                  ),
                Wrap(
                  spacing: 8,
                  children: _tags
                      .where(
                        (tag) => (tag['name'] as String).toLowerCase().contains(
                          query.toLowerCase(),
                        ),
                      )
                      .map((tag) {
                        final id = tag['id'] as int;
                        return FilterChip(
                          label: Text(tag['name'] as String),
                          selected: chosen.contains(id),
                          onSelected: (yes) => update(() {
                            if (yes) {
                              chosen.add(id);
                            } else {
                              chosen.remove(id);
                            }
                          }),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: chosen.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(sheet);
                                await _applyTags(
                                  photos,
                                  chosen.toList(),
                                  remove: true,
                                );
                              },
                        child: const Text('Remover tags'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: chosen.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(sheet);
                                await _applyTags(photos, chosen.toList());
                              },
                        child: const Text('Adicionar tags'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    search.dispose();
  }

  Future<void> _applyTags(
    List<Photo> photos,
    List<int> ids, {
    bool remove = false,
  }) async {
    var success = 0;
    for (final photo in photos) {
      try {
        if (photo.prismaPhotoId != null)
          await _api.updateTags([photo.prismaPhotoId!], ids, remove: remove);
        final next = Set<int>.of(photo.tagIds);
        if (remove) {
          next.removeAll(ids);
        } else {
          next.addAll(ids);
        }
        if (!photo.id.startsWith('remote_'))
          await _database.saveTagIds(photo.id, next.toList());
        photo.tagIds = next.toList();
        success++;
      } catch (_) {
        /* Preserva as tags anteriores da foto que falhou. */
      }
    }
    _selected.clear();
    await _loadPhotos();
    _feedback('$success de ${photos.length} foto(s) atualizada(s).');
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          api: _api,
          database: _database,
          drive: _drive,
          onBackupPending: () async {
            if (!_configured) {
              _feedback(
                'Selecione uma turma na galeria antes de salvar no Drive.',
              );
              return;
            }
            await _backupPendingToDrive();
          },
          onLogout: widget.controller.logout,
          onSaved: () async {
            _config = await _api.loadConfig();
            _driveConnected = await _drive.isSignedIn;
            _driveAutoDelete = _drive.autoDeleteAfterUpload;
            await _cleanSyncedPhotos();
          },
        ),
      ),
    );
    if (_alive) {
      _config = await _api.loadConfig();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _connectivitySubscription?.cancel();
    unawaited(_database.close().catchError((Object _) {}));
    super.dispose();
  }

  String _dayLabel(Photo photo) {
    final day = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final value = DateTime(day.year, day.month, day.day);
    if (value == today) return 'Hoje';
    if (value == today.subtract(const Duration(days: 1))) return 'Ontem';
    return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
  }

  Future<void> _renewPhotoUrl(Photo photo) async {
    if (photo.prismaPhotoId == null || photo.classId == null) return;
    final photos = await _api.getClassPhotos(photo.classId!);
    final match = photos
        .where((item) => item['id'] == photo.prismaPhotoId)
        .firstOrNull;
    if (match?['media_url'] != null) {
      photo.mediaUrl = Uri.parse(
        widget.session.baseUrl,
      ).resolve(match!['media_url'] as String).toString();
    }
  }

  Widget _photoImage(Photo photo, {int? cacheWidth, VoidCallback? onRetry}) {
    Widget failed(Object _, StackTrace? __) => ColoredBox(
      color: const Color(0xFFE8EDF6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: tinhaNavy),
            if (cacheWidth == null)
              const Text('Foto indisponível', style: TextStyle(fontSize: 12)),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: const Text('Tentar carregar novamente'),
              ),
          ],
        ),
      ),
    );
    if (photo.localPath.isNotEmpty && File(photo.localPath).existsSync()) {
      return Image.file(
        File(photo.localPath),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, error, stack) => failed(error, stack),
      );
    }
    if (photo.mediaUrl != null) {
      final url = Uri.parse(photo.mediaUrl!);
      final displayUrl = cacheWidth == null
          ? url
          : url.replace(
              queryParameters: {...url.queryParameters, 'thumbnail': 'true'},
            );
      return Image.network(
        displayUrl.toString(),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, error, stack) => failed(error, stack),
      );
    }
    return failed(StateError('Arquivo indisponível'), null);
  }

  void _viewPhoto(List<Photo> photos, int index) {
    final controller = PageController(initialPage: index);
    var current = index;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (route) => StatefulBuilder(
              builder: (route, update) {
                final photo = photos[current];
                return Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    title: Text('${current + 1} de ${photos.length}'),
                  ),
                  body: PageView.builder(
                    controller: controller,
                    itemCount: photos.length,
                    onPageChanged: (value) => update(() => current = value),
                    itemBuilder: (_, page) => InteractiveViewer(
                      child: Center(
                        child: _photoImage(
                          photos[page],
                          onRetry: () async {
                            try {
                              await _renewPhotoUrl(photos[page]);
                              update(() {});
                            } catch (_) {
                              _feedback(
                                'Foto indisponível. Tente atualizar a galeria.',
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: SafeArea(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${DateTime.fromMillisecondsSinceEpoch(photo.timestamp).day}/${DateTime.fromMillisecondsSinceEpoch(photo.timestamp).month}/${DateTime.fromMillisecondsSinceEpoch(photo.timestamp).year} · ${photo.status == SyncStatus.synced
                                ? 'Enviada'
                                : photo.status == SyncStatus.error
                                ? 'Erro de envio'
                                : 'Aguardando envio'}',
                          ),
                          if (photo.uploadError != null)
                            Text(
                              photo.uploadError!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            children: photo.tagIds
                                .map(
                                  (id) => Chip(
                                    label: Text(
                                      _tags
                                              .where((tag) => tag['id'] == id)
                                              .firstOrNull?['name']
                                              ?.toString() ??
                                          'Tag',
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(route);
                                  _editTags([photo]);
                                },
                                icon: const Icon(Icons.label_outline),
                                label: const Text('Tags'),
                              ),
                              if (photo.localPath.isNotEmpty)
                                IconButton(
                                  tooltip: 'Salvar no Google Drive',
                                  onPressed: photo.driveFileId == null
                                      ? () {
                                          Navigator.pop(route);
                                          _backupToDrive(photo);
                                        }
                                      : null,
                                  icon: const Icon(Icons.add_to_drive),
                                ),
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(route);
                                  setState(() => _selected.add(photo.id));
                                  _moveSelected();
                                },
                                icon: const Icon(Icons.drive_file_move_outline),
                                label: const Text('Mover'),
                              ),
                              if (photo.status == SyncStatus.error ||
                                  photo.status == SyncStatus.pending)
                                TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(route);
                                    _upload(photo);
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reenviar'),
                                ),
                              IconButton(
                                tooltip: 'Excluir',
                                onPressed: () {
                                  Navigator.pop(route);
                                  setState(() => _selected.add(photo.id));
                                  _deleteSelected();
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        )
        .then((_) {
          controller.dispose();
          if (_alive) _loadPhotos();
        });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePhotos;
    final groups = <String, List<Photo>>{};
    for (final photo in visible) {
      groups.putIfAbsent(_dayLabel(photo), () => []).add(photo);
    }
    final selected = _selected.isNotEmpty;
    final className = _classes
        .where((item) => item['id'] == _config.classId)
        .firstOrNull?['name']
        ?.toString();
    final sending = _photos
        .where(
          (p) =>
              p.status == SyncStatus.pending ||
              p.status == SyncStatus.scheduled ||
              p.status == SyncStatus.syncing,
        )
        .length;
    final sent = _photos.where((p) => p.status == SyncStatus.synced).length;
    final errors = _photos.where((p) => p.status == SyncStatus.error).length;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        title: selected
            ? Row(
                children: [
                  IconButton(
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(Icons.close),
                  ),
                  Text(
                    '${_selected.length} selecionada(s)',
                    style: const TextStyle(fontSize: 17),
                  ),
                ],
              )
            : const Row(
                children: [
                  GraduationCap(width: 30),
                  SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TinhaWordmark(fontSize: 22),
                      Text(
                        'Área do professor',
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
        actions: selected
            ? [
                TextButton(
                  onPressed: () => setState(
                    () => _selected.addAll(visible.map((p) => p.id)),
                  ),
                  child: const Text('Todas'),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Configurações',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loadingClasses) const LinearProgressIndicator(),
                    if (_classError != null)
                      Text(
                        _classError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (_offline)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Sem conexão. As fotos ficam salvas para envio posterior.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                    Card(
                      color: Colors.white,
                      child: ListTile(
                        onTap: _chooseClass,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFE9F0FF),
                          child: const Icon(
                            Icons.groups_outlined,
                            color: tinhaBlue,
                          ),
                        ),
                        title: Text(
                          className ?? 'Selecionar turma',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          widget.session.account.schoolName ?? 'Sem escola',
                        ),
                        trailing: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                    if (!_loadingClasses && _classes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Você ainda não está vinculado a uma turma. Procure a coordenação.',
                        ),
                      ),
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _statusChip('Todas', _photos.length, tinhaBlue),
                          _statusChip('Enviando', sending, Colors.orange),
                          _statusChip('Enviadas', sent, Colors.green),
                          _statusChip('Erro', errors, Colors.red),
                        ],
                      ),
                    ),
                    if (sending > 0 || errors > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                errors > 0
                                    ? '$errors foto(s) com falha; arquivos preservados.'
                                    : '$sending foto(s) aguardando envio.',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _syncPending,
                              child: Text(
                                errors > 0
                                    ? 'Tentar enviar todas'
                                    : 'Enviar agora',
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Fotos',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: tinhaNavy,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Filtrar fotos',
                          onPressed: _showFilters,
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (groups.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.photo_library_outlined,
                        size: 56,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _photos.isEmpty
                            ? 'Nenhuma foto nesta turma'
                            : 'Nenhuma foto para estes filtros',
                      ),
                      if (_photos.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() {
                            _statusFilter = 'Todas';
                            _dateFilter = 'Todas';
                            _tagFilter.clear();
                          }),
                          child: const Text('Limpar filtros'),
                        ),
                    ],
                  ),
                ),
              )
            else
              for (final entry in groups.entries) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: tinhaNavy,
                            ),
                          ),
                        ),
                        Text('${entry.value.length} fotos'),
                        if (selected)
                          TextButton(
                            onPressed: () => setState(
                              () => _selected.addAll(
                                entry.value.map((p) => p.id),
                              ),
                            ),
                            child: const Text('Selecionar grupo'),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 5,
                          mainAxisSpacing: 5,
                        ),
                    itemCount: entry.value.length,
                    itemBuilder: (_, index) {
                      final photo = entry.value[index];
                      return GestureDetector(
                        onLongPress: () => _toggleSelection(photo),
                        onTap: () {
                          if (selected) {
                            _toggleSelection(photo);
                          } else {
                            _viewPhoto(visible, visible.indexOf(photo));
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _photoImage(photo, cacheWidth: 320),
                              if (_selected.contains(photo.id))
                                Container(
                                  color: tinhaBlue.withValues(alpha: .23),
                                ),
                              Positioned(
                                top: 5,
                                right: 5,
                                child: _selected.contains(photo.id)
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: tinhaBlue,
                                        size: 23,
                                      )
                                    : _compactStatus(photo),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
      floatingActionButton: selected
          ? null
          : FloatingActionButton(
              shape: const CircleBorder(),
              backgroundColor: tinhaBlue,
              foregroundColor: Colors.white,
              tooltip: 'Adicionar fotos',
              onPressed: _addPhotos,
              child: const Icon(Icons.add, size: 30),
            ),
      bottomNavigationBar: selected
          ? SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: _moveSelected,
                      icon: const Icon(Icons.drive_file_move_outline),
                      label: const Text('Mover'),
                    ),
                    TextButton.icon(
                      onPressed: () => _editTags(_selectedPhotos),
                      icon: const Icon(Icons.label_outline),
                      label: const Text('Tags'),
                    ),
                    TextButton.icon(
                      onPressed: _deleteSelected,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('Excluir'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _statusChip(String label, int count, Color color) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      label: Text('$label  $count'),
      selected: _statusFilter == label,
      selectedColor: tinhaBlue,
      labelStyle: TextStyle(
        color: _statusFilter == label ? Colors.white : color,
      ),
      onSelected: (_) => setState(() => _statusFilter = label),
    ),
  );

  Widget _compactStatus(Photo photo) {
    if (photo.status == SyncStatus.syncing)
      return const CircleAvatar(
        radius: 11,
        backgroundColor: Colors.white,
        child: SizedBox.square(
          dimension: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    if (photo.status == SyncStatus.synced)
      return const CircleAvatar(
        radius: 11,
        backgroundColor: Colors.green,
        child: Icon(Icons.check, size: 14, color: Colors.white),
      );
    if (photo.status == SyncStatus.error)
      return const CircleAvatar(
        radius: 11,
        backgroundColor: Colors.red,
        child: Icon(Icons.error_outline, size: 15, color: Colors.white),
      );
    return const CircleAvatar(
      radius: 11,
      backgroundColor: Colors.white,
      child: Icon(Icons.schedule, size: 15, color: Colors.blueGrey),
    );
  }
}
