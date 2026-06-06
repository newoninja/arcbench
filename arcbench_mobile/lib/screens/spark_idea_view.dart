import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/spark_provider.dart';
import 'package:arcbench_mobile/services/voice_service.dart';
import 'package:arcbench_mobile/screens/ideas_log_view.dart';

// ─── Spark accent ───
const _sparkCyan = Color(0xFF00D4FF);
const _sparkCyanDim = Color(0xFF007A99);
const _sparkGlow = Color(0x4000D4FF);

class SparkIdeaView extends StatefulWidget {
  const SparkIdeaView({super.key});

  @override
  State<SparkIdeaView> createState() => _SparkIdeaViewState();
}

class _SparkIdeaViewState extends State<SparkIdeaView>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _voiceService = VoiceService();

  late final AnimationController _waveCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _sendCtrl;

  String? _selectedChip;
  bool _isListening = false;
  bool _isSending = false;
  int _tabIndex = 0; // 0 = Spark, 1 = Ideas Log

  static const _chips = [
    'Test Landing Page',
    'Client Proposal',
    'Marketing Funnel',
    'AI Dashboard',
    'Custom Idea',
  ];

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _sendCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _voiceService.initialize();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _pulseCtrl.dispose();
    _sendCtrl.dispose();
    _textController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  // ─── Voice ───

  Future<void> _toggleVoice() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      final text = await _voiceService.stopListening();
      setState(() {
        _isListening = false;
        if (text.isNotEmpty) {
          _textController.text = text;
          _textController.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        }
      });
    } else {
      setState(() => _isListening = true);
      await _voiceService.startListening();
      // Listen for live transcript updates
      _voiceService.addListener(_onVoiceUpdate);
    }
  }

  void _onVoiceUpdate() {
    if (!_isListening) {
      _voiceService.removeListener(_onVoiceUpdate);
      return;
    }
    if (_voiceService.currentText.isNotEmpty) {
      setState(() {
        _textController.text = _voiceService.currentText;
        _textController.selection = TextSelection.fromPosition(
          TextPosition(offset: _textController.text.length),
        );
      });
    }
    if (_voiceService.state == VoiceState.idle && _isListening) {
      setState(() => _isListening = false);
      _voiceService.removeListener(_onVoiceUpdate);
    }
  }

  // ─── Submit ───

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.heavyImpact();
    setState(() => _isSending = true);
    _sendCtrl.forward(from: 0);

    final spark = context.read<SparkProvider>();
    await spark.submitIdea(
      content: text,
      chipLabel: _selectedChip,
    );

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() {
        _isSending = false;
        _textController.clear();
        _selectedChip = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _sparkCyan, size: 20),
              const SizedBox(width: 10),
              Text('Spark sent!',
                  style: TextStyle(color: ArcBenchTheme.textPrimary)),
            ],
          ),
          backgroundColor: ArcBenchTheme.surfaceElevated,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab switcher
        _buildTabBar(),
        Expanded(
          child: _tabIndex == 0 ? _buildSparkView() : const IdeasLogView(),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ArcBenchTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Row(
        children: [
          _tabButton(0, Icons.bolt_rounded, 'Spark'),
          _tabButton(1, Icons.history_rounded, 'Ideas Log'),
        ],
      ),
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _sparkCyan.withAlpha(25) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: _sparkCyan.withAlpha(60))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? _sparkCyan : ArcBenchTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? _sparkCyan : ArcBenchTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSparkView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ArcBenchTheme.glassBlur,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _sparkCyan.withAlpha(30), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _sparkGlow,
                  blurRadius: 60,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 28),
                _buildHeader(),
                const SizedBox(height: 20),
                _buildWaveform(),
                const SizedBox(height: 20),
                _buildVoiceButton(),
                const SizedBox(height: 8),
                _buildLiveTranscript(),
                const SizedBox(height: 20),
                _buildTextInput(),
                const SizedBox(height: 16),
                _buildChips(),
                const SizedBox(height: 24),
                _buildSendButton(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_sparkCyan, Color(0xFF7B61FF)],
          ).createShader(bounds),
          child: const Icon(Icons.bolt_rounded, size: 36, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'Spark an Idea',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: ArcBenchTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Speak or type — AI builds it live',
          style: TextStyle(
            fontSize: 14,
            color: ArcBenchTheme.textSecondary.withAlpha(180),
          ),
        ),
      ],
    );
  }

  // ─── Waveform ───

  Widget _buildWaveform() {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveCtrl, _pulseCtrl]),
      builder: (context, _) {
        return SizedBox(
          width: double.infinity,
          height: 120,
          child: CustomPaint(
            painter: _WaveformPainter(
              wavePhase: _waveCtrl.value,
              pulseValue: _pulseCtrl.value,
              isActive: _isListening,
            ),
          ),
        );
      },
    );
  }

  // ─── Voice button ───

  Widget _buildVoiceButton() {
    return GestureDetector(
      onTap: _toggleVoice,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, child) {
          final scale = _isListening ? 1.0 + (_pulseCtrl.value * 0.08) : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isListening
                      ? [const Color(0xFFFF4D6A), const Color(0xFFFF8A65)]
                      : [_sparkCyan, const Color(0xFF7B61FF)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening
                            ? const Color(0xFFFF4D6A)
                            : _sparkCyan)
                        .withAlpha(_isListening ? 100 : 50),
                    blurRadius: _isListening ? 30 : 16,
                    spreadRadius: _isListening ? 4 : 0,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLiveTranscript() {
    if (!_isListening && _textController.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'Tap the mic and describe your idea\n60 seconds of voice input',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: ArcBenchTheme.textMuted.withAlpha(150),
            height: 1.5,
          ),
        ),
      );
    }

    if (_isListening) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4D6A)
                        .withAlpha((150 + 105 * _pulseCtrl.value).toInt()),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Listening...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFF4D6A)
                        .withAlpha((180 + 75 * _pulseCtrl.value).toInt()),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ─── Text input ───

  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: ArcBenchTheme.surfaceElevated.withAlpha(180),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _sparkCyan.withAlpha(40)),
        ),
        child: TextField(
          controller: _textController,
          maxLines: 4,
          minLines: 2,
          style: const TextStyle(
            fontSize: 15,
            color: ArcBenchTheme.textPrimary,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: 'Describe your idea...',
            hintStyle: TextStyle(color: ArcBenchTheme.textMuted),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  // ─── Quick chips ───

  Widget _buildChips() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final label = _chips[i];
          final selected = _selectedChip == label;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() {
                _selectedChip = selected ? null : label;
                if (!selected && label != 'Custom Idea') {
                  _textController.text = label;
                  _textController.selection = TextSelection.fromPosition(
                    TextPosition(offset: label.length),
                  );
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? _sparkCyan.withAlpha(30)
                    : ArcBenchTheme.surfaceCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? _sparkCyan.withAlpha(120)
                      : Colors.white.withAlpha(15),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? _sparkCyan : ArcBenchTheme.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Send button ───

  Widget _buildSendButton() {
    final hasContent = _textController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedBuilder(
        animation: _sendCtrl,
        builder: (context, _) {
          return SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: hasContent && !_isSending ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasContent ? _sparkCyan : _sparkCyanDim,
                foregroundColor: Colors.black,
                disabledBackgroundColor: ArcBenchTheme.surfaceElevated,
                disabledForegroundColor: ArcBenchTheme.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: hasContent ? 8 : 0,
                shadowColor: _sparkGlow,
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: 22,
                            color: hasContent
                                ? Colors.black
                                : ArcBenchTheme.textMuted),
                        const SizedBox(width: 8),
                        Text(
                          'Send Spark',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: hasContent
                                ? Colors.black
                                : ArcBenchTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Waveform CustomPainter ───

class _WaveformPainter extends CustomPainter {
  final double wavePhase;
  final double pulseValue;
  final bool isActive;

  _WaveformPainter({
    required this.wavePhase,
    required this.pulseValue,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final width = size.width;

    // Draw 3 layered sine waves
    for (var layer = 0; layer < 3; layer++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isActive ? 2.5 - (layer * 0.5) : 1.5 - (layer * 0.3)
        ..strokeCap = StrokeCap.round;

      final Color baseColor;
      switch (layer) {
        case 0:
          baseColor = _sparkCyan;
          break;
        case 1:
          baseColor = const Color(0xFF7B61FF);
          break;
        default:
          baseColor = const Color(0xFFFF4D6A);
      }

      final alpha = isActive
          ? (180 - layer * 40 + (pulseValue * 75).toInt())
          : (60 - layer * 15);
      paint.color = baseColor.withAlpha(alpha.clamp(0, 255));

      final path = Path();
      final frequency = 2.5 + layer * 0.7;
      final amplitude = isActive
          ? (size.height * 0.35 - layer * 8) * (0.7 + pulseValue * 0.3)
          : (size.height * 0.12 - layer * 3);
      final phaseOffset = wavePhase * 2 * pi + (layer * pi / 3);

      for (var x = 0.0; x <= width; x += 1.5) {
        final normalizedX = x / width;
        // Envelope: fade edges
        final envelope = sin(normalizedX * pi);
        final y = centerY +
            sin(normalizedX * frequency * 2 * pi + phaseOffset) *
                amplitude *
                envelope;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }

    // Glow center line when active
    if (isActive) {
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = _sparkCyan.withAlpha((30 + pulseValue * 30).toInt())
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final glowPath = Path();
      for (var x = 0.0; x <= width; x += 2) {
        final normalizedX = x / width;
        final envelope = sin(normalizedX * pi);
        final y = centerY +
            sin(normalizedX * 2.5 * 2 * pi + wavePhase * 2 * pi) *
                (size.height * 0.3) *
                envelope *
                (0.7 + pulseValue * 0.3);
        if (x == 0) {
          glowPath.moveTo(x, y);
        } else {
          glowPath.lineTo(x, y);
        }
      }
      canvas.drawPath(glowPath, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}
