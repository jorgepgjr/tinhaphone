import 'dart:convert';

import '../../auth/mobile_session.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/child.dart';
import '../core/models/post.dart';
import '../core/models/project.dart';

class TinhaKidsApiService {
  TinhaKidsApiService({
    http.Client? client,
    MobileSession? session,
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       _session = session;
  final http.Client _client;
  MobileSession? _session;
  final Future<void> Function()? onUnauthorized;
  String get baseUrl => _session?.baseUrl ?? defaultServer;
  String get _selectedChildKey =>
      'unified_selected_child_${_session?.scope ?? 'unbound'}';

  String resolveUrl(String value) {
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    return '$baseUrl$value';
  }

  Future<String> login(String identifier, String password) async {
    final session = await MobileAuthClient(
      client: _client,
    ).login(baseUrl, identifier, password);
    if (session.account.isTeacher) {
      throw Exception('Esta não é uma conta familiar.');
    }
    _session = session;
    return session.token;
  }

  Future<String?> getSavedToken() async => _session?.token;
  Future<String?> getSavedChildId() async {
    if (_session == null) return null;
    return (await SharedPreferences.getInstance()).getString(_selectedChildKey);
  }

  Future<void> saveSelectedChild(String childId) async {
    if (_session != null) {
      await (await SharedPreferences.getInstance()).setString(
        _selectedChildKey,
        childId,
      );
    }
  }

  Future<void> logout() async {
    _session = null;
  }

  Future<void> checkAccess(http.Response response) async {
    if ([401, 403].contains(response.statusCode)) await onUnauthorized?.call();
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
  };

  Future<List<Child>> getChildren(String token) async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/v1/children/'), headers: _headers(token))
        .timeout(const Duration(seconds: 15));
    await checkAccess(response);
    if (response.statusCode != 200) {
      throw Exception('Não foi possível carregar as crianças.');
    }
    return (jsonDecode(response.body) as List)
        .map((item) => Child.fromJson(item as Map<String, dynamic>, resolveUrl))
        .toList();
  }

  Future<List<Post>> getPosts(String token, String childId) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/v1/posts/?child_id=$childId'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    await checkAccess(response);
    if (response.statusCode != 200) {
      throw Exception('Não foi possível carregar as publicações.');
    }
    return (jsonDecode(response.body) as List)
        .map(
          (item) =>
              Post.fromJson(item as Map<String, dynamic>, childId, resolveUrl),
        )
        .toList();
  }

  Future<List<Project>> getProjects(String token, String childId) async {
    final response = await _client
        .get(
          Uri.parse('$baseUrl/api/v1/portfolio/?child_id=$childId'),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 15));
    await checkAccess(response);
    if (response.statusCode != 200) {
      throw Exception('Não foi possível carregar o portfólio.');
    }
    return (jsonDecode(response.body) as List)
        .map(
          (item) => Project.fromJson(item as Map<String, dynamic>, resolveUrl),
        )
        .toList();
  }
}
