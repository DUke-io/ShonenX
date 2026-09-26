import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/torrent_release.dart';

class NyaaScraper {
  static const String _baseUrl = 'https://nyaa.si/?page=rss&c=1_2&f=0';
  static final _log = AppLogger.scope('NyaaScraper');

  /// Searches Nyaa RSS feed for anime releases matching query.
  static Future<List<TorrentRelease>> search({
    required String query,
    int? episodeNumber,
  }) async {
    try {
      String cleanQuery = query.trim();
      if (episodeNumber != null) {
        final epPadded = episodeNumber < 10 ? '0$episodeNumber' : '$episodeNumber';
        cleanQuery = '$cleanQuery $epPadded';
      }

      final uri = Uri.parse('$_baseUrl&q=${Uri.encodeComponent(cleanQuery)}');
      _log.i('Querying Nyaa RSS: $uri');

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'KuroX-Client/2.1 (NyaaScraper)',
          'Accept': 'application/xml, text/xml',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        _log.w('Nyaa returned status: ${response.statusCode}');
        return [];
      }

      final document = html_parser.parse(response.body);
      final items = document.querySelectorAll('item');
      final List<TorrentRelease> releases = [];

      for (final item in items) {
        final title = item.querySelector('title')?.text.trim() ?? '';
        final link = item.querySelector('link')?.text.trim() ?? '';
        
        // infoHash is typically in <nyaa:infoHash> or queryable
        String infoHash = '';
        final hashElem = item.querySelector('infoHash') ??
            item.querySelector('nyaa\\:infohash') ??
            item.querySelector('infohash');
        if (hashElem != null) {
          infoHash = hashElem.text.trim();
        }

        final seedersStr = item.querySelector('seeders')?.text.trim() ?? '0';
        final leechersStr = item.querySelector('leechers')?.text.trim() ?? '0';
        final seeders = int.tryParse(seedersStr) ?? 0;
        final leechers = int.tryParse(leechersStr) ?? 0;

        if (title.isEmpty) continue;

        String magnet = '';
        if (infoHash.isNotEmpty) {
          magnet = 'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(title)}';
        } else if (link.startsWith('magnet:')) {
          magnet = link;
          final match = RegExp(r'urn:btih:([a-zA-Z0-9]+)', caseSensitive: false)
              .firstMatch(magnet);
          if (match != null) {
            infoHash = match.group(1)!;
          }
        }

        if (infoHash.isEmpty && magnet.isEmpty) continue;

        releases.add(
          TorrentRelease(
            title: title,
            magnet: magnet,
            infoHash: infoHash.toLowerCase(),
            seeders: seeders,
            leechers: leechers,
            resolution: _parseResolution(title),
            releaseGroup: _parseReleaseGroup(title),
            isDualAudio: RegExp(r'dual[- ]?audio|multi[- ]?audio', caseSensitive: false)
                .hasMatch(title),
            isBatch: RegExp(r'batch|complete', caseSensitive: false).hasMatch(title),
            source: 'Nyaa',
          ),
        );
      }

      _log.i('Nyaa found ${releases.length} releases for "$cleanQuery"');
      return releases;
    } catch (e, st) {
      _log.e('Failed to scrape Nyaa', e, st);
      return [];
    }
  }

  static String _parseResolution(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k')) return '2160p';
    if (lower.contains('1080p')) return '1080p';
    if (lower.contains('720p')) return '720p';
    return '1080p';
  }

  static String _parseReleaseGroup(String title) {
    final match = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
    if (match != null) return match.group(1)!.trim();
    return 'Unknown';
  }
}
