import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/session_provider.dart';

class TerminalOutputView extends StatefulWidget {
  final List<TerminalOutput> outputs;
  final double fontSize;
  final ScrollController? scrollController;
  final bool autoScroll;

  const TerminalOutputView({
    super.key,
    required this.outputs,
    this.fontSize = 13.0,
    this.scrollController,
    this.autoScroll = true,
  });

  @override
  State<TerminalOutputView> createState() => _TerminalOutputViewState();
}

class _TerminalOutputViewState extends State<TerminalOutputView> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void didUpdateWidget(TerminalOutputView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.outputs.length != oldWidget.outputs.length && widget.autoScroll) {
      _scrollToBottom();
    }
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

  @override
  void dispose() {
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _scrollToBottom,
      child: Container(
        color: ArcBenchTheme.terminalBg,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: widget.outputs.length,
          itemBuilder: (context, index) {
            final output = widget.outputs[index];
            return _OutputBlock(output: output, fontSize: widget.fontSize);
          },
        ),
      ),
    );
  }
}

class _OutputBlock extends StatelessWidget {
  final TerminalOutput output;
  final double fontSize;

  const _OutputBlock({required this.output, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    if (output.isInput) {
      return _buildInputBlock(output.text);
    }
    return _buildOutputBlock(output.text);
  }

  Widget _buildInputBlock(String text) {
    final clean = _stripAnsi(text).trimRight();
    if (clean.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ArcBenchTheme.arcBlue.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArcBenchTheme.arcBlue.withAlpha(25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '> ',
            style: GoogleFonts.jetBrainsMono(
              fontSize: fontSize,
              color: ArcBenchTheme.arcBlue,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          Expanded(
            child: SelectableText(
              clean,
              style: GoogleFonts.jetBrainsMono(
                fontSize: fontSize,
                color: ArcBenchTheme.arcBlue,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputBlock(String text) {
    final spans = _parseAnsiToSpans(text, fontSize);
    if (spans.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SelectableText.rich(
        TextSpan(children: spans),
      ),
    );
  }

  // ── ANSI parsing ──

  static List<TextSpan> _parseAnsiToSpans(String text, double fontSize) {
    final spans = <TextSpan>[];
    final ansiRegex = RegExp(r'\x1B\[([0-9;]*)m');
    Color currentColor = ArcBenchTheme.terminalText;
    bool isBold = false;

    int lastEnd = 0;
    for (final match in ansiRegex.allMatches(text)) {
      // Add text before this escape sequence
      if (match.start > lastEnd) {
        final segment = text.substring(lastEnd, match.start);
        if (segment.isNotEmpty) {
          spans.add(TextSpan(
            text: segment,
            style: GoogleFonts.jetBrainsMono(
              fontSize: fontSize,
              color: currentColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              height: 1.4,
            ),
          ));
        }
      }

      // Parse the SGR codes
      final codes = match.group(1) ?? '0';
      for (final code in _parseSgrCodes(codes)) {
        switch (code) {
          case 0:
            currentColor = ArcBenchTheme.terminalText;
            isBold = false;
          case 1:
            isBold = true;
          case 22:
            isBold = false;
          case 30:
            currentColor = Colors.black;
          case 31:
            currentColor = ArcBenchTheme.ansiRed;
          case 32:
            currentColor = ArcBenchTheme.ansiGreen;
          case 33:
            currentColor = ArcBenchTheme.ansiOrange;
          case 34:
            currentColor = ArcBenchTheme.ansiBlue;
          case 35:
            currentColor = ArcBenchTheme.ansiMagenta;
          case 36:
            currentColor = ArcBenchTheme.ansiCyan;
          case 37:
            currentColor = ArcBenchTheme.ansiWhite;
          case 39:
            currentColor = ArcBenchTheme.terminalText;
          case 90:
            currentColor = ArcBenchTheme.ansiBrightBlack;
          case 91:
            currentColor = ArcBenchTheme.ansiRed;
          case 92:
            currentColor = ArcBenchTheme.ansiGreen;
          case 93:
            currentColor = ArcBenchTheme.ansiYellow;
          case 94:
            currentColor = ArcBenchTheme.ansiBlue;
          case 95:
            currentColor = ArcBenchTheme.ansiMagenta;
          case 96:
            currentColor = ArcBenchTheme.ansiCyan;
          case 97:
            currentColor = ArcBenchTheme.ansiWhite;
        }
      }

      lastEnd = match.end;
    }

    // Add remaining text
    if (lastEnd < text.length) {
      final remaining = _stripNonSgrEscapes(text.substring(lastEnd));
      if (remaining.trimRight().isNotEmpty) {
        spans.add(TextSpan(
          text: remaining,
          style: GoogleFonts.jetBrainsMono(
            fontSize: fontSize,
            color: currentColor,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            height: 1.4,
          ),
        ));
      }
    }

    return spans;
  }

  static List<int> _parseSgrCodes(String raw) {
    if (raw.isEmpty) return [0];
    return raw
        .split(';')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }

  static String _stripNonSgrEscapes(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-ln-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\].*?\x07'), '')
        .replaceAll(RegExp(r'\x1B[()][AB012]'), '')
        .replaceAll(RegExp(r'\x1B[>=]'), '');
  }

  static String _stripAnsi(String text) {
    return text
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '')
        .replaceAll(RegExp(r'\x1B\].*?\x07'), '')
        .replaceAll(RegExp(r'\x1B[()][AB012]'), '')
        .replaceAll(RegExp(r'\x1B[>=]'), '');
  }
}
