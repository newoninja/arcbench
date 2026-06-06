import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import 'package:arcbench_mobile/models/spark_idea.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/services/offline_queue.dart';
import 'package:arcbench_mobile/services/websocket_service.dart';

class SparkProvider extends ChangeNotifier {
  static const _boxName = 'arcbench_sparks';
  Box<String>? _box;

  final ConnectionProvider _connection;
  final OfflineQueue _offlineQueue;

  List<SparkIdea> _ideas = [];
  List<SparkIdea> get ideas => List.unmodifiable(_ideas);

  // Live build output buffer per spark (for "Watch Build")
  final Map<String, List<Uint8List>> _sparkOutputBuffers = {};

  SparkProvider({
    required ConnectionProvider connection,
    required OfflineQueue offlineQueue,
  })  : _connection = connection,
        _offlineQueue = offlineQueue;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _loadFromBox();
    _wireWebSocketCallbacks();
  }

  void _loadFromBox() {
    if (_box == null) return;
    _ideas = _box!.values.map((raw) => SparkIdea.decode(raw)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // WebSocket callback wiring
  // ---------------------------------------------------------------------------

  void _wireWebSocketCallbacks() {
    final ws = _connection.wsService;
    if (ws == null) return;

    ws.onSparkDispatched = _onSparkDispatched;
    ws.onSparkStatus = _onSparkStatus;
    ws.onSparkList = _onSparkList;
  }

  /// Re-wire callbacks when WebSocket reconnects.
  void rewireCallbacks() {
    _wireWebSocketCallbacks();
  }

  void _onSparkDispatched(Map<String, dynamic> data) {
    final ideaId = data['idea_id'] as String? ?? '';
    if (ideaId.isEmpty) return;

    final idx = _ideas.indexWhere((i) => i.id == ideaId);
    if (idx != -1) {
      _ideas[idx] = _ideas[idx].copyWith(
        agentSlug: data['agent'] as String?,
        agentName: data['agent_name'] as String?,
        terminalId: data['terminal_id'] as String?,
        workingDir: data['working_dir'] as String?,
        status: SparkStatus.building,
        sentViaWs: true,
      );
      _box?.put(ideaId, _ideas[idx].encode());
      notifyListeners();
    }
  }

  void _onSparkStatus(Map<String, dynamic> data) {
    final ideaId = data['idea_id'] as String? ?? '';
    if (ideaId.isEmpty) return;

    final statusStr = data['status'] as String? ?? 'building';
    final idx = _ideas.indexWhere((i) => i.id == ideaId);
    if (idx == -1) return;

    _ideas[idx] = _ideas[idx].copyWith(
      status: _parseSparkStatus(statusStr),
      reviewSummary: data['review_summary'] as String? ?? _ideas[idx].reviewSummary,
      previewUrl: data['preview_url'] as String? ?? _ideas[idx].previewUrl,
      revisionCount: data['revision_count'] as int? ?? _ideas[idx].revisionCount,
    );
    _box?.put(ideaId, _ideas[idx].encode());
    notifyListeners();
  }

  void _onSparkList(List<Map<String, dynamic>> sparks) {
    // Merge server state with local state
    for (final s in sparks) {
      final id = s['id'] as String? ?? '';
      if (id.isEmpty) continue;

      final idx = _ideas.indexWhere((i) => i.id == id);
      if (idx != -1) {
        // Update existing
        _ideas[idx] = _ideas[idx].copyWith(
          status: _parseSparkStatus(s['status'] as String? ?? 'building'),
          agentSlug: s['agent_slug'] as String?,
          agentName: s['agent_name'] as String?,
          terminalId: s['terminal_id'] as String?,
          workingDir: s['working_dir'] as String?,
          reviewSummary: s['review_summary'] as String?,
          previewUrl: s['preview_url'] as String?,
          revisionCount: s['revision_count'] as int? ?? 0,
        );
        _box?.put(id, _ideas[idx].encode());
      } else {
        // New spark from server
        final idea = SparkIdea(
          id: id,
          content: s['content'] as String? ?? '',
          chipLabel: s['chip_label'] as String?,
          status: _parseSparkStatus(s['status'] as String? ?? 'building'),
          createdAt: DateTime.tryParse(s['created_at'] as String? ?? '') ?? DateTime.now(),
          sentViaWs: true,
          agentSlug: s['agent_slug'] as String?,
          agentName: s['agent_name'] as String?,
          terminalId: s['terminal_id'] as String?,
          workingDir: s['working_dir'] as String?,
          reviewSummary: s['review_summary'] as String?,
          previewUrl: s['preview_url'] as String?,
          revisionCount: s['revision_count'] as int? ?? 0,
        );
        _ideas.insert(0, idea);
        _box?.put(id, idea.encode());
      }
    }
    _ideas.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  SparkStatus _parseSparkStatus(String s) {
    switch (s) {
      case 'building': return SparkStatus.building;
      case 'reviewing': return SparkStatus.reviewing;
      case 'approved': return SparkStatus.approved;
      case 'failed': return SparkStatus.failed;
      case 'timeout': return SparkStatus.timeout;
      case 'needs_revision': return SparkStatus.needsRevision;
      case 'revising': return SparkStatus.revising;
      case 'review_failed': return SparkStatus.reviewFailed;
      case 'max_revisions_reached': return SparkStatus.maxRevisionsReached;
      case 'cancelled': return SparkStatus.cancelled;
      case 'pending_retry': return SparkStatus.pendingRetry;
      default: return SparkStatus.building;
    }
  }

  // ---------------------------------------------------------------------------
  // Submit / Delete / Update
  // ---------------------------------------------------------------------------

  Future<SparkIdea> submitIdea({
    required String content,
    String? chipLabel,
  }) async {
    final idea = SparkIdea(
      id: const Uuid().v4(),
      content: content,
      chipLabel: chipLabel,
    );

    _ideas.insert(0, idea);
    await _box?.put(idea.id, idea.encode());
    notifyListeners();

    _sendViaWs(idea);
    return idea;
  }

  void _sendViaWs(SparkIdea idea) {
    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendSparkIdea(idea.id, idea.content, chipLabel: idea.chipLabel);
      _markSent(idea.id);
    } else {
      _offlineQueue.enqueue(QueuedPrompt(
        terminalId: '__spark__${idea.id}',
        content: idea.content,
      ));
    }
  }

  void _markSent(String id) {
    final idx = _ideas.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    _ideas[idx] = _ideas[idx].copyWith(sentViaWs: true);
    _box?.put(id, _ideas[idx].encode());
    notifyListeners();
  }

  void updateStatus(String id, SparkStatus status) {
    final idx = _ideas.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    _ideas[idx] = _ideas[idx].copyWith(status: status);
    _box?.put(id, _ideas[idx].encode());
    notifyListeners();
  }

  Future<void> deleteIdea(String id) async {
    _ideas.removeWhere((i) => i.id == id);
    _sparkOutputBuffers.remove(id);
    await _box?.delete(id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Live Build Streaming (Phase 5)
  // ---------------------------------------------------------------------------

  /// Attach to a spark's build terminal to see live output.
  void attachToSpark(String sparkId) {
    final ws = _connection.wsService;
    if (ws == null || !ws.isConnected) return;

    _sparkOutputBuffers[sparkId] = [];
    ws.sendSparkAttach(sparkId);
  }

  /// Get the live output buffer for a spark.
  List<Uint8List> getSparkOutput(String sparkId) {
    return _sparkOutputBuffers[sparkId] ?? [];
  }

  // ---------------------------------------------------------------------------
  // Cancel / Retry (Phase 7)
  // ---------------------------------------------------------------------------

  void cancelSpark(String sparkId) {
    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendSparkCancel(sparkId);
    }
    updateStatus(sparkId, SparkStatus.cancelled);
  }

  void retrySpark(String sparkId) {
    final idx = _ideas.indexWhere((i) => i.id == sparkId);
    if (idx == -1) return;

    final idea = _ideas[idx];
    if (!idea.isTerminal) return;

    // Reset and re-submit
    _ideas[idx] = idea.copyWith(status: SparkStatus.building);
    _box?.put(sparkId, _ideas[idx].encode());
    notifyListeners();

    _sendViaWs(_ideas[idx]);
  }

  /// Request the server's current spark list.
  void requestSparkList() {
    final ws = _connection.wsService;
    if (ws != null && ws.isConnected) {
      ws.sendListSparks();
    }
  }
}
