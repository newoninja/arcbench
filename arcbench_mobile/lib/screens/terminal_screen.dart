import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/providers/session_provider.dart';
import 'package:arcbench_mobile/providers/settings_provider.dart';
import 'package:arcbench_mobile/services/voice_service.dart';
import 'package:arcbench_mobile/widgets/terminal_output.dart';
import 'package:arcbench_mobile/widgets/voice_button.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  VoiceService? _voiceService;
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _autoScroll = settings.autoScroll;
    if (settings.voiceEnabled) {
      _voiceService = VoiceService();
      _voiceService!.initialize();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _voiceService?.dispose();
    super.dispose();
  }

  void _sendInput() {
    final text = _inputController.text;
    if (text.isEmpty) return;

    final sp = context.read<SessionProvider>();
    if (sp.activeTerminalId == null) return;

    sp.sendInput(sp.activeTerminalId!, '$text\n');
    _inputController.clear();
    _inputFocus.requestFocus();
  }

  void _toggleAutoScroll() {
    setState(() => _autoScroll = !_autoScroll);
    context.read<SettingsProvider>().setAutoScroll(_autoScroll);
    if (_autoScroll) _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _killTerminal() {
    final sp = context.read<SessionProvider>();
    if (sp.activeTerminalId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kill Terminal?'),
        content: const Text('This will destroy the terminal process.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              sp.destroyTerminal(sp.activeTerminalId!);
            },
            style: TextButton.styleFrom(foregroundColor: ArcBenchTheme.error),
            child: const Text('Kill'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SessionProvider>();
    final conn = context.watch<ConnectionProvider>();
    final settings = context.watch<SettingsProvider>();
    final terminal = sp.activeTerminal;
    final outputs = sp.activeOutputs;

    if (terminal == null && sp.activeTerminalId == null) {
      return _buildNoTerminal();
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Hero(
                  tag: 'terminal-icon-${sp.activeTerminalId ?? "none"}',
                  child: Icon(
                    terminal?.isClaude == true
                        ? Icons.smart_toy_outlined
                        : Icons.terminal_rounded,
                    size: 16,
                    color: ArcBenchTheme.arcBlue,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    terminal?.workingDir.isNotEmpty == true
                        ? _shortenPath(terminal!.workingDir)
                        : 'Terminal',
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                _StatusDot(alive: terminal?.isAlive == true),
                const SizedBox(width: 5),
                Text(
                  terminal?.isAlive == true ? 'Running' : 'Stopped',
                  style: TextStyle(
                    fontSize: 11,
                    color: terminal?.isAlive == true
                        ? ArcBenchTheme.success
                        : ArcBenchTheme.error,
                  ),
                ),
                if (!conn.isConnected) ...[
                  const SizedBox(width: 8),
                  const Text('Disconnected',
                      style: TextStyle(
                          fontSize: 11, color: ArcBenchTheme.warning)),
                ],
              ],
            ),
          ],
        ),
        actions: [
          // Auto-scroll toggle
          Semantics(
            label: _autoScroll ? 'Disable auto-scroll' : 'Enable auto-scroll',
            toggled: _autoScroll,
            button: true,
            child: IconButton(
              icon: Icon(
                _autoScroll
                    ? Icons.vertical_align_bottom_rounded
                    : Icons.unfold_more_rounded,
                size: 20,
              ),
              tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
              color: _autoScroll ? ArcBenchTheme.arcBlue : ArcBenchTheme.textMuted,
              onPressed: _toggleAutoScroll,
            ),
          ),
          if (terminal?.isAlive == true)
            Semantics(
              label: 'Kill terminal process',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.stop_circle_outlined, size: 22),
                tooltip: 'Kill terminal',
                onPressed: _killTerminal,
                color: ArcBenchTheme.error,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Terminal output
          Expanded(
            child: outputs.isEmpty
                ? _buildWaiting()
                : TerminalOutputView(
                    outputs: outputs,
                    fontSize: settings.fontSize,
                    scrollController: _scrollController,
                    autoScroll: _autoScroll,
                  ),
          ),

          // Input bar
          if (terminal?.isAlive == true) _buildInputBar(settings),
        ],
      ),
    );
  }

  Widget _buildInputBar(SettingsProvider settings) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: ArcBenchTheme.surfaceCard,
        border:
            Border(top: BorderSide(color: ArcBenchTheme.surfaceElevated)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              label: 'Command input',
              textField: true,
              hint: 'Type a command and press send',
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 3,
                minLines: 1,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  color: ArcBenchTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type a command...',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendInput(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Voice button
          if (settings.voiceEnabled && _voiceService != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: VoiceButton(
                voiceService: _voiceService!,
                compact: true,
                onResult: (transcript) {
                  final sp = context.read<SessionProvider>();
                  if (sp.activeTerminalId != null) {
                    sp.sendInput(sp.activeTerminalId!, '$transcript\n');
                  }
                },
              ),
            ),

          // Send button
          Semantics(
            label: 'Send command',
            button: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Material(
                  color: ArcBenchTheme.arcBlue,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _sendInput,
                    borderRadius: BorderRadius.circular(12),
                    child: const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTerminal() {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Terminal'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: ArcBenchTheme.arcBlue.withAlpha(15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.terminal_rounded,
                    size: 36, color: ArcBenchTheme.arcBlue),
              ),
              const SizedBox(height: 20),
              const Text(
                'No active terminal',
                style: TextStyle(
                  color: ArcBenchTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a session or create a new one.',
                style:
                    TextStyle(color: ArcBenchTheme.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaiting() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: ArcBenchTheme.arcBlue),
          ),
          SizedBox(height: 16),
          Text('Starting terminal...',
              style:
                  TextStyle(color: ArcBenchTheme.textMuted, fontSize: 15)),
        ],
      ),
    );
  }

  String _shortenPath(String path) {
    final home = RegExp(r'^/Users/[^/]+');
    return path.replaceFirst(home, '~');
  }
}

class _StatusDot extends StatelessWidget {
  final bool alive;
  const _StatusDot({required this.alive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: alive ? ArcBenchTheme.success : ArcBenchTheme.error,
      ),
    );
  }
}
