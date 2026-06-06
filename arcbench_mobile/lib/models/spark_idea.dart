import 'dart:convert';

enum SparkStatus {
  building,
  reviewing,
  approved,
  failed,
  timeout,
  needsRevision,
  revising,
  reviewFailed,
  maxRevisionsReached,
  cancelled,
  pendingRetry,
}

SparkStatus _parseStatus(String name) {
  // Handle snake_case from backend
  switch (name) {
    case 'building':
      return SparkStatus.building;
    case 'reviewing':
      return SparkStatus.reviewing;
    case 'approved':
      return SparkStatus.approved;
    case 'failed':
      return SparkStatus.failed;
    case 'timeout':
      return SparkStatus.timeout;
    case 'needs_revision':
    case 'needsRevision':
      return SparkStatus.needsRevision;
    case 'revising':
      return SparkStatus.revising;
    case 'review_failed':
    case 'reviewFailed':
      return SparkStatus.reviewFailed;
    case 'max_revisions_reached':
    case 'maxRevisionsReached':
      return SparkStatus.maxRevisionsReached;
    case 'cancelled':
      return SparkStatus.cancelled;
    case 'pending_retry':
    case 'pendingRetry':
      return SparkStatus.pendingRetry;
    default:
      return SparkStatus.building;
  }
}

String _statusToString(SparkStatus status) {
  switch (status) {
    case SparkStatus.building:
      return 'building';
    case SparkStatus.reviewing:
      return 'reviewing';
    case SparkStatus.approved:
      return 'approved';
    case SparkStatus.failed:
      return 'failed';
    case SparkStatus.timeout:
      return 'timeout';
    case SparkStatus.needsRevision:
      return 'needs_revision';
    case SparkStatus.revising:
      return 'revising';
    case SparkStatus.reviewFailed:
      return 'review_failed';
    case SparkStatus.maxRevisionsReached:
      return 'max_revisions_reached';
    case SparkStatus.cancelled:
      return 'cancelled';
    case SparkStatus.pendingRetry:
      return 'pending_retry';
  }
}

class SparkIdea {
  final String id;
  final String content;
  final String? chipLabel;
  final SparkStatus status;
  final DateTime createdAt;
  final bool sentViaWs;

  // Agent & terminal info (filled in by spark_dispatched)
  final String? agentSlug;
  final String? agentName;
  final String? terminalId;
  final String? workingDir;

  // Review info
  final String? reviewSummary;
  final String? previewUrl;
  final int revisionCount;

  SparkIdea({
    required this.id,
    required this.content,
    this.chipLabel,
    this.status = SparkStatus.building,
    DateTime? createdAt,
    this.sentViaWs = false,
    this.agentSlug,
    this.agentName,
    this.terminalId,
    this.workingDir,
    this.reviewSummary,
    this.previewUrl,
    this.revisionCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  SparkIdea copyWith({
    SparkStatus? status,
    bool? sentViaWs,
    String? agentSlug,
    String? agentName,
    String? terminalId,
    String? workingDir,
    String? reviewSummary,
    String? previewUrl,
    int? revisionCount,
  }) =>
      SparkIdea(
        id: id,
        content: content,
        chipLabel: chipLabel,
        status: status ?? this.status,
        createdAt: createdAt,
        sentViaWs: sentViaWs ?? this.sentViaWs,
        agentSlug: agentSlug ?? this.agentSlug,
        agentName: agentName ?? this.agentName,
        terminalId: terminalId ?? this.terminalId,
        workingDir: workingDir ?? this.workingDir,
        reviewSummary: reviewSummary ?? this.reviewSummary,
        previewUrl: previewUrl ?? this.previewUrl,
        revisionCount: revisionCount ?? this.revisionCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'chip_label': chipLabel,
        'status': _statusToString(status),
        'created_at': createdAt.toIso8601String(),
        'sent_via_ws': sentViaWs,
        'agent_slug': agentSlug,
        'agent_name': agentName,
        'terminal_id': terminalId,
        'working_dir': workingDir,
        'review_summary': reviewSummary,
        'preview_url': previewUrl,
        'revision_count': revisionCount,
      };

  factory SparkIdea.fromJson(Map<String, dynamic> json) => SparkIdea(
        id: json['id'] as String,
        content: json['content'] as String,
        chipLabel: json['chip_label'] as String?,
        status: _parseStatus(json['status'] as String? ?? 'building'),
        createdAt: DateTime.parse(json['created_at'] as String),
        sentViaWs: json['sent_via_ws'] as bool? ?? false,
        agentSlug: json['agent_slug'] as String?,
        agentName: json['agent_name'] as String?,
        terminalId: json['terminal_id'] as String?,
        workingDir: json['working_dir'] as String?,
        reviewSummary: json['review_summary'] as String?,
        previewUrl: json['preview_url'] as String?,
        revisionCount: json['revision_count'] as int? ?? 0,
      );

  String encode() => jsonEncode(toJson());
  static SparkIdea decode(String raw) =>
      SparkIdea.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Whether this spark is in an active (in-progress) state.
  bool get isActive =>
      status == SparkStatus.building ||
      status == SparkStatus.reviewing ||
      status == SparkStatus.revising;

  /// Whether this spark is in a terminal (final) state.
  bool get isTerminal =>
      status == SparkStatus.approved ||
      status == SparkStatus.failed ||
      status == SparkStatus.timeout ||
      status == SparkStatus.maxRevisionsReached ||
      status == SparkStatus.cancelled;
}
