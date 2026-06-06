/// App-wide constants for ArcBench v2.

class AppConstants {
  AppConstants._();

  static const String appName = 'ArcBench';
  static const String appVersion = '2.0.0';

  // Default server connection
  static const String defaultHost = 'localhost';
  static const int defaultPort = 8000;

  // WebSocket reconnect settings
  static const int wsReconnectBaseMs = 1000;
  static const int wsReconnectMaxMs = 30000;
  static const double wsReconnectMultiplier = 2.0;
  static const int maxReconnectAttempts = 15;

  // HTTP request timeout
  static const Duration httpTimeout = Duration(seconds: 15);

  // Terminal defaults
  static const int defaultTerminalCols = 80;
  static const int defaultTerminalRows = 24;
  static const String defaultWorkingDir = '~';
}
