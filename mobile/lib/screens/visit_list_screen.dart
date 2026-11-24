import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api.dart';
import '../data/local_db.dart';
import '../data/repository.dart';
import '../data/sync.dart';
import '../labels.dart';
import '../widgets/update_dialog.dart';
import 'login_screen.dart';
import 'visit_screen.dart';

class VisitListScreen extends StatefulWidget {
  const VisitListScreen({super.key});

  @override
  State<VisitListScreen> createState() => _VisitListScreenState();
}

class _VisitListScreenState extends State<VisitListScreen> {
  List<dynamic> _visits = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Cek update aplikasi sekali saat layar jadwal dibuka.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkAppUpdate(context, silent: true);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final v = await Repository.instance.myVisits();
      setState(() {
        _visits = v;
        _error = null;
      });
      Repository.instance.prefetch(v);
      SyncService.instance.run();
    } on ApiException catch (e) {
      if (e.status == 401) return _logout();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    if (await LocalDb.instance.pendingCount() > 0 && mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Masih ada data belum terkirim'),
          content: const Text('Jika keluar sekarang, laporan yang belum terkirim akan hilang.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tetap keluar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await LocalDb.instance.clearAll();
    await Api.instance.saveSession(url: Api.instance.baseUrl, newToken: null);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todays = _visits.where((v) => v['scheduled_date'] == today).toList();
    final upcoming = _visits.where((v) => (v['scheduled_date'] as String).compareTo(today) > 0).toList();
    final earlier = _visits.where((v) => (v['scheduled_date'] as String).compareTo(today) < 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal kunjungan'),
        actions: [
          IconButton(onPressed: () => checkAppUpdate(context), icon: const Icon(Icons.system_update), tooltip: 'Cek update aplikasi'),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout), tooltip: 'Keluar'),
        ],
      ),
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null) Card(child: ListTile(leading: const Icon(Icons.error), title: Text(_error!))),
                  if (_loading && _visits.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                  _section('Hari ini', todays),
                  _section('Mendatang', upcoming),
                  _section('Sebelumnya', earlier),
                  if (!_loading && _visits.isEmpty && _error == null)
                    const Padding(padding: EdgeInsets.all(32), child: Text('Tidak ada kunjungan.', textAlign: TextAlign.center)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final date = DateFormat('EEE, d MMM', 'id_ID');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6), child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
        for (final v in items)
          Card(
            child: ListTile(
              title: Text('${v['customer_name']}'),
              subtitle: Text('${v['site_name']}\n${date.format(DateTime.parse(v['scheduled_date'] as String))} · ${visitTypes[v['visit_type']]}'),
              isThreeLine: true,
              trailing: StatusChip(v['status'] as String),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisitScreen(visit: v as Map<String, dynamic>)));
                _load();
              },
            ),
          ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'in_progress' => Colors.orange,
      'pending_review' => Colors.deepOrange,
      'revision' => Colors.red,
      'published' => Colors.green,
      _ => Colors.blue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Text(visitStatus[status] ?? status, style: TextStyle(color: color.shade800, fontSize: 12)),
    );
  }
}

/// Menampilkan jumlah data yang belum terkirim dan error sinkronisasi terakhir.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (sync.pending == 0 && sync.lastError == null) return const SizedBox.shrink();
        return Material(
          color: sync.lastError != null ? Colors.amber.shade100 : Colors.blue.shade50,
          child: ListTile(
            dense: true,
            leading: sync.running ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
            title: Text('${sync.pending} data menunggu terkirim'),
            subtitle: sync.lastError != null ? Text(sync.lastError!) : null,
            trailing: TextButton(onPressed: sync.running ? null : sync.run, child: const Text('Kirim')),
          ),
        );
      },
    );
  }
}
