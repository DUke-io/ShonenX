import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/debrid_config.dart';

class RealDebridService {
  static const String _baseUrl = 'https://api.real-debrid.com/rest/1.0';
  static final _log = AppLogger.scope('RealDebridService');

  static Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      };

  /// Verifies API key and retrieves account details.
  static Future<DebridAccountInfo> verifyAccount(String apiKey) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/user'), headers: _headers(apiKey))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final username = data['username'] as String? ?? 'User';
        final email = data['email'] as String? ?? '';
        final type = data['type'] as String? ?? 'free';
        final expStr = data['expiration'] as String?;
        final points = (data['points'] as num?)?.toInt() ?? 0;

        DateTime? expDate;
        if (expStr != null && expStr.isNotEmpty) {
          expDate = DateTime.tryParse(expStr);
        }

        return DebridAccountInfo(
          username: username,
          email: email,
          type: type,
          expirationDate: expDate,
          points: points,
        );
      } else {
        throw Exception('Real-Debrid API error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      _log.e('Failed to verify Real-Debrid account', e, st);
      rethrow;
    }
  }

  /// Checks which torrent info-hashes are already 100% cached on Real-Debrid servers.
  static Future<Map<String, bool>> checkInstantAvailability(
    String apiKey,
    List<String> hashes,
  ) async {
    if (hashes.isEmpty) return {};
    try {
      final joined = hashes.take(50).join('/');
      final res = await http
          .get(
            Uri.parse('$_baseUrl/torrents/instantAvailability/$joined'),
            headers: _headers(apiKey),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final Map<String, bool> result = {};

        for (final hash in hashes) {
          final entry = data[hash.toLowerCase()];
          if (entry != null && entry is Map && entry.containsKey('rd')) {
            final rdList = entry['rd'];
            if (rdList is List && rdList.isNotEmpty) {
              result[hash.toLowerCase()] = true;
              continue;
            }
          }
          result[hash.toLowerCase()] = false;
        }
        return result;
      }
    } catch (e) {
      _log.w('Instant availability check failed: $e');
    }
    return {};
  }

  /// Adds a magnet to Real-Debrid, selects video files, un-restricts the link,
  /// and returns the direct high-speed CDN streaming URL.
  static Future<String?> resolveMagnetStream(
    String apiKey,
    String magnet, {
    int? episodeNumber,
  }) async {
    try {
      _log.i('Adding magnet to Real-Debrid...');
      // 1. Add Magnet
      final addRes = await http.post(
        Uri.parse('$_baseUrl/torrents/addMagnet'),
        headers: _headers(apiKey),
        body: {'magnet': magnet},
      ).timeout(const Duration(seconds: 12));

      if (addRes.statusCode != 201 && addRes.statusCode != 200) {
        _log.e('Failed to add magnet: ${addRes.body}');
        return null;
      }

      final addData = jsonDecode(addRes.body) as Map<String, dynamic>;
      final torrentId = addData['id'] as String;

      // 2. Query torrent info to get file IDs
      final infoRes = await http.get(
        Uri.parse('$_baseUrl/torrents/info/$torrentId'),
        headers: _headers(apiKey),
      ).timeout(const Duration(seconds: 10));

      if (infoRes.statusCode != 200) {
        _log.e('Failed to get torrent info: ${infoRes.body}');
        return null;
      }

      final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
      final files = infoData['files'] as List<dynamic>? ?? [];

      String fileSelection = 'all';
      if (files.isNotEmpty) {
        // Find largest video file or matching episode number
        dynamic bestFile;
        int maxBytes = 0;

        for (final f in files) {
          final path = (f['path'] as String? ?? '').toLowerCase();
          final bytes = (f['bytes'] as num?)?.toInt() ?? 0;
          final isVideo = path.endsWith('.mkv') ||
              path.endsWith('.mp4') ||
              path.endsWith('.avi');

          if (!isVideo) continue;

          if (episodeNumber != null) {
            final epStr = episodeNumber < 10 ? '0$episodeNumber' : '$episodeNumber';
            if (path.contains('e$epStr') ||
                path.contains('-$epStr') ||
                path.contains(' $epStr ') ||
                path.contains(' $epStr.')) {
              bestFile = f;
              break;
            }
          }

          if (bytes > maxBytes) {
            maxBytes = bytes;
            bestFile = f;
          }
        }

        if (bestFile != null && bestFile['id'] != null) {
          fileSelection = bestFile['id'].toString();
        }
      }

      // 3. Select Files
      await http.post(
        Uri.parse('$_baseUrl/torrents/selectFiles/$torrentId'),
        headers: _headers(apiKey),
        body: {'files': fileSelection},
      ).timeout(const Duration(seconds: 10));

      // 4. Poll torrent status (up to 3 times for cached items)
      List<dynamic> links = [];
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 600));
        final pollRes = await http.get(
          Uri.parse('$_baseUrl/torrents/info/$torrentId'),
          headers: _headers(apiKey),
        );
        if (pollRes.statusCode == 200) {
          final pollData = jsonDecode(pollRes.body) as Map<String, dynamic>;
          final status = pollData['status'] as String? ?? '';
          links = pollData['links'] as List<dynamic>? ?? [];
          if (status == 'downloaded' && links.isNotEmpty) {
            break;
          }
        }
      }

      if (links.isEmpty) {
        _log.w('Torrent is not instantly cached or has no unrestricted links.');
        return null;
      }

      // 5. Unrestrict the first link
      final targetLink = links.first.toString();
      _log.i('Unrestricting link: $targetLink');

      final unrestrictRes = await http.post(
        Uri.parse('$_baseUrl/unrestrict/link'),
        headers: _headers(apiKey),
        body: {'link': targetLink},
      ).timeout(const Duration(seconds: 12));

      if (unrestrictRes.statusCode == 200) {
        final unrestrictData =
            jsonDecode(unrestrictRes.body) as Map<String, dynamic>;
        final directDownloadUrl = unrestrictData['download'] as String?;
        _log.i('Unrestricted high-speed CDN stream URL obtained successfully');
        return directDownloadUrl;
      } else {
        _log.e('Failed to unrestrict link: ${unrestrictRes.body}');
        return null;
      }
    } catch (e, st) {
      _log.e('Error resolving Real-Debrid magnet stream', e, st);
      return null;
    }
  }
}
