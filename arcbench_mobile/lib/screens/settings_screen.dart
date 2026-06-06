import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/constants.dart';
import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/providers/settings_provider.dart';
import 'package:arcbench_mobile/services/offline_queue.dart';
import 'package:arcbench_mobile/screens/connect_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _serverStatus;
  bool _statusLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    final firebase = context.read<ConnectionProvider>().firebaseService;
    if (!firebase.isAuthenticated) return;

    setState(() => _statusLoading = true);
    try {
      _serverStatus = await firebase.getUserProfile();
    } catch (_) {}
    if (mounted) setState(() => _statusLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final conn = context.watch<ConnectionProvider>();
    final queue = context.watch<OfflineQueue>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Terminal ──
          _SectionHeader(title: 'Terminal'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Font size', style: TextStyle(fontSize: 15)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: ArcBenchTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${settings.fontSize.toInt()} pt',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 13,
                            color: ArcBenchTheme.arcBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: settings.fontSize,
                    min: 8,
                    max: 24,
                    divisions: 16,
                    activeColor: ArcBenchTheme.arcBlue,
                    label: '${settings.fontSize.toInt()} pt',
                    onChanged: (v) => settings.setFontSize(v),
                  ),
                  // Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: ArcBenchTheme.terminalBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '\$ echo "Hello, ArcBench!"\nHello, ArcBench!',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: settings.fontSize,
                        color: ArcBenchTheme.terminalText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: SwitchListTile(
              title: const Text('Auto-scroll'),
              subtitle: const Text(
                'Scroll to bottom on new output',
                style:
                    TextStyle(color: ArcBenchTheme.textMuted, fontSize: 12),
              ),
              value: settings.autoScroll,
              activeColor: ArcBenchTheme.arcBlue,
              onChanged: (v) => settings.setAutoScroll(v),
            ),
          ),

          const SizedBox(height: 20),

          // ── Voice ──
          _SectionHeader(title: 'Voice'),
          Card(
            child: SwitchListTile(
              title: const Text('Voice input'),
              subtitle: const Text(
                'Hold mic button to dictate commands',
                style:
                    TextStyle(color: ArcBenchTheme.textMuted, fontSize: 12),
              ),
              value: settings.voiceEnabled,
              activeColor: ArcBenchTheme.arcBlue,
              onChanged: (v) => settings.setVoiceEnabled(v),
            ),
          ),
          if (settings.voiceEnabled)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Speech speed',
                            style: TextStyle(fontSize: 15)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ArcBenchTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${settings.voiceSpeed.toStringAsFixed(2)}x',
                            style: const TextStyle(
                              fontSize: 13,
                              color: ArcBenchTheme.arcBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: settings.voiceSpeed,
                      min: 0.25,
                      max: 2.0,
                      divisions: 7,
                      activeColor: ArcBenchTheme.arcBlue,
                      label: '${settings.voiceSpeed.toStringAsFixed(2)}x',
                      onChanged: (v) => settings.setVoiceSpeed(v),
                    ),
                    const Text(
                      'Speed for AI response text-to-speech',
                      style: TextStyle(
                          color: ArcBenchTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // ── Account ──
          _SectionHeader(title: 'Account'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _InfoRow(label: 'Email', value: conn.email ?? '-'),
                  _InfoRow(label: 'Display name', value: conn.username),
                  _InfoRow(label: 'User ID', value: conn.userId?.substring(0, 8) ?? '-'),
                  _InfoRow(
                    label: 'Status',
                    value: conn.isAuthenticated ? 'Signed in' : 'Signed out',
                    valueColor: conn.isAuthenticated
                        ? ArcBenchTheme.success
                        : ArcBenchTheme.error,
                  ),
                  _InfoRow(
                    label: 'Backend',
                    value: 'Firebase',
                    valueColor: ArcBenchTheme.arcBlue,
                  ),
                  if (_statusLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: ArcBenchTheme.arcBlue),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Offline Queue ──
          _SectionHeader(title: 'Offline Queue'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: queue.isNotEmpty
                          ? ArcBenchTheme.warning.withAlpha(20)
                          : ArcBenchTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 20,
                      color: queue.isNotEmpty
                          ? ArcBenchTheme.warning
                          : ArcBenchTheme.textMuted,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${queue.length} queued',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          queue.isEmpty
                              ? 'All prompts sent'
                              : 'Will send on reconnect',
                          style: const TextStyle(
                              color: ArcBenchTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (queue.isNotEmpty)
                    TextButton(
                      onPressed: () => queue.clear(),
                      style: TextButton.styleFrom(
                          foregroundColor: ArcBenchTheme.error),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Logout ──
          OutlinedButton.icon(
            onPressed: () async {
              await conn.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const ConnectScreen()),
                  (_) => false,
                );
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign Out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ArcBenchTheme.error,
              side: const BorderSide(color: ArcBenchTheme.error),
            ),
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              'ArcBench v${AppConstants.appVersion}',
              style: const TextStyle(
                  color: ArcBenchTheme.textMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: ArcBenchTheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: ArcBenchTheme.textMuted, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? ArcBenchTheme.textPrimary,
                fontSize: 13,
                fontFamily: 'JetBrains Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
