/// REST API client for the ArcBench v2 backend.
/// Uses JWT Bearer token authentication.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:arcbench_mobile/config/constants.dart';
import 'package:arcbench_mobile/models/terminal.dart';

class ApiService {
  final String host;
  final int port;
  String? _authToken;

  ApiService({
    required this.host,
    required this.port,
    String? authToken,
  }) : _authToken = authToken;

  /// Update the stored JWT token (e.g. after login).
  void setAuthToken(String? token) {
    _authToken = token;
  }

  String get _baseUrl => 'http://$host:$port';

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // ----------------------------------------------------------------
  // Auth
  // ----------------------------------------------------------------

  /// Register a new user. Returns the response body (includes token).
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
  }) async {
    final resp = await http
        .post(
          _uri('/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Login with username/password. Returns body with access_token.
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final resp = await http
        .post(
          _uri('/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Refresh tokens — exchange a refresh token for a new access + refresh pair.
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final resp = await http
        .post(
          _uri('/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Revoke all refresh tokens for the current user (logout).
  Future<void> serverLogout() async {
    try {
      await http
          .post(_uri('/auth/logout'), headers: _headers)
          .timeout(AppConstants.httpTimeout);
    } catch (_) {}
  }

  /// Get the current authenticated user info.
  Future<Map<String, dynamic>> me() async {
    final resp = await http
        .get(_uri('/auth/me'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  // ----------------------------------------------------------------
  // Terminals
  // ----------------------------------------------------------------

  /// List all terminals for the authenticated user.
  Future<List<TerminalInfo>> listTerminals() async {
    final resp = await http
        .get(_uri('/terminals'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    final body = _handleResponse(resp);
    final list = body['terminals'] as List<dynamic>? ?? [];
    return list.map((j) => TerminalInfo.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Create a new terminal.
  Future<Map<String, dynamic>> createTerminal({
    required String workingDir,
    int cols = 80,
    int rows = 24,
    String? command,
  }) async {
    final payload = <String, dynamic>{
      'working_dir': workingDir,
      'cols': cols,
      'rows': rows,
    };
    if (command != null) payload['command'] = command;

    final resp = await http
        .post(_uri('/terminals'), headers: _headers, body: jsonEncode(payload))
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Delete (destroy) a terminal.
  Future<Map<String, dynamic>> deleteTerminal(String terminalId) async {
    final resp = await http
        .delete(_uri('/terminals/$terminalId'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  // ----------------------------------------------------------------
  // File Browser
  // ----------------------------------------------------------------

  /// List contents of a directory on the host machine.
  Future<Map<String, dynamic>> browseDirectory({String path = '~'}) async {
    final uri = Uri.parse('$_baseUrl/browse').replace(
      queryParameters: {'path': path},
    );
    final resp = await http
        .get(uri, headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Get bookmark directories (Home, Desktop, Documents, etc.).
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final resp = await http
        .get(_uri('/browse/bookmarks'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    final body = _handleResponse(resp);
    final list = body['bookmarks'] as List<dynamic>? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ----------------------------------------------------------------
  // Status / Health
  // ----------------------------------------------------------------

  /// Get server status.
  Future<Map<String, dynamic>> getStatus() async {
    final resp = await http
        .get(_uri('/status'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Health check (no auth required).
  Future<Map<String, dynamic>> getHealth() async {
    final resp = await http
        .get(_uri('/health'), headers: {'Content-Type': 'application/json'})
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  // ----------------------------------------------------------------
  // Firebase Token Exchange
  // ----------------------------------------------------------------

  /// Exchange a Firebase ID token for backend JWT access + refresh tokens.
  Future<Map<String, dynamic>> exchangeFirebaseToken(String idToken) async {
    final resp = await http
        .post(
          _uri('/auth/firebase-exchange'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id_token': idToken}),
        )
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  // ----------------------------------------------------------------
  // Sparks
  // ----------------------------------------------------------------

  /// List all sparks for the authenticated user.
  Future<List<Map<String, dynamic>>> listSparks() async {
    final resp = await http
        .get(_uri('/sparks'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    final body = _handleResponse(resp);
    // Response is a list directly
    if (resp.body.startsWith('[')) {
      return (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Retry a failed spark.
  Future<Map<String, dynamic>> retrySpark(String sparkId) async {
    final resp = await http
        .post(_uri('/sparks/$sparkId/retry'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  /// Cancel a running spark.
  Future<Map<String, dynamic>> cancelSpark(String sparkId) async {
    final resp = await http
        .post(_uri('/sparks/$sparkId/cancel'), headers: _headers)
        .timeout(AppConstants.httpTimeout);
    return _handleResponse(resp);
  }

  // ----------------------------------------------------------------
  // Device Tokens
  // ----------------------------------------------------------------

  /// Register a device token for push notifications.
  Future<void> registerDeviceToken(String token, {String platform = 'fcm'}) async {
    await http
        .post(
          _uri('/devices/register'),
          headers: _headers,
          body: jsonEncode({'token': token, 'platform': platform}),
        )
        .timeout(AppConstants.httpTimeout);
  }

  // ----------------------------------------------------------------
  // Internal
  // ----------------------------------------------------------------

  Map<String, dynamic> _handleResponse(http.Response resp) {
    final body = resp.body.isNotEmpty
        ? jsonDecode(resp.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return body;
    }

    throw ApiException(
      statusCode: resp.statusCode,
      message: body['detail'] as String? ??
          body['message'] as String? ??
          resp.body,
    );
  }
}

/// Exception thrown when an API call returns a non-2xx status.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
