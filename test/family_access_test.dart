import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinhaphone/family/core/models/child.dart';
import 'package:tinhaphone/family/core/models/post.dart';
import 'package:tinhaphone/family/core/models/project.dart';
import 'package:tinhaphone/family/providers/app_state.dart';
import 'package:tinhaphone/family/services/tinhakids_api_service.dart';

const firstChild = Child(
  id: 'filho',
  name: 'FILHO TESTE',
  avatarUrl: '',
  classroom: 'Grupo 2',
);
const secondChild = Child(
  id: 'sofia',
  name: 'Sofia',
  avatarUrl: '',
  classroom: 'Grupo 2',
);

Post postFor(String id) => Post(
  id: 'post-$id',
  childIds: [id],
  teacherName: 'Professora',
  teacherAvatarUrl: '',
  classroomName: 'Grupo 2',
  imageUrl: '/foto-$id.png',
  caption: 'Somente $id',
  createdAt: DateTime(2026),
  likesCount: 0,
);

class FamilyApi extends TinhaKidsApiService {
  List<Child> available = [firstChild];
  String? savedChild;
  final pending = <String, Completer<List<Post>>>{};
  final requested = <String>[];
  bool failPosts = false;

  @override
  Future<String> login(String identifier, String password) async => identifier;
  @override
  Future<String?> getSavedToken() async => 'parent';
  @override
  Future<String?> getSavedChildId() async => savedChild;
  @override
  Future<void> saveSelectedChild(String childId) async {
    savedChild = childId;
  }

  @override
  Future<void> logout() async {
    savedChild = null;
  }

  @override
  Future<List<Child>> getChildren(String token) async => List.of(available);
  @override
  Future<List<Post>> getPosts(String token, String childId) async {
    requested.add(childId);
    if (failPosts) throw Exception('Acesso recusado');
    return pending.remove(childId)?.future ?? [postFor(childId)];
  }

  @override
  Future<List<Project>> getProjects(String token, String childId) async => [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'credenciais antigas não iniciam uma sessão fictícia em erro 401',
    () async {
      final api = TinhaKidsApiService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'detail': 'Credenciais inválidas.'}),
            401,
          ),
        ),
      );
      await expectLater(
        api.login('teste@teste.com', '123456'),
        throwsException,
      );
      expect(await api.getSavedToken(), isNull);
    },
  );

  test('API indisponível não inicia uma sessão fictícia', () async {
    final api = TinhaKidsApiService(
      client: MockClient(
        (request) async => throw http.ClientException('Sem conexão'),
      ),
    );
    await expectLater(api.login('teste@teste.com', '123456'), throwsException);
    expect(await api.getSavedToken(), isNull);
  });

  test('sessão de demonstração antiga é descartada', () async {
    SharedPreferences.setMockInitialValues({
      'tinhakids_token': 'tinhakids-local-demo',
      'tinhakids_selected_child': 'pedro',
    });
    final api = TinhaKidsApiService();
    expect(await api.getSavedToken(), isNull);
    expect(await api.getSavedChildId(), isNull);
  });

  test('filhos são carregados da API com autenticação', () async {
    final api = TinhaKidsApiService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/children/');
        expect(request.headers['Authorization'], 'Bearer conta-real');
        return http.Response(
          jsonEncode([
            {
              'id': 'filho',
              'name': 'FILHO TESTE',
              'avatar_url': '',
              'classroom': 'Grupo 2',
            },
          ]),
          200,
        );
      }),
    );
    expect((await api.getChildren('conta-real')).map((child) => child.name), [
      'FILHO TESTE',
    ]);
  });

  test(
    'login carrega somente os filhos vinculados e ignora seleção externa',
    () async {
      final api = FamilyApi();
      final notifier = AppNotifier(api);
      addTearDown(notifier.dispose);
      await notifier.login('parent', 'secret');
      expect(notifier.state.children, [firstChild]);
      expect(notifier.state.posts.single.childIds, ['filho']);
      await notifier.selectChild(secondChild);
      expect(notifier.state.selectedChild, firstChild);
      expect(api.requested, ['filho']);
    },
  );

  test('restauração não reutiliza aluno salvo de outra conta', () async {
    final api = FamilyApi()..savedChild = 'sofia';
    final notifier = AppNotifier(api);
    addTearDown(notifier.dispose);
    expect(await notifier.restoreSession(), isTrue);
    expect(notifier.state.selectedChild, firstChild);
    expect(notifier.state.posts.single.childIds, ['filho']);
  });

  test('atualizar reflete troca e remoção de vínculos no Prisma', () async {
    final api = FamilyApi();
    final notifier = AppNotifier(api);
    addTearDown(notifier.dispose);
    await notifier.login('parent', 'secret');
    api.available = [secondChild];
    await notifier.refresh();
    expect(notifier.state.children, [secondChild]);
    expect(notifier.state.selectedChild, secondChild);
    expect(notifier.state.posts.single.childIds, ['sofia']);
    api.available = [];
    await notifier.refresh();
    expect(notifier.state.children, isEmpty);
    expect(notifier.state.selectedChild, isNull);
    expect(notifier.state.posts, isEmpty);
    expect(notifier.state.projects, isEmpty);
  });

  test('resposta atrasada não mistura fotos ao trocar entre filhos', () async {
    final api = FamilyApi()..available = [firstChild, secondChild];
    final notifier = AppNotifier(api);
    addTearDown(notifier.dispose);
    await notifier.login('parent', 'secret');
    final delayed = Completer<List<Post>>();
    api.pending['sofia'] = delayed;
    final switching = notifier.selectChild(secondChild);
    expect(notifier.state.posts, isEmpty);
    await Future<void>.delayed(Duration.zero);
    await notifier.selectChild(firstChild);
    delayed.complete([postFor('sofia')]);
    await switching;
    expect(notifier.state.selectedChild, firstChild);
    expect(notifier.state.posts.single.childIds, ['filho']);
  });

  test(
    'sair impede que resposta pendente reabra conteúdo da família',
    () async {
      final api = FamilyApi()..available = [firstChild, secondChild];
      final notifier = AppNotifier(api);
      addTearDown(notifier.dispose);
      await notifier.login('parent', 'secret');
      final delayed = Completer<List<Post>>();
      api.pending['sofia'] = delayed;
      final switching = notifier.selectChild(secondChild);
      await Future<void>.delayed(Duration.zero);
      await notifier.logout();
      delayed.complete([postFor('sofia')]);
      await switching;
      expect(notifier.state.token, isNull);
      expect(notifier.state.children, isEmpty);
      expect(notifier.state.posts, isEmpty);
    },
  );

  test('erro de acesso não deixa fotos antigas visíveis', () async {
    final api = FamilyApi();
    final notifier = AppNotifier(api);
    addTearDown(notifier.dispose);
    await notifier.login('parent', 'secret');
    api.failPosts = true;
    await notifier.refresh();
    expect(notifier.state.posts, isEmpty);
    expect(notifier.state.error, 'Acesso recusado');
  });
}
