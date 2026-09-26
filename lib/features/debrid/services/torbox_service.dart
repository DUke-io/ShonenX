import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/debrid_config.dart';

class TorboxService {
  static const String _baseUrl = 'https://api.torbox.app/v1/api';
  static final _log = AppLogger.scope('TorboxService');

  static Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
      };

  static Future<DebridAccountInfo> verifyAccount(String apiKey) async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/user/me'), headers: _headers(apiKey))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final detail = data['data'] as Map<String, dynamic>? ?? {};
        final email = detail['email'] as String? ?? 'User';
        final plan = (detail['plan'] as num?)?.toInt() ?? 0;
        final isPremium = plan > 0;
        final expStr = detail['premium_expires_at'] as String?;

        DateTime? expDate;
        if (expStr != null && expStr.isNotEmpty) {
          expDate = DateTime.tryParse(expStr);
        }

        return DebridAccountInfo(
          username: email.split('@').first,
          email: email,
          type: isPremium ? 'premium' : 'free',
          expirationDate: expDate,
        );
      } else {
        throw Exception('Torbox API error: ${res.statusCode}');
      }
    } catch (e, st) {
      _log.e('Failed to verify Torbox account', e, st);
      rethrow;
    }
  }

  static Future<String?> resolveMagnetStream(
    String apiKey,
    String magnet, {
    int? episodeNumber,
  }) async {
    try {
      _log.i('Adding magnet to Torbox...');
      final addRes = await http.post(
        Uri.parse('$_baseUrl/torrents/createtorrent'),
        headers: _headers(apiKey),
        body: {'magnet': magnet},
      ).timeout(const Duration(seconds: 12));

      if (addRes.statusCode != 200) return null;

      final data = jsonDecode(addRes.body) as Map<String, dynamic>;
      final torrentData = data['data'] as Map<String, dynamic>?;
      final torrentId = torrentData?['torrent_id'];

      if (torrentId == null) return null;

      final reqDlUrl = Uri.parse(
        '$_baseUrl/torrents/requestdl?token=$apiKey&torrent_id=$torrentId&zip=false',
      );
      final dlRes = await http.get(reqDlUrl).timeout(const Duration(seconds: 10));

      if (dlRes.statusCode == 200) {
        final dlData = jsonDecode(dlRes.body) as Map<String, dynamic>;
        return dlData['data'] as String?;
      }
      return null;
    } catch (e, st) {
      _log.e('Torbox stream resolution error', e, st);
      return null;
    }
  }
}
