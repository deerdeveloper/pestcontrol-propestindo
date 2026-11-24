import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/api.dart';
import '../data/local_db.dart';
import '../data/repository.dart';
import '../data/sync.dart';
import '../labels.dart';
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

  Widget _photoStrip(String type, String? id) {
    final photos = _photosOf(type, id);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final ph in photos)
        ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(ph['path'] as String), width: 64, height: 64, fit: BoxFit.cover)),
      if (!locked)
        InkWell(
          onTap: () => _addPhoto(type, id),
          child: Container(width: 64, height: 64, decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)), child: const Icon(Icons.add_a_photo)),
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
      return Scaffold(appBar: AppBar(), body: Center(child: error != null ? Text(error!) : const CircularProgressIndicator()));
    }
    final checkedIn = d['checked_in'] == true;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(doc!['customer']['name'] as String),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Info'), Tab(text: 'Temuan'), Tab(text: 'Tindakan'), Tab(text: 'Rekomendasi'), Tab(text: 'Stasiun'), Tab(text: 'Selesai'),
          ]),
        ),
        body: Column(children: [
          const SyncBanner(),
          if (locked)
            ListenableBuilder(
              listenable: SyncService.instance,
              builder: (context, _) => MaterialBanner(
                content: Text(_lockText(SyncService.instance.stateOf(visitId))),
                actions: const [SizedBox.shrink()],
              ),
            ),
          if (!checkedIn && !locked)
            Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: _checkIn, icon: const Icon(Icons.login), label: const Text('Check-in di lokasi'))),
          Expanded(
            child: TabBarView(children: [
              _info(),
              _listTab('findings', _editFinding, (f) => ListTile(
                    title: Text('${_name(_opts('pest_types', 'name_id'), f['pest_type_id'])} · ${levels[f['level']]}'),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_name(_areas, f['area_id'], f['area_text'])}${f['is_active'] == true ? ' · Aktif' : ' · Tidak aktif'}${(f['remarks'] ?? '').isEmpty ? '' : '\n${f['remarks']}'}'),
                      const SizedBox(height: 6),
                      _photoStrip('finding', f['id'] as String),
                    ]),
                  )),
              _listTab('treatments', _editTreatment, (t) => ListTile(
                    title: Text(_name(_opts('treatment_methods', 'name_id'), t['method_id'])),
                    subtitle: Text('${_name(_areas, t['area_id'], t['area_text'])} · ${_name(_opts('chemicals', 'trade_name'), t['chemical_id'])} · ${t['dose_text'] ?? '-'}'),
                  )),
              _listTab('recommendations', _editRecommendation, (r) => ListTile(
                    title: Text(categories[r['category']] ?? ''),
                    subtitle: Text('${r['risk_finding']}\n→ ${r['recommendation']}'),
                  )),
              _stations(),
              _finish(),
            ]),
          ),
        ]),
      ),
    );
  }

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
    return ListView(padding: const EdgeInsets.all(16), children: [
      _kv('Lokasi', '${doc!['site']['name']}\n${doc!['site']['address']}'),
      _kv('Tanggal', '${v['scheduled_date']} · ${visitTypes[v['visit_type']]}'),
      _kv('PIC', doc!['pic']?['name'] ?? '-'),
      _kv('Status', visitStatus[status] ?? status),
      if ((v['notes'] ?? '').toString().isNotEmpty) _kv('Catatan admin', v['notes']),
      if (status == 'revision' && doc!['report']?['review_notes'] != null)
        Card(color: Colors.red.shade50, child: ListTile(leading: const Icon(Icons.edit_note), title: const Text('Catatan revisi'), subtitle: Text(doc!['report']['review_notes']))),
      if (prev.isNotEmpty) ...[
        const Divider(),
        Text('Temuan kunjungan sebelumnya (${bundle['previous_visit_date']})', style: Theme.of(context).textTheme.titleSmall),
        for (final f in prev) Text('• ${f['pest_name_id']} di ${f['area_name'] ?? '-'}: ${levels[f['level']]}'),
      ],
      if (open.isNotEmpty) ...[
        const Divider(),
        Text('Rekomendasi yang belum dikerjakan pelanggan', style: Theme.of(context).textTheme.titleSmall),
        for (final r in open) Text('• ${categories[r['category']]}: ${r['recommendation']}'),
      ],
    ]);
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );

  Widget _listTab(String key, Future<void> Function([Map<String, dynamic>?]) edit, Widget Function(Map<String, dynamic>) tile) {
    final rows = list(key);
    final canEdit = !locked && d['checked_in'] == true;
    return Scaffold(
      floatingActionButton: canEdit ? FloatingActionButton(onPressed: () => edit(), child: const Icon(Icons.add)) : null,
      body: rows.isEmpty
          ? Center(child: Text(canEdit ? 'Belum ada data. Tekan + untuk menambah.' : 'Belum ada data.'))
          : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
              for (final r in rows)
                Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: InkWell(
                    onTap: canEdit ? () => edit(r) : null,
                    onLongPress: canEdit ? () => _remove(key, r) : null,
                    child: tile(r),
                  ),
                ),
              if (canEdit) const Padding(padding: EdgeInsets.all(12), child: Text('Ketuk untuk mengubah, tahan untuk menghapus.', style: TextStyle(color: Colors.grey))),
            ]),
    );
  }

  Widget _stations() {
    final stations = (bundle['stations'] as List? ?? const []).cast<Map<String, dynamic>>();
    final checks = list('station_checks');
    final canEdit = !locked && d['checked_in'] == true;
    return Scaffold(
      floatingActionButton: canEdit ? FloatingActionButton.extended(onPressed: _scan, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan QR')) : null,
      body: ListView(padding: const EdgeInsets.only(bottom: 80), children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('${checks.length} dari ${stations.length} stasiun sudah diperiksa')),
        for (final s in stations)
          Builder(builder: (_) {
            final c = checks.where((x) => x['station_id'] == s['id']).firstOrNull;
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: ListTile(
                leading: Icon(c == null ? Icons.radio_button_unchecked : Icons.check_circle, color: c == null ? Colors.grey : (c['status'] == 'ok' ? Colors.green : Colors.orange)),
                title: Text('${s['code']} · ${s['equipment_type']}'),
                subtitle: Text(c == null ? (s['area_name'] ?? '-') : '${stationStatus[c['status']]} · ${consumption[c['bait_consumption']]}'),
                onTap: canEdit ? () => _editStation(s) : null,
              ),
            );
          }),
      ]),
    );
  }

  Widget _finish() {
    final canEdit = !locked && d['checked_in'] == true;
    Widget sig(String role, String label) {
      final s = sigs[role] as Map<String, dynamic>?;
      return Card(
        child: ListTile(
          leading: s == null ? const Icon(Icons.draw) : Image.file(File(s['path'] as String), width: 72),
          title: Text(label),
          subtitle: Text(s == null ? 'Belum tanda tangan' : s['name'] as String),
          trailing: d['checked_in'] == true && d['submitted'] != true && !delivered &&
                  (role == 'technician' || s == null || canEdit)
              ? TextButton(onPressed: () => _sign(role), child: Text(s == null ? 'Tanda tangan' : 'Ulangi'))
              : null,
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      TextFormField(
        initialValue: d['general_notes'],
        enabled: canEdit,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Catatan umum'),
        onChanged: (v) {
          d['general_notes'] = v;
          repo.saveDraft(visitId, d);
        },
      ),
      const SizedBox(height: 16),
      Text('Foto dokumentasi umum', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      _photoStrip('report', null),
      const SizedBox(height: 16),
      Text('Ringkasan: ${list('findings').length} temuan, ${list('treatments').length} tindakan, '
          '${list('recommendations').length} rekomendasi, ${list('station_checks').length} stasiun.'),
      const SizedBox(height: 16),
      sig('technician', 'Tanda tangan teknisi'),
      sig('pic', 'Tanda tangan PIC pelanggan'),
      const SizedBox(height: 8),
      const Text('Setelah PIC tanda tangan, isi laporan terkunci.', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 16),
      ListenableBuilder(listenable: SyncService.instance, builder: (context, _) => _sendSection()),
    ]);
  }

  /// Status pengiriman dan tombol kirim / coba lagi.
  Widget _sendSection() {
    final sync = SyncService.instance;
    final st = sync.stateOf(visitId);
    if (delivered) {
      return Card(
        color: Colors.green.shade50,
        child: ListTile(
          leading: const Icon(Icons.cloud_done, color: Colors.green),
          title: Text(status == 'published' ? 'Laporan sudah terbit' : 'Laporan sudah diterima server'),
          subtitle: status == 'published' ? null : const Text('Menunggu review admin'),
        ),
      );
    }
    if (d['checked_in'] != true) return const SizedBox.shrink();
    if (d['submitted'] != true) {
      return FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Kirim laporan'));
    }
    if (st.pending > 0) {
      return Card(
        color: st.error != null && !st.offline ? Colors.red.shade50 : Colors.amber.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              sync.running
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(st.offline ? Icons.cloud_off : Icons.cloud_upload, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(child: Text('Laporan belum terkirim ke server (${st.pending} data menunggu)', style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            if (st.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(st.error!)),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: sync.running ? null : _sendNow, icon: const Icon(Icons.refresh), label: Text(sync.running ? 'Sedang mengirim...' : 'Coba kirim lagi')),
          ]),
        ),
      );
    }
    // Pernah dikirim, antrian kosong, tapi server belum mencatatnya.
    return FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.send), label: const Text('Kirim ulang laporan'));
  }
}
