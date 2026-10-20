import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:share_handler/share_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tinhaphone/auth/mobile_session.dart';
import 'package:tinhaphone/main.dart';
import 'package:tinhaphone/services/db_service.dart';
import 'package:tinhaphone/services/prisma_api_service.dart';

/// Usa somente a chave de integração, sem substituir o token normal do app.
class IntegrationTokenStore implements TokenStore {
  final storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const key = 'tinhakids_integration_session_v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

/// Simula a entrega do plugin; captura, SQLite, token e rede continuam nativos/reais.
class TestSharing extends ShareHandlerPlatform {
  final events = StreamController<SharedMedia>.broadcast();
  int resets = 0;
  @override
  Stream<SharedMedia> get sharedMediaStream => events.stream;
  @override
  Future<SharedMedia?> getInitialSharedMedia() async => null;
  @override
  Future<void> resetInitialSharedMedia() async {
    resets++;
  }
}

Future<void> waitUntil(
  WidgetTester tester,
  FutureOr<bool> Function() condition, {
  String reason = 'A operação não foi concluída',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail(reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const password = String.fromEnvironment(
    'TEST_PASSWORD',
    defaultValue: 'mypassword',
  );
  const teacherEmail = String.fromEnvironment(
    'TEST_TEACHER',
    defaultValue: 'professora@girassol.com',
  );
  const familyEmail = String.fromEnvironment(
    'TEST_FAMILY',
    defaultValue: 'pai.teste@girassol.com',
  );

  testWidgets(
    'Android: sessão segura, turma, câmera/envio e família sem acesso à fila',
    (tester) async {
      if (Platform.isAndroid) {
        expect(
          (await getApplicationDocumentsDirectory()).path,
          contains('com.example.tinhaphone.integration/'),
          reason: 'Testes de integração devem usar o pacote isolado.',
        );
      }
      final store = IntegrationTokenStore();
      await store.clear();
      final controller = SessionController(store: store)..initialized = true;
      final oldSharing = ShareHandlerPlatform.instance;
      final sharing = TestSharing();
      ShareHandlerPlatform.instance = sharing;
      PrismaConfig? savedConfig;
      PrismaApiService? teacherApi;
      try {
        await tester.pumpWidget(TinhaphoneApp(controller: controller));
        expect(find.text('Entrar'), findsOneWidget);
        await controller.login(defaultServer, teacherEmail, 'senha-invalida');
        await tester.pumpAndSettle();
        expect(controller.session, isNull);
        expect(find.textContaining('senha inválidos'), findsOneWidget);

        // Autenticação real; as credenciais nunca são gravadas no aparelho.
        await controller.login(defaultServer, teacherEmail, password);
        expect(controller.error, isNull);
        expect(controller.session?.account.isTeacher, isTrue);
        final teacher = controller.session!;
        teacherApi = PrismaApiService(teacher);
        savedConfig = await teacherApi.loadConfig();
        await teacherApi.saveConfig(const PrismaConfig());
        await waitUntil(
          tester,
          () => find.text('Área do professor').evaluate().isNotEmpty,
        );
        await waitUntil(
          tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        final classes = await teacherApi.getClasses();
        expect(
          classes,
          isNotEmpty,
          reason: 'Vincule uma turma ao professor de desenvolvimento.',
        );
        final classId = classes.first['id'] as int;
        final className = classes.first['name'] as String;
        await tester.tap(find.byTooltip('Adicionar fotos'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(className).last);
        await tester.pumpAndSettle();
        expect((await teacherApi.loadConfig()).classId, classId);
        expect(find.text('Área da família'), findsNothing);

        final database = DbService(teacher.scope);
        final before = (await database.getPhotos())
            .map((photo) => photo.id)
            .toSet();
        await tester.tap(find.text('Tirar foto'));
        await tester.pump();
        await waitUntil(
          tester,
          () => find.byType(CameraPreview).evaluate().isNotEmpty,
          reason: 'Câmera do emulador não iniciou; verifique a permissão.',
        );
        await tester.tap(find.byKey(const Key('capture_photo')));
        await waitUntil(
          tester,
          () async => (await database.getPhotos()).any(
            (photo) =>
                !before.contains(photo.id) && photo.prismaPhotoId != null,
          ),
          reason: 'Captura/envio não confirmado.',
        );
        final captured = (await database.getPhotos()).firstWhere(
          (photo) => !before.contains(photo.id) && photo.prismaPhotoId != null,
        );
        expect(captured.accountScope, teacher.scope);
        expect(captured.classId, classId);
        expect(await File(captured.localPath).exists(), isTrue);
        await waitUntil(tester, () => !controller.busy);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Recebimento simulado no limite do plugin, com upload real de uma cópia.
        sharing.events.add(
          SharedMedia(
            attachments: [
              SharedAttachment(
                path: captured.localPath,
                type: SharedAttachmentType.image,
              ),
            ],
          ),
        );
        await waitUntil(
          tester,
          () async =>
              (await database.getPhotos())
                  .where(
                    (photo) =>
                        !before.contains(photo.id) &&
                        photo.prismaPhotoId != null,
                  )
                  .length >=
              2,
        );
        await waitUntil(tester, () => !controller.busy);

        // A opção de limpeza remove as cópias confirmadas, não dados do servidor.
        await tester.tap(find.byTooltip('Configurações'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
        await tester.ensureVisible(find.text('Salvar'));
        await tester.tap(find.text('Salvar'));
        await tester.pumpAndSettle();
        expect(
          (await database.getPhotos()).where(
            (photo) => !before.contains(photo.id),
          ),
          isEmpty,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();

        final restored = SessionController(store: store);
        await restored.restore();
        expect(restored.session?.account.id, teacher.account.id);
        restored.dispose();
        await tester.tap(find.byTooltip('Configurações'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Sair'));
        await tester.tap(find.text('Sair'));
        await tester.pumpAndSettle();
        expect(find.text('Entrar'), findsOneWidget);
        await controller.login(defaultServer, familyEmail, password);
        expect(controller.error, isNull);
        await waitUntil(
          tester,
          () => find.text('Área da família').evaluate().isNotEmpty,
        );
        await waitUntil(
          tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        );
        expect(find.text('Área do professor'), findsNothing);
        expect(find.text('Tirar foto'), findsNothing);
        final previous = sharing.resets;
        sharing.events.add(
          SharedMedia(
            attachments: [
              SharedAttachment(
                path: '/arquivo-inexistente.jpg',
                type: SharedAttachmentType.image,
              ),
            ],
          ),
        );
        await waitUntil(tester, () => sharing.resets > previous);
        expect(controller.busy, isFalse);
        await tester.tap(find.text('Portfólio').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Perfil').last);
        await tester.pumpAndSettle();
        expect(find.text('Área da família'), findsOneWidget);
        await tester.tap(find.byTooltip('Sair'));
        await tester.pumpAndSettle();
        expect(find.text('Entrar'), findsOneWidget);
      } finally {
        if (savedConfig != null && teacherApi != null)
          await teacherApi.saveConfig(savedConfig);
        await tester.pumpWidget(const SizedBox());
        ShareHandlerPlatform.instance = oldSharing;
        await sharing.events.close();
        await store.clear();
        controller.dispose();
      }
    },
  );
}
