import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// REST client for the U-Bike backend with Supabase bearer auth.
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path) async => _decode(await _http.get(_uri(path), headers: _headers()));

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async =>
      _decode(await _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  dynamic _decode(http.Response res) {
    final Map<String, dynamic> json =
        res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
    if (res.statusCode >= 200 && res.statusCode < 300) return json['data'] ?? json;
    final err = json['error'] as Map<String, dynamic>?;
    throw ApiException(res.statusCode, err?['message'] as String? ?? 'Request failed');
  }
}
