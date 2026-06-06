/// Manages auth state via Firebase Auth and optional WebSocket connection.
/// Uses Firebase token exchange to get backend JWTs for WebSocket auth.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:arcbench_mobile/services/firebase_service.dart';
import 'package:arcbench_mobile/services/api_service.dart';
import 'package:arcbench_mobile/services/websocket_service.dart';
import 'package:arcbench_mobile/services/storage_service.dart';
import 'package:arcbench_mobile/config/constants.dart';

class ConnectionProvider extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();

  String _host = AppConstants.defaultHost;
  int _port = AppConstants.defaultPort;
  bool _isConnected = false;
  bool _isLoading = false;
  String? _error;
  String? _backendToken; // Backend JWT from Firebase token exchange

  WebSocketService? _wsService;
  ApiService? _apiServiceInstance;
  StreamSubscription<User?>? _authSub;

  ConnectionProvider() {
    _authSub = _firebase.authStateChanges.listen(_onAuthChanged);
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  String get host => _host;
  int get port => _port;
  String get username => _firebase.displayName ?? _firebase.email ?? '';
  String? get email => _firebase.email;
  String? get userId => _firebase.uid;
  bool get isAuthenticated => _firebase.isAuthenticated;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get error => _error;
  FirebaseService get firebaseService => _firebase;
  WebSocketService? get wsService => _wsService;

  // Backend JWT token (from Firebase exchange)
  String? get token => _backendToken;

  // Expose apiService for REST calls (sparks, devices, etc.)
  ApiService? get apiService => _apiServiceInstance;

  // ---------------------------------------------------------------------------
  // Auth state listener
  // ---------------------------------------------------------------------------

  void _onAuthChanged(User? user) {
    notifyListeners();
    if (user != null) {
      _firebase.updateLastLogin();
    }
  }

  // ---------------------------------------------------------------------------
  // Restore saved state on app start
  // ---------------------------------------------------------------------------

  Future<void> loadSaved() async {
    _isLoading = true;
    notifyListeners();

    try {
      _host = await StorageService.getHost() ?? AppConstants.defaultHost;
      _port = await StorageService.getPort();

      // Firebase Auth persists sessions automatically.
      // If user is already signed in, we're good.
      if (_firebase.isAuthenticated) {
        debugPrint('[Connection] Restored Firebase session for ${_firebase.email}');
        await _connectWebSocket();
      }
    } catch (e) {
      debugPrint('[Connection] loadSaved error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Login (Firebase Auth)
  // ---------------------------------------------------------------------------

  Future<bool> login(
    String email,
    String password, {
    String? host,
    int? port,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (host != null) {
        _host = host.trim();
        await StorageService.saveHost(_host);
      }
      if (port != null) {
        _port = port;
        await StorageService.savePort(_port);
      }

      await _firebase.signIn(
        email: email.trim(),
        password: password,
      );

      await _connectWebSocket();

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _firebaseAuthError(e.code);
      _isConnected = false;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = _friendlyError(e.toString());
      _isConnected = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Register (Firebase Auth)
  // ---------------------------------------------------------------------------

  Future<bool> register(
    String email,
    String password, {
    String? displayName,
    String? host,
    int? port,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (host != null) {
        _host = host.trim();
        await StorageService.saveHost(_host);
      }
      if (port != null) {
        _port = port;
        await StorageService.savePort(_port);
      }

      await _firebase.register(
        email: email.trim(),
        password: password,
        displayName: displayName,
      );

      await _connectWebSocket();

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _firebaseAuthError(e.code);
      _isConnected = false;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = _friendlyError(e.toString());
      _isConnected = false;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Password Reset
  // ---------------------------------------------------------------------------

  Future<bool> resetPassword(String email) async {
    try {
      await _firebase.resetPassword(email.trim());
      return true;
    } catch (e) {
      _error = _friendlyError(e.toString());
      notifyListeners();
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Logout
  // ---------------------------------------------------------------------------

  Future<void> logout() async {
    _wsService?.disconnect();
    _wsService = null;
    _apiServiceInstance = null;
    _backendToken = null;
    _isConnected = false;
    _error = null;

    await _firebase.signOut();
    await StorageService.clearAuth();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // WebSocket management — Firebase token exchange → backend JWT → WebSocket
  // ---------------------------------------------------------------------------

  Future<void> _connectWebSocket() async {
    // Only connect WebSocket if host is configured (not default localhost)
    if (_host == AppConstants.defaultHost || _host.isEmpty) {
      _isConnected = true;
      return;
    }

    _wsService?.disconnect();

    try {
      // Step 1: Get Firebase ID token
      final idToken = await _firebase.currentUser?.getIdToken();
      if (idToken == null) {
        debugPrint('[Connection] No Firebase ID token available');
        return;
      }

      // Step 2: Exchange Firebase ID token for backend JWT
      final api = ApiService(host: _host, port: _port);
      final result = await api.exchangeFirebaseToken(idToken);

      _backendToken = result['access_token'] as String?;
      final refreshToken = result['refresh_token'] as String?;

      if (_backendToken == null) {
        debugPrint('[Connection] Token exchange returned no access_token');
        return;
      }

      // Save tokens for refresh
      if (refreshToken != null) {
        await StorageService.saveRefreshToken(refreshToken);
      }

      // Set up ApiService with backend token for REST calls
      api.setAuthToken(_backendToken);
      _apiServiceInstance = api;

      debugPrint('[Connection] Firebase token exchanged for backend JWT');

      // Step 3: Connect WebSocket with backend JWT
      _wsService = WebSocketService();
      _wsService!.connect(
        host: _host,
        port: _port,
        token: _backendToken!,
      );

      _wsService?.onConnected = () {
        _isConnected = true;
        notifyListeners();
      };

      _wsService?.onDisconnected = () {
        _isConnected = false;
        notifyListeners();
      };

      _wsService?.onError = (message) {
        debugPrint('[Connection] WS error: $message');
      };
    } catch (e) {
      debugPrint('[Connection] Token exchange failed: $e');
      _error = 'Failed to connect to desktop server: $e';
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _firebaseAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed: $code';
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Connection refused')) {
      return 'Cannot reach server. Is ArcBench running on your desktop?';
    }
    if (raw.contains('timeout') || raw.contains('TimeoutException')) {
      return 'Connection timed out. Check your network.';
    }
    if (raw.contains('SocketException')) {
      return 'Network error. Check your internet connection.';
    }
    return raw.length > 120 ? '${raw.substring(0, 120)}...' : raw;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _wsService?.dispose();
    super.dispose();
  }
}
