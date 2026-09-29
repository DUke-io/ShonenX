import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/core/services/backup_service.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_account.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_file.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_folder.dart';
import 'package:shonenx/features/sync/services/google_drive_service.dart';
import 'package:shonenx/shared/providers/backup_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveSyncState {
  final GoogleDriveAccount account;
  final bool isLoading;
  final bool isSyncing;
  final List<GoogleDriveFile> availableBackups;
  final List<GoogleDriveFolder> availableFolders;
  final String? errorMessage;
  final String? statusMessage;

  const GoogleDriveSyncState({
    this.account = const GoogleDriveAccount(),
    this.isLoading = false,
    this.isSyncing = false,
    this.availableBackups = const [],
    this.availableFolders = const [],
    this.errorMessage,
    this.statusMessage,
  });

  bool get isSignedIn => account.isSignedIn;

  GoogleDriveSyncState copyWith({
    GoogleDriveAccount? account,
    bool? isLoading,
    bool? isSyncing,
    List<GoogleDriveFile>? availableBackups,
    List<GoogleDriveFolder>? availableFolders,
    String? errorMessage,
    String? statusMessage,
  }) {
    return GoogleDriveSyncState(
      account: account ?? this.account,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      availableBackups: availableBackups ?? this.availableBackups,
      availableFolders: availableFolders ?? this.availableFolders,
      errorMessage: errorMessage,
      statusMessage: statusMessage,
    );
  }
}

final googleDriveSyncProvider =
    NotifierProvider<GoogleDriveSyncNotifier, GoogleDriveSyncState>(
  GoogleDriveSyncNotifier.new,
);

class GoogleDriveSyncNotifier extends Notifier<GoogleDriveSyncState> {
  static final _log = AppLogger.scope('GoogleDriveSyncNotifier');
  static const _prefKey = 'kurox_google_drive_account_v2';

  @override
  GoogleDriveSyncState build() {
    _loadStoredAccount();
    return const GoogleDriveSyncState(isLoading: true);
  }

  Future<void> _loadStoredAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final account = GoogleDriveAccount.fromJson(jsonStr);
        state = state.copyWith(account: account, isLoading: false);
        if (account.isSignedIn) {
          await _ensureValidToken();
          await refreshBackups();
        }
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      _log.e('Failed to load stored Google account: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _saveAccount(GoogleDriveAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, account.toJson());
    state = state.copyWith(account: account);
  }

  /// Ensures the access token is still fresh, refreshing it if needed.
  Future<String> _ensureValidToken() async {
    var account = state.account;
    if (!account.isSignedIn) {
      throw Exception('Not signed into Google Drive');
    }

    if (account.isTokenExpired && account.refreshToken.isNotEmpty) {
      _log.i('Refreshing expired Google Drive token...');
      final clientId = GoogleDriveService.getEffectiveClientId(
        account.customClientId,
      );
      final clientSecret = GoogleDriveService.getEffectiveClientSecret(
        account.customClientSecret,
      );

      final tokenData = await GoogleDriveService.refreshAccessToken(
        refreshToken: account.refreshToken,
        clientId: clientId,
        clientSecret: clientSecret,
      );

      final newAccessToken = tokenData['access_token'] as String;
      final expiresIn = tokenData['expires_in'] as int? ?? 3600;
      final newExpiry = DateTime.now().add(Duration(seconds: expiresIn));

      account = account.copyWith(
        accessToken: newAccessToken,
        tokenExpiry: newExpiry,
      );
      await _saveAccount(account);
    }

    return account.accessToken;
  }

  /// Signs into Google via OAuth 2.0 PKCE flow.
  Future<void> signIn() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final clientId = GoogleDriveService.getEffectiveClientId(
        state.account.customClientId,
      );
      final clientSecret = GoogleDriveService.getEffectiveClientSecret(
        state.account.customClientSecret,
      );

      final codeVerifier = GoogleDriveService.generateCodeVerifier();
      final codeChallenge =
          await GoogleDriveService.generateCodeChallenge(codeVerifier);
      final stateToken = 'kurox_${DateTime.now().millisecondsSinceEpoch}';

      String authCode = '';
      String redirectUri = '';

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: Start local loopback HTTP server
        final serverInfo =
            await GoogleDriveService.startDesktopOAuthServer();
        redirectUri = serverInfo.redirectUri;

        final authUri = GoogleDriveService.buildAuthUri(
          clientId: clientId,
          redirectUri: redirectUri,
          codeChallenge: codeChallenge,
          state: stateToken,
        );

        await launchUrl(
          Uri.parse(authUri),
          mode: LaunchMode.externalApplication,
        );

        authCode = await serverInfo.codeFuture;
        await serverInfo.server.close(force: true);
      } else {
        // Mobile (Android / iOS): Use FlutterWebAuth2
        const callbackScheme = 'kurox';
        redirectUri = '$callbackScheme://oauth2redirect';

        final authUri = GoogleDriveService.buildAuthUri(
          clientId: clientId,
          redirectUri: redirectUri,
          codeChallenge: codeChallenge,
          state: stateToken,
        );

        final result = await FlutterWebAuth2.authenticate(
          url: authUri,
          callbackUrlScheme: callbackScheme,
          options: const FlutterWebAuth2Options(
            preferEphemeral: false,
            useWebview: true,
          ),
        );

        final parsedUri = Uri.parse(result);
        authCode = parsedUri.queryParameters['code'] ?? '';
        if (authCode.isEmpty) {
          throw Exception('No authorization code returned from Google Sign-In');
        }
      }

      // Exchange code for tokens
      final tokenData = await GoogleDriveService.exchangeCodeForTokens(
        code: authCode,
        codeVerifier: codeVerifier,
        redirectUri: redirectUri,
        clientId: clientId,
        clientSecret: clientSecret,
      );

      final accessToken = tokenData['access_token'] as String;
      final refreshToken = tokenData['refresh_token'] as String? ?? '';
      final expiresIn = tokenData['expires_in'] as int? ?? 3600;
      final expiry = DateTime.now().add(Duration(seconds: expiresIn));

      // Fetch user profile
      final userProfile =
          await GoogleDriveService.fetchUserProfile(accessToken);
      final email = userProfile['email'] as String? ?? '';
      final name = userProfile['name'] as String? ?? email;
      final picture = userProfile['picture'] as String? ?? '';

      // Find or auto-create the KuroX_Backups folder
      final folder = await GoogleDriveService.findOrCreateFolder(
        accessToken,
        folderName: state.account.selectedFolderName.isNotEmpty
            ? state.account.selectedFolderName
            : 'KuroX_Backups',
      );

      final updatedAccount = state.account.copyWith(
        email: email,
        displayName: name,
        photoUrl: picture,
        accessToken: accessToken,
        refreshToken: refreshToken.isNotEmpty
            ? refreshToken
            : state.account.refreshToken,
        tokenExpiry: expiry,
        selectedFolderId: folder.id,
        selectedFolderName: folder.name,
      );

      await _saveAccount(updatedAccount);
      await refreshBackups();

      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Connected as $name',
      );
    } catch (e) {
      _log.e('Google Sign-In failed: $e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign-in failed: $e',
      );
    }
  }

  /// Signs out and disconnects Google Drive.
  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      if (state.account.accessToken.isNotEmpty) {
        await GoogleDriveService.revokeToken(state.account.accessToken);
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);

    state = GoogleDriveSyncState(
      account: GoogleDriveAccount(
        customClientId: state.account.customClientId,
        customClientSecret: state.account.customClientSecret,
      ),
      isLoading: false,
      statusMessage: 'Disconnected from Google Drive',
    );
  }

  /// Sets custom Google Cloud OAuth credentials.
  Future<void> setCustomCredentials({
    required String clientId,
    required String clientSecret,
  }) async {
    final updated = state.account.copyWith(
      customClientId: clientId.trim(),
      customClientSecret: clientSecret.trim(),
    );
    await _saveAccount(updated);
  }

  /// Loads list of Google Drive folders for the folder picker.
  Future<List<GoogleDriveFolder>> fetchFolders({String? query}) async {
    try {
      final token = await _ensureValidToken();
      final folders = await GoogleDriveService.listFolders(token, query: query);
      state = state.copyWith(availableFolders: folders);
      return folders;
    } catch (e) {
      _log.e('Failed to fetch folders: $e');
      return [];
    }
  }

  /// Selects a directory/folder to store backups in.
  Future<void> selectDirectory(GoogleDriveFolder folder) async {
    final updated = state.account.copyWith(
      selectedFolderId: folder.id,
      selectedFolderName: folder.name,
    );
    await _saveAccount(updated);
    await refreshBackups();
    state = state.copyWith(
      statusMessage: 'Directory set to "${folder.name}"',
    );
  }

  /// Creates a new directory in Google Drive and selects it.
  Future<GoogleDriveFolder> createAndSelectDirectory(String folderName) async {
    state = state.copyWith(isLoading: true);
    try {
      final token = await _ensureValidToken();
      final folder = await GoogleDriveService.createFolder(
        token,
        folderName: folderName,
      );
      await selectDirectory(folder);
      state = state.copyWith(isLoading: false);
      return folder;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to create directory: $e',
      );
      rethrow;
    }
  }

  /// Refreshes the list of backups located in the selected folder.
  Future<void> refreshBackups() async {
    if (!state.isSignedIn || state.account.selectedFolderId.isEmpty) return;

    try {
      final token = await _ensureValidToken();
      final backups = await GoogleDriveService.listBackups(
        token,
        folderId: state.account.selectedFolderId,
      );
      state = state.copyWith(availableBackups: backups);
    } catch (e) {
      _log.e('Failed to refresh backups: $e');
    }
  }

  /// Backs up all local KuroX data directly to the selected Google Drive folder.
  Future<void> backupNow({bool notify = true}) async {
    if (!state.isSignedIn) {
      throw Exception('Please sign in to Google Drive first');
    }

    state = state.copyWith(isSyncing: true, errorMessage: null);

    try {
      final token = await _ensureValidToken();
      var folderId = state.account.selectedFolderId;

      // If no folder selected yet, find or create default
      if (folderId.isEmpty) {
        final folder = await GoogleDriveService.findOrCreateFolder(
          token,
          folderName: 'KuroX_Backups',
        );
        folderId = folder.id;
        final updated = state.account.copyWith(
          selectedFolderId: folder.id,
          selectedFolderName: folder.name,
        );
        await _saveAccount(updated);
      }

      final backupService = ref.read(backupServiceProvider);
      final manifest =
          await backupService.exportData(BackupCategory.values.toSet());
      final jsonContent = manifest.toJson();

      // Primary backup file (always represents latest state)
      await GoogleDriveService.uploadBackup(
        token,
        folderId: folderId,
        fileName: 'kurox_backup.json',
        jsonContent: jsonContent,
        description:
            'KuroX Main Backup (v${manifest.appVersion}) - ${DateTime.now().toLocal()}',
      );

      // Also create a timestamped snapshot
      final now = DateTime.now();
      final timestampStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      await GoogleDriveService.uploadBackup(
        token,
        folderId: folderId,
        fileName: 'kurox_backup_$timestampStr.json',
        jsonContent: jsonContent,
        description: 'KuroX Snapshot - ${now.toLocal()}',
      );

      final totalItems = manifest.categories.fold<int>(
        0,
        (sum, cat) => sum + manifest.countFor(cat),
      );

      final updatedAccount = state.account.copyWith(
        lastSyncTimestamp: now,
        lastSyncStatus: 'Saved $totalItems items to "${state.account.selectedFolderName}"',
      );
      await _saveAccount(updatedAccount);
      await refreshBackups();

      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Backup completed ($totalItems items)',
      );
    } catch (e) {
      _log.e('Backup failed: $e');
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Backup failed: $e',
      );
      rethrow;
    }
  }

  /// Restores data from a chosen Google Drive backup file.
  Future<BackupManifest> restoreFromDrive(GoogleDriveFile file) async {
    state = state.copyWith(isSyncing: true, errorMessage: null);

    try {
      final token = await _ensureValidToken();
      final jsonStr = await GoogleDriveService.downloadBackup(
        token,
        fileId: file.id,
      );

      final manifest = BackupManifest.fromJson(jsonStr);
      final backupService = ref.read(backupServiceProvider);
      await backupService.importData(manifest, manifest.categories);

      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Restored data from ${file.name}',
      );

      return manifest;
    } catch (e) {
      _log.e('Restore failed: $e');
      state = state.copyWith(
        isSyncing: false,
        errorMessage: 'Restore failed: $e',
      );
      rethrow;
    }
  }

  /// Deletes a specific backup file from Google Drive.
  Future<void> deleteBackupFile(GoogleDriveFile file) async {
    try {
      final token = await _ensureValidToken();
      await GoogleDriveService.deleteFile(token, fileId: file.id);
      await refreshBackups();
      state = state.copyWith(statusMessage: 'Deleted ${file.name}');
    } catch (e) {
      _log.e('Failed to delete file: $e');
      state = state.copyWith(errorMessage: 'Delete failed: $e');
    }
  }

  /// Toggles automatic background sync.
  Future<void> setAutoSync(
    bool enabled, {
    AutoSyncInterval? interval,
  }) async {
    final updated = state.account.copyWith(
      autoSyncEnabled: enabled,
      autoSyncInterval: interval ?? state.account.autoSyncInterval,
    );
    await _saveAccount(updated);
  }

  /// Silent background auto-sync check on app start or schedule.
  Future<void> checkAndRunScheduledSync() async {
    if (!state.isSignedIn || !state.account.autoSyncEnabled) return;

    final now = DateTime.now();
    final lastSync = state.account.lastSyncTimestamp;

    bool shouldSync = false;
    if (lastSync == null) {
      shouldSync = true;
    } else {
      switch (state.account.autoSyncInterval) {
        case AutoSyncInterval.disabled:
          shouldSync = false;
        case AutoSyncInterval.onAppStart:
          shouldSync = true;
        case AutoSyncInterval.every6Hours:
          shouldSync = now.difference(lastSync).inHours >= 6;
        case AutoSyncInterval.daily:
          shouldSync = now.difference(lastSync).inHours >= 24;
      }
    }

    if (shouldSync) {
      _log.i('Running background auto-sync to Google Drive...');
      try {
        await backupNow(notify: false);
      } catch (e) {
        _log.w('Scheduled background sync failed: $e');
      }
    }
  }
}
