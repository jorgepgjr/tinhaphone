import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinhaphone/auth/mobile_session.dart';
import 'package:tinhaphone/main.dart';

import 'support/session_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    final font = FontLoader('Nunito')
      ..addFont(rootBundle.load('lib/assets/fonts/Nunito.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<SessionController> openLogin(
    WidgetTester tester, {
    Size size = const Size(423, 752),
    Future<http.Response> Function(http.Request)? respond,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SessionController(
      store: MemoryTokenStore(),
      api: MobileAuthClient(
        client: MockClient(
          respond ??
              (_) async => http.Response('{"detail":"Acesso inválido."}', 401),
        ),
      ),
    )..initialized = true;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('login-preview'),
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: TinhaphoneApp(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
    return controller;
  }

  testWidgets('login reproduz a referência visual', (tester) async {
    debugDisableShadows = false;
    try {
      await openLogin(tester);
      expect(find.text('TinhaKids'), findsOneWidget);
      expect(
        find.text('Cada momento escolar merece ser compartilhado.'),
        findsOneWidget,
      );
      expect(find.text('Endereço da API'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('login-preview')),
        matchesGoldenFile('goldens/login.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('mostra e oculta senha sem alterar o conteúdo', (tester) async {
    await openLogin(tester);
    final password = find.widgetWithText(TextFormField, 'Senha');
    await tester.enterText(password, 'senha-de-teste');
    expect(
      tester.widget<TextFormField>(password).controller!.text,
      'senha-de-teste',
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Mostrar senha'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isFalse,
    );
    await tester.tap(find.byTooltip('Ocultar senha'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
      isTrue,
    );
    expect(
      tester.widget<TextFormField>(password).controller!.text,
      'senha-de-teste',
    );
  });

  testWidgets('servidor é expansível e valida o endereço informado', (
    tester,
  ) async {
    await openLogin(tester);
    await tester.tap(find.text('Servidor de testes'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'teste@escola.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'teste',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Endereço da API'),
      'endereço inválido',
    );
    await tester.ensureVisible(find.text('Entrar'));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe um endereço válido.'), findsOneWidget);
    await tester.tap(find.text('Servidor de testes'));
    await tester.pumpAndSettle();
    expect(find.text('Endereço da API'), findsNothing);
  });

  testWidgets('validação vazia não envia requisições', (tester) async {
    var requests = 0;
    await openLogin(
      tester,
      respond: (_) async {
        requests++;
        return http.Response('{}', 401);
      },
    );
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('carregamento bloqueia reenvios e mantém feedback de erro', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var requests = 0;
    await openLogin(
      tester,
      respond: (_) {
        requests++;
        return response.future;
      },
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'teste@escola.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'teste',
    );
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(requests, 1);
    response.complete(
      http.Response('{"detail":"E-mail ou senha inválidos."}', 401),
    );
    await tester.pumpAndSettle();
    expect(find.text('E-mail ou senha inválidos.'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Senha'))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'tela pequena com teclado e texto ampliado permite rolar o formulário',
    (tester) async {
      await openLogin(tester, size: const Size(320, 568), textScale: 1.5);
      tester.view.viewInsets = const FakeViewPadding(bottom: 230);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Servidor de testes'));
      await tester.tap(find.text('Servidor de testes'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Entrar'));
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();
      expect(find.text('Informe sua senha.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
