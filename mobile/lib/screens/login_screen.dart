import 'package:material_ui/material_ui.dart';

import '../data/api.dart';
import '../data/app_update.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/update_dialog.dart';
import 'visit_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _url = TextEditingController(text: Api.instance.baseUrl);
  bool _busy = false;
  bool _showServer = false;
  bool _hide = true;
  String? _error;
  String _version = '';

  @override
  void initState() {
    super.initState();
    AppUpdater.instance.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.login(_url.text.trim(), _email.text.trim(), _password.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const VisitListScreen()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header hijau seperti landing page
            Container(
              decoration: const BoxDecoration(gradient: heroGradient),
              padding: EdgeInsets.fromLTRB(24, top + 28, 24, 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Emblem(size: 48),
                  SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PROPESTINDO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 17)),
                    Text('Profesional Pest Control Indonesia', style: TextStyle(color: Color(0xFF9FBCAA), fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withValues(alpha: .14))),
                  child: const Text('Aplikasi Teknisi', style: TextStyle(color: Color(0xFFD9EADF), fontWeight: FontWeight.w600, fontSize: 12.5)),
                ),
                const SizedBox(height: 14),
                const Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Laporan kunjungan\n'),
                    TextSpan(text: 'langsung dari lapangan.', style: TextStyle(color: AppColors.gold)),
                  ]),
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -.5),
                ),
                const SizedBox(height: 8),
                const Text('Tetap bisa diisi tanpa sinyal. Data terkirim otomatis saat online.', style: TextStyle(color: Color(0xFFC4D6CA), fontSize: 14)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Masuk ke akun teknisi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_showServer) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Alamat server', prefixIcon: Icon(Icons.dns_outlined)),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Notice(icon: Icons.error_outline, text: _error!, tone: Tone.danger),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? 'Memproses...' : 'Masuk')),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      TextButton.icon(
                        onPressed: () => setState(() => _showServer = !_showServer),
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        label: const Text('Pengaturan server'),
                      ),
                    ]),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                      onPressed: () async {
                        // Endpoint update tidak butuh login, cukup alamat server.
                        Api.instance.baseUrl = _url.text.trim();
                        await checkAppUpdate(context);
                      },
                      child: Text('Versi $_version · Cek update'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
