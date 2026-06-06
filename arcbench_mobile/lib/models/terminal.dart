/// Terminal info model matching the v2 ArcBench backend.

class TerminalInfo {
  final String id;
  final String userId;
  final String workingDir;
  final String mode;
  final String command;
  final bool isAlive;
  final String createdAt;
  final String lastActive;

  const TerminalInfo({
    required this.id,
    required this.userId,
    this.workingDir = '',
    this.mode = 'claude',
    this.command = 'claude',
    this.isAlive = false,
    this.createdAt = '',
    this.lastActive = '',
  });

  factory TerminalInfo.fromJson(Map<String, dynamic> json) => TerminalInfo(
        id: json['id'] ?? json['terminal_id'] ?? '',
        userId: json['user_id'] ?? '',
        workingDir: json['working_dir'] ?? '',
        mode: json['mode'] ?? json['command'] ?? 'claude',
        command: json['command'] ?? json['mode'] ?? 'claude',
        isAlive: json['is_alive'] ?? false,
        createdAt: json['created_at'] ?? '',
        lastActive: json['last_active'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'working_dir': workingDir,
        'mode': mode,
        'command': command,
        'is_alive': isAlive,
        'created_at': createdAt,
        'last_active': lastActive,
      };

  bool get isClaude => mode == 'claude';
  bool get isShell => mode == 'shell';

  /// Short ID for display (first 8 chars).
  String get shortId => id.length > 8 ? id.substring(0, 8) : id;

  @override
  String toString() => 'TerminalInfo($shortId, mode=$mode, alive=$isAlive, dir=$workingDir)';
}
