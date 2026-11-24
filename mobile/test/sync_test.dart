import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:propestindo_teknisi/data/api.dart';
import 'package:propestindo_teknisi/data/outbox.dart';
import 'package:propestindo_teknisi/data/sync.dart';

/// Server palsu: mencatat item yang terkirim dan bisa diatur untuk gagal.
class FakeServer {
  final sent = <String>[];
  Object? Function(OutboxItem item)? failWith;

  Future<void> send(OutboxItem item) async {
    final err = failWith?.call(item);
    if (err != null) throw err;
    sent.add('${item.visitId}:${item.kind}');
  }
}

Future<void> queueReport(MemoryOutboxStore store, String visit) async {
  await store.enqueue(visit, 'report', {'general_notes': 'x'});
  await store.enqueue(visit, 'attachment', {'id': 'f1', 'owner_type': 'report', 'path': '/tmp/f1.jpg'});
  await store.enqueue(visit, 'signature', {'role': 'technician', 'name': 'Teknisi', 'path': '/tmp/t.png'});
  await store.enqueue(visit, 'signature', {'role': 'pic', 'name': 'PIC', 'path': '/tmp/p.png'});
  await store.enqueue(visit, 'submit', {});
}

void main() {
  late MemoryOutboxStore store;
  late FakeServer server;
  late SyncService sync;

  setUp(() {
    store = MemoryOutboxStore();
    server = FakeServer();
    sync = SyncService(store: store, sender: server.send, canSend: () => true);
  });

  test('semua item terkirim berurutan dan antrian kosong', () async {
    await queueReport(store, 'v1');
    final st = await sync.flushVisit('v1');
    expect(st.done, isTrue);
    expect(server.sent, ['v1:report', 'v1:attachment', 'v1:signature', 'v1:signature', 'v1:submit']);
    expect(sync.pending, 0);
    expect(sync.lastError, isNull);
  });

  test('tanpa koneksi: data tetap di antrian dan ditandai offline', () async {
    await queueReport(store, 'v1');
    server.failWith = (_) => ApiException('Tidak ada koneksi ke server');
    final st = await sync.flushVisit('v1');
    expect(st.pending, 5);
    expect(st.offline, isTrue);
    expect(st.error, contains('Tidak ada koneksi'));

    server.failWith = null;
    expect((await sync.flushVisit('v1')).done, isTrue);
  });

  test('ditolak server: error terlihat dengan nama langkah, kunjungan lain tetap terkirim', () async {
    await queueReport(store, 'v1');
    await queueReport(store, 'v2');
    server.failWith = (i) => i.visitId == 'v1' && i.kind == 'signature' && i.payload['role'] == 'pic'
        ? ApiException('upload tidak valid atau lebih dari 15 MB', status: 400)
        : null;
    await sync.run();

    final v1 = sync.stateOf('v1');
    expect(v1.pending, 2, reason: 'TTD PIC dan submit v1 tertahan');
    expect(v1.offline, isFalse);
    expect(v1.error, 'Tanda tangan PIC: upload tidak valid atau lebih dari 15 MB');
    expect(sync.stateOf('v2').done, isTrue);
    expect(server.sent, isNot(contains('v1:submit')), reason: 'urutan per kunjungan dijaga');
    expect(sync.lastError, contains('Tanda tangan PIC'));
  });

  test('isi laporan yang sudah terkunci di server dilewati, laporan tetap terkirim', () async {
    await queueReport(store, 'v1');
    server.failWith = (i) => i.kind == 'report'
        ? ApiException('laporan sudah ditandatangani PIC dan terkunci', status: 409, code: 'report_locked')
        : null;
    expect((await sync.flushVisit('v1')).done, isTrue);
    expect(server.sent.last, 'v1:submit');
  });

  test('foto yang sudah terhapus dari HP dilewati', () async {
    await queueReport(store, 'v1');
    server.failWith = (i) => i.kind == 'attachment' ? const PathNotFoundException('/tmp/f1.jpg', OSError()) : null;
    expect((await sync.flushVisit('v1')).done, isTrue);
  });

  test('file tanda tangan hilang: tidak diam-diam, error tampil', () async {
    await queueReport(store, 'v1');
    server.failWith = (i) => i.kind == 'signature' ? const PathNotFoundException('/tmp/t.png', OSError()) : null;
    final st = await sync.flushVisit('v1');
    expect(st.done, isFalse);
    expect(st.error, contains('file tidak ditemukan'));
  });

  test('error tak terduga tidak hilang diam-diam', () async {
    await queueReport(store, 'v1');
    server.failWith = (i) => i.kind == 'report' ? StateError('rusak') : null;
    final st = await sync.flushVisit('v1');
    expect(st.pending, 5);
    expect(st.error, contains('Isi laporan'));
  });

  test('data yang masuk saat pengiriman berjalan ikut terkirim pada panggilan yang sama', () async {
    await store.enqueue('v1', 'start', {});
    var injected = false;
    server.failWith = (i) {
      if (!injected) {
        injected = true;
        // Teknisi menekan Kirim saat antrian check-in masih berjalan.
        store.enqueue('v1', 'report', {});
        store.enqueue('v1', 'submit', {});
        sync.run();
      }
      return null;
    };
    await sync.run();
    expect(sync.stateOf('v1').done, isTrue);
    expect(server.sent.first, 'v1:start');
    expect(server.sent.last, 'v1:submit');
  });

  test('tidak mengirim apa pun bila belum login', () async {
    sync = SyncService(store: store, sender: server.send, canSend: () => false);
    await queueReport(store, 'v1');
    await sync.run();
    expect(server.sent, isEmpty);
  });
}
