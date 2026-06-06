import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class QueuedPrompt {
  final String terminalId;
  final String content;
  final DateTime queuedAt;

  QueuedPrompt({
    required this.terminalId,
    required this.content,
    DateTime? queuedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'terminal_id': terminalId,
        'content': content,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory QueuedPrompt.fromJson(Map<String, dynamic> json) => QueuedPrompt(
        terminalId: json['terminal_id'],
        content: json['content'],
        queuedAt: DateTime.parse(json['queued_at']),
      );
}

class OfflineQueue extends ChangeNotifier {
  static const _boxName = 'arcbench_offline_queue';
  Box<String>? _box;

  List<QueuedPrompt> _queue = [];

  List<QueuedPrompt> get queue => List.unmodifiable(_queue);
  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _loadFromBox();
  }

  void _loadFromBox() {
    if (_box == null) return;
    _queue = _box!.values
        .map((raw) => QueuedPrompt.fromJson(jsonDecode(raw)))
        .toList();
    notifyListeners();
  }

  Future<void> enqueue(QueuedPrompt prompt) async {
    _queue.add(prompt);
    await _box?.add(jsonEncode(prompt.toJson()));
    notifyListeners();
    debugPrint(
        '[OfflineQueue] Queued prompt for terminal ${prompt.terminalId}');
  }

  QueuedPrompt? dequeue() {
    if (_queue.isEmpty) return null;
    final prompt = _queue.removeAt(0);
    _persistAll();
    notifyListeners();
    return prompt;
  }

  List<QueuedPrompt> drainAll() {
    final all = List<QueuedPrompt>.from(_queue);
    _queue.clear();
    _box?.clear();
    notifyListeners();
    return all;
  }

  Future<void> _persistAll() async {
    await _box?.clear();
    for (final p in _queue) {
      await _box?.add(jsonEncode(p.toJson()));
    }
  }

  Future<void> clear() async {
    _queue.clear();
    await _box?.clear();
    notifyListeners();
  }
}
