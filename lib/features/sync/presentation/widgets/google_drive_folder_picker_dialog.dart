import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_folder.dart';
import 'package:shonenx/features/sync/providers/google_drive_sync_provider.dart';

class GoogleDriveFolderPickerDialog extends ConsumerStatefulWidget {
  final String currentFolderId;
  final String currentFolderName;

  const GoogleDriveFolderPickerDialog({
    super.key,
    required this.currentFolderId,
    required this.currentFolderName,
  });

  static Future<GoogleDriveFolder?> show(
    BuildContext context, {
    required String currentFolderId,
    required String currentFolderName,
  }) {
    return showModalBottomSheet<GoogleDriveFolder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => GoogleDriveFolderPickerDialog(
        currentFolderId: currentFolderId,
        currentFolderName: currentFolderName,
      ),
    );
  }

  @override
  ConsumerState<GoogleDriveFolderPickerDialog> createState() =>
      _GoogleDriveFolderPickerDialogState();
}

class _GoogleDriveFolderPickerDialogState
    extends ConsumerState<GoogleDriveFolderPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newFolderController = TextEditingController();
  List<GoogleDriveFolder> _folders = [];
  bool _isLoading = true;
  String? _error;
  GoogleDriveFolder? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _fetchFolders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _fetchFolders({String? query}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final notifier = ref.read(googleDriveSyncProvider.notifier);
      final folders = await notifier.fetchFolders(query: query);
      if (mounted) {
        setState(() {
          _folders = folders;
          _isLoading = false;
          if (_selectedFolder == null && widget.currentFolderId.isNotEmpty) {
            _selectedFolder = folders.where((f) => f.id == widget.currentFolderId).firstOrNull;
          }
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

  void _showCreateFolderDialog() {
    _newFolderController.text = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Folder'),
        content: TextField(
          controller: _newFolderController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            hintText: 'e.g. KuroX_Backups',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = _newFolderController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx).pop();

              try {
                final notifier = ref.read(googleDriveSyncProvider.notifier);
                final newFolder = await notifier.createAndSelectDirectory(name);
                if (mounted) {
                  Navigator.of(context).pop(newFolder);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to create folder: $e')),
                  );
                }
              }
            },
            child: const Text('Create & Select'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding + 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_shared_rounded, color: cs.primary, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Drive Folder',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Choose where to save your KuroX data',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: _showCreateFolderDialog,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('New Folder'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Search Box
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search folders...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _fetchFolders();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (val) => _fetchFolders(query: val),
          ),

          const SizedBox(height: 12),

          // Content List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: cs.error, size: 40),
                            const SizedBox(height: 8),
                            Text(
                              'Failed to load folders: $_error',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error, fontSize: 13),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: () => _fetchFolders(),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _folders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.folder_off_outlined,
                                    size: 48, color: cs.onSurfaceVariant),
                                const SizedBox(height: 8),
                                Text(
                                  'No folders found in Google Drive',
                                  style: TextStyle(
                                      color: cs.onSurfaceVariant, fontSize: 14),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _showCreateFolderDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create "KuroX_Backups"'),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _folders.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 56),
                            itemBuilder: (ctx, index) {
                              final folder = _folders[index];
                              final isSelected =
                                  _selectedFolder?.id == folder.id ||
                                  (_selectedFolder == null &&
                                      folder.id == widget.currentFolderId);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.folder_rounded,
                                    color: isSelected
                                        ? cs.onPrimaryContainer
                                        : cs.primary,
                                  ),
                                ),
                                title: Text(
                                  folder.name,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                                subtitle: folder.modifiedTime != null
                                    ? Text(
                                        'Modified: ${DateFormat.yMMMd().format(folder.modifiedTime!)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded,
                                        color: cs.primary)
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                selected: isSelected,
                                selectedTileColor:
                                    cs.primary.withValues(alpha: 0.08),
                                onTap: () {
                                  setState(() => _selectedFolder = folder);
                                },
                              );
                            },
                          ),
          ),

          const SizedBox(height: 16),

          // Confirm Action
          FilledButton(
            onPressed: _selectedFolder != null
                ? () => Navigator.of(context).pop(_selectedFolder)
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _selectedFolder != null
                  ? 'Use "${_selectedFolder!.name}" as Directory'
                  : 'Select a Directory',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
