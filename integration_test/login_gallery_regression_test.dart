import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tinhaphone/auth/mobile_session.dart';
import 'package:tinhaphone/main.dart';
import 'package:tinhaphone/services/prisma_api_service.dart';
import 'unified_app_test.dart' show IntegrationTokenStore, waitUntil;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('servidor editável, adicionar fotos e informações familiares', (
    tester,
  ) async {
    final store = IntegrationTokenStore();
    await store.clear();
    final controller = SessionController(store: store)..initialized = true;
    await tester.pumpWidget(TinhaphoneApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servidor de testes'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-address')),
      '10.0.2.2:8000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'professora@girassol.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'mypassword',
    );
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await waitUntil(tester, () => controller.session != null);
    final api = PrismaApiService(controller.session!);
    final config = await api.loadConfig();
    try {
      // A primeira entrada não possui turma salva: o + deve orientar a seleção.
      await waitUntil(
        tester,
        () =>
            find.byType(FloatingActionButton).evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Adicionar fotos'));
      await tester.pumpAndSettle();
      if (find.text('Selecionar turma').evaluate().isNotEmpty) {
        await tester.tap(find.text('Grupo 2').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Adicionar fotos'), findsOneWidget);
      expect(find.text('Tirar foto'), findsOneWidget);
      expect(find.text('Escolher da galeria'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await controller.logout();
      await tester.pumpAndSettle();
      await controller.login(
        '10.0.2.2:8000',
        'pai.teste@girassol.com',
        'mypassword',
      );
      await waitUntil(
        tester,
        () => find.byTooltip('Informações da publicação').evaluate().isNotEmpty,
      );
      await tester.tap(find.byTooltip('Informações da publicação').first);
      await tester.pumpAndSettle();
      expect(find.text('Compartilhado por'), findsOneWidget);
      expect(find.text('Fotografias'), findsOneWidget);
      expect(find.text('Sobre este momento'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Fechar informações'));
      await tester.pumpAndSettle();
    } finally {
      await api.saveConfig(config);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await store.clear();
    }
  });
}
