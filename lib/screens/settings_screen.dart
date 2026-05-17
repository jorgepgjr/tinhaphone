import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/drive_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DriveService _driveService = DriveService();
  bool _autoDelete = false;
  bool _applyWatermark = true;
  bool _wifiOnlySync = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoDelete = prefs.getBool('auto_delete') ?? false;
      _applyWatermark = prefs.getBool('apply_watermark') ?? true;
      _wifiOnlySync = prefs.getBool('wifi_only_sync') ?? false;
    });
  }

  Future<void> _toggleAutoDelete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_delete', value);
    setState(() {
      _autoDelete = value;
    });
  }

  Future<void> _toggleWatermark(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('apply_watermark', value);
    setState(() {
      _applyWatermark = value;
    });
  }

  Future<void> _toggleWifiOnlySync(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wifi_only_sync', value);
    setState(() {
      _wifiOnlySync = value;
    });
  }

  Future<void> _showFolderSelectionDialog() async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final folders = await _driveService.getFolders();
      if (!mounted) return;
      Navigator.pop(context); // close progress dialog

      final selectedFolderId = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Selecione uma pasta para Sincronismo'),
            content: SizedBox(
              width: double.maxFinite,
              child: folders.isEmpty
                  ? const Text('Nenhuma pasta encontrada.')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.folder,
                            color: Colors.indigo,
                          ),
                          title: Text(folder.name ?? 'Pasta Sem Nome'),
                          onTap: () => Navigator.pop(context, folder.id),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () async {
                  TextEditingController controller = TextEditingController();
                  final newFolderName = await showDialog<String>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Nova Pasta'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Nome da Pasta',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, controller.text),
                          child: const Text('Criar'),
                        ),
                      ],
                    ),
                  );

                  if (newFolderName != null && newFolderName.isNotEmpty) {
                    Navigator.pop(context); // close list dialog
                    // Show progress
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) =>
                          const Center(child: CircularProgressIndicator()),
                    );
                    try {
                      final newFolder = await _driveService.createFolder(
                        newFolderName,
                      );
                      if (newFolder.id != null) {
                        await _driveService.setTargetFolder(
                          newFolder.id!,
                          newFolder.name!,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Pasta selecionada: ${newFolder.name}',
                              ),
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      print('Erro ao criar pasta: $e');
                    } finally {
                      if (mounted) Navigator.pop(context); // close progress
                    }
                  }
                },
                child: const Text('Nova Pasta'),
              ),
            ],
          );
        },
      );

      if (selectedFolderId != null) {
        final folder = folders.firstWhere((f) => f.id == selectedFolderId);
        await _driveService.setTargetFolder(
          selectedFolderId,
          folder.name ?? 'Pasta Sem Nome',
        );
        setState(() {}); // refresh UI to show folder name
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pasta selecionada: ${folder.name}')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // close progress
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao carregar pastas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configurações',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Geral',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Limpar fotos automaticamente após Sincronismo'),
            subtitle: const Text(
              'As fotos locais serão excluídas automaticamente do dispositivo após envia-las ao Google Drive com sucesso.',
            ),
            activeColor: Colors.indigo,
            value: _autoDelete,
            onChanged: _toggleAutoDelete,
          ),
          SwitchListTile(
            title: const Text('Aplicar Marca D\'água nas fotos'),
            subtitle: const Text(
              'A imagem \'lib/assets/guri.png\' será aplicada nas fotos tiradas.',
            ),
            activeColor: Colors.indigo,
            value: _applyWatermark,
            onChanged: _toggleWatermark,
          ),
          SwitchListTile(
            title: const Text('Sincronizar apenas no Wi-Fi'),
            subtitle: const Text(
              'O sincronismo será agendado para quando houver uma conexão Wi-Fi ativa.',
            ),
            activeColor: Colors.indigo,
            value: _wifiOnlySync,
            onChanged: _toggleWifiOnlySync,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Google Drive',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder, color: Colors.indigo),
            title: const Text('Pasta de Destino do Sincronismo'),
            subtitle: Text(
              _driveService.targetFolderName ??
                  'Diretório Raiz (Nenhuma pasta selecionada explicitamente)',
            ),
            trailing: const Icon(Icons.edit, size: 20, color: Colors.grey),
            onTap: _showFolderSelectionDialog,
          ),
        ],
      ),
    );
  }
}
