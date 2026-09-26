import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/core/services/backup_service.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';
import 'package:shonenx/features/backup/services/cloud_sync_service.dart';
import 'package:shonenx/shared/providers/backup_provider.dart';

final cloudSyncConfigProvider =
    NotifierProvider<CloudSyncNotifier, CloudSyncConfig>(CloudSyncNotifier.new);

class CloudSyncNotifier extends Notifier<CloudSyncConfig> {
  static const _prefKey = 'kurox_cloud_sync_config';
  final _log = AppLogger.scope('CloudSyncNotifier');

  @override
  CloudSyncConfig build() {
    _loadFromPrefs();
    return const CloudSyncConfig();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        state = CloudSyncConfig.fromJson(json);
      }
    } catch (e) {
      _log.e('Failed to load cloud sync config', e);
    }
  }

  Future<void> saveConfig(CloudSyncConfig config) async {
    state = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, config.toJson());
    } catch (e) {
      _log.e('Failed to save cloud sync config', e);
    }
  }

  Future<void> setProvider(CloudSyncProviderType type) async {
    await saveConfig(state.copyWith(providerType: type));
  }

  Future<void> setWebDavCredentials({
    required String url,
    required String username,
    required String password,
    String? filePath,
  }) async {
    await saveConfig(
      state.copyWith(
        providerType: CloudSyncProviderType.webdav,
        webdavUrl: url.trim(),
        webdavUsername: username.trim(),
        webdavPassword: password.trim(),
        webdavFilePath: filePath?.trim() ?? state.webdavFilePath,
      ),
    );
  }

  Future<void> setGistCredentials({
    required String token,
    String? gistId,
  }) async {
    await saveConfig(
      state.copyWith(
        providerType: CloudSyncProviderType.githubGist,
        gistToken: token.trim(),
        gistId: gistId?.trim() ?? state.gistId,
      ),
    );
  }

  Future<void> setInterval(AutoSyncInterval interval) async {
    await saveConfig(state.copyWith(autoSyncInterval: interval));
  }

  /// Verifies credentials against the selected cloud provider.
  Future<String> testConnection() async {
    final status = await CloudSyncService.testConnection(state);
    await saveConfig(state.copyWith(lastSyncStatus: status));
    return status;
  }

  /// Synchronizes local library & history with the cloud.
  Future<({bool success, String message})> syncNow({
    bool forceUpload = false,
    bool forceDownload = false,
  }) async {
    if (!state.isConfigured) {
      return (success: false, message: 'Cloud sync is not configured yet');
    }

    final backupService = ref.read(backupServiceProvider);

    try {
      _log.i('Starting cloud sync...');

      if (forceUpload) {
        final manifest = await backupService.exportData(
          BackupCategory.values.toSet(),
        );
        final newGistId = await CloudSyncService.uploadManifest(
          state,
          manifest.toJson(),
        );

        final updated = state.copyWith(
          gistId: newGistId ?? state.gistId,
          lastSyncTimestamp: DateTime.now(),
          lastSyncStatus: 'Uploaded backup to cloud successfully',
        );
        await saveConfig(updated);
        return (success: true, message: 'Uploaded backup to cloud successfully');
      }

      if (forceDownload) {
        final manifest = await CloudSyncService.downloadManifest(state);
        if (manifest == null) {
          return (success: false, message: 'No backup found in cloud');
        }
        await backupService.importData(manifest, manifest.categories);
        final updated = state.copyWith(
          lastSyncTimestamp: DateTime.now(),
          lastSyncStatus: 'Restored backup from cloud successfully',
        );
        await saveConfig(updated);
        return (success: true, message: 'Restored backup from cloud successfully');
      }

      // Bi-directional timestamp-based sync
      final remoteManifest = await CloudSyncService.downloadManifest(state);

      if (remoteManifest != null && state.lastSyncTimestamp != null) {
        if (remoteManifest.exportDate.isAfter(state.lastSyncTimestamp!)) {
          // Remote is newer, download and merge
          _log.i('Remote backup is newer, applying to local store...');
          await backupService.importData(
            remoteManifest,
            remoteManifest.categories,
          );
          final updated = state.copyWith(
            lastSyncTimestamp: DateTime.now(),
            lastSyncStatus: 'Synced (Downloaded latest revision from cloud)',
          );
          await saveConfig(updated);
          return (
            success: true,
            message: 'Synced: downloaded latest cloud backup',
          );
        }
      }

      // Otherwise local is newer or first sync -> upload
      final localManifest = await backupService.exportData(
        BackupCategory.values.toSet(),
      );
      final newGistId = await CloudSyncService.uploadManifest(
        state,
        localManifest.toJson(),
      );

      final updated = state.copyWith(
        gistId: newGistId ?? state.gistId,
        lastSyncTimestamp: DateTime.now(),
        lastSyncStatus: 'Synced (Uploaded latest changes to cloud)',
      );
      await saveConfig(updated);
      return (success: true, message: 'Synced: uploaded latest changes to cloud');
    } catch (e, st) {
      _log.e('Cloud sync failed', e, st);
      final errMsg = 'Sync failed: $e';
      await saveConfig(state.copyWith(lastSyncStatus: errMsg));
      return (success: false, message: errMsg);
    }
  }

  /// Automatically triggered on app startup to run silent background sync if enabled.
  Future<void> checkAndRunScheduledSync() async {
    if (!state.isConfigured || state.autoSyncInterval == AutoSyncInterval.disabled) {
      return;
    }

    final now = DateTime.now();
    final last = state.lastSyncTimestamp;

    bool shouldSync = false;
    if (last == null) {
      shouldSync = true;
    } else {
      switch (state.autoSyncInterval) {
        case AutoSyncInterval.onAppStart:
          shouldSync = true;
          break;
        case AutoSyncInterval.every6Hours:
          shouldSync = now.difference(last).inHours >= 6;
          break;
        case AutoSyncInterval.daily:
          shouldSync = now.difference(last).inHours >= 24;
          break;
        case AutoSyncInterval.disabled:
          shouldSync = false;
          break;
      }
    }

    if (shouldSync) {
      _log.i('Triggering scheduled silent background cloud sync...');
      await syncNow();
    }
  }
}
