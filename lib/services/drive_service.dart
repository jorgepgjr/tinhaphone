import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _client.send(request..headers.addAll(_headers));

  @override
  void close() => _client.close();
}

/// Drive preferences and the saved Google account are kept separate per app account.
class DriveService {
  DriveService(this.accountScope) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(accountScope)) {
      throw ArgumentError('Conta inválida');
    }
  }

  final String accountScope;
  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  GoogleAuthClient? _authClient;
  bool _initialized = false;
  Future<void>? _initializing;
  String? _targetFolderId;
  String? _targetFolderName;
  String? _savedGoogleEmail;
  bool _autoDeleteAfterUpload = false;

  static const _scopes = [drive.DriveApi.driveFileScope];

  // This is the existing web OAuth client ID used by the original Drive integration.
  static const _serverClientId =
      '498748867390-o4cs1mahtk733jjtn24o3n2ai4uinokg.apps.googleusercontent.com';

  String get _folderIdKey => 'drive_target_folder_id_$accountScope';
  String get _folderNameKey => 'drive_target_folder_name_$accountScope';
  String get _accountKey => 'drive_account_email_$accountScope';
  String get _cleanupKey => 'drive_auto_delete_$accountScope';

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    if (_initializing != null) return _initializing;
    final task = _initialize();
    _initializing = task;
    try {
      await task;
    } finally {
      if (identical(_initializing, task)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    await GoogleSignIn.instance.initialize(
      serverClientId: Platform.isAndroid ? _serverClientId : null,
    );
    final prefs = await SharedPreferences.getInstance();
    _targetFolderId = prefs.getString(_folderIdKey);
    _targetFolderName = prefs.getString(_folderNameKey);
    _savedGoogleEmail = prefs.getString(_accountKey);
    _autoDeleteAfterUpload = prefs.getBool(_cleanupKey) ?? false;
    _initialized = true;
  }

  Future<bool> get isSignedIn async {
    await _initIfNeeded();
    return _currentUser != null && _driveApi != null;
  }

  String? get currentUserEmail => _currentUser?.email;
  String? get targetFolderId => _targetFolderId;
  String? get targetFolderName => _targetFolderName;
  bool get autoDeleteAfterUpload => _autoDeleteAfterUpload;

  Future<void> setAutoDeleteAfterUpload(bool value) async {
    await _initIfNeeded();
    _autoDeleteAfterUpload = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleanupKey, value);
  }

  Future<void> setTargetFolder(String? folderId, String? folderName) async {
    await _initIfNeeded();
    _targetFolderId = folderId;
    _targetFolderName = folderId == null ? null : folderName;
    final prefs = await SharedPreferences.getInstance();
    if (folderId == null) {
      await prefs.remove(_folderIdKey);
      await prefs.remove(_folderNameKey);
    } else {
      await prefs.setString(_folderIdKey, folderId);
      await prefs.setString(_folderNameKey, folderName ?? 'Pasta');
    }
  }

  Future<void> signIn() async {
    await _initIfNeeded();
    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      await _useAccount(account);
    } catch (error) {
      debugPrint('Google Drive connection failed: $error');
      rethrow;
    }
  }

  Future<void> signInSilently() async {
    await _initIfNeeded();
    if (_currentUser != null && _driveApi != null) return;
    // Never inherit another teacher's Google identity when this app account has
    // not connected Drive or has a different saved Google account.
    if (_savedGoogleEmail == null) return;
    try {
      final account = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (account != null && account.email == _savedGoogleEmail) {
        await _useAccount(account, persistEmail: false);
      }
    } catch (error) {
      debugPrint('Google Drive silent connection failed: $error');
    }
  }

  Future<void> _useAccount(
    GoogleSignInAccount account, {
    bool persistEmail = true,
  }) async {
    _currentUser = account;
    await _initDriveApi();
    if (_driveApi == null) {
      _currentUser = null;
      throw Exception('Não foi possível autorizar o acesso ao Google Drive.');
    }
    if (persistEmail) {
      _savedGoogleEmail = account.email;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountKey, account.email);
    }
  }

  Future<void> _initDriveApi() async {
    final account = _currentUser;
    if (account == null) return;
    Map<String, String>? headers = await account.authorizationClient
        .authorizationHeaders(_scopes);
    if (headers == null) {
      await account.authorizationClient.authorizeScopes(_scopes);
      headers = await account.authorizationClient.authorizationHeaders(_scopes);
    }
    if (headers == null) return;
    _authClient?.close();
    final client = GoogleAuthClient(headers);
    _authClient = client;
    _driveApi = drive.DriveApi(client);
  }

  Future<List<drive.File>> getFolders() async {
    final api = await _requireDriveApi();
    final folders = await api.files
        .list(
          q: "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
          spaces: 'drive',
          $fields: 'files(id, name)',
          orderBy: 'name',
          pageSize: 1000,
        )
        .timeout(const Duration(seconds: 15));
    return folders.files ?? [];
  }

  Future<drive.File> createFolder(String name) async {
    final api = await _requireDriveApi();
    final folder = drive.File()
      ..name = name.trim()
      ..mimeType = 'application/vnd.google-apps.folder';
    return api.files.create(folder).timeout(const Duration(seconds: 15));
  }

  Future<String> uploadFile(File file, String filename) async {
    final api = await _requireDriveApi();
    if (!await file.exists())
      throw Exception('O arquivo desta foto não está disponível.');
    final driveFile = drive.File()
      ..name = filename
      ..parents = _targetFolderId == null ? null : [_targetFolderId!];
    final result = await api.files
        .create(
          driveFile,
          uploadMedia: drive.Media(file.openRead(), await file.length()),
        )
        .timeout(const Duration(seconds: 60));
    final id = result.id;
    if (id == null) throw Exception('O Google Drive não confirmou o arquivo.');
    return id;
  }

  Future<drive.DriveApi> _requireDriveApi() async {
    await _initIfNeeded();
    if (_driveApi == null) await signInSilently();
    final api = _driveApi;
    if (api == null) {
      throw Exception('Conecte sua conta do Google Drive para enviar fotos.');
    }
    return api;
  }

  Future<void> signOut() async {
    await _initIfNeeded();
    try {
      await GoogleSignIn.instance.signOut();
    } finally {
      _authClient?.close();
      _authClient = null;
      _currentUser = null;
      _driveApi = null;
      _savedGoogleEmail = null;
      _targetFolderId = null;
      _targetFolderName = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accountKey);
      await prefs.remove(_folderIdKey);
      await prefs.remove(_folderNameKey);
    }
  }
}
