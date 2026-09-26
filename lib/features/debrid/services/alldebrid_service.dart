import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/debrid_config.dart';

class AllDebridService {
  static const String _baseUrl = 'https://api.alldebrid.com/v4';
  static final _log = AppLogger.scope('AllDebridService');

  static Future<DebridAccountInfo> verifyAccount(String apiKey) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/user?agent=kurox&apikey=$apiKey'),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final user = data['data']?['user'] as Map<String, dynamic>? ?? {};
        final username = user['username'] as String? ?? 'User';
        final email = user['email'] as String? ?? '';
        final isPremium = user['isPremium'] as bool? ?? false;
        final premiumUntil = (user['premiumUntil'] as num?)?.toInt() ?? 0;

        DateTime? expDate;
        if (premiumUntil > 0) {
          expDate = DateTime.fromMillisecondsSinceEpoch(premiumUntil * 1000);
        }

        return DebridAccountInfo(
          username: username,
          email: email,
          type: isPremium ? 'premium' : 'free',
          expirationDate: expDate,
        );
      } else {
        throw Exception('AllDebrid API error: ${res.statusCode}');
      }
    } catch (e, st) {
      _log.e('Failed to verify AllDebrid account', e, st);
      rethrow;
    }
  }

  static Future<String?> resolveMagnetStream(
    String apiKey,
    String magnet, {
    int? episodeNumber,
  }) async {
    try {
      _log.i('Uploading magnet to AllDebrid...');
      final uploadUrl = Uri.parse(
        '$_baseUrl/magnet/upload?agent=kurox&apikey=$apiKey&magnets[]=${Uri.encodeComponent(magnet)}',
      );
      final uploadRes = await http.get(uploadUrl).timeout(const Duration(seconds: 12));

      if (uploadRes.statusCode != 200) return null;

      final data = jsonDecode(uploadRes.body) as Map<String, dynamic>;
      final magnets = data['data']?['magnets'] as List<dynamic>? ?? [];
      if (magnets.isEmpty) return null;

      final firstMagnet = magnets.first as Map<String, dynamic>;
      final torrentId = firstMagnet['id'];
      if (torrentId == null) return null;

      // Status check
      final statusUrl = Uri.parse(
        '$_baseUrl/magnet/status?agent=kurox&apikey=$apiKey&id=$torrentId',
      );
      final statusRes = await http.get(statusUrl);
      if (statusRes.statusCode == 200) {
        final sData = jsonDecode(statusRes.body) as Map<String, dynamic>;
        final links = sData['data']?['magnets']?['links'] as List<dynamic>? ?? [];
        if (links.isNotEmpty) {
          final firstLink = links.first['link'] as String?;
          if (firstLink != null) {
            // Unlock link
            final unlockUrl = Uri.parse(
              '$_baseUrl/link/unlock?agent=kurox&apikey=$apiKey&link=${Uri.encodeComponent(firstLink)}',
            );
            final unlockRes = await http.get(unlockUrl);
            if (unlockRes.statusCode == 200) {
              final uData = jsonDecode(unlockRes.body) as Map<String, dynamic>;
              return uData['data']?['link'] as String?;
            }
          }
        }
      }
      return null;
    } catch (e, st) {
      _log.e('AllDebrid stream resolution error', e, st);
      return null;
    }
  }
}
