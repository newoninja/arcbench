import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/session_provider.dart';
import 'package:arcbench_mobile/screens/sessions_screen.dart';
import 'package:arcbench_mobile/screens/terminal_screen.dart';
import 'package:arcbench_mobile/screens/folder_browser_screen.dart';
import 'package:arcbench_mobile/screens/settings_screen.dart';
import 'package:arcbench_mobile/screens/spark_idea_view.dart';
import 'package:arcbench_mobile/widgets/connection_status_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  void switchToTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _onNewSession() {
    HapticFeedback.mediumImpact();

    showModalBottomSheet<_CreateConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateTerminalSheet(),
    ).then((result) {
      if (result != null && mounted) {
        final sp = context.read<SessionProvider>();
        sp.createTerminal(
          command: result.command,
          workingDir: result.workingDir,
        );
        setState(() => _currentIndex = 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectionStatusBar(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                SessionsScreen(),
                TerminalScreen(),
                SparkIdeaView(),
                FolderBrowserScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        height: 68,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers_rounded),
            label: 'Sessions',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined),
            selectedIcon: Icon(Icons.terminal_rounded),
            label: 'Terminal',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt_rounded),
            label: 'Spark',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: Semantics(
        label: 'Create new terminal session',
        button: true,
        child: FloatingActionButton(
          onPressed: _onNewSession,
          tooltip: 'New Session',
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
    );
  }
}

// ─── Create terminal bottom sheet ───

class _CreateConfig {
  final String? command;
  final String workingDir;
  const _CreateConfig({this.command, required this.workingDir});
}

class _CreateTerminalSheet extends StatefulWidget {
  const _CreateTerminalSheet();

  @override
  State<_CreateTerminalSheet> createState() => _CreateTerminalSheetState();
}

class _CreateTerminalSheetState extends State<_CreateTerminalSheet> {
  String? _command = 'claude';
  String _workingDir = '~';

  Future<void> _pickFolder() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            FolderBrowserScreen(initialPath: _workingDir, pickerMode: true),
      ),
    );
    if (path != null && mounted) {
      setState(() => _workingDir = path);
    }
  }

  String _shortenPath(String path) {
    final home = RegExp(r'^/Users/[^/]+');
    return path.replaceFirst(home, '~');
  }

  void _create() {
    Navigator.of(context)
        .pop(_CreateConfig(command: _command, workingDir: _workingDir));
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: ArcBenchTheme.surfaceCard,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: ArcBenchTheme.textMuted.withAlpha(60),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 20, color: ArcBenchTheme.arcBlue),
                SizedBox(width: 10),
                Text(
                  'New Session',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ArcBenchTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Command selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COMMAND',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ArcBenchTheme.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _CommandOption(
                        icon: Icons.smart_toy_outlined,
                        label: 'Claude Code',
                        isSelected: _command == 'claude',
                        onTap: () => setState(() => _command = 'claude'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CommandOption(
                        icon: Icons.terminal_rounded,
                        label: 'Shell',
                        isSelected: _command == null,
                        onTap: () => setState(() => _command = null),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Working directory
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WORKING DIRECTORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ArcBenchTheme.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Semantics(
                  label: 'Working directory: ${_shortenPath(_workingDir)}',
                  hint: 'Tap to browse folders',
                  button: true,
                  child: GestureDetector(
                  onTap: _pickFolder,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ArcBenchTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF333333)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_rounded,
                            size: 20, color: ArcBenchTheme.warning),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _shortenPath(_workingDir),
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 13,
                              color: ArcBenchTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 20, color: ArcBenchTheme.textMuted),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Create button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _create,
                child: Text(
                  'Launch ${_command == 'claude' ? 'Claude Code' : 'Shell'}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _CommandOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CommandOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, ${isSelected ? "selected" : "not selected"}',
      button: true,
      selected: isSelected,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? ArcBenchTheme.arcBlue.withAlpha(20)
              : ArcBenchTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? ArcBenchTheme.arcBlue.withAlpha(100)
                : const Color(0xFF333333),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 24,
                color: isSelected
                    ? ArcBenchTheme.arcBlue
                    : ArcBenchTheme.textMuted),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? ArcBenchTheme.arcBlue
                    : ArcBenchTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
