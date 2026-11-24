import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/api.dart';
import '../data/local_db.dart';
import '../data/repository.dart';
import '../data/sync.dart';
import '../labels.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/forms.dart';
import 'scan_screen.dart';
import 'signature_screen.dart';
import 'visit_list_screen.dart';

/// Layar pengisian laporan kunjungan, mengikuti 6 bagian form Excel Propestindo.
/// Semua isian langsung disimpan di HP, lalu dikirim lewat antrian sinkronisasi.
class VisitScreen extends StatefulWidget {
  const VisitScreen({super.key, required this.visit});
  final Map<String, dynamic> visit;

  @override
  State<VisitScreen> createState() => _VisitScreenState();
}

class _VisitScreenState extends State<VisitScreen> {
  final repo = Repository.instance;
  Map<String, dynamic>? doc;
  Map<String, dynamic> bundle = {};
  Map<String, dynamic> catalog = {};
  Map<String, dynamic> d = {};
  String? error;

  String get visitId => widget.visit['id'] as String;
  String get status => (doc?['visit']?['status'] ?? widget.visit['status']) as String;

  List<Map<String, dynamic>> list(String k) => (d[k] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> get sigs => d['signatures'] as Map<String, dynamic>;

  /// Server sudah menerima laporan (menunggu review atau sudah terbit).
  bool get delivered => status == 'pending_review' || status == 'published';

  /// Laporan terkunci setelah dikirim, atau setelah PIC tanda tangan.
  bool get locked =>
      d['submitted'] == true || sigs['pic'] != null || status == 'pending_review' || status == 'published' || status == 'cancelled';

  int _lastPending = 0;

  @override
  void initState() {
    super.initState();
    _lastPending = SyncService.instance.stateOf(visitId).pending;
    SyncService.instance.addListener(_onSync);
    _load();
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSync);
    super.dispose();
  }

  /// Antrian kunjungan ini habis terkirim di latar belakang: ambil status terbaru dari server.
  void _onSync() {
    final p = SyncService.instance.stateOf(visitId).pending;
    if (_lastPending > 0 && p == 0) _refreshStatus();
    _lastPending = p;
  }

  Future<void> _load() async {
    try {
      final b = await repo.bundle(visitId);
      final c = await repo.catalog();
      final document = b['document'] as Map<String, dynamic>;
      final draft = await repo.draft(visitId, document);
      // Laporan dikembalikan admin untuk revisi: buka kunci supaya bisa diperbaiki.
      if (document['visit']['status'] == 'revision' && draft['submitted'] == true && await LocalDb.instance.pendingCount(visitId) == 0) {
        draft['submitted'] = false;
        (draft['signatures'] as Map<String, dynamic>).remove('pic');
      }
      setState(() {
        bundle = b;
        catalog = c;
        doc = document;
        d = draft;
      });
    } on ApiException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _save() async {
    await repo.saveDraft(visitId, d);
    setState(() {});
  }

  Map<String, String> _opts(String key, String label, {String? where}) => {
        for (final x in (catalog[key] as List? ?? const []).cast<Map<String, dynamic>>())
          if (where == null || x[where] != null) x['id'] as String: x[label] as String,
      };
  Map<String, String> get _areas => {for (final a in (bundle['areas'] as List? ?? const [])) a['id'] as String: a['name'] as String};
  String _name(Map<String, String> m, String? id, [String? fallback]) => m[id] ?? fallback ?? '-';

  Future<void> _checkIn() async {
    double? lat, lng;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 15)));
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {
      // Lokasi tidak wajib; check-in tetap jalan tanpa GPS.
    }
    await repo.checkIn(visitId, d, lat: lat, lng: lng);
    setState(() {});
  }

  Future<String?> _takePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
    if (x == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'photos', '${uuid.v4()}.jpg'));
    await file.parent.create(recursive: true);
    await File(x.path).copy(file.path);
    return file.path;
  }

  Future<void> _addPhoto(String ownerType, String? ownerId) async {
    final path = await _takePhoto();
    if (path == null) return;
    list('photos').add({'id': uuid.v4(), 'owner_type': ownerType, 'owner_id': ownerId, 'path': path, 'caption': null});
    await _save();
  }

  List<Map<String, dynamic>> _photosOf(String type, String? id) =>
      list('photos').where((x) => x['owner_type'] == type && x['owner_id'] == id).toList();

  Widget _photoStrip(String type, String? id, {double size = 64}) {
    final photos = _photosOf(type, id);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final ph in photos)
        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(ph['path'] as String), width: size, height: size, fit: BoxFit.cover)),
      if (!locked)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _addPhoto(type, id),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: const Color(0xFFB7C6BD), width: 1.5), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.add_a_photo_outlined, color: AppColors.green700),
          ),
        ),
    ]);
  }

  // ---------- Form tiap bagian ----------

  Future<void> _editFinding([Map<String, dynamic>? row]) async {
    final pests = _opts('pest_types', 'name_id');
    final res = await editSheet(context,
        title: row == null ? 'Tambah temuan hama' : 'Ubah temuan',
        initial: row ?? {'id': uuid.v4(), 'level': 'low', 'is_active': true},
        validate: (m) => m['pest_type_id'] == null ? 'Pilih jenis hama' : (m['area_id'] == null && (m['area_text'] ?? '').isEmpty ? 'Pilih area atau isi lokasi lain' : null),
        build: (m, set) => [
              Pick(label: 'Hama', value: m['pest_type_id'], items: pests, onChanged: (v) => set(() => m['pest_type_id'] = v)),
              Pick(label: 'Area', value: m['area_id'], items: _areas, allowEmpty: true, onChanged: (v) => set(() => m['area_id'] = v)),
              if (m['area_id'] == null) Field(label: 'Lokasi lain (jika tidak ada di daftar)', value: m['area_text'], onChanged: (v) => m['area_text'] = v),
              Pick(label: 'Tingkat infestasi', value: m['level'], items: levels, onChanged: (v) => set(() => m['level'] = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Hama masih aktif'), value: m['is_active'] == true, onChanged: (v) => set(() => m['is_active'] = v)),
              Field(label: 'Keterangan', value: m['remarks'], onChanged: (v) => m['remarks'] = v, maxLines: 2),
            ]);
    if (res == null) return;
    _upsert('findings', res);
  }

  Future<void> _editTreatment([Map<String, dynamic>? row]) async {
    final methods = _opts('treatment_methods', 'name_id');
    final chems = _opts('chemicals', 'trade_name');
    final doses = (catalog['chemical_doses'] as List? ?? const []).cast<Map<String, dynamic>>();
    final res = await editSheet(context,
        title: row == null ? 'Tambah tindakan' : 'Ubah tindakan',
        initial: row ?? {'id': uuid.v4()},
        validate: (m) => m['method_id'] == null ? 'Pilih metode' : null,
        build: (m, set) {
          // Isi dosis standar otomatis saat bahan dan metode dipilih.
          void suggestDose() {
            final match = doses.where((x) => x['chemical_id'] == m['chemical_id'] && (x['method_id'] == null || x['method_id'] == m['method_id']));
            if (match.isNotEmpty && (m['dose_text'] ?? '').isEmpty) m['dose_text'] = match.first['dose_text'];
          }
          return [
            Pick(label: 'Metode', value: m['method_id'], items: methods, onChanged: (v) => set(() { m['method_id'] = v; suggestDose(); })),
            Pick(label: 'Area', value: m['area_id'], items: _areas, allowEmpty: true, onChanged: (v) => set(() => m['area_id'] = v)),
            if (m['area_id'] == null) Field(label: 'Area lain', value: m['area_text'], onChanged: (v) => m['area_text'] = v),
            Pick(label: 'Bahan kimia', value: m['chemical_id'], items: chems, allowEmpty: true, onChanged: (v) => set(() { m['chemical_id'] = v; suggestDose(); })),
            Field(key: ValueKey(m['dose_text']), label: 'Dosis', value: m['dose_text'], onChanged: (v) => m['dose_text'] = v),
            Field(label: 'Jumlah dipakai', value: m['quantity_used'], onChanged: (v) => m['quantity_used'] = v),
            Field(label: 'Alat (mis. Backpack Sprayer)', value: m['equipment'], onChanged: (v) => m['equipment'] = v),
          ];
        });
    if (res == null) return;
    _upsert('treatments', res);
  }

  Future<void> _editRecommendation([Map<String, dynamic>? row]) async {
    final res = await editSheet(context,
        title: row == null ? 'Tambah rekomendasi' : 'Ubah rekomendasi',
        initial: row ?? {'id': uuid.v4(), 'category': 'sanitation'},
        validate: (m) => (m['risk_finding'] ?? '').isEmpty || (m['recommendation'] ?? '').isEmpty ? 'Isi temuan risiko dan rekomendasi' : null,
        build: (m, set) => [
              Pick(label: 'Kategori', value: m['category'], items: categories, onChanged: (v) => set(() => m['category'] = v)),
              Field(label: 'Temuan risiko / kondisi lapangan', value: m['risk_finding'], onChanged: (v) => m['risk_finding'] = v, maxLines: 2),
              Field(label: 'Rekomendasi untuk klien', value: m['recommendation'], onChanged: (v) => m['recommendation'] = v, maxLines: 3),
            ]);
    if (res == null) return;
    _upsert('recommendations', res);
  }

  Future<void> _editStation(Map<String, dynamic> station) async {
    final checks = list('station_checks');
    final existing = checks.where((c) => c['station_id'] == station['id']).firstOrNull;
    final res = await editSheet(context,
        title: '${station['code']} · ${station['equipment_type']}',
        initial: existing ?? {'station_id': station['id'], 'status': 'ok', 'bait_consumption': 'none'},
        build: (m, set) => [
              Text('Area: ${station['area_name'] ?? '-'}'),
              const SizedBox(height: 12),
              Pick(label: 'Kondisi alat', value: m['status'], items: stationStatus, onChanged: (v) => set(() => m['status'] = v)),
              Pick(label: 'Konsumsi umpan', value: m['bait_consumption'], items: consumption, onChanged: (v) => set(() => m['bait_consumption'] = v)),
              Field(label: 'Temuan', value: m['finding'], onChanged: (v) => m['finding'] = v),
            ]);
    if (res == null) return;
    checks.removeWhere((c) => c['station_id'] == station['id']);
    checks.add(res);
    await _save();
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (value == null || !mounted) return;
    final station = (bundle['stations'] as List).cast<Map<String, dynamic>>().where((s) => s['qr_value'] == value || s['code'] == value).firstOrNull;
    if (station == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR tidak cocok dengan stasiun di lokasi ini')));
      return;
    }
    await _editStation(station);
  }

  void _upsert(String key, Map<String, dynamic> row) {
    final l = list(key);
    final i = l.indexWhere((x) => x['id'] == row['id']);
    i >= 0 ? l[i] = row : l.add(row);
    _save();
  }

  void _remove(String key, Map<String, dynamic> row) {
    list(key).removeWhere((x) => x['id'] == row['id']);
    list('photos').removeWhere((x) => x['owner_id'] == row['id']);
    _save();
  }

  Future<void> _sign(String role) async {
    final nameCtrl = TextEditingController(text: role == 'pic' ? (d['pic_name'] ?? '') : (doc?['technician']?['name'] ?? ''));
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(role == 'pic' ? 'Nama PIC pelanggan' : 'Nama teknisi'),
        content: TextField(controller: nameCtrl, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(c, nameCtrl.text.trim()), child: const Text('Lanjut'))],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final path = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => SignatureScreen(title: 'Tanda tangan $name')));
    if (path == null) return;
    sigs[role] = {'name': name, 'path': path, 'signed_at': DateTime.now().toUtc().toIso8601String()};
    if (role == 'pic') d['pic_name'] = name;
    await _save();
  }

  Future<void> _submit() async {
    if (sigs['technician'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tanda tangan teknisi wajib diisi sebelum laporan dikirim')));
      return;
    }
    final resend = d['submitted'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(resend ? 'Kirim ulang laporan?' : 'Kirim laporan?'),
        content: Text(resend
            ? 'Server belum menerima laporan ini. Semua isi, foto, dan tanda tangan akan dikirim ulang.'
            : 'Setelah dikirim, laporan tidak bisa diubah kecuali dikembalikan admin untuk revisi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.submit(visitId, d, resend: resend);
    if (!mounted) return;
    setState(() {});
    await _sendNow();
  }

  /// Mengirim antrian kunjungan ini sekarang dan menunggu hasilnya, lalu memberi tahu teknisi.
  Future<void> _sendNow() async {
    final sync = SyncService.instance;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Mengirim laporan ke server...')),
          ]),
        ),
      ),
    );
    VisitSyncState st;
    var slow = false;
    try {
      st = await sync.flushVisit(visitId).timeout(const Duration(minutes: 3));
    } on TimeoutException {
      st = sync.stateOf(visitId);
      slow = true;
    } catch (e) {
      st = VisitSyncState(pending: sync.stateOf(visitId).pending, error: '$e');
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // tutup dialog proses

    if (st.done) {
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laporan terkirim. Status: menunggu review admin.'), backgroundColor: Colors.green),
      );
      Navigator.pop(context);
      return;
    }

    final retry = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(st.offline || slow ? Icons.cloud_off : Icons.error_outline, color: st.offline || slow ? Colors.orange : Colors.red),
        title: Text(st.offline || slow ? 'Laporan belum terkirim' : 'Laporan ditolak server'),
        content: Text([
          if (slow) 'Pengiriman masih berjalan lebih dari 3 menit (sinyal lemah).'
          else if (st.offline) 'Tidak bisa terhubung ke server.',
          if (st.error != null) st.error!,
          'Data laporan aman tersimpan di HP (${st.pending} data menunggu). '
              '${st.offline || slow ? 'Aplikasi akan mencoba lagi otomatis saat ada sinyal.' : 'Perbaiki masalahnya lalu tekan Coba lagi, atau hubungi admin.'}',
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tutup')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Coba lagi')),
        ],
      ),
    );
    if (retry == true && mounted) await _sendNow();
  }

  /// Mengambil status terbaru kunjungan dari server setelah terkirim.
  Future<void> _refreshStatus() async {
    try {
      final b = await repo.bundle(visitId);
      if (mounted) setState(() => doc = b['document'] as Map<String, dynamic>);
    } catch (_) {
      // Tidak masalah: status akan diperbarui saat daftar jadwal dimuat ulang.
    }
  }

  // ---------- Tampilan ----------

  @override
  Widget build(BuildContext context) {
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Notice(icon: Icons.error_outline, text: error!, tone: Tone.danger))
              : const CircularProgressIndicator(),
        ),
      );
    }
    final checkedIn = d['checked_in'] == true;
    final stations = (bundle['stations'] as List? ?? const []);
    Tab tab(IconData icon, String label, [String? count]) => Tab(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Text(label),
              if (count != null && count != '0') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .08), borderRadius: BorderRadius.circular(99)),
                  child: Text(count, style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ]),
          ),
        );
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doc!['customer']['name'] as String, overflow: TextOverflow.ellipsis),
            Text('${doc!['site']['name']} · ${DateFormat('d MMM yyyy', 'id_ID').format(DateTime.parse(doc!['visit']['scheduled_date'] as String))}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFB9D2C1), fontWeight: FontWeight.w500)),
          ]),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: StatusChip(status))],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(62),
            child: Container(
              color: AppColors.bg,
              child: Column(children: [
                LinearProgressIndicator(value: _progress(), minHeight: 3, color: AppColors.gold, backgroundColor: AppColors.green900),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TabBar(
                    isScrollable: true,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    indicator: BoxDecoration(color: AppColors.green800, borderRadius: BorderRadius.circular(99)),
                    splashBorderRadius: BorderRadius.circular(99),
                    tabs: [
                      tab(Icons.info_outline, 'Info'),
                      tab(Icons.pest_control_outlined, 'Temuan', '${list('findings').length}'),
                      tab(Icons.sanitizer_outlined, 'Tindakan', '${list('treatments').length}'),
                      tab(Icons.lightbulb_outline, 'Rekomendasi', '${list('recommendations').length}'),
                      tab(Icons.track_changes, 'Stasiun', stations.isEmpty ? null : '${list('station_checks').length}/${stations.length}'),
                      tab(Icons.send_outlined, 'Selesai'),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
        body: Column(children: [
          const SyncBanner(margin: EdgeInsets.fromLTRB(12, 12, 12, 0)),
          if (locked)
            ListenableBuilder(
              listenable: SyncService.instance,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Notice(
                  icon: delivered ? Icons.cloud_done_outlined : Icons.lock_outline,
                  tone: delivered ? Tone.success : Tone.warn,
                  text: _lockText(SyncService.instance.stateOf(visitId)),
                ),
              ),
            ),
          if (!checkedIn && !locked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.gold50, Colors.white]),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFBEEBF), width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Row(children: [
                    CircleAvatar(backgroundColor: AppColors.gold, foregroundColor: AppColors.green950, child: Icon(Icons.place_outlined)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sudah sampai di lokasi?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        Text('Check-in mencatat jam mulai dan lokasi GPS.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.green950),
                    onPressed: _checkIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Check-in di lokasi'),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: TabBarView(children: [
              _info(),
              _listTab('findings', _editFinding, Icons.pest_control_outlined, 'Tambah temuan', (f) {
                final lv = f['level'] as String?;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_name(_opts('pest_types', 'name_id'), f['pest_type_id']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                    Pill(levels[lv] ?? '-', color: _levelColor(lv).$1, bg: _levelColor(lv).$2),
                  ]),
                  const SizedBox(height: 2),
                  Text('${_name(_areas, f['area_id'], f['area_text'])} · ${f['is_active'] == true ? 'Aktif' : 'Tidak aktif'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  if ((f['remarks'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${f['remarks']}')),
                  const SizedBox(height: 10),
                  _photoStrip('finding', f['id'] as String),
                ]);
              }),
              _listTab('treatments', _editTreatment, Icons.sanitizer_outlined, 'Tambah tindakan', (t) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name(_opts('treatment_methods', 'name_id'), t['method_id']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('${_name(_areas, t['area_id'], t['area_text'])} · ${_name(_opts('chemicals', 'trade_name'), t['chemical_id'])}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    Text('Dosis ${t['dose_text'] ?? '-'} · Jumlah ${t['quantity_used'] ?? '-'}${(t['equipment'] ?? '').toString().isEmpty ? '' : ' · ${t['equipment']}'}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  ])),
              _listTab('recommendations', _editRecommendation, Icons.lightbulb_outline, 'Tambah rekomendasi', (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Pill(categories[r['category']] ?? '', color: AppColors.ink2, bg: AppColors.line2, dot: false),
                    const SizedBox(height: 8),
                    Text('${r['risk_finding']}', style: const TextStyle(color: AppColors.ink2)),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.arrow_forward, size: 16, color: AppColors.green600)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${r['recommendation']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                    ]),
                  ])),
              _stations(),
              _finish(),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Perkiraan kemajuan pengisian (untuk garis emas di bawah header).
  double _progress() {
    final stations = (bundle['stations'] as List? ?? const []);
    final steps = [
      d['checked_in'] == true,
      list('findings').isNotEmpty || list('treatments').isNotEmpty,
      stations.isEmpty || list('station_checks').length >= stations.length,
      sigs['technician'] != null,
      sigs['pic'] != null,
      delivered,
    ];
    return steps.where((x) => x).length / steps.length;
  }

  (Color, Color) _levelColor(String? lv) => switch (lv) {
        'high' => (AppColors.red, AppColors.red50),
        'medium' => (AppColors.amber, AppColors.amber50),
        'low' => (AppColors.green700, AppColors.green50),
        _ => (AppColors.muted, AppColors.line2),
      };

  String _lockText(VisitSyncState st) {
    if (status == 'published') return 'Laporan sudah terbit.';
    if (delivered) return 'Laporan sudah diterima server, menunggu review admin.';
    if (d['submitted'] == true) {
      return st.pending > 0 ? 'Laporan belum terkirim ke server. Buka tab Selesai untuk mengirim.' : 'Laporan belum diterima server. Buka tab Selesai untuk kirim ulang.';
    }
    return 'Laporan terkunci setelah tanda tangan PIC. Buka tab Selesai untuk mengirim.';
  }

  Widget _info() {
    final v = doc!['visit'];
    final prev = (bundle['previous_findings'] as List? ?? const []);
    final open = (bundle['open_recommendations'] as List? ?? const []);
    final contacts = (bundle['contacts'] as List? ?? const []);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Panel(
        child: Column(children: [
          _kv('Lokasi', '${doc!['site']['name']}\n${doc!['site']['address']}'),
          _kv('Tanggal', '${DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.parse(v['scheduled_date'] as String))}\n${visitTypes[v['visit_type']]}'),
          _kv('PIC', doc!['pic']?['name'] ?? '-'),
          _kv('Status', visitStatus[status] ?? status, last: true),
        ]),
      ),
      if ((v['notes'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 10),
        Notice(icon: Icons.sticky_note_2_outlined, tone: Tone.info, title: 'Catatan admin', text: '${v['notes']}'),
      ],
      if (status == 'revision' && doc!['report']?['review_notes'] != null) ...[
        const SizedBox(height: 10),
        Notice(icon: Icons.edit_note, tone: Tone.danger, title: 'Catatan revisi', text: '${doc!['report']['review_notes']}'),
      ],
      if (contacts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Panel(
          title: 'Kontak PIC',
          child: Column(children: [
            for (final c in contacts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: AppColors.gold, foregroundColor: AppColors.green950,
                      child: Text('${c['name']}'.isEmpty ? '?' : '${c['name']}'[0], style: const TextStyle(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${c['position'] ?? '-'}${c['is_primary'] == true ? ' · PIC utama' : ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ]),
                  ),
                  if ((c['phone'] ?? '').toString().isNotEmpty) SelectableText('${c['phone']}', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.green700)),
                ]),
              ),
          ]),
        ),
      ],
      if (prev.isNotEmpty) ...[
        const SizedBox(height: 10),
        Panel(
          title: 'Temuan kunjungan sebelumnya (${bundle['previous_visit_date']})',
          child: Column(children: [
            for (final f in prev)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.pest_control_outlined, size: 17, color: AppColors.green600),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${f['pest_name_id']} di ${f['area_name'] ?? '-'}')),
                  Pill(levels[f['level']] ?? '-', color: _levelColor(f['level'] as String?).$1, bg: _levelColor(f['level'] as String?).$2),
                ]),
              ),
          ]),
        ),
      ],
      if (open.isNotEmpty) ...[
        const SizedBox(height: 10),
        Panel(
          title: 'Rekomendasi yang belum dikerjakan pelanggan',
          child: Column(children: [
            for (final r in open)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.lightbulb_outline, size: 17, color: AppColors.gold600),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${categories[r['category']]}: ${r['recommendation']}')),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }

  Widget _kv(String k, String v, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 86, child: Text(k, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _listTab(String key, Future<void> Function([Map<String, dynamic>?]) edit, IconData icon, String addLabel, Widget Function(Map<String, dynamic>) tile) {
    final rows = list(key);
    final canEdit = !locked && d['checked_in'] == true;
    return Scaffold(
      floatingActionButton: canEdit ? FloatingActionButton.extended(onPressed: () => edit(), icon: const Icon(Icons.add), label: Text(addLabel)) : null,
      body: rows.isEmpty
          ? ListView(padding: const EdgeInsets.all(12), children: [
              Panel(child: EmptyView(icon: icon, title: 'Belum ada data', text: canEdit ? 'Tekan tombol $addLabel di bawah.' : null)),
            ])
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.line)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: canEdit ? () => edit(r) : null,
                      onLongPress: canEdit ? () => _remove(key, r) : null,
                      child: Padding(padding: const EdgeInsets.all(14), child: tile(r)),
                    ),
                  ),
                ),
              if (canEdit)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Ketuk untuk mengubah, tahan untuk menghapus.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ),
            ]),
    );
  }

  Widget _stations() {
    final stations = (bundle['stations'] as List? ?? const []).cast<Map<String, dynamic>>();
    final checks = list('station_checks');
    final canEdit = !locked && d['checked_in'] == true;
    return Scaffold(
      floatingActionButton: canEdit ? FloatingActionButton.extended(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan QR')) : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${checks.length} dari ${stations.length} stasiun sudah diperiksa', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: stations.isEmpty ? 0 : checks.length / stations.length, minHeight: 8, backgroundColor: AppColors.line2),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (stations.isEmpty) const Panel(child: EmptyView(icon: Icons.track_changes, title: 'Lokasi ini belum punya stasiun monitoring')),
        for (final s in stations)
          Builder(builder: (_) {
            final c = checks.where((x) => x['station_id'] == s['id']).firstOrNull;
            final (fg, bg) = switch (c?['status']) {
              'ok' => (AppColors.green700, AppColors.green50),
              'check' => (AppColors.amber, AppColors.amber50),
              'replace' => (AppColors.red, AppColors.red50),
              _ => (AppColors.muted, AppColors.line2),
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: canEdit ? () => _editStation(s) : null,
                child: Row(children: [
                  Icon(c == null ? Icons.radio_button_unchecked : Icons.check_circle, color: c == null ? const Color(0xFFB7C6BD) : fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['code']} · ${s['equipment_type']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(c == null ? (s['area_name'] ?? '-') : '${stationStatus[c['status']]} · ${consumption[c['bait_consumption']]}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    ]),
                  ),
                  if (c != null) Pill(stationStatus[c['status']] ?? '', color: fg, bg: bg),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  Widget _finish() {
    final canEdit = !locked && d['checked_in'] == true;
    final stations = (bundle['stations'] as List? ?? const []);
    Widget sig(String role, String label) {
      final s = sigs[role] as Map<String, dynamic>?;
      final canSign = d['checked_in'] == true && d['submitted'] != true && !delivered && (role == 'technician' || s == null || canEdit);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 64,
            height: 48,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line, width: 1.5)),
            child: s == null ? const Icon(Icons.draw_outlined, color: Color(0xFFB7C6BD)) : Image.file(File(s['path'] as String), fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(s == null ? 'Belum ada' : s['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          if (canSign)
            s == null
                ? FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w700, fontSize: 13)), onPressed: () => _sign(role), child: const Text('Tanda tangan'))
                : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: const TextStyle(fontFamily: 'PlusJakartaSans', fontWeight: FontWeight.w700, fontSize: 13)), onPressed: () => _sign(role), child: const Text('Ulangi'))
          else if (s != null)
            const Icon(Icons.check_circle, color: AppColors.green600),
        ]),
      );
    }

    Widget count(IconData icon, int n, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: Column(children: [
              Icon(icon, size: 20, color: AppColors.green700),
              const SizedBox(height: 2),
              Text('$n', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ]),
          ),
        );

    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        count(Icons.pest_control_outlined, list('findings').length, 'Temuan'),
        const SizedBox(width: 8),
        count(Icons.sanitizer_outlined, list('treatments').length, 'Tindakan'),
        const SizedBox(width: 8),
        count(Icons.lightbulb_outline, list('recommendations').length, 'Rekomendasi'),
        const SizedBox(width: 8),
        count(Icons.track_changes, list('station_checks').length, 'Stasiun${stations.isEmpty ? '' : '/${stations.length}'}'),
      ]),
      const SizedBox(height: 10),
      Panel(
        child: TextFormField(
          initialValue: d['general_notes'],
          enabled: canEdit,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Catatan umum', alignLabelWithHint: true),
          onChanged: (v) {
            d['general_notes'] = v;
            repo.saveDraft(visitId, d);
          },
        ),
      ),
      const SizedBox(height: 10),
      Panel(title: 'Foto dokumentasi umum', child: _photoStrip('report', null, size: 84)),
      const SizedBox(height: 10),
      Panel(
        title: 'Tanda tangan',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sig('technician', 'Teknisi'),
          const Divider(),
          sig('pic', 'PIC pelanggan'),
          const SizedBox(height: 6),
          const Text('Setelah PIC tanda tangan, isi laporan terkunci.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 14),
      ListenableBuilder(listenable: SyncService.instance, builder: (context, _) => _sendSection()),
      const SizedBox(height: 24),
    ]);
  }

  /// Status pengiriman dan tombol kirim / coba lagi.
  Widget _sendSection() {
    final sync = SyncService.instance;
    final st = sync.stateOf(visitId);
    final gold = FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.green950, minimumSize: const Size(48, 54));
    if (delivered) {
      return Notice(
        icon: Icons.cloud_done_outlined,
        tone: Tone.success,
        title: status == 'published' ? 'Laporan sudah terbit' : 'Laporan sudah diterima server',
        text: status == 'published' ? 'PDF laporan sudah bisa dilihat pelanggan.' : 'Menunggu review admin',
      );
    }
    if (d['checked_in'] != true) return const SizedBox.shrink();
    if (d['submitted'] != true) {
      return FilledButton.icon(style: gold, onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Kirim laporan'));
    }
    if (st.pending > 0) {
      final bad = st.error != null && !st.offline;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Notice(
          tone: bad ? Tone.danger : Tone.warn,
          icon: st.offline ? Icons.cloud_off : Icons.cloud_upload_outlined,
          title: 'Laporan belum terkirim ke server (${st.pending} data menunggu)',
          text: st.error ?? 'Aplikasi akan mencoba lagi otomatis saat ada sinyal.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: sync.running ? null : _sendNow,
          icon: sync.running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh),
          label: Text(sync.running ? 'Sedang mengirim...' : 'Coba kirim lagi'),
        ),
      ]);
    }
    // Pernah dikirim, antrian kosong, tapi server belum mencatatnya.
    return FilledButton.icon(style: gold, onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Kirim ulang laporan'));
  }
}
