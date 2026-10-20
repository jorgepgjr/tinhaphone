import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../auth/mobile_session.dart';
import '../models/photo.dart';

class PrismaConfig {
  final int? classId;
  final bool autoDeleteSynced;
  const PrismaConfig({this.classId, this.autoDeleteSynced = false});
}

class PrismaApiService {
  final MobileSession session;
  final Future<void> Function()? onUnauthorized;
  final http.Client client;
  PrismaApiService(this.session, {this.onUnauthorized, http.Client? client})
    : client = client ?? http.Client();
  String get _prefix => 'unified_teacher_${session.scope}_';
  Future<PrismaConfig> loadConfig() async {
    final p = await SharedPreferences.getInstance();
    return PrismaConfig(
      classId: p.getInt('${_prefix}class'),
      autoDeleteSynced: p.getBool('${_prefix}cleanup') ?? false,
    );
  }

  Future<void> saveConfig(PrismaConfig config) async {
    final p = await SharedPreferences.getInstance();
    if (config.classId == null) {
      await p.remove('${_prefix}class');
    } else {
      await p.setInt('${_prefix}class', config.classId!);
    }
    await p.setBool('${_prefix}cleanup', config.autoDeleteSynced);
  }

  Future<void> _check(http.Response response) async {
    if ([401, 403].contains(response.statusCode)) await onUnauthorized?.call();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      readResponse(response);
    }
  }

  Future<List<Map<String, dynamic>>> getClasses() async {
    if (!session.account.isTeacher) {
      throw StateError('Acesso exclusivo do professor.');
    }
    final response = await client
        .get(
          Uri.parse('${session.baseUrl}/api/classes/'),
          headers: {'Authorization': 'Bearer ${session.token}'},
        )
        .timeout(const Duration(seconds: 15));
    await _check(response);
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  bool owns(Photo photo) =>
      session.account.isTeacher &&
      photo.accountScope == session.scope &&
      photo.ownerId == session.account.id &&
      photo.schoolId == session.account.schoolId &&
      photo.server == session.baseUrl &&
      photo.classId != null;
  Future<int> uploadPhoto(Photo photo) async {
    if (!owns(photo)) throw StateError('Esta foto pertence a outra conta.');
    // Nunca usa a turma atualmente selecionada para alterar uma foto pendente.
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${session.baseUrl}/api/photos/upload'),
          )
          ..headers['Authorization'] = 'Bearer ${session.token}'
          ..fields['class_id'] = photo.classId.toString()
          ..fields['client_upload_id'] = photo.id
          ..fields['title'] = 'Foto enviada pelo TinhaKids'
          ..files.add(
            await http.MultipartFile.fromPath(
              'file',
              File(photo.localPath).path,
            ),
          );
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 45)),
    ).timeout(const Duration(seconds: 45));
    await _check(response);
    return readResponse(response)['id'] as int;
  }

  Future<dynamic> _jsonRequest(
    String method,
    String path, [
    Object? body,
  ]) async {
    final uri = Uri.parse('${session.baseUrl}$path');
    final headers = {
      'Authorization': 'Bearer ${session.token}',
      'Content-Type': 'application/json',
    };
    final encoded = body == null ? null : jsonEncode(body);
    final response = await switch (method) {
      'POST' => client.post(uri, headers: headers, body: encoded),
      'PUT' => client.put(uri, headers: headers, body: encoded),
      'DELETE' => client.delete(uri, headers: headers),
      _ => client.get(uri, headers: headers),
    }.timeout(const Duration(seconds: 20));
    await _check(response);
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> getTags() async =>
      (await _jsonRequest('GET', '/api/tags/') as List)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> getClassPhotos(int classId) async =>
      (await _jsonRequest('GET', '/api/photos/class/$classId') as List)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createTag(String name) async =>
      (await _jsonRequest('POST', '/api/tags/', {'name': name}))
          as Map<String, dynamic>;

  Future<void> updateTags(
    List<int> photoIds,
    List<int> tagIds, {
    bool remove = false,
  }) async {
    await _jsonRequest('POST', '/api/photos/tags/batch', {
      'photo_ids': photoIds,
      'tag_ids': tagIds,
      'remove': remove,
    });
  }

  Future<void> movePhoto(int photoId, int classId) async {
    await _jsonRequest('PUT', '/api/photos/$photoId/class', {
      'class_id': classId,
    });
  }

  Future<void> deleteRemotePhoto(int photoId) async {
    await _jsonRequest('DELETE', '/api/photos/$photoId');
  }
}
