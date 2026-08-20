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
  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiBaseUrl}$path').replace(queryParameters: query);

  Map<String, String> _headers({bool json = true}) {
    final token = supabase.auth.currentSession?.accessToken;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send(
    () => _client.get(_uri(path, query), headers: _headers()),
    path: path,
  );

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) => _send(
    () => _client.post(
      _uri(path, query),
      headers: _headers(),
      body: jsonEncode(body),
    ),
    path: path,
  );

  Future<dynamic> patch(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) => _send(
    () => _client.patch(
      _uri(path, query),
      headers: _headers(),
      body: jsonEncode(body),
    ),
    path: path,
  );

  Future<dynamic> postForm(
    String path, {
    required Map<String, String> fields,
    Map<String, String>? query,
    bool longTimeout = false,
  }) => _send(
    () => _client.post(
      _uri(path, query),
      headers: _headers(json: false),
      body: fields,
    ),
    longTimeout: longTimeout,
    path: path,
  );

  /// POST with extended timeout for slow backend work.
  Future<dynamic> postLong(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) => _send(
    () => _client.post(
      _uri(path, query),
      headers: _headers(),
      body: jsonEncode(body),
    ),
    longTimeout: true,
    path: path,
  );

  /// Multipart POST for image upload.
  Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    Map<String, String>? query,
    bool longTimeout = false,
  }) {
    return _send(
      () async {
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
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      },
      longTimeout: longTimeout,
      path: path,
    );
  }

  static const _timeout = Duration(seconds: 30);
  static const _longTimeout = Duration(seconds: 120);

  Future<dynamic> _send(
    Future<http.Response> Function() call, {
    bool longTimeout = false,
    required String path,
  }) async {
    var response = await call().timeout(longTimeout ? _longTimeout : _timeout);
    // Login and signup are bootstrap requests; refreshing on their 401s
    // would retry invalid credentials with the existing session.
    final isPublicAuth =
        path == '/auth/login' ||
        path == '/auth/signup';
    if (response.statusCode == 401 && !isPublicAuth) {
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
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body) as dynamic;
      } on FormatException {
        body = response.body;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    final detail = (body is Map && body['detail'] != null)
        ? body['detail'].toString()
        : 'Request failed (${response.statusCode})';
    throw ApiException(response.statusCode, detail);
  }
}
