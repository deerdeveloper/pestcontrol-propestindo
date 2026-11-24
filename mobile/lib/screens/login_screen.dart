import 'package:material_ui/material_ui.dart';

import '../data/api.dart';
import '../data/app_update.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/logo.png', height: 80),
                const SizedBox(height: 8),
                Text('Aplikasi Teknisi', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _login()),
                if (_showServer) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Alamat server')),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 20),
                FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? 'Memproses...' : 'Masuk')),
                TextButton(onPressed: () => setState(() => _showServer = !_showServer), child: const Text('Pengaturan server')),
                TextButton(
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
      ),
    );
  }
}
