import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:arcbench_mobile/config/theme.dart';
import 'package:arcbench_mobile/providers/connection_provider.dart';

class FolderBrowserScreen extends StatefulWidget {
  final String? initialPath;
  final bool pickerMode;

  const FolderBrowserScreen({
    super.key,
    this.initialPath,
    this.pickerMode = false,
  });

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  String _currentPath = '~';
  String? _parentPath;
  List<_DirEntry> _entries = [];
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;
  String? _error;

  // Tree view: tracks expanded directories
  final Map<String, List<_DirEntry>> _expandedDirs = {};
  final Set<String> _loadingDirs = {};

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? '~';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadBookmarks();
      _loadDirectory(_currentPath);
    });
  }

  Future<void> _loadBookmarks() async {
    final api = context.read<ConnectionProvider>().apiService;
    if (api == null) return;
    try {
      final bm = await api.getBookmarks();
      if (mounted) setState(() => _bookmarks = bm);
    } catch (_) {}
  }

  Future<void> _loadDirectory(String path) async {
    final api = context.read<ConnectionProvider>().apiService;
    if (api == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _expandedDirs.clear();
    });

    try {
      final result = await api.browseDirectory(path: path);
      if (mounted) {
        setState(() {
          _currentPath = result['path'] as String? ?? path;
          _parentPath = result['parent'] as String?;
          final items = result['items'] as List<dynamic>? ?? [];
          _entries = items
              .map((e) => _DirEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleExpand(String dirPath) async {
    if (_expandedDirs.containsKey(dirPath)) {
      setState(() => _expandedDirs.remove(dirPath));
      return;
    }

    final api = context.read<ConnectionProvider>().apiService;
    if (api == null) return;

    setState(() => _loadingDirs.add(dirPath));

    try {
      final result = await api.browseDirectory(path: dirPath);
      final items = result['items'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _expandedDirs[dirPath] = items
              .map((e) => _DirEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          _loadingDirs.remove(dirPath);
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDirs.remove(dirPath));
    }
  }

  void _navigateTo(String path) {
    HapticFeedback.selectionClick();
    _loadDirectory(path);
  }

  void _selectCurrentPath() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(_currentPath);
  }

  String _shortenPath(String path) {
    final home = RegExp(r'^/Users/[^/]+');
    return path.replaceFirst(home, '~');
  }

  @override
  Widget build(BuildContext context) {
    final isPicker = widget.pickerMode;

    return Scaffold(
      appBar: isPicker
          ? AppBar(
              title: const Text('Choose Folder'),
              actions: [
                TextButton.icon(
                  onPressed: _selectCurrentPath,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Select'),
                  style: TextButton.styleFrom(
                      foregroundColor: ArcBenchTheme.arcBlue),
                ),
              ],
            )
          : AppBar(
              title: const Text('Files'),
              automaticallyImplyLeading: false,
            ),
      body: Column(
        children: [
          // Path bar
          _PathBar(
            path: _shortenPath(_currentPath),
            onRefresh: () => _loadDirectory(_currentPath),
          ),

          // Bookmarks
          if (_bookmarks.isNotEmpty)
            _BookmarksRow(
              bookmarks: _bookmarks,
              currentPath: _currentPath,
              onTap: _navigateTo,
            ),

          const Divider(height: 1, color: Color(0xFF2A2A2A)),

          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadDirectory(_currentPath),
              color: ArcBenchTheme.arcBlue,
              child: _buildContent(),
            ),
          ),

          // Selection bar (picker mode)
          if (isPicker)
            _SelectionBar(
              path: _shortenPath(_currentPath),
              onSelect: _selectCurrentPath,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: ArcBenchTheme.arcBlue),
      );
    }

    if (_error != null) {
      return _buildError();
    }

    final dirs = _entries.where((e) => e.isDir).toList();
    final files = _entries.where((e) => !e.isDir).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Parent
        if (_parentPath != null)
          _EntryTile(
            icon: Icons.arrow_upward_rounded,
            iconColor: ArcBenchTheme.arcBlue,
            name: '..',
            subtitle: 'Parent folder',
            onTap: () => _navigateTo(_parentPath!),
            depth: 0,
          ),

        // Folders with tree expansion
        if (dirs.isNotEmpty) ...[
          _SectionHeader(label: 'Folders', count: dirs.length),
          ...dirs.expand((d) => _buildTreeItem(d, 0)),
        ],

        // Files
        if (files.isNotEmpty) ...[
          _SectionHeader(label: 'Files', count: files.length),
          ...files.map((f) => _EntryTile(
                icon: _iconForFile(f.name),
                iconColor: ArcBenchTheme.textMuted,
                name: f.name,
                subtitle: f.size != null ? _formatSize(f.size!) : null,
                onTap: null,
                depth: 0,
              )),
        ],

        if (dirs.isEmpty && files.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Text('This folder is empty',
                  style: TextStyle(
                      color: ArcBenchTheme.textMuted, fontSize: 14)),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildTreeItem(_DirEntry entry, int depth) {
    final isExpanded = _expandedDirs.containsKey(entry.path);
    final isLoading = _loadingDirs.contains(entry.path);

    final widgets = <Widget>[
      _EntryTile(
        icon: isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        iconColor: const Color(0xFFFFAB40),
        name: entry.name,
        onTap: () {
          if (widget.pickerMode) {
            _navigateTo(entry.path);
          } else {
            _toggleExpand(entry.path);
          }
        },
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: ArcBenchTheme.textMuted),
              )
            else
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.chevron_right_rounded,
                color: ArcBenchTheme.textMuted,
                size: 20,
              ),
          ],
        ),
        depth: depth,
      ),
    ];

    // Show children if expanded
    if (isExpanded) {
      final children = _expandedDirs[entry.path]!;
      final childDirs = children.where((e) => e.isDir);
      final childFiles = children.where((e) => !e.isDir);

      for (final child in childDirs) {
        widgets.addAll(_buildTreeItem(child, depth + 1));
      }
      for (final child in childFiles) {
        widgets.add(_EntryTile(
          icon: _iconForFile(child.name),
          iconColor: ArcBenchTheme.textMuted.withAlpha(150),
          name: child.name,
          subtitle: child.size != null ? _formatSize(child.size!) : null,
          onTap: null,
          depth: depth + 1,
        ));
      }
    }

    return widgets;
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_outlined,
                size: 48, color: ArcBenchTheme.textMuted),
            const SizedBox(height: 16),
            const Text('Cannot access this folder',
                style: TextStyle(
                    color: ArcBenchTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(
                    color: ArcBenchTheme.textMuted, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_parentPath != null)
              OutlinedButton.icon(
                onPressed: () => _navigateTo(_parentPath!),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Go Back'),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'swift' || 'rs' || 'go' || 'java' ||
      'c' || 'cpp' || 'h' || 'rb' =>
        Icons.code_rounded,
      'md' || 'txt' || 'rtf' => Icons.description_rounded,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object_rounded,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' =>
        Icons.image_rounded,
      'pdf' => Icons.picture_as_pdf_rounded,
      'zip' || 'tar' || 'gz' || 'rar' => Icons.archive_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ─── Data model ───

class _DirEntry {
  final String name;
  final String path;
  final bool isDir;
  final int? size;

  const _DirEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size,
  });

  factory _DirEntry.fromJson(Map<String, dynamic> json) => _DirEntry(
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        isDir: json['is_dir'] as bool? ?? false,
        size: json['size'] as int?,
      );
}

// ─── Widgets ───

class _PathBar extends StatelessWidget {
  final String path;
  final VoidCallback onRefresh;

  const _PathBar({required this.path, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: ArcBenchTheme.surfaceCard,
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded,
              size: 18, color: Color(0xFFFFAB40)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: ArcBenchTheme.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: ArcBenchTheme.textMuted,
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}

class _BookmarksRow extends StatelessWidget {
  final List<Map<String, dynamic>> bookmarks;
  final String currentPath;
  final ValueChanged<String> onTap;

  const _BookmarksRow({
    required this.bookmarks,
    required this.currentPath,
    required this.onTap,
  });

  IconData _iconFor(String label) {
    return switch (label) {
      'Home' => Icons.home_rounded,
      'Desktop' => Icons.desktop_mac_rounded,
      'Documents' => Icons.description_rounded,
      'Downloads' => Icons.download_rounded,
      'Projects' => Icons.folder_special_rounded,
      'Developer' || 'Code' => Icons.code_rounded,
      'repos' => Icons.source_rounded,
      _ => Icons.folder_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      color: ArcBenchTheme.surfaceCard,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: bookmarks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final bm = bookmarks[index];
          final label = bm['label'] as String;
          final path = bm['path'] as String;
          final isActive = currentPath == path;

          return GestureDetector(
            onTap: () => onTap(path),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? ArcBenchTheme.arcBlue.withAlpha(30)
                    : ArcBenchTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? ArcBenchTheme.arcBlue.withAlpha(80)
                      : const Color(0xFF333333),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconFor(label),
                      size: 14,
                      color: isActive
                          ? ArcBenchTheme.arcBlue
                          : ArcBenchTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? ArcBenchTheme.arcBlue
                            : ArcBenchTheme.textSecondary,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;

  const _SectionHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ArcBenchTheme.textMuted,
                letterSpacing: 1.2,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: ArcBenchTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$count',
                style: const TextStyle(
                    fontSize: 10, color: ArcBenchTheme.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final int depth;

  const _EntryTile({
    required this.icon,
    required this.iconColor,
    required this.name,
    this.subtitle,
    this.onTap,
    this.trailing,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16.0 + (depth * 20.0),
            right: 16,
            top: 11,
            bottom: 11,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: onTap != null
                              ? ArcBenchTheme.textPrimary
                              : ArcBenchTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 11, color: ArcBenchTheme.textMuted)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final String path;
  final VoidCallback onSelect;

  const _SelectionBar({required this.path, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Selected directory',
                    style: TextStyle(
                        fontSize: 11, color: ArcBenchTheme.textMuted)),
                const SizedBox(height: 2),
                Text(path,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: ArcBenchTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: onSelect,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(80, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Select',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
