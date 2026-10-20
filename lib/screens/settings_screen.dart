import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../services/drive_service.dart';
import '../services/prisma_api_service.dart';
import 'error_logs_screen.dart';

class SettingsScreen extends StatefulWidget {
  final PrismaApiService api;
  final DbService database;
  final Future<void> Function()? onSaved;
  final DriveService? drive;
  final Future<void> Function()? onBackupPending;
  final Future<bool> Function()? onLogout;
  const SettingsScreen({
    super.key,
    required this.api,
    required this.database,
    this.onSaved,
    this.drive,
    this.onBackupPending,
    this.onLogout,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PrismaConfig? _config;
  bool _saving = false;
  bool _driveConnected = false;
  bool _driveAutoDelete = false;
  bool _driveBusy = false;
  bool _backupRunning = false;
  String? _error;
  String? _driveError;
  late final DriveService _drive =
      widget.drive ?? DriveService(widget.api.session.scope);
  bool get _driveAvailable => widget.drive != null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.api.loadConfig();
      final connected = _driveAvailable ? await _drive.isSignedIn : false;
      if (mounted) {
        setState(() {
          _config = c;
          _driveConnected = connected;
          _driveAutoDelete = _driveAvailable && _drive.autoDeleteAfterUpload;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível abrir as configurações.');
      }
    }
  }

  Future<void> _connectDrive() async {
    if (_driveBusy || !_driveAvailable) return;
    setState(() {
      _driveBusy = true;
      _driveError = null;
    });
    try {
      await _drive.signIn();
      if (mounted) {
        setState(() => _driveConnected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta do Google Drive conectada.')),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _driveError =
              'Não foi possível conectar ao Drive. Confira a conta e tente novamente.',
        );
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  Future<void> _backupPending() async {
    if (_driveBusy || widget.onBackupPending == null) return;
    setState(() {
      _driveBusy = true;
      _backupRunning = true;
      _driveError = null;
    });
    try {
      await widget.onBackupPending!();
      final connected = await _drive.isSignedIn;
      if (mounted) setState(() => _driveConnected = connected);
    } catch (_) {
      if (mounted) {
        setState(
          () => _driveError =
              'Não foi possível salvar no Drive. Tente novamente.',
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _driveBusy = false;
          _backupRunning = false;
        });
    }
  }

  Future<void> _logout() async {
    final loggedOut = await widget.onLogout!();
    if (mounted && !loggedOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde o envio das fotos terminar para sair.'),
        ),
      );
    }
  }

  Future<void> _disconnectDrive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar do Google Drive?'),
        content: const Text(
          'As fotos já enviadas continuam na sua conta Google. Os próximos envios ficam pausados até você conectar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true || _driveBusy) return;
    setState(() {
      _driveBusy = true;
      _driveError = null;
    });
    try {
      await _drive.signOut();
      if (mounted) {
        setState(() {
          _driveConnected = false;
          _driveAutoDelete = false;
        });
        await widget.onSaved?.call();
      }
    } catch (_) {
      if (mounted)
        setState(() => _driveError = 'Não foi possível desconectar do Drive.');
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  Future<void> _chooseFolder() async {
    if (!_driveConnected || _driveBusy) return;
    setState(() {
      _driveBusy = true;
      _driveError = null;
    });
    try {
      final folders = await _drive.getFolders();
      if (!mounted) return;
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pasta do Google Drive'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('Meu Drive'),
                  subtitle: const Text('Salvar na pasta principal'),
                  onTap: () => Navigator.pop(context, 'root'),
                ),
                for (final folder in folders)
                  if (folder.id != null)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name ?? 'Pasta sem nome'),
                      onTap: () => Navigator.pop(context, folder.id),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'create'),
              child: const Text('Criar pasta'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );
      var folderChanged = false;
      if (selected == 'create' && mounted) {
        final name = await showDialog<String>(
          context: context,
          builder: (context) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('Nova pasta'),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome da pasta'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Criar'),
                ),
              ],
            );
          },
        );
        if (name != null && name.trim().isNotEmpty) {
          final folder = await _drive.createFolder(name);
          if (folder.id != null) {
            await _drive.setTargetFolder(folder.id!, folder.name ?? name);
            folderChanged = true;
          }
        }
      } else if (selected == 'root') {
        await _drive.setTargetFolder(null, null);
        folderChanged = true;
      } else if (selected != null) {
        final folder = folders.where((item) => item.id == selected).firstOrNull;
        await _drive.setTargetFolder(selected, folder?.name ?? 'Pasta');
        folderChanged = true;
      }
      if (mounted && folderChanged) {
        await widget.onSaved?.call();
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _drive.targetFolderName == null
                  ? 'Pasta principal selecionada.'
                  : 'Pasta "${_drive.targetFolderName}" selecionada.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _driveError =
              'Não foi possível carregar ou alterar as pastas. Tente novamente.',
        );
    } finally {
      if (mounted) setState(() => _driveBusy = false);
    }
  }

  Future<void> _toggleDriveCleanup(bool value) async {
    try {
      await _drive.setAutoDeleteAfterUpload(value);
      if (mounted) {
        setState(() => _driveAutoDelete = value);
        await widget.onSaved?.call();
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _driveError = 'Não foi possível salvar essa preferência.',
        );
    }
  }

  Future<void> _save() async {
    if (_config == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveConfig(_config!);
      await widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configurações salvas.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar. Tente novamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Configurações')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.api.session.account.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(widget.api.session.account.email),
        Text(widget.api.session.account.schoolName ?? ''),
        const SizedBox(height: 16),
        if (_config == null && _error == null) const LinearProgressIndicator(),
        if (_config != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apagar automaticamente fotos sincronizadas'),
            subtitle: const Text(
              'Libera somente cópias desta conta após o Prisma confirmar o envio. Fotos pendentes e originais da galeria não são apagados.',
            ),
            value: _config!.autoDeleteSynced,
            onChanged: _saving
                ? null
                : (value) => setState(
                    () => _config = PrismaConfig(
                      classId: _config!.classId,
                      autoDeleteSynced: value ?? false,
                    ),
                  ),
          ),
        const Divider(height: 32),
        const Text(
          'Google Drive',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _driveConnected
              ? 'Conectado${_drive.currentUserEmail == null ? '' : ': ${_drive.currentUserEmail}'}'
              : 'Envie uma cópia das fotos para sua conta Google.',
        ),
        const SizedBox(height: 8),
        if (_driveConnected)
          OutlinedButton.icon(
            onPressed: _driveBusy ? null : _disconnectDrive,
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar Google Drive'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: _driveBusy ? null : _connectDrive,
            icon: _driveBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_to_drive),
            label: Text(_driveBusy ? 'Conectando...' : 'Conectar Google Drive'),
          ),
        if (_driveConnected) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Pasta de destino'),
            subtitle: Text(
              _drive.targetFolderName ?? 'Meu Drive (pasta principal)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _driveBusy ? null : _chooseFolder,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Apagar a cópia local depois de sincronizar'),
            subtitle: const Text(
              'Só remove a cópia do app após a foto ser confirmada no Drive e no Prisma. O original da galeria permanece.',
            ),
            value: _driveAutoDelete,
            onChanged: _driveBusy ? null : _toggleDriveCleanup,
          ),
        ],
        if (_driveError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _driveError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.onBackupPending != null)
          OutlinedButton.icon(
            onPressed: _driveBusy ? null : _backupPending,
            icon: _backupRunning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _backupRunning
                  ? 'Salvando no Drive...'
                  : 'Salvar pendentes no Drive',
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton(
          onPressed: _saving || _config == null ? null : _save,
          child: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Registros de erro desta conta'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ErrorLogsScreen(database: widget.database),
            ),
          ),
        ),
        if (widget.onLogout != null) ...[
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sair'),
            subtitle: const Text('Encerrar sessão neste aparelho'),
            enabled: !_driveBusy && !_saving,
            onTap: _logout,
          ),
        ],
      ],
    ),
  );
}
