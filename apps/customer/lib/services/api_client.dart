import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

/// Thin REST client for the U-Bike backend. Attaches the current Supabase
/// access token as a Bearer credential on every call.
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

  Future<dynamic> get(String path) async {
    final res = await _http.get(_uri(path), headers: _headers());
    return _decode(res);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final res = await _http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final Map<String, dynamic> json =
        res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : {};
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json['data'] ?? json;
    }
    final err = json['error'] as Map<String, dynamic>?;
    throw ApiException(res.statusCode, err?['message'] as String? ?? 'Request failed');
  }
}
