import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';

/// Info APK terbaru dari GitHub Release, didapat lewat server (GET /api/app/android).
class AppUpdateInfo {
  AppUpdateInfo({required this.current, required this.latest, required this.notes, required this.url, required this.size, this.sha256});

  final String current;
  final String latest;
  final String notes;
  final String url;
  final int size;
  final String? sha256;

  bool get available => isNewer(latest, current);
}

class AppUpdater {
  AppUpdater._();
  static final AppUpdater instance = AppUpdater._();

  /// Versi aplikasi yang sedang terpasang, misalnya 1.2.0.
  Future<String> currentVersion() async => (await PackageInfo.fromPlatform()).version;

  /// Menanyakan versi terbaru ke server. Mengembalikan null jika bukan Android.
  Future<AppUpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    final current = await currentVersion();
    final res = await Api.instance.get('/app/android') as Map<String, dynamic>;
    var url = res['download_url'] as String;
    // Repo private: server memberi alamat relatif dan meneruskan file dari GitHub.
    if (url.startsWith('/')) url = '${Api.instance.baseUrl}$url';
    final sha = res['sha256'] as String?;
    return AppUpdateInfo(
      current: current,
      latest: res['version'] as String,
      notes: (res['notes'] as String?) ?? '',
      url: url,
      size: (res['size'] as num?)?.toInt() ?? 0,
      sha256: (sha == null || sha.isEmpty) ? null : sha,
    );
  }
}

/// true jika [latest] (misalnya v1.3.0) lebih baru dari [current] (misalnya 1.2.5).
bool isNewer(String latest, String current) {
  List<int> parse(String v) {
    v = v.trim().replaceFirst(RegExp('^v'), '').split('+').first.split('-').first;
    final parts = v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  final a = parse(latest), b = parse(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
