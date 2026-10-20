import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinhaphone/auth/mobile_session.dart';
import 'package:tinhaphone/family/core/models/child.dart';
import 'package:tinhaphone/family/core/models/post.dart';
import 'package:tinhaphone/family/core/models/project.dart';
import 'package:tinhaphone/family/core/theme/app_theme.dart';
import 'package:tinhaphone/family/providers/app_state.dart';
import 'package:tinhaphone/family/services/tinhakids_api_service.dart';
import 'package:tinhaphone/family/views/main_layout.dart';

import 'support/session_fixtures.dart';

const _children = [
  Child(id: 'sofia', name: 'Sofia', avatarUrl: '', classroom: 'Grupo 2'),
  Child(id: 'miguel', name: 'Miguel', avatarUrl: '', classroom: 'Grupo 2'),
  Child(id: 'helena', name: 'Helena', avatarUrl: '', classroom: 'Grupo 2'),
];

Post _postFor(String child) => Post(
  id: 'post-$child',
  childIds: [child],
  teacherName: 'Professora Escola Girassol',
  teacherAvatarUrl: '',
  classroomName: 'Grupo 2',
  imageUrl: 'https://images.test/$child/0.png',
  imageUrls: List.generate(
    4,
    (index) => 'https://images.test/$child/$index.png',
  ),
  caption:
      'Publicação de teste de ${_children.firstWhere((item) => item.id == child).name}',
  createdAt: DateTime(2026, 10, 4, 1, 35),
  likesCount: 0,
);

class _FeedApi extends TinhaKidsApiService {
  List<Child> children = List.of(_children);
  bool emptyPosts = false;
  bool fail = false;
  bool missingPhoto = false;
  int refreshes = 0;
  final requested = <String>[];
  Completer<List<Post>>? pending;

  @override
  Future<String?> getSavedToken() async => 'family-test';
  @override
  Future<String?> getSavedChildId() async => null;
  @override
  Future<void> saveSelectedChild(String childId) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<List<Child>> getChildren(String token) async {
    refreshes++;
    if (fail) throw Exception('Sem conexão');
    return children;
  }

  @override
  Future<List<Post>> getPosts(String token, String childId) async {
    requested.add(childId);
    if (pending != null) return pending!.future;
    return emptyPosts
        ? []
        : [
            missingPhoto
                ? _postFor(childId).copyWith(imageUrl: '', imageUrls: [''])
                : _postFor(childId),
          ];
  }

  @override
  Future<List<Project>> getProjects(String token, String childId) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image fixture;
  setUpAll(() async {
    await (FontLoader(
      'Nunito',
    )..addFont(rootBundle.load('lib/assets/fonts/Nunito.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final image = Completer<ui.Image>();
    // Cor de teste, sem pessoas nem conteúdo de produção no snapshot visual.
    ui.decodeImageFromPixels(
      Uint8List.fromList([209, 226, 248, 255]),
      1,
      1,
      ui.PixelFormat.rgba8888,
      image.complete,
    );
    fixture = await image.future;
  });
  tearDownAll(() => fixture.dispose());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openFeed(
    WidgetTester tester,
    _FeedApi api, {
    Size size = const Size(423, 752),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final child in _children) {
      for (final url in _postFor(child.id).imageUrls) {
        PaintingBinding.instance.imageCache.putIfAbsent(
          NetworkImage(url),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: fixture.clone())),
          ),
        );
      }
    }
    final controller = SessionController(store: MemoryTokenStore())
      ..initialized = true
      ..session = familySession;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('family-feed-preview'),
        child: ProviderScope(
          overrides: [apiProvider.overrideWithValue(api)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: FamilyLayout(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      controller.dispose();
    });
  }

  testWidgets('publicações segue a referência sem dados fictícios no app', (
    tester,
  ) async {
    debugDisableShadows = false;
    try {
      await openFeed(tester, _FeedApi());
      await tester.pumpAndSettle();
      expect(find.text('Área da família'), findsOneWidget);
      expect(find.text('Sofia'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.text('Publicação de teste de Sofia'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('family-feed-preview')),
        matchesGoldenFile('goldens/family_feed.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets(
    'carrossel permite avançar, voltar, deslizar e escolher indicador',
    (tester) async {
      await openFeed(tester, _FeedApi());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Próxima foto'));
      await tester.pumpAndSettle();
      expect(find.text('2/4'), findsOneWidget);
      await tester.tap(find.byTooltip('Foto anterior'));
      await tester.pumpAndSettle();
      expect(find.text('1/4'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2/4'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Ir para foto 4'));
      await tester.pumpAndSettle();
      expect(find.text('4/4'), findsOneWidget);
      await tester.tap(find.byTooltip('Próxima foto'));
      await tester.pumpAndSettle();
      expect(find.text('1/4'), findsOneWidget);
    },
  );

  testWidgets('troca de filho limpa a publicação e reinicia o carrossel', (
    tester,
  ) async {
    final api = _FeedApi();
    await openFeed(tester, api);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próxima foto'));
    await tester.pumpAndSettle();
    final pending = Completer<List<Post>>();
    api.pending = pending;
    await tester.tap(find.text('Miguel'));
    await tester.pump();
    expect(find.text('Publicação de teste de Sofia'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([_postFor('miguel')]);
    await tester.pumpAndSettle();
    expect(find.text('Publicação de teste de Miguel'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);
    expect(api.requested, ['sofia', 'miguel']);
  });

  testWidgets('menu exibe os dados reais da publicação', (tester) async {
    await openFeed(tester, _FeedApi());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Informações da publicação'));
    await tester.pumpAndSettle();
    expect(find.text('Informações da publicação'), findsOneWidget);
    expect(find.text('4 fotos'), findsOneWidget);
    expect(find.text('04/10/2026 às 01:35'), findsOneWidget);
    expect(find.text('Compartilhado por'), findsOneWidget);
    expect(find.text('Sobre este momento'), findsOneWidget);
    await expectLater(
      find.byKey(const ValueKey('family-feed-preview')),
      matchesGoldenFile('goldens/family-post-details.png'),
    );
    await tester.tap(find.byTooltip('Fechar informações'));
    await tester.pumpAndSettle();
    expect(find.text('Informações da publicação'), findsNothing);
  });

  testWidgets('erro permite tentar novamente e mostra estado vazio', (
    tester,
  ) async {
    final api = _FeedApi()..fail = true;
    await openFeed(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível atualizar'), findsOneWidget);
    api
      ..fail = false
      ..emptyPosts = true;
    await tester.ensureVisible(find.text('Atualizar').first);
    await tester.tap(find.text('Atualizar').first);
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma publicação ainda'), findsOneWidget);
    expect(api.refreshes, 2);
  });

  testWidgets('foto indisponível não quebra a publicação', (tester) async {
    await openFeed(tester, _FeedApi()..missingPhoto = true);
    await tester.pumpAndSettle();
    expect(find.text('Foto indisponível'), findsOneWidget);
    expect(find.text('Publicação de teste de Sofia'), findsOneWidget);
    expect(find.byTooltip('Próxima foto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem vínculos não inventa filhos e mantém as outras abas', (
    tester,
  ) async {
    await openFeed(tester, _FeedApi()..children = []);
    await tester.pumpAndSettle();
    expect(find.text('Sofia'), findsNothing);
    expect(find.textContaining('Nenhum aluno está vinculado'), findsOneWidget);
    await tester.tap(find.text('Portfólio').last);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum projeto publicado ainda.'), findsOneWidget);
    await tester.tap(find.text('Perfil').last);
    await tester.pumpAndSettle();
    expect(find.text('Área da família'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('texto ampliado e nomes longos cabem em tela pequena', (
    tester,
  ) async {
    final api = _FeedApi()
      ..children = [
        const Child(
          id: 'sofia',
          name: 'Sofia Maria da Silva',
          avatarUrl: '',
          classroom: 'Grupo 2',
        ),
        _children[1],
      ];
    await openFeed(tester, api, size: const Size(320, 568), scale: 1.5);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
