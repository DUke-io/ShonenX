import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/core/utils/env.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_file.dart';
import 'package:shonenx/features/sync/domain/models/google_drive_folder.dart';

class GoogleDriveService {
  static final _log = AppLogger.scope('GoogleDriveService');
  static const _authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _userinfoEndpoint = 'https://www.googleapis.com/oauth2/v2/userinfo';
  static const _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';
  static const _driveApiBase = 'https://www.googleapis.com/drive/v3';
  static const _uploadApiBase = 'https://www.googleapis.com/upload/drive/v3/files';

  static const List<String> driveScopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
    'https://www.googleapis.com/auth/userinfo.profile',
    'https://www.googleapis.com/auth/userinfo.email',
  ];

  static String getEffectiveClientId(String? customClientId) {
    if (customClientId != null && customClientId.trim().isNotEmpty) {
      return customClientId.trim();
    }
    return Env.GOOGLE_CLIENT_ID;
  }

  static String getEffectiveClientSecret(String? customClientSecret) {
    if (customClientSecret != null && customClientSecret.trim().isNotEmpty) {
      return customClientSecret.trim();
    }
    return Env.GOOGLE_CLIENT_SECRET;
  }

  static String generateCodeVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(64, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static Future<String> generateCodeChallenge(String verifier) async {
    final sha256 = Sha256();
    final hash = await sha256.hash(ascii.encode(verifier));
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  static String buildAuthUri({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
  }) {
    final queryParams = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': driveScopes.join(' '),
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    };

    final uri = Uri.parse(_authEndpoint).replace(queryParameters: queryParams);
    return uri.toString();
  }

  /// Starts a temporary local HTTP loopback server to capture OAuth redirect code on desktop.
  static Future<({HttpServer server, String redirectUri, Future<String> codeFuture})>
      startDesktopOAuthServer() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final redirectUri = 'http://127.0.0.1:$port';

    final completer = Completer<String>();

    server.listen((HttpRequest request) async {
      try {
        final queryParams = request.uri.queryParameters;
        final code = queryParams['code'];
        final error = queryParams['error'];

        if (code != null) {
          request.response.headers.contentType = ContentType.html;
          request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>KuroX - Google Drive Connected</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #0d1117;
      color: #e6edf3;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #161b22;
      border: 1px solid #30363d;
      border-radius: 12px;
      padding: 32px 48px;
      text-align: center;
      box-shadow: 0 8px 24px rgba(0,0,0,0.5);
    }
    h2 { color: #58a6ff; margin-bottom: 8px; }
    p { color: #8b949e; font-size: 14px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>✓ Google Drive Connected</h2>
    <p>Authentication complete. You can close this window and return to KuroX.</p>
  </div>
</body>
</html>
''');
          await request.response.close();
          if (!completer.isCompleted) completer.complete(code);
        } else if (error != null) {
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html><body><h3>Login Failed: $error</h3></body></html>');
          await request.response.close();
          if (!completer.isCompleted) completer.completeError(Exception('Google OAuth Error: $error'));
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    return (
      server: server,
      redirectUri: redirectUri,
      codeFuture: completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          server.close(force: true);
          throw TimeoutException('Google Sign-In timed out after 5 minutes');
        },
      ),
    );
  }

  /// Exchanges the authorization code for access and refresh tokens.
  static Future<Map<String, dynamic>> exchangeCodeForTokens({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    required String clientId,
    String? clientSecret,
  }) async {
    final body = {
      'code': code,
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
      'code_verifier': codeVerifier,
    };
    if (clientSecret != null && clientSecret.isNotEmpty) {
      body['client_secret'] = clientSecret;
    }

    _log.i('Exchanging auth code with Google token endpoint...');
    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      _log.e('Token exchange failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to obtain Google tokens: ${response.body}');
    }
  }

  /// Refreshes the access token using the stored refresh token.
  static Future<Map<String, dynamic>> refreshAccessToken({
    required String refreshToken,
    required String clientId,
    String? clientSecret,
  }) async {
    final body = {
      'refresh_token': refreshToken,
      'client_id': clientId,
      'grant_type': 'refresh_token',
    };
    if (clientSecret != null && clientSecret.isNotEmpty) {
      body['client_secret'] = clientSecret;
    }

    _log.i('Refreshing Google Drive access token...');
    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      _log.e('Token refresh failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to refresh Google token: ${response.body}');
    }
  }

  /// Fetches Google User Profile (email, name, picture).
  static Future<Map<String, dynamic>> fetchUserProfile(String accessToken) async {
    final res = await http.get(
      Uri.parse(_userinfoEndpoint),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to fetch Google profile (HTTP ${res.statusCode})');
    }
  }

  /// Revokes an access/refresh token.
  static Future<void> revokeToken(String token) async {
    try {
      await http.post(
        Uri.parse('$_revokeEndpoint?token=$token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      );
    } catch (e) {
      _log.w('Revoke token error: $e');
    }
  }

  /// Lists folders in the user's Google Drive.
  static Future<List<GoogleDriveFolder>> listFolders(
    String accessToken, {
    String? query,
  }) async {
    final queryParts = [
      "mimeType = 'application/vnd.google-apps.folder'",
      "trashed = false",
    ];

    if (query != null && query.trim().isNotEmpty) {
      final safeQ = query.replaceAll("'", "\\'");
      queryParts.add("name contains '$safeQ'");
    }

    final uri = Uri.parse('$_driveApiBase/files').replace(queryParameters: {
      'q': queryParts.join(' and '),
      'fields': 'files(id, name, parents, modifiedTime)',
      'orderBy': 'name',
      'pageSize': '50',
    });

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? [];
      return files
          .map((f) => GoogleDriveFolder.fromJson(f as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to list Google Drive folders (HTTP ${res.statusCode})');
    }
  }

  /// Creates a new directory/folder in Google Drive.
  static Future<GoogleDriveFolder> createFolder(
    String accessToken, {
    required String folderName,
    String? parentFolderId,
  }) async {
    final body = <String, dynamic>{
      'name': folderName,
      'mimeType': 'application/vnd.google-apps.folder',
    };
    if (parentFolderId != null && parentFolderId.isNotEmpty) {
      body['parents'] = [parentFolderId];
    }

    final res = await http.post(
      Uri.parse('$_driveApiBase/files'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return GoogleDriveFolder.fromJson(json);
    } else {
      throw Exception('Failed to create Google Drive folder: ${res.body}');
    }
  }

  /// Finds an existing folder by name or creates it in the root.
  static Future<GoogleDriveFolder> findOrCreateFolder(
    String accessToken, {
    required String folderName,
  }) async {
    final folders = await listFolders(accessToken, query: folderName);
    for (final f in folders) {
      if (f.name.toLowerCase() == folderName.toLowerCase()) {
        return f;
      }
    }
    return createFolder(accessToken, folderName: folderName);
  }

  /// Uploads or overwrites a backup JSON file in the target directory.
  static Future<GoogleDriveFile> uploadBackup(
    String accessToken, {
    required String folderId,
    required String fileName,
    required String jsonContent,
    String? description,
  }) async {
    // 1. Check if file already exists in this folder
    final searchUri = Uri.parse('$_driveApiBase/files').replace(queryParameters: {
      'q': "'$folderId' in parents and name = '$fileName' and trashed = false",
      'fields': 'files(id, name)',
    });

    final searchRes = await http.get(
      searchUri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    String? existingFileId;
    if (searchRes.statusCode == 200) {
      final searchJson = jsonDecode(searchRes.body) as Map<String, dynamic>;
      final files = searchJson['files'] as List<dynamic>? ?? [];
      if (files.isNotEmpty) {
        existingFileId = files.first['id'] as String?;
      }
    }

    const boundary = 'kurox_boundary_multipart_sync';
    final metadata = <String, dynamic>{
      'name': fileName,
      'mimeType': 'application/json',
      'description': description ?? 'KuroX automated cloud backup',
    };
    if (existingFileId == null) {
      metadata['parents'] = [folderId];
    }

    final metadataHeader =
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(metadata)}\r\n';
    final mediaHeader =
        '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n';
    final footer = '\r\n--$boundary--';

    final bodyBytes = utf8.encode(metadataHeader) +
        utf8.encode(mediaHeader) +
        utf8.encode(jsonContent) +
        utf8.encode(footer);

    http.Response uploadRes;

    if (existingFileId != null) {
      // Update existing file
      final patchUri =
          Uri.parse('$_uploadApiBase/$existingFileId?uploadType=multipart&fields=id,name,size,modifiedTime,description');
      uploadRes = await http.patch(
        patchUri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': '${bodyBytes.length}',
        },
        body: bodyBytes,
      );
    } else {
      // Create new file
      final postUri =
          Uri.parse('$_uploadApiBase?uploadType=multipart&fields=id,name,size,modifiedTime,description');
      uploadRes = await http.post(
        postUri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
          'Content-Length': '${bodyBytes.length}',
        },
        body: bodyBytes,
      );
    }

    if (uploadRes.statusCode == 200 || uploadRes.statusCode == 201) {
      final json = jsonDecode(uploadRes.body) as Map<String, dynamic>;
      return GoogleDriveFile.fromJson(json);
    } else {
      _log.e('Upload backup failed: ${uploadRes.statusCode} - ${uploadRes.body}');
      throw Exception('Failed to save data to Google Drive: ${uploadRes.body}');
    }
  }

  /// Lists all backup files located in the selected folder.
  static Future<List<GoogleDriveFile>> listBackups(
    String accessToken, {
    required String folderId,
  }) async {
    final uri = Uri.parse('$_driveApiBase/files').replace(queryParameters: {
      'q': "'$folderId' in parents and trashed = false and (mimeType = 'application/json' or name contains 'backup' or name contains 'kurox')",
      'fields': 'files(id, name, size, modifiedTime, description)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '30',
    });

    final res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/json',
      },
    );

    if (res.statusCode == 200) {
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final files = json['files'] as List<dynamic>? ?? [];
      return files
          .map((f) => GoogleDriveFile.fromJson(f as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to list backups from Google Drive (HTTP ${res.statusCode})');
    }
  }

  /// Downloads raw JSON content of a backup file from Google Drive.
  static Future<String> downloadBackup(
    String accessToken, {
    required String fileId,
  }) async {
    final uri = Uri.parse('$_driveApiBase/files/$fileId?alt=media');
    final res = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (res.statusCode == 200) {
      return utf8.decode(res.bodyBytes);
    } else {
      throw Exception('Failed to download backup file (HTTP ${res.statusCode})');
    }
  }

  /// Deletes a file from Google Drive.
  static Future<void> deleteFile(
    String accessToken, {
    required String fileId,
  }) async {
    final uri = Uri.parse('$_driveApiBase/files/$fileId');
    final res = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to delete file from Google Drive: ${res.body}');
    }
  }
}
