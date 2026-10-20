import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:tinhaphone/auth/mobile_session.dart';
import 'package:tinhaphone/main.dart';
import 'package:tinhaphone/models/photo.dart';
import 'package:tinhaphone/services/db_service.dart';
import 'package:tinhaphone/services/prisma_api_service.dart';
import 'package:tinhaphone/screens/home_screen.dart';
import 'support/session_fixtures.dart';

Map<String, dynamic> accountJson(MobileSession session) => {
  'id': session.account.id,
  'name': session.account.name,
  'email': session.account.email,
  'profile': session.account.profile,
  'school_id': session.account.schoolId,
  'school_name': session.account.schoolName,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'professor: carregamento, turma vazia e erro não liberam a câmera',
    (tester) async {
      final reply = Completer<http.Response>();
      final controller = SessionController(
        store: MemoryTokenStore(),
        api: MobileAuthClient(client: MockClient((request) => reply.future)),
      )..session = teacherSession;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            session: teacherSession,
            controller: controller,
            database: _EmptyDatabase(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      reply.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Você ainda não está vinculado'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('Adicionar fotos'));
      await tester.pump();
      expect(
        find.textContaining('Peça o vínculo à coordenação'),
        findsOneWidget,
      );
      expect(find.text('Tirar foto'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();

      final failed = SessionController(
        store: MemoryTokenStore(),
        api: MobileAuthClient(
          client: MockClient(
            (_) async => http.Response('{"detail":"Erro"}', 500),
          ),
        ),
      )..session = teacherSession;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            session: teacherSession,
            controller: failed,
            database: _EmptyDatabase(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Não foi possível carregar suas turmas'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
      failed.dispose();
    },
  );

  testWidgets('botão + pede a turma e abre as opções de captura', (
    tester,
  ) async {
    final controller = SessionController(
      store: MemoryTokenStore(),
      api: MobileAuthClient(
        client: MockClient(
          (request) async => http.Response(
            request.url.path == '/api/classes/'
                ? '[{"id":1,"name":"Grupo 2"}]'
                : '[]',
            200,
          ),
        ),
      ),
    )..session = teacherSession;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          session: teacherSession,
          controller: controller,
          database: _EmptyDatabase(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adicionar fotos'));
    await tester.pumpAndSettle();
    expect(find.text('Selecionar turma'), findsWidgets);
    await tester.tap(find.text('Grupo 2').last);
    await tester.pumpAndSettle();
    expect(find.text('Adicionar fotos'), findsOneWidget);
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Escolher da galeria'), findsOneWidget);
    expect((await PrismaApiService(teacherSession).loadConfig()).classId, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('normaliza IP sem protocolo e mantém HTTPS e caminhos explícitos', () {
    expect(normalizeServer(' 10.0.2.2:8000/ '), 'http://10.0.2.2:8000');
    expect(normalizeServer('192.168.1.10:8000'), 'http://192.168.1.10:8000');
    expect(normalizeServer('api.example.com'), 'https://api.example.com');
    expect(
      normalizeServer('https://api.example.com/mobile/'),
      'https://api.example.com/mobile',
    );
    for (final value in [
      '',
      'endereço inválido',
      'ftp://example.com',
      'http://user:pass@example.com',
    ]) {
      expect(() => normalizeServer(value), throwsException);
    }
  });

  test(
    'logout durante gravação segura não reabre nem persiste sessão antiga',
    () async {
      final writing = Completer<void>();
      final release = Completer<void>();
      final store = _DelayedStore(writing, release);
      final controller = SessionController(
        store: store,
        api: MobileAuthClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'access_token': teacherSession.token,
                'account': accountJson(teacherSession),
              }),
              200,
            ),
          ),
        ),
      );
      final login = controller.login(
        teacherSession.baseUrl,
        'teacher@test.com',
        'secret1',
      );
      await writing.future;
      final logout = controller.logout();
      release.complete();
      await login;
      await logout;
      expect(controller.session, isNull);
      expect(store.value, isNull);
    },
  );

  test(
    'validar ao retornar recusa sessão inativa mas mantém fila/token sem rede',
    () async {
      var offline = true;
      final store = MemoryTokenStore('token-preservado');
      final controller = SessionController(
        store: store,
        api: MobileAuthClient(
          client: MockClient((_) async {
            if (offline) throw http.ClientException('Sem rede');
            return http.Response('{"detail":"Conta inativa"}', 403);
          }),
        ),
      )..session = teacherSession;
      await controller.revalidate();
      expect(controller.session, teacherSession);
      expect(store.value, 'token-preservado');
      offline = false;
      await controller.revalidate();
      expect(controller.session, isNull);
      expect(store.value, isNull);
    },
  );

  test(
    'login identifica o perfil no servidor e não persiste a senha',
    () async {
      final store = MemoryTokenStore();
      final client = MockClient((request) async {
        expect(request.url.path, '/api/mobile/auth/login');
        expect(jsonDecode(request.body), {
          'email': 'teacher@test.com',
          'password': 'secret1',
        });
        return http.Response(
          jsonEncode({
            'access_token': teacherSession.token,
            'account': accountJson(teacherSession),
          }),
          200,
        );
      });
      final controller = SessionController(
        api: MobileAuthClient(client: client),
        store: store,
      );
      await controller.login(
        teacherSession.baseUrl,
        ' TEACHER@test.com ',
        'secret1',
      );
      expect(controller.session!.account.isTeacher, isTrue);
      expect(store.value, contains(teacherSession.token));
      expect(store.value, isNot(contains('secret1')));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'restauração usa me e rejeita token expirado sem usar preferências antigas',
    () async {
      SharedPreferences.setMockInitialValues({
        'prisma_email': 'old@test.com',
        'prisma_password': 'old',
        'tinhakids_token': 'old',
      });
      final store = MemoryTokenStore(
        jsonEncode({'server': teacherSession.baseUrl, 'token': 'expired'}),
      );
      final controller = SessionController(
        store: store,
        api: MobileAuthClient(
          client: MockClient((request) async {
            expect(request.url.path, '/api/mobile/auth/me');
            expect(request.headers['Authorization'], 'Bearer expired');
            return http.Response('{"detail":"Sessão expirada"}', 401);
          }),
        ),
      );
      await controller.restore();
      expect(controller.session, isNull);
      expect(store.value, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('prisma_password'),
        'old',
      );
    },
  );

  test(
    'sem conexão não autentica offline e preserva token para validar depois',
    () async {
      final saved = jsonEncode({
        'server': teacherSession.baseUrl,
        'token': teacherSession.token,
      });
      final store = MemoryTokenStore(saved);
      final controller = SessionController(
        store: store,
        api: MobileAuthClient(
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
      );
      await controller.restore();
      expect(controller.session, isNull);
      expect(store.value, saved);
    },
  );

  test(
    'logout bloqueado durante envio; expiração aguarda operação e não muda outra sessão',
    () async {
      final controller = SessionController(store: MemoryTokenStore())
        ..session = teacherSession;
      expect(controller.beginWork(teacherSession), isTrue);
      expect(await controller.logout(), isFalse);
      await controller.invalidate(teacherSession);
      expect(controller.beginWork(teacherSession), isFalse);
      await controller.endWork();
      expect(controller.session, isNull);
      controller.session = familySession;
      await controller.invalidate(teacherSession);
      expect(controller.session, familySession);
    },
  );

  test('resposta atrasada do login não reabre sessão após sair', () async {
    final reply = Completer<http.Response>();
    final controller = SessionController(
      store: MemoryTokenStore(),
      api: MobileAuthClient(client: MockClient((_) => reply.future)),
    );
    final login = controller.login(
      teacherSession.baseUrl,
      'teacher@test.com',
      'secret1',
    );
    await controller.logout();
    reply.complete(
      http.Response(
        jsonEncode({
          'access_token': teacherSession.token,
          'account': accountJson(teacherSession),
        }),
        200,
      ),
    );
    await login;
    expect(controller.session, isNull);
  });

  test(
    'turma e limpeza são exclusivas da conta e não herdam senha ou turma antiga',
    () async {
      SharedPreferences.setMockInitialValues({
        'prisma_class_id': 999,
        'auto_delete_synced': true,
      });
      final first = PrismaApiService(teacherSession),
          second = PrismaApiService(otherTeacherSession);
      expect((await first.loadConfig()).classId, isNull);
      expect((await first.loadConfig()).autoDeleteSynced, isFalse);
      await first.saveConfig(
        const PrismaConfig(classId: 10, autoDeleteSynced: true),
      );
      expect((await second.loadConfig()).classId, isNull);
      expect((await second.loadConfig()).autoDeleteSynced, isFalse);
      expect((await first.loadConfig()).classId, 10);
    },
  );

  test(
    'envio usa destino da foto e recusa outra conta antes da rede',
    () async {
      final root = await Directory.systemTemp.createTemp('unified_upload_');
      try {
        final file = await File(
          p.join(root.path, 'photo.jpg'),
        ).writeAsBytes([1, 2, 3]);
        final photo = Photo(
          id: 'photo',
          localPath: file.path,
          timestamp: 1,
          accountScope: teacherSession.scope,
          ownerId: teacherSession.account.id,
          schoolId: teacherSession.account.schoolId,
          server: teacherSession.baseUrl,
          classId: 10,
        );
        var requests = 0;
        final client = MockClient((request) async {
          requests++;
          expect(request.headers['Authorization'], 'Bearer teacher-token');
          expect(request.body, contains('name="class_id"\r\n\r\n10'));
          return http.Response('{"id":25}', 201);
        });
        final api = PrismaApiService(teacherSession, client: client);
        await api.saveConfig(const PrismaConfig(classId: 20));
        expect(await api.uploadPhoto(photo), 25);
        expect(requests, 1);
        await expectLater(
          PrismaApiService(
            otherTeacherSession,
            client: client,
          ).uploadPhoto(photo),
          throwsStateError,
        );
        await expectLater(
          PrismaApiService(familySession, client: client).uploadPhoto(photo),
          throwsStateError,
        );
        expect(requests, 1);
        final anotherServer = MobileSession(
          token: 'x',
          baseUrl: 'http://other.test',
          account: teacherSession.account,
        );
        expect(anotherServer.scope, isNot(teacherSession.scope));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'fila SQLite nova separa fotos e logs e preserva o banco antigo',
    () async {
      sqfliteFfiInit();
      final root = await Directory.systemTemp.createTemp('unified_database_');
      final factory = createDatabaseFactoryFfi();
      await factory.setDatabasesPath(root.path);
      final old = await File(
        p.join(root.path, 'photo_vault.db'),
      ).writeAsBytes([7, 8, 9]);
      final first = DbService(teacherSession.scope, factory: factory),
          second = DbService(otherTeacherSession.scope, factory: factory);
      try {
        final photo = Photo(
          id: 'local',
          localPath: '/photo.jpg',
          timestamp: 1,
          accountScope: teacherSession.scope,
          ownerId: '1',
          schoolId: 1,
          server: teacherSession.baseUrl,
          classId: 10,
          status: SyncStatus.syncing,
        );
        await first.savePhoto(photo);
        await first.saveLog('Erro privado', 'Detalhes');
        expect(await second.getPhotos(), isEmpty);
        expect(await second.getLogs(), isEmpty);
        await expectLater(second.savePhoto(photo), throwsStateError);
        await first.recoverInterruptedUploads();
        final saved = (await first.getPhotos()).single;
        expect(saved.classId, 10);
        expect(saved.status, SyncStatus.pending);
        expect(saved.ownerId, '1');
        expect(await old.readAsBytes(), [7, 8, 9]);
      } finally {
        await first.close();
        await second.close();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets('login único exibe feedback de erro sem abrir nenhuma área', (
    tester,
  ) async {
    final controller = SessionController(
      store: MemoryTokenStore(),
      api: MobileAuthClient(
        client: MockClient(
          (_) async =>
              http.Response('{"detail":"E-mail ou senha inválidos."}', 401),
        ),
      ),
    )..initialized = true;
    await tester.pumpWidget(TinhaphoneApp(controller: controller));
    expect(find.text('TinhaKids'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'bad@test.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'wrong',
    );
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(find.text('Área da família'), findsNothing);
    expect(find.text('Câmera escolar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('conta familiar sem alunos abre apenas sua área e pode sair', (
    tester,
  ) async {
    final controller =
        SessionController(
            store: MemoryTokenStore(),
            api: MobileAuthClient(
              client: MockClient((request) async {
                expect(request.url.path, '/api/v1/children/');
                return http.Response('[]', 200);
              }),
            ),
          )
          ..initialized = true
          ..session = familySession;
    await tester.pumpWidget(TinhaphoneApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Área da família'), findsOneWidget);
    expect(find.textContaining('Nenhum aluno está vinculado'), findsOneWidget);
    expect(find.text('Tirar foto'), findsNothing);
    await tester.tap(find.byTooltip('Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Área da família'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('galeria do professor filtra e seleciona fotos da turma', (
    tester,
  ) async {
    final controller = SessionController(
      store: MemoryTokenStore(),
      api: MobileAuthClient(
        client: MockClient((request) async {
          if (request.url.path == '/api/classes/')
            return http.Response('[{"id":1,"name":"Grupo 2"}]', 200);
          if (request.url.path == '/api/photos/class/1')
            return http.Response('[]', 200);
          if (request.url.path == '/api/tags/') return http.Response('[]', 200);
          return http.Response('[]', 200);
        }),
      ),
    )..session = teacherSession;
    SharedPreferences.setMockInitialValues({
      'unified_teacher_${teacherSession.scope}_class': 1,
    });
    final photo = Photo(
      id: 'local-1',
      localPath: 'arquivo-ausente.jpg',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      accountScope: teacherSession.scope,
      ownerId: teacherSession.account.id,
      schoolId: teacherSession.account.schoolId,
      server: teacherSession.baseUrl,
      classId: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          session: teacherSession,
          controller: controller,
          database: _GalleryDatabase(photo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Grupo 2'), findsOneWidget);
    expect(find.text('Todas  1'), findsOneWidget);
    await tester.longPress(find.byIcon(Icons.schedule).first);
    await tester.pumpAndSettle();
    expect(find.text('1 selecionada(s)'), findsOneWidget);
    expect(find.text('Mover'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _DelayedStore extends MemoryTokenStore {
  final Completer<void> writing, release;
  _DelayedStore(this.writing, this.release);
  @override
  Future<void> write(String value) async {
    writing.complete();
    await release.future;
    await super.write(value);
  }
}

class _EmptyDatabase extends DbService {
  _EmptyDatabase() : super(teacherSession.scope);
  @override
  Future<List<Photo>> getPhotos() async => [];
  @override
  Future<void> recoverInterruptedUploads() async {}
  @override
  Future<void> saveLog(String message, String? details) async {}
  @override
  Future<void> close() async {}
}

class _GalleryDatabase extends _EmptyDatabase {
  final Photo photo;
  _GalleryDatabase(this.photo);
  @override
  Future<List<Photo>> getPhotos() async => [photo];
}
