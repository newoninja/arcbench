/// WebSocket client for the ArcBench v2 multiplexed terminal protocol.
/// Connects to ws://host:port/ws?token=JWT and routes messages by terminal_id.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:arcbench_mobile/config/constants.dart';
import 'package:arcbench_mobile/models/terminal.dart';

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

// ---------------------------------------------------------------------------
// Callback signatures
// ---------------------------------------------------------------------------

typedef OnOutput = void Function(String terminalId, Uint8List data);
typedef OnTerminalCreated = void Function(String terminalId, Map<String, dynamic> details);
typedef OnTerminalDestroyed = void Function(String terminalId);
typedef OnTerminalList = void Function(List<TerminalInfo> terminals);
typedef OnModeSwitched = void Function(String oldTerminalId, String newTerminalId, Map<String, dynamic> details);
typedef OnCommandSent = void Function(String terminalId, String command);
typedef OnWsError = void Function(String message);
typedef OnWsConnected = void Function();
typedef OnWsDisconnected = void Function();

// Spark callbacks
typedef OnSparkDispatched = void Function(Map<String, dynamic> data);
typedef OnSparkStatus = void Function(Map<String, dynamic> data);
typedef OnSparkList = void Function(List<Map<String, dynamic>> sparks);

// ---------------------------------------------------------------------------
// WebSocketService
// ---------------------------------------------------------------------------

class WebSocketService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  String _host = '';
  int _port = 0;
  String _token = '';
  WsConnectionState _state = WsConnectionState.disconnected;
  int _reconnectAttempts = 0;

  // ---- Callbacks ----
  OnOutput? onOutput;
  OnTerminalCreated? onTerminalCreated;
  OnTerminalDestroyed? onTerminalDestroyed;
  OnTerminalList? onTerminalList;
  OnModeSwitched? onModeSwitched;
  OnCommandSent? onCommandSent;
  OnWsError? onError;
  OnWsConnected? onConnected;
  OnWsDisconnected? onDisconnected;

  // Spark callbacks
  OnSparkDispatched? onSparkDispatched;
  OnSparkStatus? onSparkStatus;
  OnSparkList? onSparkList;

  // ---- Getters ----
  WsConnectionState get state => _state;
  bool get isConnected => _state == WsConnectionState.connected;

  // ------------------------------------------------------------------
  // Connect / Disconnect
  // ------------------------------------------------------------------

  /// Open a WebSocket connection to the ArcBench v2 backend.
  void connect({
    required String host,
    required int port,
    required String token,
  }) {
    _host = host;
    _port = port;
    _token = token;
    _reconnectAttempts = 0;
    _doConnect();
  }

  void _doConnect() {
    _cleanup();
    _state = WsConnectionState.connecting;
    notifyListeners();

    final wsUrl = 'ws://$_host:$_port/ws?token=$_token';

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );
      _state = WsConnectionState.connected;
      _reconnectAttempts = 0;
      notifyListeners();
      onConnected?.call();
      debugPrint('[WS] Connected to $wsUrl');
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Gracefully disconnect. No auto-reconnect.
  void disconnect() {
    _reconnectTimer?.cancel();
    _cleanup();
    _state = WsConnectionState.disconnected;
    notifyListeners();
    onDisconnected?.call();
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  // ------------------------------------------------------------------
  // Reconnect logic (exponential backoff)
  // ------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      _state = WsConnectionState.disconnected;
      notifyListeners();
      onError?.call('Max reconnect attempts reached');
      onDisconnected?.call();
      return;
    }

    _state = WsConnectionState.reconnecting;
    notifyListeners();

    final delayMs = min(
      (AppConstants.wsReconnectBaseMs *
              pow(AppConstants.wsReconnectMultiplier, _reconnectAttempts))
          .toInt(),
      AppConstants.wsReconnectMaxMs,
    );

    debugPrint(
        '[WS] Reconnecting in ${delayMs}ms (attempt ${_reconnectAttempts + 1})');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectAttempts++;
      _doConnect();
    });
  }

  void _onWsError(dynamic error) {
    debugPrint('[WS] Error: $error');
    onDisconnected?.call();
    _scheduleReconnect();
  }

  void _onWsDone() {
    debugPrint('[WS] Connection closed');
    onDisconnected?.call();
    _scheduleReconnect();
  }

  // ------------------------------------------------------------------
  // Receive messages
  // ------------------------------------------------------------------

  void _onMessage(dynamic raw) {
    final rawStr = raw as String;

    // Server sends plain "ping" text frames for heartbeat — reply "pong".
    if (rawStr == 'ping') {
      _channel?.sink.add('pong');
      return;
    }

    try {
      final msg = jsonDecode(rawStr) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';

      switch (type) {
        case 'output':
          _handleOutput(msg);
          break;
        case 'created':
          onTerminalCreated?.call(
            msg['terminal_id'] as String? ?? '',
            msg,
          );
          break;
        case 'attached':
          // Terminal successfully attached — treat same as created for UI.
          onTerminalCreated?.call(
            msg['terminal_id'] as String? ?? '',
            msg,
          );
          break;
        case 'session_start':
          // Server confirms the WS session. Mark connected, fire callback.
          _state = WsConnectionState.connected;
          _reconnectAttempts = 0;
          notifyListeners();
          onConnected?.call();
          debugPrint('[WS] Session started (user: ${msg['user_id']})');
          break;
        case 'attached_all':
          // Server re-attached all previous terminals on reconnect.
          debugPrint('[WS] Re-attached ${msg['terminal_ids']} terminals');
          break;
        case 'connection_status':
          debugPrint('[WS] Connection status: ${msg['message']}');
          break;
        case 'terminated':
        case 'destroyed':
          onTerminalDestroyed?.call(
            msg['terminal_id'] as String? ?? '',
          );
          break;
        case 'terminal_list':
          _handleTerminalList(msg);
          break;
        case 'switched':
          onModeSwitched?.call(
            msg['old_terminal_id'] as String? ?? '',
            msg['new_terminal_id'] as String? ?? '',
            msg,
          );
          break;
        case 'command_sent':
          onCommandSent?.call(
            msg['terminal_id'] as String? ?? '',
            msg['command'] as String? ?? '',
          );
          break;
        case 'spark_dispatched':
          onSparkDispatched?.call(msg);
          break;
        case 'spark_status':
          onSparkStatus?.call(msg);
          break;
        case 'spark_list':
          final list = msg['sparks'] as List<dynamic>? ?? [];
          onSparkList?.call(list.cast<Map<String, dynamic>>());
          break;
        case 'spark_attached':
          // Treat like a regular terminal attach for output routing
          onTerminalCreated?.call(
            msg['terminal_id'] as String? ?? '',
            msg,
          );
          break;
        case 'error':
          onError?.call(msg['message'] as String? ?? 'Unknown error');
          break;
        default:
          debugPrint('[WS] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[WS] Parse error: $e');
    }
  }

  void _handleOutput(Map<String, dynamic> msg) {
    final terminalId = msg['terminal_id'] as String? ?? '';
    final dataStr = msg['data'] as String? ?? '';
    if (dataStr.isEmpty) return;

    // Backend sends base64-encoded terminal output.
    final bytes = base64Decode(dataStr);
    onOutput?.call(terminalId, Uint8List.fromList(bytes));
  }

  void _handleTerminalList(Map<String, dynamic> msg) {
    final list = msg['terminals'] as List<dynamic>? ?? [];
    final terminals = list
        .map((j) => TerminalInfo.fromJson(j as Map<String, dynamic>))
        .toList();
    onTerminalList?.call(terminals);
  }

  // ------------------------------------------------------------------
  // Send messages
  // ------------------------------------------------------------------

  /// Create a new terminal via the WebSocket.
  void sendCreate({
    required String workingDir,
    int cols = 80,
    int rows = 24,
    String? command,
  }) {
    _send({
      'type': 'create',
      'working_dir': workingDir,
      'cols': cols,
      'rows': rows,
      if (command != null) 'command': command,
    });
  }

  /// Attach to an existing terminal.
  void sendAttach(String terminalId) {
    _send({'type': 'attach', 'terminal_id': terminalId});
  }

  /// Detach from a terminal (stop receiving output).
  void sendDetach(String terminalId) {
    _send({'type': 'detach', 'terminal_id': terminalId});
  }

  /// Send terminal input (keystrokes).
  void sendInput(String terminalId, String data) {
    _send({
      'type': 'input',
      'terminal_id': terminalId,
      'data': base64Encode(utf8.encode(data)),
    });
  }

  /// Send raw bytes as terminal input.
  void sendInputBytes(String terminalId, Uint8List data) {
    _send({
      'type': 'input',
      'terminal_id': terminalId,
      'data': base64Encode(data),
    });
  }

  /// Resize a terminal.
  void sendResize(String terminalId, {required int cols, required int rows}) {
    _send({
      'type': 'resize',
      'terminal_id': terminalId,
      'cols': cols,
      'rows': rows,
    });
  }

  /// Destroy a terminal.
  void sendDestroy(String terminalId) {
    _send({'type': 'destroy', 'terminal_id': terminalId});
  }

  /// Request the list of terminals.
  void sendList() {
    _send({'type': 'list'});
  }

  /// Run a command in an existing terminal.
  void sendRunCommand(String terminalId, String command) {
    _send({
      'type': 'run_command',
      'terminal_id': terminalId,
      'command': command,
    });
  }

  /// Switch terminal mode (claude <-> shell).
  void sendSwitchMode(String terminalId, {required String mode, String? shellPath}) {
    _send({
      'type': 'switch_mode',
      'terminal_id': terminalId,
      'mode': mode,
      if (shellPath != null) 'shell_path': shellPath,
    });
  }

  /// Send a spark idea to the backend.
  void sendSparkIdea(String ideaId, String content, {String? chipLabel}) {
    _send({
      'type': 'spark_idea',
      'idea_id': ideaId,
      'content': content,
      if (chipLabel != null) 'chip_label': chipLabel,
    });
  }

  /// Request the list of sparks from the backend.
  void sendListSparks() {
    _send({'type': 'list_sparks'});
  }

  /// Attach to a spark's build terminal to watch live output.
  void sendSparkAttach(String sparkId) {
    _send({'type': 'spark_attach', 'spark_id': sparkId});
  }

  /// Cancel a running spark.
  void sendSparkCancel(String sparkId) {
    _send({'type': 'spark_cancel', 'spark_id': sparkId});
  }

  void _send(Map<String, dynamic> data) {
    if (_channel == null) {
      debugPrint('[WS] Cannot send - not connected');
      onError?.call('Not connected to server');
      return;
    }
    _channel!.sink.add(jsonEncode(data));
  }

  // ------------------------------------------------------------------
  // Dispose
  // ------------------------------------------------------------------

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
