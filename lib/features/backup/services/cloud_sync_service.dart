import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/services/backup_service.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/backup/domain/models/cloud_sync_config.dart';

class CloudSyncService {
  static final _log = AppLogger.scope('CloudSyncService');

  /// Tests cloud credentials and returns account/connection label.
  static Future<String> testConnection(CloudSyncConfig config) async {
    switch (config.providerType) {
      case CloudSyncProviderType.webdav:
        return _testWebDav(config);
      case CloudSyncProviderType.githubGist:
        return _testGitHubGist(config);
      case CloudSyncProviderType.disabled:
        throw Exception('Cloud sync is disabled');
    }
  }

  static Future<String> _testWebDav(CloudSyncConfig config) async {
    final cleanUrl = config.webdavUrl.endsWith('/')
        ? config.webdavUrl.substring(0, config.webdavUrl.length - 1)
        : config.webdavUrl;
    final uri = Uri.parse(cleanUrl);

    final basicAuth =
        'Basic ${base64Encode(utf8.encode("${config.webdavUsername}:${config.webdavPassword}"))}';

    final res = await http.get(
      uri,
      headers: {
        'Authorization': basicAuth,
        'User-Agent': 'KuroX-CloudSync/2.1',
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200 ||
        res.statusCode == 207 ||
        res.statusCode == 404 ||
        res.statusCode == 301 ||
        res.statusCode == 302) {
      return 'WebDAV Connected (${config.webdavUsername})';
    } else {
      throw Exception('WebDAV authentication failed (HTTP ${res.statusCode})');
    }
  }

  static Future<String> _testGitHubGist(CloudSyncConfig config) async {
    final res = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: {
        'Authorization': 'Bearer ${config.gistToken.trim()}',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'KuroX-CloudSync/2.1',
      },
    ).timeout(const Duration(seconds: 10));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final login = data['login'] as String? ?? 'GitHub User';
      return 'Connected to GitHub Gist (@$login)';
    } else {
      throw Exception('Invalid GitHub Personal Access Token (HTTP ${res.statusCode})');
    }
  }

  /// Uploads serialized backup JSON to the configured cloud provider.
  /// Returns updated Gist ID if created.
  static Future<String?> uploadManifest(
    CloudSyncConfig config,
    String jsonContent,
  ) async {
    switch (config.providerType) {
      case CloudSyncProviderType.webdav:
        await _uploadWebDav(config, jsonContent);
        return null;
      case CloudSyncProviderType.githubGist:
        return await _uploadGitHubGist(config, jsonContent);
      case CloudSyncProviderType.disabled:
        return null;
    }
  }

  static Future<void> _uploadWebDav(
    CloudSyncConfig config,
    String jsonContent,
  ) async {
    final cleanUrl = config.webdavUrl.endsWith('/')
        ? config.webdavUrl
        : '${config.webdavUrl}/';
    final targetUri = Uri.parse('$cleanUrl${config.webdavFilePath}');

    final basicAuth =
        'Basic ${base64Encode(utf8.encode("${config.webdavUsername}:${config.webdavPassword}"))}';

    _log.i('Uploading backup to WebDAV: $targetUri');
    final res = await http.put(
      targetUri,
      headers: {
        'Authorization': basicAuth,
        'Content-Type': 'application/json',
        'User-Agent': 'KuroX-CloudSync/2.1',
      },
      body: utf8.encode(jsonContent),
    ).timeout(const Duration(seconds: 20));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      _log.i('WebDAV upload succeeded (HTTP ${res.statusCode})');
    } else {
      throw Exception('WebDAV upload failed (HTTP ${res.statusCode}): ${res.body}');
    }
  }

  static Future<String> _uploadGitHubGist(
    CloudSyncConfig config,
    String jsonContent,
  ) async {
    final token = config.gistToken.trim();
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'KuroX-CloudSync/2.1',
      'Content-Type': 'application/json',
    };

    final payload = {
      'description': 'KuroX Automated Cloud Sync Backup',
      'public': false,
      'files': {
        'kurox_backup.json': {'content': jsonContent},
      },
    };

    if (config.gistId.isNotEmpty) {
      // Update existing Gist
      _log.i('Updating existing GitHub Gist ${config.gistId}...');
      final patchUrl = Uri.parse('https://api.github.com/gists/${config.gistId}');
      final res = await http.patch(
        patchUrl,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        _log.i('Gist updated successfully');
        return config.gistId;
      }
    }

    // Create new Gist if none exists or patch failed
    _log.i('Creating new private GitHub Gist...');
    final postUrl = Uri.parse('https://api.github.com/gists');
    final res = await http.post(
      postUrl,
      headers: headers,
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newGistId = data['id'] as String;
      _log.i('Created private Gist with ID: $newGistId');
      return newGistId;
    } else {
      throw Exception('GitHub Gist creation failed (HTTP ${res.statusCode}): ${res.body}');
    }
  }

  /// Downloads and parses the remote BackupManifest from the configured cloud.
  static Future<BackupManifest?> downloadManifest(CloudSyncConfig config) async {
    switch (config.providerType) {
      case CloudSyncProviderType.webdav:
        return await _downloadWebDav(config);
      case CloudSyncProviderType.githubGist:
        return await _downloadGitHubGist(config);
      case CloudSyncProviderType.disabled:
        return null;
    }
  }

  static Future<BackupManifest?> _downloadWebDav(CloudSyncConfig config) async {
    final cleanUrl = config.webdavUrl.endsWith('/')
        ? config.webdavUrl
        : '${config.webdavUrl}/';
    final targetUri = Uri.parse('$cleanUrl${config.webdavFilePath}');

    final basicAuth =
        'Basic ${base64Encode(utf8.encode("${config.webdavUsername}:${config.webdavPassword}"))}';

    _log.i('Downloading backup from WebDAV: $targetUri');
    final res = await http.get(
      targetUri,
      headers: {
        'Authorization': basicAuth,
        'Accept': 'application/json',
        'User-Agent': 'KuroX-CloudSync/2.1',
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final jsonStr = utf8.decode(res.bodyBytes);
      return BackupManifest.fromJson(jsonStr);
    } else if (res.statusCode == 404) {
      _log.i('No existing backup found on WebDAV server (HTTP 404)');
      return null;
    } else {
      throw Exception('WebDAV download failed (HTTP ${res.statusCode})');
    }
  }

  static Future<BackupManifest?> _downloadGitHubGist(CloudSyncConfig config) async {
    if (config.gistId.isEmpty) return null;

    final token = config.gistToken.trim();
    final url = Uri.parse('https://api.github.com/gists/${config.gistId}');

    _log.i('Downloading backup from GitHub Gist ${config.gistId}...');
    final res = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'KuroX-CloudSync/2.1',
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final files = data['files'] as Map<String, dynamic>? ?? {};
      final backupFile = files['kurox_backup.json'] as Map<String, dynamic>?;
      final content = backupFile?['content'] as String?;

      if (content != null && content.isNotEmpty) {
        return BackupManifest.fromJson(content);
      }
    }
    return null;
  }
}
