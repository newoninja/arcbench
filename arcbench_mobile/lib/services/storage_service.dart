/// Secure storage for auth credentials and connection settings.
/// Uses flutter_secure_storage for all sensitive data.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // --- Storage keys ---
  static const _keyAuthToken = 'arcbench_auth_token';
  static const _keyRefreshToken = 'arcbench_refresh_token';
  static const _keyUsername = 'arcbench_username';
  static const _keyHost = 'arcbench_host';
  static const _keyPort = 'arcbench_port';

  // ----- Auth Token (JWT) -----

  static Future<void> saveAuthToken(String token) async {
    await _secureStorage.write(key: _keyAuthToken, value: token);
  }

  static Future<String?> getAuthToken() async {
    return _secureStorage.read(key: _keyAuthToken);
  }

  static Future<void> deleteAuthToken() async {
    await _secureStorage.delete(key: _keyAuthToken);
  }

  // ----- Refresh Token -----

  static Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _keyRefreshToken, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _keyRefreshToken);
  }

  static Future<void> deleteRefreshToken() async {
    await _secureStorage.delete(key: _keyRefreshToken);
  }

  // ----- Username -----

  static Future<void> saveUsername(String username) async {
    await _secureStorage.write(key: _keyUsername, value: username);
  }

  static Future<String?> getUsername() async {
    return _secureStorage.read(key: _keyUsername);
  }

  // ----- Host -----

  static Future<void> saveHost(String host) async {
    await _secureStorage.write(key: _keyHost, value: host);
  }

  static Future<String?> getHost() async {
    return _secureStorage.read(key: _keyHost);
  }

  // ----- Port -----

  static Future<void> savePort(int port) async {
    await _secureStorage.write(key: _keyPort, value: port.toString());
  }

  static Future<int> getPort() async {
    final value = await _secureStorage.read(key: _keyPort);
    return value != null ? int.tryParse(value) ?? 8000 : 8000;
  }

  // ----- Helpers -----

  /// Whether the user has a stored auth token.
  static Future<bool> isAuthenticated() async {
    final token = await getAuthToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear all stored data (logout).
  static Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }

  /// Clear only auth data, keep host/port.
  static Future<void> clearAuth() async {
    await _secureStorage.delete(key: _keyAuthToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyUsername);
  }
}
