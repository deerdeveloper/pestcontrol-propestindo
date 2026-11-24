import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alamat server bawaan. Bisa diubah saat build:
/// flutter run --dart-define=API_URL=https://api.propestindo.co.id
const defaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;

  /// true jika gagal karena jaringan (perlu dicoba lagi nanti), bukan karena data ditolak server.
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

/// Klien REST API backend Go.
class Api {
  Api._();
  static final Api instance = Api._();

  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 60)));
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
      final r = e.response;
      if (r == null) throw ApiException('Tidak ada koneksi ke server');
      final msg = r.data is Map ? (r.data['error'] ?? 'Gagal (${r.statusCode})') : 'Gagal (${r.statusCode})';
      throw ApiException(msg.toString(), status: r.statusCode);
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
