import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/mobile_session.dart';

const _navy = Color(0xFF142454);
const _blue = Color(0xFF245CF5);
const _muted = Color(0xFF60697F);
const _border = Color(0xFFDCE2ED);

class LoginScreen extends StatefulWidget {
  final SessionController controller;
  const LoginScreen({super.key, required this.controller});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  late final _server = TextEditingController(text: defaultServer);
  final _form = GlobalKey<FormState>();
  bool _showPassword = false;
  bool _showServer = false;

  @override
  void initState() {
    super.initState();
    _restoreServer();
  }

  Future<void> _restoreServer() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('mobile_login_server');
      if (mounted &&
          saved != null &&
          _server.text == defaultServer &&
          !_showServer) {
        _server.text = saved;
      }
    } catch (_) {
      // A preferência é opcional; falhas de armazenamento não impedem o login.
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (widget.controller.loading || !_form.currentState!.validate()) return;
    try {
      _server.text = normalizeServer(_server.text);
    } catch (_) {
      setState(() => _showServer = true);
      return;
    }
    final server = _server.text;
    FocusScope.of(context).unfocus();
    await widget.controller.login(server, _email.text, _password.text);
    if (widget.controller.session != null) {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('mobile_login_server', server);
      } catch (_) {
        // A sessão segura já foi salva pelo controlador.
      }
    }
    if (mounted) _password.clear();
  }

  InputDecoration _decoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w400),
    prefixIcon: Icon(icon, size: 24, color: _muted),
    prefixIconConstraints: const BoxConstraints(minWidth: 54),
    filled: true,
    fillColor: const Color(0xFFFEFEFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _blue, width: 1.5),
    ),
    errorMaxLines: 2,
  );

  @override
  Widget build(BuildContext context) => Theme(
    // A identidade do login não altera o visual das áreas já existentes.
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Nunito'),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xFFFCFDFF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: CustomPaint(painter: _LoginBackground())),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.symmetric(
                  horizontal: viewport.maxWidth < 360 ? 20 : 30,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (viewport.maxHeight - 48).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _Brand(),
                          const SizedBox(height: 18),
                          _buildCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildCard() => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x257592BC),
          blurRadius: 36,
          spreadRadius: 2,
          offset: Offset(0, 16),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 32),
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                enabled: !widget.controller.loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                style: const TextStyle(fontSize: 17, color: _navy),
                decoration: _decoration('E-mail', Icons.mail_outline_rounded),
                validator: (v) => v == null || !v.contains('@')
                    ? 'Informe seu e-mail.'
                    : null,
              ),
              const SizedBox(height: 13),
              TextFormField(
                controller: _password,
                enabled: !widget.controller.loading,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: const TextStyle(fontSize: 17, color: _navy),
                onFieldSubmitted: (_) => _login(),
                decoration: _decoration('Senha', Icons.lock_outline_rounded)
                    .copyWith(
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Ocultar senha'
                            : 'Mostrar senha',
                        onPressed: widget.controller.loading
                            ? null
                            : () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: _muted,
                          size: 24,
                        ),
                      ),
                    ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Informe sua senha.' : null,
              ),
              const SizedBox(height: 13),
              _buildServer(),
              if (widget.controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.controller.error!,
                      style: const TextStyle(
                        color: Color(0xFFB3261E),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF304C80),
                      Color(0xFF36558C),
                      Color(0xFF304C80),
                    ],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x307C9EC9),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: widget.controller.loading ? null : _login,
                  child: widget.controller.loading
                      ? Semantics(
                          label: 'Entrando',
                          child: const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Entrar'),
                            SizedBox(width: 10),
                            Icon(Icons.arrow_forward_rounded, size: 24),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildServer() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: _navy,
          disabledForegroundColor: _muted,
          side: const BorderSide(color: _border),
          minimumSize: const Size.fromHeight(50),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16),
        ),
        onPressed: widget.controller.loading
            ? null
            : () => setState(() => _showServer = !_showServer),
        child: Row(
          children: [
            const Icon(Icons.storage_rounded, color: _muted, size: 23),
            const SizedBox(width: 15),
            const Expanded(child: Text('Servidor de testes')),
            Icon(
              _showServer
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: _muted,
            ),
          ],
        ),
      ),
      if (_showServer) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('server-address'),
          controller: _server,
          enabled: !widget.controller.loading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _login(),
          autocorrect: false,
          style: const TextStyle(fontSize: 14, color: _navy),
          decoration: _decoration('Endereço da API', Icons.link_rounded).copyWith(
            helperText:
                'Use o endereço da API com a porta, por exemplo: 192.168.1.10:8000. No emulador Android: 10.0.2.2:8000.',
            helperMaxLines: 4,
          ),
          validator: (v) {
            try {
              normalizeServer(v ?? '');
              return null;
            } catch (_) {
              return 'Informe um endereço válido.';
            }
          },
        ),
      ],
    ],
  );
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ExcludeSemantics(
        child: CustomPaint(size: Size(62, 48), painter: _GraduationCap()),
      ),
      const SizedBox(height: 10),
      const Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Tinha',
              style: TextStyle(color: _navy),
            ),
            TextSpan(
              text: 'Kids',
              style: TextStyle(color: _blue),
            ),
          ],
        ),
        semanticsLabel: 'TinhaKids',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 40,
          height: 1.1,
          letterSpacing: -1.6,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 6),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'Cada momento escolar merece ser compartilhado.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16.5,
            height: 1.35,
            color: Color(0xFF565E75),
          ),
        ),
      ),
    ],
  );
}

class _GraduationCap extends CustomPainter {
  const _GraduationCap();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 62, size.height / 48);
    final outline = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(59, 17)
        ..lineTo(59, 35),
      Paint()
        ..color = _blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(14, 24)
        ..lineTo(14, 37)
        ..lineTo(30.5, 46)
        ..lineTo(47, 37)
        ..lineTo(47, 24),
      outline,
    );
    canvas.drawPath(
      Path()
        ..moveTo(4, 17)
        ..lineTo(30.5, 3)
        ..lineTo(57, 17)
        ..lineTo(30.5, 31)
        ..close(),
      outline,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraduationCap oldDelegate) => false;
}

class _LoginBackground extends CustomPainter {
  const _LoginBackground();

  @override
  void paint(Canvas canvas, Size size) {
    // Curvas vetoriais: o fundo acompanha a tela sem ampliar uma imagem.
    canvas.save();
    canvas.scale(size.width / 423, size.height / 752);
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(196, 0)
        ..cubicTo(182, 72, 143, 86, 74, 84)
        ..cubicTo(35, 81, 25, 132, 0, 147)
        ..close(),
      Paint()..color = const Color(0xFFEDF3FC),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(150, 0)
        ..cubicTo(137, 65, 88, 42, 48, 79)
        ..cubicTo(29, 97, 34, 125, 0, 147)
        ..close(),
      Paint()..color = const Color(0xFFDCE9FA),
    );
    canvas.drawOval(
      const Rect.fromLTWH(361, 60, 146, 144),
      Paint()..color = const Color(0xFFEEF3FA),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, 655)
        ..cubicTo(67, 641, 144, 671, 171, 752)
        ..lineTo(0, 752)
        ..close(),
      Paint()..color = const Color(0xFFDCE9FA),
    );
    final line = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFA9C4F0), Color(0xFFE0EAFB)],
      ).createShader(const Rect.fromLTWH(0, 0, 423, 752))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(
      Path()
        ..moveTo(0, 105)
        ..cubicTo(37, 73, 63, 87, 99, 83),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(232, 752)
        ..cubicTo(263, 697, 314, 724, 350, 689)
        ..cubicTo(380, 657, 383, 630, 423, 617),
      line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LoginBackground oldDelegate) => false;
}
