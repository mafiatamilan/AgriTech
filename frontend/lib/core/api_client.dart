import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'supabase.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin HTTP client for the FastAPI backend.
///
/// Attaches the Supabase access token to every request. On a 401 it
/// refreshes the Supabase session once and retries before giving up.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
        '${AppConfig.apiBaseUrl}$path',
      ).replace(queryParameters: query);

  Map<String, String> _headers({bool json = true}) {
    final token = supabase.auth.currentSession?.accessToken;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(() => _client.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body, Map<String, String>? query}) =>
      _send(() => _client.post(
            _uri(path, query),
            headers: _headers(),
            body: jsonEncode(body),
          ));

  Future<dynamic> patch(String path, {Object? body, Map<String, String>? query}) =>
      _send(() => _client.patch(
            _uri(path, query),
            headers: _headers(),
            body: jsonEncode(body),
          ));

  /// Multipart POST (photo upload, chat messages with image).
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    Map<String, String>? query,
  }) {
    final request = http.MultipartRequest('POST', _uri(path, query));
    request.headers.addAll(_headers(json: false));
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile(
        fileField,
        file.openRead(),
        file.lengthSync(),
        filename: file.uri.pathSegments.last,
      ),
    );
    return _send(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
  }

  static const _timeout = Duration(seconds: 10);

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    var response = await call().timeout(_timeout);
    if (response.statusCode == 401) {
      // Expired Supabase session — refresh once and retry.
      try {
        await supabase.auth.refreshSession();
      } on Exception {
        // Refresh failed; fall through and surface the 401.
      }
      final token = supabase.auth.currentSession?.accessToken;
      if (token != null) {
        response = await call().timeout(_timeout);
      }
      if (response.statusCode == 401) {
        // Still unauthorized after the refresh — back to the login screen.
        await supabase.auth.signOut();
      }
    }
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty
        ? null
        : jsonDecode(response.body) as dynamic;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    final detail = (body is Map && body['detail'] != null)
        ? body['detail'].toString()
        : 'Request failed (${response.statusCode})';
    throw ApiException(response.statusCode, detail);
  }
}