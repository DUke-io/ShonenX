import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/torrent_release.dart';

class AnimeToshoScraper {
  static const String _baseUrl = 'https://animetosho.org/api/v1/search';
  static final _log = AppLogger.scope('AnimeToshoScraper');

  /// Searches AnimeTosho for torrent releases matching query and/or anilist ID.
  static Future<List<TorrentRelease>> search({
    required String query,
    String? anilistId,
    int? episodeNumber,
  }) async {
    try {
      final queryParams = <String, String>{
        'order': 'seeders_desc',
      };

      String cleanQuery = query.trim();
      if (episodeNumber != null) {
        final epPadded = episodeNumber < 10 ? '0$episodeNumber' : '$episodeNumber';
        cleanQuery = '$cleanQuery $epPadded';
      }

      queryParams['q'] = cleanQuery;
      if (anilistId != null && anilistId.isNotEmpty) {
        queryParams['aid'] = anilistId;
      }

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      _log.i('Querying AnimeTosho: $uri');

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'KuroX-Client/2.1 (AnimeToshoScraper)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        _log.w('AnimeTosho returned status: ${response.statusCode}');
        return [];
      }

      final List<dynamic> data = jsonDecode(response.body);
      final List<TorrentRelease> releases = [];

      for (final item in data) {
        if (item is! Map<String, dynamic>) continue;

        final title = item['title'] as String? ?? '';
        final magnetUri = item['magnet_uri'] as String? ?? '';
        String infoHash = item['info_hash'] as String? ?? '';

        if (infoHash.isEmpty && magnetUri.isNotEmpty) {
          final match = RegExp(r'urn:btih:([a-zA-Z0-9]+)', caseSensitive: false)
              .firstMatch(magnetUri);
          if (match != null) {
            infoHash = match.group(1)!;
          }
        }

        if (infoHash.isEmpty && magnetUri.isEmpty) continue;

        final sizeBytes = (item['total_size'] as num?)?.toInt() ?? 0;
        final seeders = (item['seeders'] as num?)?.toInt() ?? 0;
        final leechers = (item['leechers'] as num?)?.toInt() ?? 0;
        final torrentUrl = item['torrent_url'] as String?;

        // Extract metadata from title
        final resolution = _parseResolution(title);
        final group = _parseReleaseGroup(title);
        final isDualAudio = RegExp(
          r'dual[- ]?audio|multi[- ]?audio|flac',
          caseSensitive: false,
        ).hasMatch(title);
        final isBatch = RegExp(
          r'batch|01[-~]\d+|complete',
          caseSensitive: false,
        ).hasMatch(title);

        releases.add(
          TorrentRelease(
            title: title,
            magnet: magnetUri.isNotEmpty
                ? magnetUri
                : 'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}',
            infoHash: infoHash.toLowerCase(),
            torrentUrl: torrentUrl,
            sizeBytes: sizeBytes,
            seeders: seeders,
            leechers: leechers,
            resolution: resolution,
            releaseGroup: group,
            isDualAudio: isDualAudio,
            isBatch: isBatch,
            source: 'AnimeTosho',
          ),
        );
      }

      _log.i('AnimeTosho found ${releases.length} releases for "$cleanQuery"');
      return releases;
    } catch (e, st) {
      _log.e('Failed to scrape AnimeTosho', e, st);
      return [];
    }
  }

  static String _parseResolution(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k')) return '2160p';
    if (lower.contains('1080p')) return '1080p';
    if (lower.contains('720p')) return '720p';
    if (lower.contains('480p')) return '480p';
    return '1080p';
  }

  static String _parseReleaseGroup(String title) {
    final match = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
    if (match != null) return match.group(1)!.trim();
    return 'Unknown';
  }
}
