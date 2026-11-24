import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alamat server bawaan. Bisa diubah saat build:
/// flutter run --dart-define=API_URL=https://api.propestindo.co.id
const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.code});
  final String message;
  final int? status;

  /// Kode error tetap dari server (mis. `report_locked`), jika ada.
  final String? code;

  /// true jika gagal karena jaringan (perlu dicoba lagi nanti), bukan karena data ditolak server.
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Mengubah DioException menjadi pesan yang bisa dipahami teknisi.
ApiException apiErrorFrom(DioException e) {
  final r = e.response;
  if (r == null) {
    final msg = switch (e.type) {
      DioExceptionType.connectionTimeout => 'Server tidak menjawab (koneksi habis waktu)',
      DioExceptionType.sendTimeout => 'Upload terlalu lama, sinyal lemah. Akan dicoba lagi',
      DioExceptionType.receiveTimeout => 'Server terlalu lama membalas. Akan dicoba lagi',
      DioExceptionType.badCertificate => 'Sertifikat HTTPS server tidak valid',
      _ => 'Tidak ada koneksi ke server',
    };
    return ApiException(msg);
  }
  final code = r.statusCode;
  if (r.data is Map) {
    final m = r.data as Map;
    return ApiException((m['error'] ?? 'Gagal ($code)').toString(), status: code, code: m['code']?.toString());
  }
  // Balasan bukan JSON biasanya datang dari reverse proxy (nginx, Cloudflare), bukan dari aplikasi.
  final msg = switch (code) {
    413 => 'File terlalu besar untuk server/proxy (413). Naikkan batas upload, mis. client_max_body_size 20m di nginx',
    502 || 503 || 504 => 'Server sedang tidak bisa dihubungi ($code)',
    404 => 'Alamat server salah atau API tidak ditemukan (404). Cek alamat server di halaman login',
    _ => 'Gagal ($code)',
  };
  return ApiException(msg, status: code);
}

/// Klien REST API backend Go.
class Api {
  Api._();
  static final Api instance = Api._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    sendTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 60),
  ));
  String baseUrl = defaultApiUrl;
  String? token;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('api_url') ?? defaultApiUrl;
    token = p.getString('token');
  }

  Future<void> saveSession({required String url, String? newToken}) async {
    final p = await SharedPreferences.getInstance();
    baseUrl = url;
    token = newToken;
    await p.setString('api_url', url);
    newToken == null ? await p.remove('token') : await p.setString('token', newToken);
  }

  Future<dynamic> _send(String method, String path, {Object? data}) async {
    try {
      final res = await _dio.request<dynamic>(
        '$baseUrl/api$path',
        data: data,
        options: Options(method: method, headers: {if (token != null) 'Authorization': 'Bearer $token'}),
      );
      return res.data;
    } on DioException catch (e) {
      throw apiErrorFrom(e);
    }
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, data: body);
  Future<dynamic> put(String path, Object body) => _send('PUT', path, data: body);

  Future<dynamic> upload(String path, File file, Map<String, String> fields) async {
    final form = FormData.fromMap({...fields, 'file': await MultipartFile.fromFile(file.path)});
    return _send('POST', path, data: form);
  }

  Future<Map<String, dynamic>> login(String url, String email, String password) async {
    url = url.trim().replaceAll(RegExp(r'/+$'), '');
    baseUrl = url;
    final res = await post('/auth/login', {'email': email, 'password': password}) as Map<String, dynamic>;
    final user = res['user'] as Map<String, dynamic>;
    if (user['role'] != 'technician') {
      throw ApiException('Aplikasi ini khusus teknisi. Admin dan pelanggan memakai aplikasi web.', status: 403);
    }
    await saveSession(url: url, newToken: res['token'] as String);
    return user;
  }
}
