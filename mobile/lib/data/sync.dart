import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'local_db.dart';

/// Mengirim antrian outbox ke server secara berurutan saat ada koneksi.
class SyncService extends ChangeNotifier {
  SyncService._();
  static final SyncService instance = SyncService._();

  bool running = false;
  int pending = 0;
  String? lastError;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> init() async {
    pending = await LocalDb.instance.pendingCount();
    _sub ??= Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) run();
    });
    run();
  }

  Future<void> run() async {
    if (running || Api.instance.token == null) return;
    running = true;
    lastError = null;
    notifyListeners();
    try {
      for (final item in await LocalDb.instance.outbox()) {
        final id = item['id'] as int;
        final visitId = item['visit_id'] as String;
        final payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
        try {
          await _send(visitId, item['kind'] as String, payload);
          await LocalDb.instance.removeOutbox(id);
        } on ApiException catch (e) {
          lastError = e.message;
          if (!e.isNetwork) await LocalDb.instance.markOutboxError(id, e.message);
          break; // berhenti supaya urutan tetap terjaga, coba lagi nanti
        }
      }
    } finally {
      pending = await LocalDb.instance.pendingCount();
      running = false;
      notifyListeners();
    }
  }

  Future<void> _send(String visitId, String kind, Map<String, dynamic> p) async {
    final api = Api.instance;
    switch (kind) {
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
          'signer_name': p['name'] as String,
          'signed_at': p['signed_at'] as String,
        });
      case 'submit':
        await api.post('/visits/$visitId/submit');
      default:
        throw ApiException('Jenis antrian tidak dikenal: $kind', status: 0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
