import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'local_db.dart';
import 'sync.dart';

const uuid = Uuid();

/// Mengambil data dari server bila online, dan memakai cache lokal bila offline.
class Repository {
  Repository._();
  static final Repository instance = Repository._();
  final _db = LocalDb.instance;
  final _api = Api.instance;

  Future<T> _cached<T>(String key, Future<dynamic> Function() fetch) async {
    try {
      final data = await fetch();
      await _db.putCache(key, data as Object);
      return data as T;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final cached = await _db.getCache(key);
      if (cached == null) rethrow;
      return cached as T;
    }
  }

  Future<Map<String, dynamic>> catalog() => _cached('catalog', () => _api.get('/catalog'));

  /// Kunjungan 7 hari ke belakang sampai 30 hari ke depan.
  Future<List<dynamic>> myVisits() {
    final f = DateFormat('yyyy-MM-dd');
    final now = DateTime.now();
    final from = f.format(now.subtract(const Duration(days: 7)));
    final to = f.format(now.add(const Duration(days: 30)));
    return _cached('my_visits', () => _api.get('/me/visits?from=$from&to=$to'));
  }

  Future<Map<String, dynamic>> bundle(String visitId) => _cached('bundle:$visitId', () => _api.get('/visits/$visitId/bundle'));

  /// Mengunduh katalog dan bundle semua kunjungan supaya siap dipakai offline.
  Future<void> prefetch(List<dynamic> visits) async {
    await catalog();
    for (final v in visits) {
      if (['scheduled', 'in_progress', 'revision'].contains(v['status'])) {
        try {
          await bundle(v['id'] as String);
        } catch (_) {}
      }
    }
  }

  /// Draf laporan lokal. Jika belum ada, dibuat dari laporan di server (misal saat revisi).
  Future<Map<String, dynamic>> draft(String visitId, Map<String, dynamic> doc) async {
    final existing = await _db.getDraft(visitId);
    if (existing != null) return existing;
    final r = doc['report'] as Map<String, dynamic>?;
    List<Map<String, dynamic>> rows(String k, List<String> keep) => [
          for (final x in (r?[k] as List? ?? const []))
            {for (final f in keep) f: (x as Map)[f]}
        ];
    return {
      'checked_in': r != null,
      'submitted': false,
      'started_at': r?['started_at'],
      'pic_name': r?['pic_name'] ?? doc['pic']?['name'],
      'general_notes': r?['general_notes'],
      'findings': rows('findings', ['id', 'pest_type_id', 'area_id', 'area_text', 'level', 'is_active', 'remarks']),
      'treatments': rows('treatments', ['id', 'method_id', 'area_id', 'area_text', 'chemical_id', 'dose_text', 'quantity_used', 'equipment']),
      'recommendations': rows('recommendations', ['id', 'category', 'risk_finding', 'recommendation']),
      'station_checks': rows('station_checks', ['id', 'station_id', 'status', 'bait_consumption', 'finding']),
      'photos': <Map<String, dynamic>>[],
      'signatures': <String, dynamic>{},
    };
  }

  Future<void> saveDraft(String visitId, Map<String, dynamic> d) => _db.saveDraft(visitId, d);

  Future<void> checkIn(String visitId, Map<String, dynamic> d, {double? lat, double? lng}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    d['checked_in'] = true;
    d['started_at'] ??= now;
    await _db.saveDraft(visitId, d);
    await _db.enqueue(visitId, 'start', {'started_at': d['started_at'], 'lat': lat, 'lng': lng});
    SyncService.instance.run();
  }

  /// Mengantrikan seluruh laporan: isi, foto, tanda tangan, lalu kirim untuk review.
  Future<void> submit(String visitId, Map<String, dynamic> d) async {
    d['finished_at'] ??= DateTime.now().toUtc().toIso8601String();
    await _db.enqueue(visitId, 'report', {
      'pic_name': d['pic_name'],
      'general_notes': d['general_notes'],
      'started_at': d['started_at'],
      'finished_at': d['finished_at'],
      'findings': d['findings'],
      'treatments': d['treatments'],
      'recommendations': d['recommendations'],
      'station_checks': d['station_checks'],
    });
    for (final ph in (d['photos'] as List).cast<Map<String, dynamic>>()) {
      if (ph['queued'] == true) continue;
      await _db.enqueue(visitId, 'attachment', ph);
      ph['queued'] = true;
    }
    final sigs = d['signatures'] as Map<String, dynamic>;
    for (final role in ['technician', 'pic']) {
      final s = sigs[role] as Map<String, dynamic>?;
      if (s == null || s['queued'] == true) continue;
      await _db.enqueue(visitId, 'signature', {'role': role, 'name': s['name'], 'path': s['path'], 'signed_at': s['signed_at']});
      s['queued'] = true;
    }
    await _db.enqueue(visitId, 'submit', {});
    d['submitted'] = true;
    await _db.saveDraft(visitId, d);
    SyncService.instance.run();
  }
}
