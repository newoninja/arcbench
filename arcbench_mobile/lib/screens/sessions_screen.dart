import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/providers/session_provider.dart';
import 'package:arcbench_mobile/screens/connect_screen.dart';
import 'package:arcbench_mobile/screens/home_shell.dart';
import 'package:arcbench_mobile/widgets/terminal_card.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionProvider>().loadTerminals();
    });
  }

  void _openTerminal(String terminalId) {
    final sp = context.read<SessionProvider>();
    sp.attachTerminal(terminalId);

    final shell = context.findAncestorStateOfType<HomeShellState>();
    shell?.switchToTab(1);
  }

  void _deleteTerminal(String terminalId) {
    context.read<SessionProvider>().destroyTerminal(terminalId);
  }

  Future<void> _logout() async {
    await context.read<ConnectionProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ConnectScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        automaticallyImplyLeading: false,
        actions: [
          Semantics(
            label: 'Sign out',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.logout_rounded, size: 22),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
          ),
        ],
      ),
      body: Consumer<SessionProvider>(
        builder: (context, sp, _) {
          if (sp.isLoading && sp.terminals.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: ArcBenchTheme.arcBlue),
            );
          }

          if (sp.terminals.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () => sp.loadTerminals(),
            color: ArcBenchTheme.arcBlue,
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 120),
              itemCount: sp.terminals.length,
              itemBuilder: (context, index) {
                final terminal = sp.terminals[index];
                final outputs = sp.outputsFor(terminal.id);
                final lastOutput =
                    outputs.isNotEmpty ? outputs.last.text.trim() : null;

                return Dismissible(
                  key: ValueKey(terminal.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: ArcBenchTheme.error.withAlpha(30),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: ArcBenchTheme.error),
                  ),
                  confirmDismiss: (_) async {
                    HapticFeedback.mediumImpact();
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Kill Terminal?'),
                        content: const Text(
                            'This will destroy the terminal process.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                                foregroundColor: ArcBenchTheme.error),
                            child: const Text('Kill'),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _deleteTerminal(terminal.id),
                  child: TerminalCard(
                    terminal: terminal,
                    lastOutput: lastOutput,
                    isActive: terminal.id == sp.activeTerminalId,
                    onTap: () => _openTerminal(terminal.id),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: ArcBenchTheme.surfaceCard,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.terminal_rounded,
                  size: 44, color: ArcBenchTheme.textMuted.withAlpha(120)),
            ),
            const SizedBox(height: 24),
            const Text(
              'No sessions yet',
              style: TextStyle(
                color: ArcBenchTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to launch a terminal.',
              style:
                  TextStyle(color: ArcBenchTheme.textMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
