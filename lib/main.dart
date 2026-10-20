import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';
import 'auth/mobile_session.dart';
import 'family/core/theme/app_theme.dart';
import 'family/providers/app_state.dart';
import 'family/services/tinhakids_api_service.dart';
import 'family/views/main_layout.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const TinhaphoneApp());
}

class TinhaphoneApp extends StatefulWidget {
  final SessionController? controller;
  const TinhaphoneApp({super.key, this.controller});
  @override
  State<TinhaphoneApp> createState() => _TinhaphoneAppState();
}

class _TinhaphoneAppState extends State<TinhaphoneApp>
    with WidgetsBindingObserver {
  late final controller = widget.controller ?? SessionController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!controller.initialized) controller.restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.revalidate();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final session = controller.session;
      Widget home;
      if (!controller.initialized) {
        home = const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else if (session == null) {
        home = LoginScreen(controller: controller);
      } else if (session.account.isTeacher) {
        home = HomeScreen(
          key: ValueKey(session.scope),
          session: session,
          controller: controller,
        );
      } else {
        home = ProviderScope(
          key: ValueKey(session.scope),
          overrides: [
            apiProvider.overrideWithValue(
              TinhaKidsApiService(
                session: session,
                client: controller.api.client,
                onUnauthorized: () => controller.invalidate(session),
              ),
            ),
          ],
          child: _FamilySharingGuard(
            child: FamilyLayout(controller: controller),
          ),
        );
      }
      // Uma nova sessão ganha também uma pilha de navegação nova: voltar nunca reabre a outra conta.
      return MaterialApp(
        key: ValueKey(session?.scope ?? 'login'),
        title: 'TinhaKids',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: home,
      );
    },
  );
}

/// A família descarta referências ao compartilhamento sem importar, copiar ou enviar imagens.
class _FamilySharingGuard extends StatefulWidget {
  final Widget child;
  const _FamilySharingGuard({required this.child});
  @override
  State<_FamilySharingGuard> createState() => _FamilySharingGuardState();
}

class _FamilySharingGuardState extends State<_FamilySharingGuard> {
  StreamSubscription<SharedMedia>? subscription;
  @override
  void initState() {
    super.initState();
    _discard();
  }

  Future<void> _discard() async {
    try {
      final handler = ShareHandler.instance;
      subscription = handler.sharedMediaStream.listen((_) {
        handler.resetInitialSharedMedia();
      }, onError: (Object _) {});
      await handler.resetInitialSharedMedia();
    } catch (_) {
      /* Plataformas sem extensão de compartilhamento não exigem ação. */
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
