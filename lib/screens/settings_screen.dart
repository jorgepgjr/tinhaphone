import 'package:flutter/material.dart';

import '../services/prisma_api_service.dart';
import 'error_logs_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool initialSetup;
  final Future<void> Function()? onSaved;

  const SettingsScreen({super.key, this.initialSetup = false, this.onSaved});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = PrismaApiService();
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _classId = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  bool _autoDeleteSynced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _api.loadConfig();
    _url.text = config.baseUrl;
    _email.text = config.email;
    _password.text = config.password;
    _classId.text = config.classId.toString();
    _autoDeleteSynced = config.autoDeleteSynced;
    if (mounted) setState(() => _loading = false);
  }

  PrismaConfig _config() => PrismaConfig(
    baseUrl: _url.text.trim(),
    email: _email.text.trim(),
    password: _password.text,
    classId: int.tryParse(_classId.text) ?? 2,
    autoDeleteSynced: _autoDeleteSynced,
  );

  Future<void> _save() async {
    await _api.saveConfig(_config());
    await widget.onSaved?.call();
    if (mounted && widget.initialSetup) {
      Navigator.of(context).pop(true);
    } else if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configurações salvas.')));
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final classes = await _api.testConnection(_config());
      if (!mounted) return;
      final names = classes
          .map((item) => '${item['id']} — ${item['name']}')
          .join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conexão aprovada. Turmas: $names')),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    _classId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Integração com o Prisma',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'No emulador Android, 10.0.2.2 aponta para este computador. Em um celular físico, informe o IP do computador na rede local.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: 'Endereço da API',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail da professora',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _classId,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Código da turma',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.groups_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Apagar automaticamente fotos sincronizadas',
                  ),
                  subtitle: const Text(
                    'Libera o espaço das cópias do Tinhaphone somente após o Prisma confirmar o envio. Fotos pendentes e originais da galeria não são apagados. Ao salvar, também limpa as cópias já enviadas.',
                  ),
                  value: _autoDeleteSynced,
                  onChanged: (value) =>
                      setState(() => _autoDeleteSynced = value ?? false),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_outlined),
                  label: const Text('Testar conexão e listar turmas'),
                ),
                const Divider(height: 40),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Histórico de erros'),
                  subtitle: const Text(
                    'Consulte falhas de envio armazenadas neste aparelho.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ErrorLogsScreen()),
                  ),
                ),
              ],
            ),
    );
  }
}
