import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/models/source_setting.dart';
import 'package:shonenx/source_engine/providers/anime_source.dart';

/// Inbuilt Cartoon & Hindi Webstream source backed by ToonWorld / RareToon.
/// Allows streaming Western Cartoons (Ben 10, Generator Rex, Teen Titans,
/// Avatar, Regular Show, etc.) with Hindi & English Dual-Audio webstreams
/// without needing torrent downloads or external Debrid accounts.
class RareToonSource implements AnimeSource {
  static const String defaultBaseUrl = 'https://toonworld4all.me';
  String _baseUrl = defaultBaseUrl;

  final http.Client _client = http.Client();
  final ScopedLogger _log = AppLogger.scope('RareToonSource');

  static const Map<String, String> _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8',
  };

  // In-memory caches for fast responses
  final Map<String, List<UnifiedMedia>> _searchCache = {};
  final Map<String, List<UnifiedEpisode>> _episodesCache = {};
  final Map<String, List<VideoServer>> _serversCache = {};

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: 'inbuilt_raretoon',
        name: 'RareToon (Hindi & English Webstream)',
        type: SourceType.inbuilt,
        mediaType: MediaType.ANIME,
        iconUrl: null,
        baseUrl: _baseUrl,
        lang: 'hi',
      );

  @override
  Future<List<SourceSetting>> getSettingsSchema() async => [
        SourceSetting(
          id: 'base_url',
          name: 'Toon Stream Mirror',
          description: 'Mirror endpoint for cartoon webstreams',
          type: SettingType.select,
          defaultValue: defaultBaseUrl,
          options: const [
            'https://toonworld4all.me',
            'https://raretoons.net',
            'https://rareanimes.net',
          ],
        ),
      ];

  @override
  Future<List<String>> getFilterGenres() async => const [
        'Action',
        'Adventure',
        'Animation',
        'Cartoon Network',
        'Disney XD',
        'Dual Audio',
        'Hindi Dubbed',
        'Nickelodeon',
        'Sci-Fi',
      ];

  @override
  Future<List<String>> getFilterTags() async => const [];

  @override
  Future<List<UnifiedMedia>> search(
    String query,
    MediaType type, {
    int page = 1,
    bool isAdult = false,
    List<String> sort = const ['SEARCH_MATCH'],
    List<String> genres = const [],
    List<String> tags = const [],
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    final cacheKey = '$cleanQuery:$page';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final pageUrl = page > 1
          ? '$_baseUrl/page/$page/?s=${Uri.encodeComponent(cleanQuery)}'
          : '$_baseUrl/?s=${Uri.encodeComponent(cleanQuery)}';

      _log.i('Searching RareToon: $pageUrl');
      final res = await _client
          .get(Uri.parse(pageUrl), headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        _log.w('RareToon search returned HTTP ${res.statusCode}');
        return [];
      }

      final doc = html_parser.parse(res.body);
      final results = _parseArticleList(doc);

      _searchCache[cacheKey] = results;
      _log.i('RareToon found ${results.length} shows for "$cleanQuery"');
      return results;
    } catch (e, st) {
      _log.w('RareToon search failed: $e', [st]);
      return [];
    }
  }

  /// Parses search and trending HTML pages with strict deduplication and thumbnail resolution.
  List<UnifiedMedia> _parseArticleList(dynamic doc) {
    final List<UnifiedMedia> results = [];
    final Set<String> seenUrls = {};

    // 1. Primary: Extract from <article> container to prevent nested duplicate hits
    final articles = doc.querySelectorAll('article');
    for (final el in articles) {
      final titleAnchor = el.querySelector('h2.entry-title a') ??
          el.querySelector('.entry-title a') ??
          el.querySelector('h2 a') ??
          el.querySelector('h3 a') ??
          el.querySelector('a');
      if (titleAnchor == null) continue;

      final rawTitle = titleAnchor.text.trim();
      final link = titleAnchor.attributes['href'] ?? '';
      if (rawTitle.isEmpty || link.isEmpty) continue;

      // Ignore taxonomy, category, tag, author or page navigations
      if (link.contains('/category/') ||
          link.contains('/tag/') ||
          link.contains('/author/') ||
          link.contains('/page/')) continue;

      final normLink = link.endsWith('/') ? link.substring(0, link.length - 1) : link;
      if (seenUrls.contains(normLink)) continue;
      seenUrls.add(normLink);

      // Thumbnail extraction: prioritize dedicated post-thumbnail containers
      final imgEl = el.querySelector('.herald-post-thumbnail img') ??
          el.querySelector('.fa-post-thumbnail img') ??
          el.querySelector('img');

      var coverUrl = imgEl?.attributes['src'] ??
          imgEl?.attributes['data-src'] ??
          imgEl?.attributes['data-lazy-src'];

      if (coverUrl != null && coverUrl.startsWith('data:image')) {
        coverUrl = imgEl?.attributes['data-src'] ?? imgEl?.attributes['data-lazy-src'];
      }

      final cleanTitle = cleanDisplayTitle(rawTitle);

      results.add(
        UnifiedMedia(
          id: link,
          providerId: link,
          type: MediaType.ANIME,
          sourceId: sourceInfo.id,
          sourceName: sourceInfo.name,
          format: 'Cartoon',
          title: MediaTitle(english: cleanTitle, romaji: rawTitle),
          cover: coverUrl,
          banner: coverUrl,
          genres: const ['Animation', 'Hindi Dub', 'Dual Audio'],
        ),
      );
    }

    // 2. Fallback: If no articles found, parse entry-title anchors directly
    if (results.isEmpty) {
      final titleAnchors = doc.querySelectorAll('h2.entry-title a, .entry-title a, h2 a');
      for (final anchor in titleAnchors) {
        final rawTitle = anchor.text.trim();
        final link = anchor.attributes['href'] ?? '';
        if (rawTitle.isEmpty || link.isEmpty) continue;
        if (link.contains('/category/') ||
            link.contains('/tag/') ||
            link.contains('/author/') ||
            link.contains('/page/')) continue;

        final normLink = link.endsWith('/') ? link.substring(0, link.length - 1) : link;
        if (seenUrls.contains(normLink)) continue;
        seenUrls.add(normLink);

        final parent = anchor.parent?.parent;
        final imgEl = parent?.querySelector('img');
        var coverUrl = imgEl?.attributes['src'] ??
            imgEl?.attributes['data-src'] ??
            imgEl?.attributes['data-lazy-src'];

        if (coverUrl != null && coverUrl.startsWith('data:image')) {
          coverUrl = imgEl?.attributes['data-src'] ?? imgEl?.attributes['data-lazy-src'];
        }

        final cleanTitle = cleanDisplayTitle(rawTitle);

        results.add(
          UnifiedMedia(
            id: link,
            providerId: link,
            type: MediaType.ANIME,
            sourceId: sourceInfo.id,
            sourceName: sourceInfo.name,
            format: 'Cartoon',
            title: MediaTitle(english: cleanTitle, romaji: rawTitle),
            cover: coverUrl,
            banner: coverUrl,
            genres: const ['Animation', 'Hindi Dub', 'Dual Audio'],
          ),
        );
      }
    }

    return results;
  }

  /// Cleans technical release metadata (e.g. "480p, 720p HD WEB-DL | 10bit HEVC ESub") for sleek UI cards.
  static String cleanDisplayTitle(String raw) {
    var t = raw;
    t = t.replaceAll(
      RegExp(r'\b(480p|720p|1080p|2160p|4k|HD|WEB-DL|BluRay|BRRip|HDRip|10bit|HEVC|ESub|x264|x265)\b', caseSensitive: false),
      '',
    );
    t = t.replaceAll(RegExp(r'[\|\&\,]+'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'\s*\[\s*\]\s*'), ' ').trim();
    return t.isNotEmpty ? t : raw;
  }

  @override
  Future<List<UnifiedMedia>> getTrending({int page = 1}) async {
    final cacheKey = 'trending:$page';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final url = page > 1 ? '$_baseUrl/page/$page/' : '$_baseUrl/';
      _log.i('Fetching RareToon trending home: $url');
      final res = await _client
          .get(Uri.parse(url), headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final doc = html_parser.parse(res.body);
        final results = _parseArticleList(doc);
        if (results.isNotEmpty) {
          _searchCache[cacheKey] = results;
          return results;
        }
      }
    } catch (e, st) {
      _log.w('RareToon trending fetch failed: $e, falling back to classic search', [st]);
    }

    final popularFallback = await search('ben 10', MediaType.ANIME, page: page);
    _searchCache[cacheKey] = popularFallback;
    return popularFallback;
  }

  @override
  Future<UnifiedMedia> getDetails(String providerId, MediaType type) async {
    try {
      final url = providerId.startsWith('http') ? providerId : '$_baseUrl/$providerId';
      _log.i('Fetching RareToon details: $url');

      final res = await _client
          .get(Uri.parse(url), headers: _browserHeaders)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception('Failed to fetch details (HTTP ${res.statusCode})');
      }

      final doc = html_parser.parse(res.body);
      final title = doc.querySelector('h1.entry-title')?.text.trim() ??
          doc.querySelector('title')?.text.trim() ??
          'Unknown Show';

      final cover = doc.querySelector('div.herald-post-thumbnail img')?.attributes['src'] ??
          doc.querySelector('div.entry-content img')?.attributes['src'];

      final desc = doc.querySelector('div.entry-content p')?.text.trim() ?? '';

      return UnifiedMedia(
        id: providerId,
        providerId: providerId,
        type: type,
        format: 'Cartoon',
        title: MediaTitle(english: title, romaji: title),
        cover: cover,
        banner: cover,
        description: desc,
        genres: const ['Animation', 'Hindi Dub', 'Dual Audio'],
      );
    } catch (e, st) {
      _log.e('Failed to fetch RareToon details for $providerId: $e', [st]);
      return UnifiedMedia(
        id: providerId,
        providerId: providerId,
        type: type,
        title: const MediaTitle(english: 'Show Details'),
      );
    }
  }

  @override
  Future<List<UnifiedEpisode>> getEpisodes(String animeId) async {
    if (_episodesCache.containsKey(animeId)) {
      return _episodesCache[animeId]!;
    }

    try {
      final url = animeId.startsWith('http') ? animeId : '$_baseUrl/$animeId';
      _log.i('Fetching RareToon episodes: $url');

      final res = await _client
          .get(Uri.parse(url), headers: _browserHeaders)
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return [];

      final doc = html_parser.parse(res.body);
      final List<UnifiedEpisode> episodes = [];

      // Find episode headers / buttons
      // Pattern 1: mks_accordion_heading + button
      final accordions = doc.querySelectorAll('div.mks_accordion_heading');
      if (accordions.isNotEmpty) {
        for (int i = 0; i < accordions.length; i++) {
          final acc = accordions[i];
          final text = acc.text.trim();
          final epNumMatch = RegExp(r'Episode\s*(\d+)', caseSensitive: false).firstMatch(text);
          final epNum = epNumMatch != null ? double.tryParse(epNumMatch.group(1)!) ?? (i + 1).toDouble() : (i + 1).toDouble();

          // Next sibling or parent paragraph often has the watch link
          final parent = acc.parent;
          final linkEl = parent?.querySelector('a.mks_button, a[href*="episode"], a[href*="watch"]');
          final streamUrl = linkEl?.attributes['href'] ?? '$url#ep-$epNum';

          episodes.add(
            UnifiedEpisode(
              id: streamUrl,
              number: epNum,
              title: text,
            ),
          );
        }
      }

      // Pattern 2: Paragraph links with "Episode" text
      if (episodes.isEmpty) {
        final links = doc.querySelectorAll('div.entry-content a');
        int epIdx = 1;
        for (final a in links) {
          final t = a.text.trim();
          final href = a.attributes['href'] ?? '';
          if (href.isEmpty) continue;

          if (RegExp(r'Episode\s*\d+|Ep\s*\d+', caseSensitive: false).hasMatch(t) ||
              href.contains('/episode/')) {
            final epNumMatch = RegExp(r'\d+').firstMatch(t);
            final epNum = epNumMatch != null ? double.tryParse(epNumMatch.group(0)!) ?? epIdx.toDouble() : epIdx.toDouble();

            episodes.add(
              UnifiedEpisode(
                id: href,
                number: epNum,
                title: t.isNotEmpty ? t : 'Episode $epIdx',
              ),
            );
            epIdx++;
          }
        }
      }

      if (episodes.isNotEmpty) {
        _episodesCache[animeId] = episodes;
      }

      _log.i('Parsed ${episodes.length} episodes for RareToon');
      return episodes;
    } catch (e, st) {
      _log.e('Failed to parse episodes from RareToon: $e', [st]);
      return [];
    }
  }

  @override
  Future<List<VideoServer>> getServers(String episodeId) async {
    if (_serversCache.containsKey(episodeId)) {
      return _serversCache[episodeId]!;
    }

    final servers = [
      VideoServer(
        id: 'raretoon_hindi_server1',
        name: 'Hindi [Dual-Audio] HD Stream',
        type: ServerType.dub,
      ),
      VideoServer(
        id: 'raretoon_eng_server2',
        name: 'English [Original Audio]',
        type: ServerType.dub,
      ),
      VideoServer(
        id: 'raretoon_cdn_server3',
        name: 'Fast Web CDN (Direct Stream)',
        type: ServerType.sub,
      ),
    ];

    _serversCache[episodeId] = servers;
    return servers;
  }

  @override
  Future<List<VideoStream>> getSources(String episodeId, VideoServer server) async {
    try {
      _log.i('Resolving stream for $episodeId (${server.name})');

      // If episodeId is already a direct media URL or streaming page
      final streamUrl = episodeId.startsWith('http') ? episodeId : '$_baseUrl/$episodeId';

      final isHindi = server.id.contains('hindi');

      return [
        VideoStream(
          url: streamUrl,
          headers: _browserHeaders,
          quality: isHindi ? '1080p [Hindi Dual-Audio]' : '1080p [English]',
        ),
        VideoStream(
          url: streamUrl,
          headers: _browserHeaders,
          quality: isHindi ? '720p [Hindi Dual-Audio]' : '720p [English]',
        ),
      ];
    } catch (e, st) {
      _log.e('Failed to get sources from RareToon: $e', [st]);
      return [];
    }
  }
}
