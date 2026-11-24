import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api.dart';
import '../data/local_db.dart';
import '../data/repository.dart';
import '../data/sync.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/ui.dart';
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
    final revisions = _visits.where((v) => v['status'] == 'revision').length;
    final sent = todays.where((v) => v['status'] == 'pending_review' || v['status'] == 'published').length;
    final top = MediaQuery.of(context).padding.top;
    final hour = DateTime.now().hour;
    final greeting = hour < 11 ? 'Selamat pagi' : hour < 15 ? 'Selamat siang' : hour < 18 ? 'Selamat sore' : 'Selamat malam';
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: top + 80,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Header hijau
            Container(
              decoration: const BoxDecoration(gradient: heroGradient),
              padding: EdgeInsets.fromLTRB(18, top + 14, 8, 64),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Emblem(size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$greeting,', style: const TextStyle(color: Color(0xFFB9D2C1), fontSize: 13, fontWeight: FontWeight.w600)),
                      const Text('Jadwal kunjungan', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  IconButton(onPressed: () => checkAppUpdate(context), icon: const Icon(Icons.system_update_outlined, color: Colors.white), tooltip: 'Cek update aplikasi'),
                  IconButton(onPressed: _logout, icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'Keluar'),
                ]),
                const SizedBox(height: 10),
                Text(DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()), style: const TextStyle(color: Color(0xFFB9D2C1), fontSize: 13)),
              ]),
            ),
            Transform.translate(
              offset: const Offset(0, -44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Ringkasan
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.line),
                      boxShadow: const [BoxShadow(color: Color(0x22062616), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -12)],
                    ),
                    child: ListenableBuilder(
                      listenable: SyncService.instance,
                      builder: (context, _) => Row(children: [
                        _stat('${todays.length}', 'Hari ini'),
                        _stat('$sent', 'Terkirim'),
                        _stat('$revisions', 'Revisi', warn: revisions > 0),
                        _stat('${SyncService.instance.pending}', 'Antrian', warn: SyncService.instance.pending > 0, last: true),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SyncBanner(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Notice(icon: Icons.error_outline, text: _error!, tone: Tone.danger),
                  ],
                  if (_loading && _visits.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                  _section('Hari ini', todays),
                  _section('Mendatang', upcoming),
                  _section('Sebelumnya', earlier),
                  if (!_loading && _visits.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Panel(child: EmptyView(icon: Icons.event_available_outlined, title: 'Tidak ada kunjungan.', text: 'Jadwal dari admin akan muncul di sini. Tarik ke bawah untuk memuat ulang.')),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, {bool warn = false, bool last = false}) => Expanded(
        child: Container(
          decoration: BoxDecoration(border: last ? null : const Border(right: BorderSide(color: AppColors.line2))),
          child: Column(children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: warn ? AppColors.red : AppColors.green800)),
            Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ]),
        ),
      );

  Widget _section(String title, List<dynamic> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title, count: items.length),
        for (final v in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: VisitCard(
              visit: v as Map<String, dynamic>,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VisitScreen(visit: v)));
                _load();
              },
            ),
          ),
      ],
    );
  }
}

/// Kartu satu kunjungan di daftar jadwal.
class VisitCard extends StatelessWidget {
  const VisitCard({super.key, required this.visit, required this.onTap});
  final Map<String, dynamic> visit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final date = DateTime.parse(v['scheduled_date'] as String);
    final status = v['status'] as String;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: statusColors(status).$1, width: 4))),
          padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
          child: Row(children: [
            Container(
              width: 54,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: AppColors.green50, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Text(DateFormat('EEE', 'id_ID').format(date).toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.green600)),
                Text('${date.day}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.green800, height: 1.15)),
                Text(DateFormat('MMM', 'id_ID').format(date).toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.green600)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${v['customer_name']}', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 3),
                  Expanded(child: Text('${v['site_name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(status),
                  Text(visitTypes[v['visit_type']] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                ]),
                ListenableBuilder(
                  listenable: SyncService.instance,
                  builder: (context, _) {
                    final st = SyncService.instance.stateOf(v['id'] as String);
                    if (st.pending == 0) return const SizedBox.shrink();
                    final bad = st.error != null && !st.offline;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        Icon(bad ? Icons.error_outline : Icons.cloud_upload_outlined, size: 14, color: bad ? AppColors.red : AppColors.amber),
                        const SizedBox(width: 4),
                        Text(bad ? 'Gagal terkirim' : 'Belum terkirim', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: bad ? AppColors.red : AppColors.amber)),
                      ]),
                    );
                  },
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFB7C6BD)),
          ]),
        ),
      ),
    );
  }
}

/// Warna (teks, latar) untuk setiap status kunjungan.
(Color, Color) statusColors(String status) => switch (status) {
      'in_progress' => (AppColors.amber, AppColors.amber50),
      'pending_review' => (const Color(0xFF8A6100), AppColors.gold50),
      'revision' => (AppColors.red, AppColors.red50),
      'published' => (AppColors.green700, AppColors.green50),
      'cancelled' => (AppColors.muted, AppColors.line2),
      _ => (AppColors.blue, AppColors.blue50),
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = statusColors(status);
    return Pill(visitStatus[status] ?? status, color: fg, bg: bg);
  }
}

/// Menampilkan jumlah data yang belum terkirim dan error sinkronisasi terakhir.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key, this.margin = EdgeInsets.zero});
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (sync.pending == 0) return const SizedBox.shrink();
        final rejected = sync.lastError != null && !sync.offline;
        return Padding(
          padding: margin,
          child: Notice(
            tone: rejected ? Tone.danger : Tone.warn,
            icon: sync.offline ? Icons.cloud_off : (rejected ? Icons.error_outline : Icons.cloud_upload_outlined),
            title: '${sync.pending} data belum terkirim ke server',
            text: sync.lastError ?? (sync.running ? 'Sedang mengirim...' : 'Tekan Kirim untuk mencoba sekarang'),
            trailing: sync.running
                ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: sync.run, child: const Text('Kirim')),
          ),
        );
      },
    );
  }
}
