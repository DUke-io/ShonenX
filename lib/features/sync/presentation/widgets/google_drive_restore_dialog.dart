import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shonenx/core/services/backup_service.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_file.dart';
import 'package:shonenx/features/sync/providers/google_drive_sync_provider.dart';

class GoogleDriveRestoreDialog extends ConsumerStatefulWidget {
  const GoogleDriveRestoreDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const GoogleDriveRestoreDialog(),
    );
  }

  @override
  ConsumerState<GoogleDriveRestoreDialog> createState() =>
      _GoogleDriveRestoreDialogState();
}

class _GoogleDriveRestoreDialogState
    extends ConsumerState<GoogleDriveRestoreDialog> {
  GoogleDriveFile? _selectedFile;
  bool _isRestoring = false;

  void _confirmRestore(GoogleDriveFile file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Google Drive?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${file.name}'),
            const SizedBox(height: 4),
            Text('Size: ${file.formattedSize}'),
            if (file.modifiedTime != null) ...[
              const SizedBox(height: 4),
              Text(
                'Date: ${DateFormat.yMMMd().add_jm().format(file.modifiedTime!)}',
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Restoring will merge bookmarks, watch history, tracker links, and settings into your local data.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restore_rounded),
            label: const Text('Confirm Restore'),
            onPressed: () async {
              Navigator.of(ctx).pop(); // Close confirm dialog
              setState(() => _isRestoring = true);

              try {
                final notifier = ref.read(googleDriveSyncProvider.notifier);
                final manifest = await notifier.restoreFromDrive(file);

                if (mounted) {
                  final total = manifest.categories.fold<int>(
                    0,
                    (sum, cat) => sum + manifest.countFor(cat),
                  );
                  Navigator.of(context).pop(); // Close sheet
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Successfully restored $total items from Google Drive!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isRestoring = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Restore error: $e'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(GoogleDriveFile file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Backup File?'),
        content: Text(
          'Are you sure you want to permanently delete "${file.name}" from your Google Drive?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref
                  .read(googleDriveSyncProvider.notifier)
                  .deleteBackupFile(file);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final syncState = ref.watch(googleDriveSyncProvider);
    final backups = syncState.availableBackups;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
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

          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_download_rounded, color: cs.primary, size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Restore from Google Drive',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Backups found in "${syncState.account.selectedFolderName}"',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Backups',
                onPressed: () =>
                    ref.read(googleDriveSyncProvider.notifier).refreshBackups(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_isRestoring)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Restoring data from Google Drive...',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else if (backups.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 48,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No backup files found in this directory',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap "Backup Now" on the previous screen to save your first backup.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: backups.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 56),
                itemBuilder: (ctx, index) {
                  final file = backups[index];
                  final isMainBackup = file.name == 'kurox_backup.json';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isMainBackup
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      child: Icon(
                        isMainBackup
                            ? Icons.star_rounded
                            : Icons.description_outlined,
                        color: isMainBackup
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            file.name,
                            style: TextStyle(
                              fontWeight: isMainBackup
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isMainBackup) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'LATEST',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${file.formattedSize} • ${file.modifiedTime != null ? DateFormat.yMMMd().add_jm().format(file.modifiedTime!) : "Unknown date"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDelete(file),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _confirmRestore(file),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('Restore'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
