import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'outbox.dart';

/// Database lokal SQLite supaya aplikasi tetap bisa dipakai tanpa sinyal.
///
/// - `cache`  : data dari server (katalog, daftar kunjungan, bundle lokasi) dalam bentuk JSON.
/// - `drafts` : isian laporan yang sedang dikerjakan teknisi, per kunjungan.
/// - `outbox` : antrian perubahan yang belum terkirim ke server, diproses berurutan.
class LocalDb implements OutboxStore {
  LocalDb._();
  static final LocalDb instance = LocalDb._();
  late Database _db;

  Future<void> init() async {
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'propestindo.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE cache (key TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE drafts (visit_id TEXT PRIMARY KEY, json TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await db.execute('''CREATE TABLE outbox (
          id INTEGER PRIMARY KEY AUTOINCREMENT, visit_id TEXT NOT NULL, kind TEXT NOT NULL,
          payload TEXT NOT NULL, created_at TEXT NOT NULL, error TEXT)''');
      },
    );
  }

  String get _now => DateTime.now().toIso8601String();

  Future<void> putCache(String key, Object value) => _db.insert(
      'cache', {'key': key, 'json': jsonEncode(value), 'updated_at': _now},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<dynamic> getCache(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String);
  }

  Future<void> saveDraft(String visitId, Map<String, dynamic> draft) => _db.insert(
      'drafts', {'visit_id': visitId, 'json': jsonEncode(draft), 'updated_at': _now},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>?> getDraft(String visitId) async {
    final rows = await _db.query('drafts', where: 'visit_id = ?', whereArgs: [visitId]);
    return rows.isEmpty ? null : jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
  }

  @override
  Future<void> enqueue(String visitId, String kind, Map<String, dynamic> payload) => _db.insert(
      'outbox', {'visit_id': visitId, 'kind': kind, 'payload': jsonEncode(payload), 'created_at': _now});

  @override
  Future<List<OutboxItem>> outbox() async =>
      [for (final r in await _db.query('outbox', orderBy: 'id')) OutboxItem.fromRow(r)];

  @override
  Future<int> pendingCount([String? visitId]) async {
    final rows = await _db.rawQuery(
        'SELECT count(*) AS n FROM outbox${visitId == null ? '' : ' WHERE visit_id = ?'}', [?visitId]);
    return rows.first['n'] as int;
  }

  @override
  Future<void> removeOutbox(int id) => _db.delete('outbox', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> markOutboxError(int id, String? error) =>
      _db.update('outbox', {'error': error}, where: 'id = ?', whereArgs: [id]);

  Future<void> clearAll() async {
    await _db.delete('cache');
    await _db.delete('drafts');
    await _db.delete('outbox');
  }
}
