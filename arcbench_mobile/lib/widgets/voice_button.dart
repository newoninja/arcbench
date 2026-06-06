import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/services/voice_service.dart';

class VoiceButton extends StatefulWidget {
  final VoiceService voiceService;
  final void Function(String transcript) onResult;
  final bool compact;

  const VoiceButton({
    super.key,
    required this.voiceService,
    required this.onResult,
    this.compact = false,
  });

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtl;

  @override
  void initState() {
    super.initState();
    _animCtl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animCtl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    HapticFeedback.mediumImpact();
    _animCtl.repeat();
    await widget.voiceService.startListening();
  }

  Future<void> _stop() async {
    _animCtl.stop();
    _animCtl.reset();
    final text = await widget.voiceService.stopListening();
    if (text.isNotEmpty) widget.onResult(text);
  }

  void _cancel() {
    _animCtl.stop();
    _animCtl.reset();
    widget.voiceService.cancelListening();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.voiceService,
      builder: (context, _) {
        final listening = widget.voiceService.isListening;
        return widget.compact
            ? _buildCompact(listening)
            : _buildFull(listening);
      },
    );
  }

  Widget _buildCompact(bool listening) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _cancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: listening
              ? ArcBenchTheme.error
              : ArcBenchTheme.surfaceElevated,
        ),
        child: listening
            ? _WaveformIcon(animation: _animCtl, size: 20)
            : const Icon(Icons.mic_rounded,
                color: ArcBenchTheme.textSecondary, size: 20),
      ),
    );
  }

  Widget _buildFull(bool listening) {
    final currentText = widget.voiceService.currentText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live transcription
        if (listening && currentText.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: ArcBenchTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ArcBenchTheme.arcBlue.withAlpha(50)),
            ),
            child: Text(
              currentText,
              style: const TextStyle(
                color: ArcBenchTheme.textPrimary,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Mic button with waveform
        GestureDetector(
          onTapDown: (_) => _start(),
          onTapUp: (_) => _stop(),
          onTapCancel: _cancel,
          child: SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Waveform rings
                if (listening)
                  AnimatedBuilder(
                    animation: _animCtl,
                    builder: (_, __) {
                      return CustomPaint(
                        size: const Size(100, 100),
                        painter: _WaveformRingPainter(
                          progress: _animCtl.value,
                          color: ArcBenchTheme.error,
                        ),
                      );
                    },
                  ),
                // Button
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        listening ? ArcBenchTheme.error : ArcBenchTheme.arcBlue,
                    boxShadow: [
                      BoxShadow(
                        color: (listening
                                ? ArcBenchTheme.error
                                : ArcBenchTheme.arcBlue)
                            .withAlpha(60),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: listening
                      ? _WaveformIcon(animation: _animCtl, size: 28)
                      : const Icon(Icons.mic_rounded,
                          color: Colors.white, size: 28),
                ),
              ],
            ),
          ),
        ),

        if (listening)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Listening... release to send',
              style: TextStyle(color: ArcBenchTheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Animated waveform bars inside the mic button.
class _WaveformIcon extends StatelessWidget {
  final Animation<double> animation;
  final double size;

  const _WaveformIcon({required this.animation, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        return CustomPaint(
          size: Size(size, size),
          painter: _WaveformBarsPainter(progress: animation.value),
        );
      },
    );
  }
}

class _WaveformBarsPainter extends CustomPainter {
  final double progress;

  _WaveformBarsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    const barCount = 5;
    final barSpacing = size.width / (barCount + 1);
    final centerY = size.height / 2;
    final maxHeight = size.height * 0.6;

    for (int i = 0; i < barCount; i++) {
      final x = barSpacing * (i + 1);
      final phase = progress * 2 * pi + (i * pi / 3);
      final height = maxHeight * (0.3 + 0.7 * ((sin(phase) + 1) / 2));

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformBarsPainter old) => old.progress != progress;
}

class _WaveformRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaveformRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = 32.0 + ringProgress * 18;
      final opacity = (1.0 - ringProgress) * 0.3;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withAlpha((255 * opacity).round())
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformRingPainter old) => old.progress != progress;
}
