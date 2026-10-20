import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/mobile_session.dart';
import '../../widgets/tinha_brand.dart';
import '../providers/app_state.dart';
import 'feed/feed_tab.dart';
import 'portfolio/portfolio_tab.dart';
import 'profile/profile_tab.dart';

class FamilyLayout extends ConsumerStatefulWidget {
  final SessionController controller;
  const FamilyLayout({super.key, required this.controller});
  @override
  ConsumerState<FamilyLayout> createState() => _FamilyLayoutState();
}

class _FamilyLayoutState extends ConsumerState<FamilyLayout> {
  int _index = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(appProvider.notifier).restoreSession();
    });
  }

  Future<void> _logout() async {
    await ref.read(appProvider.notifier).logout();
    await widget.controller.logout();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Nunito'),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFFF4F8FD),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          84 +
              (MediaQuery.textScalerOf(context).scale(28) - 28).clamp(0, 56) *
                  1.5,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(22),
          ),
          child: CustomPaint(
            painter: const _HeaderBackground(),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const GraduationCap(),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: TinhaWordmark(),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Área da família',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF535E7A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _logout,
                      tooltip: 'Sair',
                      icon: const Icon(
                        Icons.logout_rounded,
                        size: 27,
                        color: tinhaNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), Color(0xFFEDF5FD)],
          ),
        ),
        child: IndexedStack(
          index: _index,
          children: const [FeedTab(), PortfolioTab(), ProfileTab()],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0C7098C5),
              blurRadius: 24,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              indicatorColor: const Color(0xFFDDEAFF),
              indicatorShape: const StadiumBorder(),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? tinhaBlue
                      : const Color(0xFF46516C),
                  size: 27,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: states.contains(WidgetState.selected)
                      ? tinhaBlue
                      : const Color(0xFF535E7A),
                ),
              ),
            ),
            child: NavigationBar(
              height: 82,
              selectedIndex: _index,
              onDestinationSelected: (v) => setState(() => _index = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  label: 'Publicações',
                ),
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  label: 'Portfólio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  label: 'Perfil',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _HeaderBackground extends CustomPainter {
  const _HeaderBackground();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.srcOver);
    canvas.save();
    canvas.scale(size.width / 423, size.height / 85);
    canvas.drawPath(
      Path()
        ..moveTo(167, 0)
        ..lineTo(423, 0)
        ..lineTo(423, 85)
        ..cubicTo(350, 103, 332, 32, 266, 30)
        ..cubicTo(216, 30, 182, 35, 167, 0)
        ..close(),
      Paint()..color = const Color(0xFFEAF3FF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(229, 0)
        ..lineTo(394, 0)
        ..cubicTo(354, 34, 360, 69, 318, 67)
        ..cubicTo(279, 65, 245, 39, 229, 0)
        ..close(),
      Paint()..color = const Color(0xFFDDEBFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeaderBackground oldDelegate) => false;
}
