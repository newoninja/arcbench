/// Terminal provider — manages terminal lifecycle, I/O, and WS routing.
/// Uses Firestore for terminal metadata, WebSocket for live I/O.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:arcbench_mobile/models/terminal.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';

// ---------------------------------------------------------------------------
// TerminalOutput — a single chunk of text in a terminal's scrollback.
// ---------------------------------------------------------------------------

class TerminalOutput {
  final String text;
  final DateTime time;
  final bool isInput;

  const TerminalOutput({
    required this.text,
    required this.time,
    this.isInput = false,
  });
}

// ---------------------------------------------------------------------------
// SessionProvider (terminal provider)
// ---------------------------------------------------------------------------

class SessionProvider extends ChangeNotifier {
  final ConnectionProvider _connection;

  List<TerminalInfo> _terminals = [];
  String? _activeTerminalId;
  final Map<String, List<TerminalOutput>> _outputs = {};
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _terminalsSub;

  SessionProvider({required ConnectionProvider connection})
      : _connection = connection {
    _setupWsCallbacks();
    _listenToTerminals();
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  List<TerminalInfo> get terminals => List.unmodifiable(_terminals);
  String? get activeTerminalId => _activeTerminalId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<TerminalOutput> outputsFor(String terminalId) =>
      List.unmodifiable(_outputs[terminalId] ?? const []);

  List<TerminalOutput> get activeOutputs =>
      _activeTerminalId != null ? outputsFor(_activeTerminalId!) : const [];

  TerminalInfo? get activeTerminal {
    if (_activeTerminalId == null) return null;
    try {
      return _terminals.firstWhere((t) => t.id == _activeTerminalId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Firestore real-time listener
  // ---------------------------------------------------------------------------

  void _listenToTerminals() {
    _terminalsSub?.cancel();
    final firebase = _connection.firebaseService;
    if (!firebase.isAuthenticated) return;

    _terminalsSub = firebase.terminalsStream().listen(
      (terminals) {
        _terminals = terminals;
        if (_activeTerminalId != null &&
            !_terminals.any((t) => t.id == _activeTerminalId)) {
          _activeTerminalId = _terminals.isNotEmpty ? _terminals.first.id : null;
        }
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[SessionProvider] terminalsStream error: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // WS callback wiring
  // ---------------------------------------------------------------------------

  void _setupWsCallbacks() {
    final ws = _connection.wsService;
    if (ws == null) return;

    ws.onOutput = _onOutput;
    ws.onTerminalCreated = _onTerminalCreated;
    ws.onTerminalDestroyed = _onTerminalDestroyed;
    ws.onTerminalList = _onTerminalList;
    ws.onModeSwitched = _onModeSwitched;
    ws.onCommandSent = _onCommandSent;
  }

  void rebindWebSocket() {
    _setupWsCallbacks();
    _listenToTerminals();
  }

  // ---------------------------------------------------------------------------
  // Load terminals (from Firestore)
  // ---------------------------------------------------------------------------

  Future<void> loadTerminals() async {
    final firebase = _connection.firebaseService;
    if (!firebase.isAuthenticated) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _terminals = await firebase.listTerminals();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Terminal actions
  // ---------------------------------------------------------------------------

  Future<void> createTerminal({String? command, String workingDir = '~'}) async {
    final firebase = _connection.firebaseService;
    if (!firebase.isAuthenticated) {
      _error = 'Not authenticated';
      notifyListeners();
      return;
    }

    try {
      final terminalId = await firebase.createTerminal(
        workingDir: workingDir,
        mode: command != null ? 'claude' : 'shell',
      );

      _outputs.putIfAbsent(terminalId, () => []);
      _activeTerminalId = terminalId;
      notifyListeners();

      // Also send via WebSocket if connected to desktop server
      final ws = _connection.wsService;
      if (ws != null && ws.isConnected) {
        ws.sendCreate(
          workingDir: workingDir,
          cols: 80,
          rows: 24,
          command: command,
        );
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void attachTerminal(String terminalId) {
    _activeTerminalId = terminalId;
    notifyListeners();

    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendAttach(terminalId);
    }
  }

  void detachTerminal(String terminalId) {
    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendDetach(terminalId);
    }

    if (_activeTerminalId == terminalId) {
      _activeTerminalId = null;
      notifyListeners();
    }
  }

  void sendInput(String terminalId, String text) {
    _appendOutput(terminalId, text, isInput: true);

    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendInput(terminalId, text);
    }

    // Update last active in Firestore
    _connection.firebaseService.updateTerminalActivity(terminalId);
  }

  Future<void> destroyTerminal(String terminalId) async {
    // Mark as dead in Firestore
    await _connection.firebaseService.deleteTerminal(terminalId);

    // Also destroy via WebSocket if connected
    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendDestroy(terminalId);
    }

    _terminals.removeWhere((t) => t.id == terminalId);
    if (_activeTerminalId == terminalId) {
      _activeTerminalId = _terminals.isNotEmpty ? _terminals.last.id : null;
    }
    notifyListeners();
  }

  void setActiveTerminal(String? terminalId) {
    _activeTerminalId = terminalId;
    notifyListeners();
  }

  void runCommand(String terminalId, String command) {
    final ws = _connection.wsService;
    if (ws == null || !ws.isConnected) return;
    ws.sendRunCommand(terminalId, command);
  }

  void switchMode(String terminalId, {required String mode}) {
    final ws = _connection.wsService;
    if (ws == null || !ws.isConnected) return;
    ws.sendSwitchMode(terminalId, mode: mode);
  }

  void clearOutput(String terminalId) {
    _outputs[terminalId]?.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Save session to Firestore
  // ---------------------------------------------------------------------------

  Future<void> saveCurrentSession({String? name}) async {
    if (_activeTerminalId == null) return;
    final outputs = _outputs[_activeTerminalId!];
    if (outputs == null || outputs.isEmpty) return;

    await _connection.firebaseService.saveSession(
      terminalId: _activeTerminalId!,
      name: name ?? 'Session ${DateTime.now().toIso8601String()}',
      output: outputs
          .map((o) => {
                'text': o.text,
                'time': o.time.toIso8601String(),
                'isInput': o.isInput,
              })
          .toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // WS callbacks
  // ---------------------------------------------------------------------------

  void _onOutput(String terminalId, Uint8List data) {
    final text = utf8.decode(data, allowMalformed: true);
    _appendOutput(terminalId, text);
    notifyListeners();
  }

  void _onTerminalCreated(String terminalId, Map<String, dynamic> details) {
    final exists = _terminals.any((t) => t.id == terminalId);
    if (!exists) {
      _terminals.add(TerminalInfo.fromJson({
        ...details,
        'id': terminalId,
        'is_alive': true,
      }));
    }
    _outputs.putIfAbsent(terminalId, () => []);
    _activeTerminalId = terminalId;
    notifyListeners();
  }

  void _onTerminalDestroyed(String terminalId) {
    _terminals.removeWhere((t) => t.id == terminalId);
    if (_activeTerminalId == terminalId) {
      _activeTerminalId = _terminals.isNotEmpty ? _terminals.last.id : null;
    }
    notifyListeners();
  }

  void _onModeSwitched(String oldTerminalId, String newTerminalId, Map<String, dynamic> details) {
    _terminals.removeWhere((t) => t.id == oldTerminalId);
    _terminals.add(TerminalInfo.fromJson({
      ...details,
      'id': newTerminalId,
      'is_alive': true,
    }));
    final oldOutput = _outputs.remove(oldTerminalId);
    if (oldOutput != null) {
      _outputs[newTerminalId] = oldOutput;
    }
    _outputs.putIfAbsent(newTerminalId, () => []);
    if (_activeTerminalId == oldTerminalId) {
      _activeTerminalId = newTerminalId;
    }
    notifyListeners();
  }

  void _onCommandSent(String terminalId, String command) {
    _appendOutput(terminalId, '> $command\n', isInput: true);
    notifyListeners();
  }

  void _onTerminalList(List<TerminalInfo> terminals) {
    _terminals = terminals;
    if (_activeTerminalId != null &&
        !_terminals.any((t) => t.id == _activeTerminalId)) {
      _activeTerminalId = _terminals.isNotEmpty ? _terminals.first.id : null;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _appendOutput(String terminalId, String text, {bool isInput = false}) {
    _outputs.putIfAbsent(terminalId, () => []);
    _outputs[terminalId]!.add(TerminalOutput(
      text: text,
      time: DateTime.now(),
      isInput: isInput,
    ));
  }

  @override
  void dispose() {
    _terminalsSub?.cancel();
    super.dispose();
  }
}
