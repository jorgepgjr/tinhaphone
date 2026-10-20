import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

String normalizeServer(String value) {
  var address = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (!address.contains('://') && address.isNotEmpty) {
    final local = RegExp(
      r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)',
    ).hasMatch(address);
    address = '${local ? 'http' : 'https'}://$address';
  }
  final uri = Uri.tryParse(address);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'\s').hasMatch(address)) {
    throw Exception('Informe um endereço válido para o servidor.');
  }
  return uri.toString();
}

String get defaultServer => const String.fromEnvironment('API_URL').isNotEmpty
    ? normalizeServer(const String.fromEnvironment('API_URL'))
    : Platform.isAndroid
    ? 'http://10.0.2.2:8000'
    : 'http://127.0.0.1:8000';

class MobileAccount {
  final String id, name, email, profile;
  final int? schoolId;
  final String? schoolName;
  const MobileAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.profile,
    this.schoolId,
    this.schoolName,
  });
  bool get isTeacher => profile == 'PROFESSOR';
  factory MobileAccount.fromJson(Map<String, dynamic> data) {
    final profile = data['profile'] as String;
    if (!['PROFESSOR', 'FAMILIAR'].contains(profile)) {
      throw Exception('Perfil não habilitado para o aplicativo.');
    }
    return MobileAccount(
      id: data['id'].toString(),
      name: data['name'] as String,
      email: data['email'] as String,
      profile: profile,
      schoolId: data['school_id'] as int?,
      schoolName: data['school_name'] as String?,
    );
  }
}

class MobileSession {
  final String token, baseUrl;
  final MobileAccount account;
  const MobileSession({
    required this.token,
    required this.baseUrl,
    required this.account,
  });
  String get scope => sha256
      .convert(
        utf8.encode(
          jsonEncode([baseUrl, account.profile, account.id, account.schoolId]),
        ),
      )
      .toString();
}

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  static const _key = 'tinhakids_unified_session_v1';
  final FlutterSecureStorage storage;
  SecureTokenStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );
  @override
  Future<String?> read() => storage.read(key: _key);
  @override
  Future<void> write(String value) => storage.write(key: _key, value: value);
  @override
  Future<void> clear() => storage.delete(key: _key);
}

class MobileAuthClient {
  final http.Client client;
  MobileAuthClient({http.Client? client}) : client = client ?? http.Client();
  Future<MobileSession> login(
    String server,
    String email,
    String password,
  ) async {
    final url = normalizeServer(server);
    final response = await client
        .post(
          Uri.parse('$url/api/mobile/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = readResponse(response);
    return MobileSession(
      token: data['access_token'] as String,
      baseUrl: url,
      account: MobileAccount.fromJson(data['account'] as Map<String, dynamic>),
    );
  }

  Future<MobileSession> validate(String server, String token) async {
    final url = normalizeServer(server);
    final response = await client
        .get(
          Uri.parse('$url/api/mobile/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    return MobileSession(
      token: token,
      baseUrl: url,
      account: MobileAccount.fromJson(readResponse(response)),
    );
  }
}

class ApiFailure implements Exception {
  final int status;
  final String message;
  const ApiFailure(this.status, this.message);
  @override
  String toString() => message;
}

Map<String, dynamic> readResponse(http.Response response) {
  Map<String, dynamic> data;
  try {
    data = jsonDecode(response.body) as Map<String, dynamic>;
  } catch (_) {
    throw ApiFailure(
      response.statusCode,
      'Não foi possível acessar o servidor. Tente novamente.',
    );
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw ApiFailure(
      response.statusCode,
      data['detail'] is String
          ? data['detail'] as String
          : 'Confira os dados e tente novamente.',
    );
  }
  return data;
}

class SessionController extends ChangeNotifier {
  final MobileAuthClient api;
  final TokenStore store;
  MobileSession? session;
  bool loading = false, initialized = false, expired = false;
  String? error;
  int _version = 0, _work = 0;
  Future<void> _storageQueue = Future.value();
  bool _disposed = false;
  SessionController({MobileAuthClient? api, TokenStore? store})
    : api = api ?? MobileAuthClient(),
      store = store ?? SecureTokenStore();
  bool get busy => _work > 0;
  bool owns(MobileSession value) => !_disposed && session == value && !expired;
  Future<void> _store(Future<void> Function() operation) {
    final next = _storageQueue
        .catchError((Object _) {})
        .then((_) => operation());
    _storageQueue = next;
    return next;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_version;
    super.dispose();
  }

  bool beginWork(MobileSession value) {
    if (!owns(value)) return false;
    _work++;
    notifyListeners();
    return true;
  }

  Future<void> endWork() async {
    if (_work > 0) _work--;
    if (_work == 0 && expired) {
      await logout();
    } else {
      notifyListeners();
    }
  }

  Future<void> restore() async {
    final version = ++_version;
    loading = true;
    notifyListeners();
    try {
      final saved = await store.read();
      if (version != _version) return;
      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        final restored = await api.validate(
          data['server'] as String,
          data['token'] as String,
        );
        if (version != _version) return;
        session = restored;
      }
    } catch (error) {
      if (version != _version) return;
      // Não lê as credenciais/configurações nem os tokens dos aplicativos antigos.
      this.error = 'Não foi possível validar a sessão. Entre novamente.';
      if (error is ApiFailure && [401, 403, 409].contains(error.status)) {
        await _store(store.clear);
      }
    } finally {
      if (version == _version) {
        loading = false;
        initialized = true;
        notifyListeners();
      }
    }
  }

  Future<void> login(String server, String email, String password) async {
    if (loading || busy) return;
    final version = ++_version;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.login(server, email, password);
      if (version != _version) return;
      await _store(
        () => store.write(
          jsonEncode({'server': result.baseUrl, 'token': result.token}),
        ),
      );
      if (version != _version) return;
      session = result;
      expired = false;
    } catch (error) {
      if (version == _version) {
        this.error = error is ApiFailure
            ? error.message
            : error is TimeoutException
            ? 'O servidor demorou para responder. Confira o endereço e a conexão.'
            : error is SocketException || error is http.ClientException
            ? 'Não foi possível conectar ao servidor. Confira o endereço, a porta e se o celular está na mesma rede do computador.'
            : 'Não foi possível entrar. Confira o endereço do servidor e tente novamente.';
      }
    } finally {
      if (version == _version) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> invalidate([MobileSession? expected]) async {
    if (_disposed) return;
    if (expected != null && session != expected) return;
    expired = true;
    error =
        'Sua sessão expirou. Entre novamente. As fotos pendentes foram preservadas.';
    if (!busy) {
      await logout();
    } else {
      notifyListeners();
    }
  }

  Future<bool> logout() async {
    if (busy) return false;
    ++_version;
    session = null;
    expired = false;
    loading = true;
    notifyListeners();
    try {
      await _store(store.clear);
    } finally {
      loading = false;
      notifyListeners();
    }
    return true;
  }

  Future<void> revalidate() async {
    final current = session;
    if (current == null || loading || busy || !owns(current)) return;
    try {
      final validated = await api.validate(current.baseUrl, current.token);
      if (owns(current) && validated.scope != current.scope)
        await invalidate(current);
    } on ApiFailure catch (failure) {
      if ([401, 403, 409].contains(failure.status)) await invalidate(current);
    } catch (_) {
      /* Sem conexão: preserva a fila e o token; a API valida todo envio. */
    }
  }
}
