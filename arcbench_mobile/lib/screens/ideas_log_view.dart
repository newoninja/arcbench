import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/models/spark_idea.dart';
import 'package:arcbench_mobile/providers/spark_provider.dart';
import 'package:arcbench_mobile/widgets/terminal_output.dart';

const _sparkCyan = Color(0xFF00D4FF);

class IdeasLogView extends StatelessWidget {
  const IdeasLogView({super.key});

  @override
  Widget build(BuildContext context) {
    final spark = context.watch<SparkProvider>();
    final ideas = spark.ideas;

    if (ideas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined,
                size: 56, color: ArcBenchTheme.textMuted.withAlpha(80)),
            const SizedBox(height: 16),
            Text(
              'No sparks yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ArcBenchTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your ideas will appear here',
              style: TextStyle(
                fontSize: 14,
                color: ArcBenchTheme.textMuted.withAlpha(150),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: ideas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _IdeaCard(idea: ideas[i]),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  final SparkIdea idea;
  const _IdeaCard({required this.idea});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(idea.id),
      direction: idea.isActive
          ? DismissDirection.endToStart // Swipe left to cancel active sparks
          : DismissDirection.endToStart, // Swipe left to delete terminal sparks
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: idea.isActive
              ? ArcBenchTheme.warning.withAlpha(30)
              : ArcBenchTheme.error.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          idea.isActive ? Icons.cancel_outlined : Icons.delete_outline_rounded,
          color: idea.isActive ? ArcBenchTheme.warning : ArcBenchTheme.error,
        ),
      ),
      confirmDismiss: (direction) async {
        if (idea.isActive) {
          // Cancel the spark
          HapticFeedback.mediumImpact();
          context.read<SparkProvider>().cancelSpark(idea.id);
          return false; // Don't remove from list — status update will handle UI
        }
        return true; // Allow delete
      },
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        context.read<SparkProvider>().deleteIdea(idea.id);
      },
      child: GestureDetector(
        onTap: () => _showDetail(context),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ArcBenchTheme.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: chip label + status badge
              Row(
                children: [
                  if (idea.chipLabel != null) ...[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _sparkCyan.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _sparkCyan.withAlpha(50)),
                      ),
                      child: Text(
                        idea.chipLabel!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _sparkCyan,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (idea.agentName != null) ...[
                    Text(
                      idea.agentName!,
                      style: TextStyle(
                        fontSize: 11,
                        color: ArcBenchTheme.textMuted.withAlpha(150),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  _StatusBadge(status: idea.status, revisionCount: idea.revisionCount),
                ],
              ),
              const SizedBox(height: 12),

              // Content
              Text(
                idea.content,
                style: const TextStyle(
                  fontSize: 15,
                  color: ArcBenchTheme.textPrimary,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // Review summary (if available)
              if (idea.reviewSummary != null && idea.reviewSummary!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withAlpha(10)),
                  ),
                  child: Text(
                    idea.reviewSummary!,
                    style: TextStyle(
                      fontSize: 12,
                      color: ArcBenchTheme.textMuted.withAlpha(180),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Bottom row: actions + timestamp
              Row(
                children: [
                  // Watch Build button (for active sparks)
                  if (idea.isActive && idea.terminalId != null)
                    _ActionButton(
                      icon: Icons.play_circle_outline_rounded,
                      label: 'Watch Build',
                      color: _sparkCyan,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.read<SparkProvider>().attachToSpark(idea.id);
                        _showBuildOutput(context, idea);
                      },
                    ),

                  // Preview URL (for completed sparks)
                  if (idea.previewUrl != null) ...[
                    _ActionButton(
                      icon: Icons.open_in_new_rounded,
                      label: 'Preview',
                      color: const Color(0xFF69F0AE),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        // Copy URL to clipboard
                        Clipboard.setData(ClipboardData(text: idea.previewUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Preview URL copied: ${idea.previewUrl}'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                  ],

                  // Retry button (for failed sparks)
                  if (idea.isTerminal &&
                      idea.status != SparkStatus.approved &&
                      idea.status != SparkStatus.cancelled)
                    _ActionButton(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      color: const Color(0xFFFFAB40),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        context.read<SparkProvider>().retrySpark(idea.id);
                      },
                    ),

                  const Spacer(),

                  Icon(Icons.access_time_rounded,
                      size: 13, color: ArcBenchTheme.textMuted.withAlpha(120)),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(idea.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: ArcBenchTheme.textMuted.withAlpha(150),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (idea.sentViaWs)
                    Icon(Icons.check_circle_outline_rounded,
                        size: 14, color: ArcBenchTheme.success.withAlpha(180))
                  else
                    Icon(Icons.cloud_queue_rounded,
                        size: 14, color: ArcBenchTheme.warning.withAlpha(150)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ArcBenchTheme.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusBadge(status: idea.status, revisionCount: idea.revisionCount),
                const Spacer(),
                if (idea.agentName != null)
                  Text(idea.agentName!, style: TextStyle(color: ArcBenchTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 16),
            Text(idea.content, style: const TextStyle(fontSize: 16, color: ArcBenchTheme.textPrimary)),
            if (idea.reviewSummary != null) ...[
              const SizedBox(height: 16),
              const Text('Review Summary', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ArcBenchTheme.textMuted)),
              const SizedBox(height: 6),
              Text(idea.reviewSummary!, style: TextStyle(fontSize: 14, color: ArcBenchTheme.textPrimary.withAlpha(200))),
            ],
            if (idea.previewUrl != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.link_rounded, size: 16, color: _sparkCyan),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(idea.previewUrl!, style: const TextStyle(fontSize: 13, color: _sparkCyan)),
                  ),
                ],
              ),
            ],
            if (idea.workingDir != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 16, color: ArcBenchTheme.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(idea.workingDir!, style: TextStyle(fontSize: 12, color: ArcBenchTheme.textMuted.withAlpha(150))),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showBuildOutput(BuildContext context, SparkIdea idea) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ArcBenchTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.terminal_rounded, color: _sparkCyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Live Build: ${idea.agentName ?? idea.id}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ArcBenchTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _StatusBadge(status: idea.status, revisionCount: idea.revisionCount),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            Expanded(
              child: Container(
                color: ArcBenchTheme.surface,
                padding: const EdgeInsets.all(8),
                child: const Center(
                  child: Text(
                    'Terminal output streaming...',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 13,
                      color: ArcBenchTheme.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatefulWidget {
  final SparkStatus status;
  final int revisionCount;
  const _StatusBadge({required this.status, this.revisionCount = 0});

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    if (_shouldPulse) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
    }
  }

  bool get _shouldPulse =>
      widget.status == SparkStatus.building ||
      widget.status == SparkStatus.revising ||
      widget.status == SparkStatus.reviewing;

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (widget.status) {
      SparkStatus.building => ('Building', _sparkCyan, Icons.build_rounded),
      SparkStatus.reviewing => (
          'Grok Reviewing',
          const Color(0xFFFFAB40),
          Icons.visibility_rounded
        ),
      SparkStatus.approved => (
          'Approved',
          const Color(0xFF69F0AE),
          Icons.check_circle_rounded
        ),
      SparkStatus.failed => (
          'Failed',
          const Color(0xFFFF5252),
          Icons.error_outline_rounded
        ),
      SparkStatus.timeout => (
          'Timed Out',
          const Color(0xFF9E9E9E),
          Icons.timer_off_rounded
        ),
      SparkStatus.needsRevision => (
          'Needs Revision',
          const Color(0xFFFFAB40),
          Icons.edit_note_rounded
        ),
      SparkStatus.revising => (
          widget.revisionCount > 0
              ? 'Revising (${widget.revisionCount}/3)'
              : 'Revising',
          const Color(0xFFFFAB40),
          Icons.autorenew_rounded
        ),
      SparkStatus.reviewFailed => (
          'Review Failed',
          const Color(0xFFFF5252),
          Icons.rate_review_outlined
        ),
      SparkStatus.maxRevisionsReached => (
          'Max Revisions',
          const Color(0xFFFF5252),
          Icons.block_rounded
        ),
      SparkStatus.cancelled => (
          'Cancelled',
          const Color(0xFF9E9E9E),
          Icons.cancel_outlined
        ),
      SparkStatus.pendingRetry => (
          'Pending Retry',
          const Color(0xFFFFAB40),
          Icons.pending_outlined
        ),
    };

    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );

    if (_shouldPulse && _pulseController != null) {
      return AnimatedBuilder(
        animation: _pulseController!,
        builder: (_, child) => Opacity(
          opacity: 0.6 + 0.4 * _pulseController!.value,
          child: child,
        ),
        child: badge,
      );
    }

    return badge;
  }
}
