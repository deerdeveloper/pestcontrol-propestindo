import 'dart:convert';

/// Satu perubahan yang menunggu dikirim ke server.
class OutboxItem {
  OutboxItem({required this.id, required this.visitId, required this.kind, required this.payload, this.error});

  factory OutboxItem.fromRow(Map<String, Object?> r) => OutboxItem(
        id: r['id'] as int,
        visitId: r['visit_id'] as String,
        kind: r['kind'] as String,
        payload: jsonDecode(r['payload'] as String) as Map<String, dynamic>,
        error: r['error'] as String?,
      );

  final int id;
  final String visitId;

  /// start, report, attachment, signature, submit
  final String kind;
  final Map<String, dynamic> payload;

  /// Error terakhir saat mencoba mengirim item ini.
  final String? error;

  /// Nama langkah yang dipahami teknisi, dipakai di pesan error.
  String get label => switch (kind) {
        'start' => 'Check-in',
        'report' => 'Isi laporan',
        'attachment' => 'Foto',
        'signature' => payload['role'] == 'pic' ? 'Tanda tangan PIC' : 'Tanda tangan teknisi',
        'submit' => 'Kirim laporan',
        _ => kind,
      };
}

/// Penyimpanan antrian. Diimplementasikan LocalDb (SQLite); di test memakai versi memori.
abstract class OutboxStore {
  Future<void> enqueue(String visitId, String kind, Map<String, dynamic> payload);
  Future<List<OutboxItem>> outbox();
  Future<int> pendingCount([String? visitId]);
  Future<void> removeOutbox(int id);
  Future<void> markOutboxError(int id, String? error);
}

/// Antrian di memori, untuk test.
class MemoryOutboxStore implements OutboxStore {
  final List<OutboxItem> items = [];
  int _next = 1;

  @override
  Future<void> enqueue(String visitId, String kind, Map<String, dynamic> payload) async =>
      items.add(OutboxItem(id: _next++, visitId: visitId, kind: kind, payload: payload));

  @override
  Future<List<OutboxItem>> outbox() async => List.of(items);

  @override
  Future<int> pendingCount([String? visitId]) async => items.where((x) => visitId == null || x.visitId == visitId).length;

  @override
  Future<void> removeOutbox(int id) async => items.removeWhere((x) => x.id == id);

  @override
  Future<void> markOutboxError(int id, String? error) async {
    final i = items.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final x = items[i];
    items[i] = OutboxItem(id: x.id, visitId: x.visitId, kind: x.kind, payload: x.payload, error: error);
  }
}
