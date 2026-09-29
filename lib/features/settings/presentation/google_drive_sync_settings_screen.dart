import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_folder.dart';
import 'package:shonenx/features/sync/presentation/widgets/google_drive_folder_picker_dialog.dart';
import 'package:shonenx/features/sync/presentation/widgets/google_drive_restore_dialog.dart';
import 'package:shonenx/features/sync/providers/google_drive_sync_provider.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';

class GoogleDriveSyncSettingsScreen extends ConsumerStatefulWidget {
  const GoogleDriveSyncSettingsScreen({super.key});

  @override
  ConsumerState<GoogleDriveSyncSettingsScreen> createState() =>
      _GoogleDriveSyncSettingsScreenState();
}

class _GoogleDriveSyncSettingsScreenState
    extends ConsumerState<GoogleDriveSyncSettingsScreen> {
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  bool _customCredsExpanded = false;

  @override
  void initState() {
    super.initState();
    final account = ref.read(googleDriveSyncProvider).account;
    _clientIdController.text = account.customClientId;
    _clientSecretController.text = account.customClientSecret;
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSignIn() async {
    final notifier = ref.read(googleDriveSyncProvider.notifier);
    await notifier.signIn();
    final state = ref.read(googleDriveSyncProvider);
    if (state.errorMessage != null) {
      _showSnack(state.errorMessage!, isError: true);
    } else if (state.statusMessage != null) {
      _showSnack(state.statusMessage!);
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Drive?'),
        content: const Text(
          'Your existing backups on Google Drive will remain safe, but this device will stop syncing with your Google account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(googleDriveSyncProvider.notifier).signOut();
      _showSnack('Disconnected from Google Drive');
    }
  }

  Future<void> _handleChangeDirectory() async {
    final state = ref.read(googleDriveSyncProvider);
    final selectedFolder = await GoogleDriveFolderPickerDialog.show(
      context,
      currentFolderId: state.account.selectedFolderId,
      currentFolderName: state.account.selectedFolderName,
    );

    if (selectedFolder != null) {
      await ref
          .read(googleDriveSyncProvider.notifier)
          .selectDirectory(selectedFolder);
      _showSnack('Storage directory set to "${selectedFolder.name}"');
    }
  }

  Future<void> _handleBackupNow() async {
    try {
      final notifier = ref.read(googleDriveSyncProvider.notifier);
      await notifier.backupNow();
      final state = ref.read(googleDriveSyncProvider);
      if (state.statusMessage != null) {
        _showSnack(state.statusMessage!);
      }
    } catch (e) {
      _showSnack('Backup failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final syncState = ref.watch(googleDriveSyncProvider);
    final account = syncState.account;
    final isSignedIn = syncState.isSignedIn;

    return AppScaffold(
      title: 'Google Drive Sync',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          // Hero Banner Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSignedIn
                    ? [
                        cs.primary.withValues(alpha: 0.25),
                        cs.tertiary.withValues(alpha: 0.15),
                      ]
                    : [
                        cs.surfaceContainerHighest,
                        cs.surfaceContainer,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSignedIn
                    ? cs.primary.withValues(alpha: 0.3)
                    : cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.cloud_sync_rounded,
                            size: 28,
                            color: isSignedIn ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Google Drive Cloud Sync',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isSignedIn
                                  ? 'Active & Synchronized'
                                  : 'Disconnected',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSignedIn
                                    ? Colors.greenAccent
                                    : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isSignedIn)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 14, color: Colors.greenAccent),
                            SizedBox(width: 4),
                            Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isSignedIn
                      ? 'Backups are stored inside your Google Drive directory "${account.selectedFolderName}". All bookmarks, watch progress, and settings remain private to your account.'
                      : 'Connect your personal Google account to back up and sync your library, watch progress, tracker links, and settings across all your devices.',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (account.lastSyncTimestamp != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.history_rounded,
                          size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        'Last sync: ${DateFormat.yMMMd().add_jm().format(account.lastSyncTimestamp!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Google Account Section
          SettingsSection(
            title: 'Google Account',
            subtitle: 'Log into your Google account for private cloud storage',
            children: [
              if (!isSignedIn)
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'No Google Account Linked',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to select a directory on your Google Drive and automatically sync your data.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: syncState.isLoading ? null : _handleSignIn,
                          icon: syncState.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            syncState.isLoading
                                ? 'Connecting...'
                                : 'Sign in with Google',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: cs.primaryContainer,
                          backgroundImage: account.photoUrl.isNotEmpty
                              ? CachedNetworkImageProvider(account.photoUrl)
                              : null,
                          child: account.photoUrl.isEmpty
                              ? Icon(Icons.person, color: cs.onPrimaryContainer)
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.displayName.isNotEmpty
                                    ? account.displayName
                                    : 'Google User',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                account.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _handleSignOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(
                              color: cs.error.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('Disconnect'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // Storage Directory Section ("choose a directory then save their data there")
          if (isSignedIn) ...[
            SettingsSection(
              title: 'Drive Directory / Folder',
              subtitle: 'Choose which directory in your Google Drive to store data in',
              children: [
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              child: Icon(
                                Icons.folder_shared_rounded,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.selectedFolderName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    account.selectedFolderId.isNotEmpty
                                        ? 'Directory ID: ${account.selectedFolderId.substring(0, account.selectedFolderId.length > 12 ? 12 : account.selectedFolderId.length)}...'
                                        : 'Root Google Drive folder',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _handleChangeDirectory,
                              child: const Text('Change Folder'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Backups and snapshots will be created directly in "${account.selectedFolderName}".',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Backup & Restore Actions
            SettingsSection(
              title: 'Backup & Restore Actions',
              subtitle: 'Save local KuroX data to Drive or restore from cloud',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            syncState.isSyncing ? null : _handleBackupNow,
                        icon: syncState.isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(
                          syncState.isSyncing
                              ? 'Saving...'
                              : 'Save Data to Drive',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: syncState.isSyncing
                            ? null
                            : () => GoogleDriveRestoreDialog.show(context),
                        icon: const Icon(Icons.cloud_download_rounded),
                        label: const Text(
                          'Restore Data',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Automated Sync
            SettingsSection(
              title: 'Auto-Sync Preferences',
              subtitle: 'Keep your data synced without manual backups',
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text(
                    'Auto-Sync to Google Drive',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Automatically saves updates to your Drive directory',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: account.autoSyncEnabled,
                  onChanged: (val) {
                    ref
                        .read(googleDriveSyncProvider.notifier)
                        .setAutoSync(val);
                  },
                ),
                if (account.autoSyncEnabled) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SegmentedButton<AutoSyncInterval>(
                      segments: const [
                        ButtonSegment(
                          value: AutoSyncInterval.onAppStart,
                          label: Text('On Launch'),
                        ),
                        ButtonSegment(
                          value: AutoSyncInterval.every6Hours,
                          label: Text('6 Hours'),
                        ),
                        ButtonSegment(
                          value: AutoSyncInterval.daily,
                          label: Text('Daily'),
                        ),
                      ],
                      selected: {account.autoSyncInterval},
                      onSelectionChanged: (set) {
                        ref
                            .read(googleDriveSyncProvider.notifier)
                            .setAutoSync(true, interval: set.first);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Advanced / Custom Google Cloud Credentials (Optional)
          SettingsSection(
            title: 'Custom OAuth Client (Optional)',
            subtitle: 'Use your own Google Cloud project credentials if desired',
            children: [
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ExpansionTile(
                  title: const Text(
                    'Custom Google Cloud API Credentials',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    account.customClientId.isNotEmpty
                        ? 'Using custom Client ID'
                        : 'Using default KuroX Client ID',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  leading: const Icon(Icons.key_rounded),
                  initiallyExpanded: _customCredsExpanded,
                  onExpansionChanged: (exp) =>
                      setState(() => _customCredsExpanded = exp),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'If you want your own unlimited API quota, you can create a free OAuth 2.0 Client ID in Google Cloud Console with Google Drive API enabled.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _clientIdController,
                            decoration: const InputDecoration(
                              labelText: 'Google Client ID',
                              hintText: 'xxxx.apps.googleusercontent.com',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _clientSecretController,
                            decoration: const InputDecoration(
                              labelText: 'Google Client Secret (Optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () async {
                              await ref
                                  .read(googleDriveSyncProvider.notifier)
                                  .setCustomCredentials(
                                    clientId: _clientIdController.text,
                                    clientSecret: _clientSecretController.text,
                                  );
                              _showSnack('Saved custom Google credentials');
                            },
                            child: const Text('Save Credentials'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
