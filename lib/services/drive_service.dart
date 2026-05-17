import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class DriveService {
  static final DriveService _instance = DriveService._internal();
  factory DriveService() => _instance;
  DriveService._internal();

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;
  bool _initialized = false;
  String? _targetFolderId;
  String? _targetFolderName;

  final List<String> _scopes = [drive.DriveApi.driveFileScope];

  // IMPORTANTE PARA ANDROID:
  // Crie uma credencial do tipo "Web Application" (Aplicativo da Web) no Google Cloud Console
  // e cole o Client ID gerado aqui. O Android precisa dele para acessar o Drive API.
  static const String _serverClientId =
      '498748867390-o4cs1mahtk733jjtn24o3n2ai4uinokg.apps.googleusercontent.com';

  Future<void> _initIfNeeded() async {
    if (_initialized) return;

    await GoogleSignIn.instance.initialize(
      serverClientId: Platform.isAndroid ? _serverClientId : null,
    );

    final prefs = await SharedPreferences.getInstance();
    _targetFolderId = prefs.getString('drive_target_folder_id');
    _targetFolderName = prefs.getString('drive_target_folder_name');

    _initialized = true;
  }

  Future<bool> get isSignedIn async {
    return _currentUser != null;
  }

  String? get targetFolderId => _targetFolderId;
  String? get targetFolderName => _targetFolderName;

  Future<void> setTargetFolder(String folderId, String folderName) async {
    _targetFolderId = folderId;
    _targetFolderName = folderName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_target_folder_id', folderId);
    await prefs.setString('drive_target_folder_name', folderName);
  }

  Future<void> signIn() async {
    await _initIfNeeded();
    try {
      _currentUser = await GoogleSignIn.instance.authenticate(
        scopeHint: _scopes,
      );
      if (_currentUser != null) {
        await _initDriveApi();
      }
    } catch (error) {
      debugPrint('Error signing in: $error');
      rethrow;
    }
  }

  Future<void> signInSilently() async {
    await _initIfNeeded();

    // Se já estiver logado na sessão atual, não tenta logar de novo
    if (_currentUser != null) return;

    try {
      _currentUser = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (_currentUser != null) {
        await _initDriveApi();
      }
    } catch (error) {
      debugPrint('Error signing in silently: $error');
    }
  }

  Future<void> _initDriveApi() async {
    if (_currentUser == null) {
      debugPrint('DriveService: _currentUser is null in _initDriveApi');
      return;
    }

    try {
      // Primeiro tentamos pegar os headers direto se a pessoa já deu a permissão antes
      Map<String, String>? headers = await _currentUser!.authorizationClient
          .authorizationHeaders(_scopes);

      // Se não conseguimos, pedimos a permissão de forma interativa
      if (headers == null) {
        debugPrint('DriveService: headers are null, requesting scopes...');
        await _currentUser!.authorizationClient.authorizeScopes(_scopes);
        headers = await _currentUser!.authorizationClient.authorizationHeaders(
          _scopes,
        );
        if (headers == null) {
          debugPrint('DriveService: user denied scopes');
        }
      }

      if (headers == null) {
        debugPrint('DriveService: still no headers after trying to authorize');
        return;
      }

      final client = GoogleAuthClient(headers);
      _driveApi = drive.DriveApi(client);
      debugPrint('DriveService: _driveApi initialized successfully!');
    } catch (e) {
      debugPrint('DriveService: error initializing drive api: $e');
    }
  }

  Future<List<drive.File>> getFolders() async {
    if (_driveApi == null) {
      await _initDriveApi();
      if (_driveApi == null) {
        throw Exception(
          'Not signed in to Google Drive or missing authorization',
        );
      }
    }

    try {
      final fileList = await _driveApi!.files.list(
        q: "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      return fileList.files ?? [];
    } catch (e) {
      debugPrint('Error getting folders: $e');
      rethrow;
    }
  }

  Future<drive.File> createFolder(String name) async {
    if (_driveApi == null) throw Exception('Drive API not initialized');

    var folder = drive.File();
    folder.name = name;
    folder.mimeType = 'application/vnd.google-apps.folder';

    return await _driveApi!.files.create(folder);
  }

  Future<String?> uploadFile(File file, String filename) async {
    if (_driveApi == null) {
      await _initDriveApi();
      if (_driveApi == null) {
        throw Exception(
          'Not signed in to Google Drive or missing authorization',
        );
      }
    }

    try {
      var driveFile = drive.File();
      driveFile.name = filename;

      if (_targetFolderId != null) {
        driveFile.parents = [_targetFolderId!];
      }

      final result = await _driveApi!.files.create(
        driveFile,
        uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      );
      return result.id;
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _initIfNeeded();
    await GoogleSignIn.instance.signOut();
    _currentUser = null;
    _driveApi = null;

    // Do we clear the target folder on sign out? Probably yes for safety.
    _targetFolderId = null;
    _targetFolderName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drive_target_folder_id');
    await prefs.remove('drive_target_folder_name');
  }
}
