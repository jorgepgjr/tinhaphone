import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PrismaConfig {
  final String baseUrl;
  final String email;
  final String password;
  final int classId;

  const PrismaConfig({
    required this.baseUrl,
    required this.email,
    required this.password,
    required this.classId,
  });
}

class PrismaApiService {
  static const _baseUrlKey = 'prisma_base_url';
  static const _emailKey = 'prisma_email';
  static const _passwordKey = 'prisma_password';
  static const _classIdKey = 'prisma_class_id';

  String get _defaultBaseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';

  Future<bool> hasSavedConfig() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.containsKey(_baseUrlKey) &&
        preferences.containsKey(_emailKey) &&
        preferences.containsKey(_passwordKey) &&
        preferences.containsKey(_classIdKey);
  }

  Future<PrismaConfig> loadConfig() async {
    final preferences = await SharedPreferences.getInstance();
    return PrismaConfig(
      baseUrl: (preferences.getString(_baseUrlKey) ?? _defaultBaseUrl)
          .replaceAll(RegExp(r'/$'), ''),
      email: preferences.getString(_emailKey) ?? 'marilia@school.com',
      password: preferences.getString(_passwordKey) ?? 'mypassword',
      classId: preferences.getInt(_classIdKey) ?? 2,
    );
  }

  Future<void> saveConfig(PrismaConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(
        _baseUrlKey,
        config.baseUrl.replaceAll(RegExp(r'/$'), ''),
      ),
      preferences.setString(_emailKey, config.email.trim()),
      preferences.setString(_passwordKey, config.password),
      preferences.setInt(_classIdKey, config.classId),
    ]);
  }

  Future<String> _login(PrismaConfig config) async {
    final response = await http
        .post(
          Uri.parse('${config.baseUrl}/api/auth/login'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'username': config.email, 'password': config.password},
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200)
      throw Exception(data['detail'] ?? 'Falha na autenticação com o Prisma.');
    return data['access_token'] as String;
  }

  Future<List<Map<String, dynamic>>> testConnection(PrismaConfig config) async {
    final token = await _login(config);
    final response = await http
        .get(
          Uri.parse('${config.baseUrl}/api/classes/'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200)
      throw Exception('A conta não tem acesso às turmas.');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<int> uploadPhoto(File file) async {
    final config = await loadConfig();
    final token = await _login(config);
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${config.baseUrl}/api/photos/upload'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['class_id'] = config.classId.toString()
          ..fields['title'] = 'Foto enviada pelo Tinhaphone'
          ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201)
      throw Exception(data['detail'] ?? 'Falha ao enviar a foto.');
    return data['id'] as int;
  }
}
