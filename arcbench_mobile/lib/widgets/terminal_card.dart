import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/models/terminal.dart';

class TerminalCard extends StatelessWidget {
  final TerminalInfo terminal;
  final String? lastOutput;
  final bool isActive;
  final VoidCallback onTap;

  const TerminalCard({
    super.key,
    required this.terminal,
    this.lastOutput,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = terminal.workingDir.isNotEmpty
        ? _shortenPath(terminal.workingDir)
        : 'Terminal ${terminal.shortId}';

    return Semantics(
      button: true,
      label: '$displayName, ${terminal.isClaude ? "Claude Code" : "Shell"}, '
          '${terminal.isAlive ? "running" : "stopped"}',
      hint: 'Double tap to open terminal',
      child: Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isActive
            ? BorderSide(color: ArcBenchTheme.arcBlue.withAlpha(80), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Type icon — Hero for smooth transition to ChatScreen
              Hero(
                tag: 'terminal-icon-${terminal.id}',
                child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (terminal.isClaude
                          ? ArcBenchTheme.arcBlue
                          : ArcBenchTheme.textMuted)
                      .withAlpha(20),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  terminal.isClaude
                      ? Icons.smart_toy_outlined
                      : Icons.terminal_rounded,
                  color: terminal.isClaude
                      ? ArcBenchTheme.arcBlue
                      : ArcBenchTheme.textSecondary,
                  size: 22,
                ),
              ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      terminal.workingDir.isNotEmpty
                          ? _shortenPath(terminal.workingDir)
                          : 'Terminal ${terminal.shortId}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _AnimatedStatusDot(alive: terminal.isAlive),
                        const SizedBox(width: 6),
                        Text(
                          terminal.isAlive ? 'Running' : 'Stopped',
                          style: TextStyle(
                            color: terminal.isAlive
                                ? ArcBenchTheme.success
                                : ArcBenchTheme.error,
                            fontSize: 12,
                          ),
                        ),
                        if (terminal.command.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: ArcBenchTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              terminal.command,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: ArcBenchTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                        if (terminal.createdAt.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(
                            _relativeTime(terminal.createdAt),
                            style: const TextStyle(
                                color: ArcBenchTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                    if (lastOutput != null && lastOutput!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _cleanPreview(lastOutput!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: ArcBenchTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              ExcludeSemantics(
                child: Icon(Icons.chevron_right_rounded,
                    color: ArcBenchTheme.textMuted, size: 22),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  String _shortenPath(String path) {
    if (path.length <= 30) return path;
    final parts = path.split('/');
    if (parts.length > 2) {
      return '.../${parts[parts.length - 2]}/${parts.last}';
    }
    return path;
  }

  String _relativeTime(String iso) {
    try {
      final d = DateTime.parse(iso);
      final diff = DateTime.now().difference(d);
      if (diff.inSeconds < 60) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${(diff.inDays / 7).floor()}w ago';
    } catch (_) {
      return '';
    }
  }

  String _cleanPreview(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\].*?\x07'), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
  }
}

class _AnimatedStatusDot extends StatefulWidget {
  final bool alive;
  const _AnimatedStatusDot({required this.alive});

  @override
  State<_AnimatedStatusDot> createState() => _AnimatedStatusDotState();
}

class _AnimatedStatusDotState extends State<_AnimatedStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    if (widget.alive) _ctl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedStatusDot old) {
    super.didUpdateWidget(old);
    if (widget.alive && !_ctl.isAnimating) {
      _ctl.repeat(reverse: true);
    } else if (!widget.alive && _ctl.isAnimating) {
      _ctl.stop();
      _ctl.reset();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        final opacity = widget.alive ? (0.5 + 0.5 * _ctl.value) : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                (widget.alive ? ArcBenchTheme.success : ArcBenchTheme.error)
                    .withAlpha((255 * opacity).round()),
            boxShadow: widget.alive
                ? [
                    BoxShadow(
                      color: ArcBenchTheme.success
                          .withAlpha((60 * _ctl.value).round()),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}
