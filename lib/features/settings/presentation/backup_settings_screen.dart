import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/router/app_navigator.dart';
import 'package:shonenx/core/services/backup_service.dart';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';
import 'package:shonenx/features/backup/providers/cloud_sync_provider.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/shared/providers/backup_provider.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';

class BackupSettingsScreen extends ConsumerStatefulWidget {
  const BackupSettingsScreen({super.key});

  @override
  ConsumerState<BackupSettingsScreen> createState() =>
      _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends ConsumerState<BackupSettingsScreen> {
  final _exportCategories = Set<BackupCategory>.from(BackupCategory.values);
  bool _exporting = false;

  late TextEditingController _webdavUrlController;
  late TextEditingController _webdavUsernameController;
  late TextEditingController _webdavPasswordController;
  late TextEditingController _webdavPathController;
  late TextEditingController _gistTokenController;
  late TextEditingController _gistIdController;

  bool _obscureWebdavPassword = true;
  bool _obscureGistToken = true;
  bool _isTesting = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    final cloudConfig = ref.read(cloudSyncConfigProvider);
    _webdavUrlController = TextEditingController(text: cloudConfig.webdavUrl);
    _webdavUsernameController =
        TextEditingController(text: cloudConfig.webdavUsername);
    _webdavPasswordController =
        TextEditingController(text: cloudConfig.webdavPassword);
    _webdavPathController =
        TextEditingController(text: cloudConfig.webdavFilePath);
    _gistTokenController = TextEditingController(text: cloudConfig.gistToken);
    _gistIdController = TextEditingController(text: cloudConfig.gistId);
  }

  @override
  void dispose() {
    _webdavUrlController.dispose();
    _webdavUsernameController.dispose();
    _webdavPasswordController.dispose();
    _webdavPathController.dispose();
    _gistTokenController.dispose();
    _gistIdController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_exportCategories.isEmpty) {
      _snack('Select at least one category');
      return;
    }

    setState(() => _exporting = true);

    try {
      final service = ref.read(backupServiceProvider);
      final manifest = await service.exportData(_exportCategories);
      final json = manifest.toJson();

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'shonenx_backup_$timestamp.json';

      String? savePath;

      if (Platform.isAndroid || Platform.isIOS) {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save backup',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: Uint8List.fromList(utf8.encode(json)),
        );
      } else {
        savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save backup',
          fileName: fileName,
        );
        if (savePath != null) {
          await File(savePath).writeAsString(json);
        }
      }

      if (savePath != null && mounted) {
        _snack('Backup saved');
      }
    } catch (e) {
      if (mounted) _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final json = await file.readAsString();
      final manifest = BackupManifest.fromJson(json);

      if (mounted) {
        context.pushSettingsBackupPreview(manifest);
      }
    } catch (e) {
      if (mounted) _snack('Invalid backup file');
    }
  }

  Future<void> _saveAndTestCloud() async {
    final notifier = ref.read(cloudSyncConfigProvider.notifier);
    final current = ref.read(cloudSyncConfigProvider);

    if (current.providerType == CloudSyncProviderType.webdav) {
      await notifier.setWebDavCredentials(
        url: _webdavUrlController.text,
        username: _webdavUsernameController.text,
        password: _webdavPasswordController.text,
        filePath: _webdavPathController.text,
      );
    } else if (current.providerType == CloudSyncProviderType.githubGist) {
      await notifier.setGistCredentials(
        token: _gistTokenController.text,
        gistId: _gistIdController.text,
      );
    }

    setState(() => _isTesting = true);
    try {
      final status = await notifier.testConnection();
      if (mounted) _snack(status);
    } catch (e) {
      if (mounted) _snack('Connection test failed: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _triggerCloudSync({bool forceUpload = false}) async {
    final notifier = ref.read(cloudSyncConfigProvider.notifier);
    setState(() => _isSyncing = true);
    try {
      final result = await notifier.syncNow(forceUpload: forceUpload);
      if (mounted) _snack(result.message);
    } catch (e) {
      if (mounted) _snack('Sync error: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloudConfig = ref.watch(cloudSyncConfigProvider);
    final cs = Theme.of(context).colorScheme;

    return AppScaffold(
      title: 'Backup & Restore',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          // Cloud & WebDAV Auto-Sync Section
          SettingsSection(
            title: 'Automated Cloud & WebDAV Backup',
            subtitle:
                'Keep bookmarks, watch history, tracker links, and settings synced across all devices',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SegmentedButton<CloudSyncProviderType>(
                  segments: const [
                    ButtonSegment(
                      value: CloudSyncProviderType.disabled,
                      label: Text('Off'),
                    ),
                    ButtonSegment(
                      value: CloudSyncProviderType.webdav,
                      label: Text('WebDAV'),
                    ),
                    ButtonSegment(
                      value: CloudSyncProviderType.githubGist,
                      label: Text('GitHub Gist'),
                    ),
                  ],
                  selected: {cloudConfig.providerType},
                  onSelectionChanged: (set) {
                    ref
                        .read(cloudSyncConfigProvider.notifier)
                        .setProvider(set.first);
                  },
                ),
              ),
              if (cloudConfig.providerType == CloudSyncProviderType.webdav) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _webdavUrlController,
                    decoration: const InputDecoration(
                      labelText: 'WebDAV Server URL',
                      hintText: 'https://cloud.example.com/remote.php/dav/files/user/',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _webdavUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username / Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _webdavPasswordController,
                    obscureText: _obscureWebdavPassword,
                    decoration: InputDecoration(
                      labelText: 'Password / App Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureWebdavPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(
                            () =>
                                _obscureWebdavPassword = !_obscureWebdavPassword,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _webdavPathController,
                    decoration: const InputDecoration(
                      labelText: 'Remote File Name',
                      hintText: 'kurox_backup.json',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ] else if (cloudConfig.providerType ==
                  CloudSyncProviderType.githubGist) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _gistTokenController,
                    obscureText: _obscureGistToken,
                    decoration: InputDecoration(
                      labelText: 'GitHub Personal Access Token (PAT)',
                      hintText: 'ghp_...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureGistToken
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(
                            () => _obscureGistToken = !_obscureGistToken,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _gistIdController,
                    decoration: const InputDecoration(
                      labelText: 'Gist ID (Leave empty to auto-create)',
                      hintText: 'Optional custom gist ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
              if (cloudConfig.providerType != CloudSyncProviderType.disabled) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _saveAndTestCloud,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.link_rounded),
                          label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSyncing
                              ? null
                              : () => _triggerCloudSync(forceUpload: true),
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded),
                          label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text('Auto-Sync Frequency'),
                  subtitle: Text(cloudConfig.autoSyncInterval.displayName),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final interval in AutoSyncInterval.values)
                              ListTile(
                                title: Text(interval.displayName),
                                trailing:
                                    cloudConfig.autoSyncInterval == interval
                                        ? Icon(Icons.check, color: cs.primary)
                                        : null,
                                onTap: () {
                                  ref
                                      .read(cloudSyncConfigProvider.notifier)
                                      .setInterval(interval);
                                  Navigator.pop(ctx);
                                },
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (cloudConfig.lastSyncStatus != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Text(
                      'Status: ${cloudConfig.lastSyncStatus!}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
            ],
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Local Export Section
          SettingsSection(
            title: 'Manual Local Export',
            subtitle: 'Choose categories to include in .json backup',
            children: [
              for (final cat in BackupCategory.values)
                SettingsSwitchTile(
                  icon: cat.icon,
                  title: cat.label,
                  subtitle: cat.description,
                  value: _exportCategories.contains(cat),
                  onChanged: (v) => setState(() {
                    v
                        ? _exportCategories.add(cat)
                        : _exportCategories.remove(cat);
                  }),
                ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: FilledButton.icon(
                  onPressed: _exporting ? null : _export,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(_exporting ? 'Exporting…' : 'Export Local Backup'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Local Import Section
          SettingsSection(
            title: 'Manual Local Import',
            children: [
              SettingsActionTile(
                icon: Icons.download_outlined,
                title: 'Restore from file',
                subtitle: 'Select a .json backup file',
                onTap: _import,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
