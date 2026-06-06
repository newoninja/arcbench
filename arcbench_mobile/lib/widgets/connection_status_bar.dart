import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';
import 'package:arcbench_mobile/services/websocket_service.dart';

class ConnectionStatusBar extends StatelessWidget {
  const ConnectionStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final ws = conn.wsService;
    final wsState = ws?.state ?? WsConnectionState.disconnected;

    final isHealthy = wsState == WsConnectionState.connected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isHealthy ? 0 : 32,
      width: double.infinity,
      color: _colorForState(wsState),
      child: isHealthy
          ? const SizedBox.shrink()
          : SafeArea(
              bottom: false,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (wsState == WsConnectionState.reconnecting)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Icon(
                      _iconForState(wsState),
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _labelForState(wsState),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Color _colorForState(WsConnectionState state) {
    switch (state) {
      case WsConnectionState.connecting:
        return ArcBenchTheme.arcBlue.withAlpha(200);
      case WsConnectionState.reconnecting:
        return ArcBenchTheme.warning.withAlpha(200);
      case WsConnectionState.disconnected:
        return ArcBenchTheme.error.withAlpha(200);
      case WsConnectionState.connected:
        return Colors.transparent;
    }
  }

  IconData _iconForState(WsConnectionState state) {
    switch (state) {
      case WsConnectionState.connecting:
        return Icons.cloud_sync_outlined;
      case WsConnectionState.reconnecting:
        return Icons.sync_rounded;
      case WsConnectionState.disconnected:
        return Icons.cloud_off_rounded;
      case WsConnectionState.connected:
        return Icons.cloud_done_outlined;
    }
  }

  String _labelForState(WsConnectionState state) {
    switch (state) {
      case WsConnectionState.connecting:
        return 'Connecting...';
      case WsConnectionState.reconnecting:
        return 'Reconnecting...';
      case WsConnectionState.disconnected:
        return 'Disconnected';
      case WsConnectionState.connected:
        return 'Connected';
    }
  }
}
