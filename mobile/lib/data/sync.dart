import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'local_db.dart';
import 'outbox.dart';

/// Mengirim satu item antrian ke server. Bisa diganti di test.
typedef OutboxSender = Future<void> Function(OutboxItem item);

/// Status antrian satu kunjungan.
class VisitSyncState {
  const VisitSyncState({this.pending = 0, this.error, this.offline = false});

  /// Jumlah data kunjungan ini yang belum terkirim.
  final int pending;

  /// Error terakhir (sudah diberi nama langkahnya), atau null.
  final String? error;

  /// true jika tertahan karena tidak ada koneksi, bukan karena ditolak server.
  final bool offline;

  bool get done => pending == 0;
}

/// Mengirim antrian outbox ke server secara berurutan.
///
/// - Urutan dijaga per kunjungan. Jika satu kunjungan ditolak server, kunjungan lain tetap dikirim.
/// - Jika tidak ada koneksi, semua berhenti dan dicoba lagi saat sinyal kembali / tiap 2 menit.
/// - Setiap kegagalan disimpan per item supaya bisa ditampilkan ke teknisi, tidak hilang diam-diam.
class SyncService extends ChangeNotifier {
  SyncService({OutboxStore? store, OutboxSender? sender, bool Function()? canSend})
      : _storeOverride = store,
        _sender = sender ?? sendToApi,
        _canSend = canSend ?? (() => Api.instance.token != null);

  static final SyncService instance = SyncService();

  final OutboxStore? _storeOverride;
  OutboxStore get _store => _storeOverride ?? LocalDb.instance;
  final OutboxSender _sender;
  final bool Function() _canSend;

  bool running = false;
  int pending = 0;
  String? lastError;

  /// true jika putaran terakhir berhenti karena tidak ada koneksi ke server.
  bool offline = false;
  Map<String, VisitSyncState> visits = {};

  Future<void>? _current;
  bool _again = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;

  Future<void> init() async {
    await _refresh();
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) run();
    });
    _timer ??= Timer.periodic(const Duration(minutes: 2), (_) {
      if (pending > 0) run();
    });
    run();
  }

  VisitSyncState stateOf(String visitId) => visits[visitId] ?? const VisitSyncState();

  /// Menjalankan pengiriman. Jika sedang berjalan, satu putaran lagi dijadwalkan supaya
  /// data yang baru masuk antrian ikut terkirim; Future ini selesai setelah putaran itu.
  Future<void> run() {
    if (!_canSend()) return Future.value();
    final cur = _current;
    if (cur != null) {
      _again = true;
      return cur;
    }
    final f = _loop().whenComplete(() => _current = null);
    _current = f;
    return f;
  }

  /// Mengirim sekarang dan mengembalikan status kunjungan ini setelahnya.
  Future<VisitSyncState> flushVisit(String visitId) async {
    await run();
    return stateOf(visitId);
  }

  Future<void> _loop() async {
    running = true;
    notifyListeners();
    try {
      do {
        _again = false;
        lastError = null;
        offline = false;
        final blocked = <String>{}; // kunjungan yang tertahan karena ditolak server
        for (final item in await _store.outbox()) {
          if (blocked.contains(item.visitId)) continue;
          final failure = await _sendOne(item);
          if (failure == null) continue;
          lastError = failure.message;
          await _store.markOutboxError(item.id, failure.message);
          if (failure.offline) {
            offline = true;
            _again = false;
            break; // tidak ada koneksi: berhenti semua, coba lagi nanti
          }
          blocked.add(item.visitId);
        }
      } while (_again);
    } finally {
      await _refresh();
      running = false;
      notifyListeners();
    }
  }

  /// Mengirim satu item. Mengembalikan null bila selesai (terkirim, atau memang boleh dilewati).
  Future<({String message, bool offline})?> _sendOne(OutboxItem item) async {
    try {
      await _sender(item);
      await _store.removeOutbox(item.id);
      return null;
    } on ApiException catch (e) {
      if (alreadyOnServer(item, e)) {
        await _store.removeOutbox(item.id);
        return null;
      }
      return (message: '${item.label}: ${e.message}', offline: e.isNetwork);
    } on FileSystemException catch (e) {
      if (item.kind == 'attachment') {
        // Foto sudah terhapus dari HP: lewati supaya laporan tetap bisa terkirim.
        debugPrint('Foto ${item.payload['path']} tidak ada, dilewati: $e');
        await _store.removeOutbox(item.id);
        return null;
      }
      return (message: '${item.label}: file tidak ditemukan di HP', offline: false);
    } catch (e) {
      // Error lain (data rusak, dsb.) jangan sampai hilang diam-diam.
      return (message: '${item.label}: $e', offline: false);
    }
  }

  Future<void> _refresh() async {
    final items = await _store.outbox();
    final byVisit = <String, List<OutboxItem>>{};
    for (final x in items) {
      byVisit.putIfAbsent(x.visitId, () => []).add(x);
    }
    pending = items.length;
    lastError ??= items.map((x) => x.error).whereType<String>().firstOrNull;
    visits = {
      for (final e in byVisit.entries)
        e.key: VisitSyncState(
          pending: e.value.length,
          error: e.value.map((x) => x.error).whereType<String>().firstOrNull,
          offline: offline,
        ),
    };
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

/// Penolakan server yang berarti data ini sebenarnya sudah ada di server.
///
/// Isi laporan ditolak dengan kode `report_locked` karena tanda tangan PIC sudah sampai.
/// Antrian selalu mengirim isi laporan sebelum tanda tangan PIC, jadi isi di server sudah
/// versi terakhir dan item ini boleh dilewati.
bool alreadyOnServer(OutboxItem item, ApiException e) => item.kind == 'report' && e.code == 'report_locked';

/// Pengirim bawaan: memanggil REST API backend di alamat server yang dipakai saat login.
Future<void> sendToApi(OutboxItem item) async {
  final api = Api.instance;
  final visitId = item.visitId;
  final p = item.payload;
  switch (item.kind) {
    case 'start':
      await api.post('/visits/$visitId/start', p);
    case 'report':
      await api.put('/visits/$visitId/report', p);
    case 'attachment':
      await api.upload('/visits/$visitId/attachments', File(p['path'] as String), {
        'id': p['id'] as String,
        'owner_type': p['owner_type'] as String,
        if (p['owner_id'] != null) 'owner_id': p['owner_id'] as String,
        if (p['caption'] != null) 'caption': p['caption'] as String,
      });
    case 'signature':
      await api.upload('/visits/$visitId/signatures', File(p['path'] as String), {
        'signer_role': p['role'] as String,
        'signer_name': (p['name'] ?? '') as String,
        'signed_at': (p['signed_at'] ?? '') as String,
      });
    case 'submit':
      await api.post('/visits/$visitId/submit');
    default:
      throw ApiException('Jenis antrian tidak dikenal: ${item.kind}', status: 0);
  }
}
