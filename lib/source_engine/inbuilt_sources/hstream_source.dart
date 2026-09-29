import 'dart:async';
import 'dart:convert';
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

/// Inbuilt adult anime source backed by hstream.moe.
///
/// Flow:
///   1. Search  → POST /search with CSRF token + query
///   2. Details → GET /hentai/{slug} to parse episode list
///   3. Servers → static (single CDN server)
///   4. Sources → POST /player/api with episode_id → DASH manifests
///
/// This source runs alongside the primary HiAnime source. The user sees
/// both in the source picker – one for mainstream anime, one for 18+ content.
class HstreamSource implements AnimeSource {
  static const String _baseUrl = 'https://hstream.moe';

  final http.Client _client = http.Client();
  final ScopedLogger _log = AppLogger.scope('HstreamSource');

  // ─── Session state (lazy-refreshed) ───
  String? _csrfToken;
  String? _cookieHeader;
  DateTime? _sessionExpiry;

  // ─── In-memory caches ───
  final Map<String, List<UnifiedMedia>> _searchCache = {};
  final Map<String, List<UnifiedEpisode>> _episodesCache = {};

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: 'inbuilt_hstream',
        name: 'Hstream',
        type: SourceType.inbuilt,
        mediaType: MediaType.ANIME,
        iconUrl: null,
        baseUrl: _baseUrl,
        lang: 'en',
      );

  @override
  Future<List<SourceSetting>> getSettingsSchema() async => const [];

  @override
  Future<List<String>> getFilterGenres() async => const [
        'Ahegao',
        'Big Boobs',
        'Blowjob',
        'Comedy',
        'Creampie',
        'Drama',
        'Fantasy',
        'Harem',
        'Incest',
        'Milf',
        'NTR',
        'Romance',
        'School',
        'Vanilla',
      ];

  @override
  Future<List<String>> getFilterTags() async => const [];

  // ──────────────────────────── Session ────────────────────────────

  /// Ensures a valid CSRF token + session cookies exist.
  /// Tokens are lazily refreshed every 25 minutes.
  Future<void> _ensureSession() async {
    final now = DateTime.now();
    if (_csrfToken != null &&
        _sessionExpiry != null &&
        now.isBefore(_sessionExpiry!)) {
      return;
    }

    final log = _log.child('_ensureSession');
    log.d('Refreshing CSRF session…');

    try {
      final res = await _client
          .get(Uri.parse(_baseUrl), headers: _browserHeaders())
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        log.w('Home page returned ${res.statusCode}');
        return;
      }

      // Extract CSRF token from HTML
      final tokenMatch =
          RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(res.body);
      if (tokenMatch != null) {
        _csrfToken = tokenMatch.group(1);
      }

      // Collect cookies from response headers
      final rawCookies = res.headers['set-cookie'];
      if (rawCookies != null) {
        _cookieHeader = rawCookies
            .split(RegExp(r',(?=[A-Za-z_])'))
            .map((c) => c.split(';').first.trim())
            .join('; ');
      }

      _sessionExpiry = now.add(const Duration(minutes: 25));
      log.d('Session ready — token=${_csrfToken?.substring(0, 8)}…');
    } catch (e, st) {
      log.e('Session init failed: $e', e, st);
    }
  }

  Map<String, String> _browserHeaders({String? referer}) => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        if (_cookieHeader != null) 'Cookie': _cookieHeader!,
        if (referer != null) 'Referer': referer,
      };

  // ──────────────────────────── Search ─────────────────────────────

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
    final log = _log.child('search');
    final cacheKey = '$query|$page';
    if (_searchCache.containsKey(cacheKey)) return _searchCache[cacheKey]!;

    await _ensureSession();

    try {
      final body = '_token=${Uri.encodeComponent(_csrfToken ?? '')}'
          '&live-search=${Uri.encodeComponent(query)}';

      final res = await _client.post(
        Uri.parse('$_baseUrl/search'),
        headers: {
          ..._browserHeaders(referer: _baseUrl),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        log.w('Search returned ${res.statusCode}');
        return [];
      }

      final results = _parseSearchResults(res.body);
      _searchCache[cacheKey] = results;
      log.i('Search "$query" → ${results.length} results');
      return results;
    } catch (e, st) {
      log.e('Search error: $e', e, st);
      return [];
    }
  }

  List<UnifiedMedia> _parseSearchResults(String html) {
    final results = <UnifiedMedia>[];
    // Cards: <a href="https://hstream.moe/hentai/{slug}">...<img alt="Title" src="...">
    final cardPattern = RegExp(
      r'<a[^>]+href="https://hstream\.moe/hentai/([^"]+)"[^>]*>'
      r'[\s\S]*?'
      r'alt="([^"]*)"'
      r'[\s\S]*?'
      r'src="([^"]*)"'
      r'[\s\S]*?</a>',
      caseSensitive: false,
    );

    for (final match in cardPattern.allMatches(html)) {
      final slug = match.group(1) ?? '';
      final title = match.group(2) ?? slug;
      final thumb = match.group(3) ?? '';

      if (slug.isEmpty) continue;

      results.add(UnifiedMedia(
        id: slug,
        type: MediaType.ANIME,
        sourceId: sourceInfo.id,
        sourceName: sourceInfo.name,
        providerId: slug,
        title: MediaTitle(
          english: title,
          romaji: title,
        ),
        cover: thumb.startsWith('http') ? thumb : '$_baseUrl$thumb',
        isAdult: true,
        genres: const ['Hentai'],
      ));
    }

    return results;
  }

  // ──────────────────────────── Trending ───────────────────────────

  @override
  Future<List<UnifiedMedia>> getTrending({int page = 1}) async {
    // The homepage shows the latest releases — reuse as "trending"
    final log = _log.child('getTrending');
    await _ensureSession();

    try {
      final res = await _client
          .get(Uri.parse(_baseUrl), headers: _browserHeaders())
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return [];

      final results = _parseSearchResults(res.body);
      log.i('Trending → ${results.length} items');
      return results;
    } catch (e, st) {
      log.e('Trending error: $e', e, st);
      return [];
    }
  }

  // ──────────────────────────── Details ────────────────────────────

  @override
  Future<UnifiedMedia> getDetails(String providerId, MediaType type) async {
    final log = _log.child('getDetails');

    await _ensureSession();

    final url = '$_baseUrl/hentai/$providerId';
    final res = await _client
        .get(Uri.parse(url), headers: _browserHeaders())
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) {
      throw Exception('Failed to load details for $providerId');
    }

    final doc = html_parser.parse(res.body);

    // Title from <h1> or <title>
    final titleEl = doc.querySelector('h1');
    final rawTitle = titleEl?.text.trim() ?? providerId;

    // Parse series title (strip episode number)
    final seriesTitle =
        rawTitle.replaceAll(RegExp(r'\s*-\s*\d+$'), '').trim();

    // Thumbnail
    final ogImage =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    final coverUrl = ogImage ?? '';

    // Description
    final descEl = doc.querySelector('meta[name="description"]');
    final description = descEl?.attributes['content'];

    return UnifiedMedia(
      id: providerId,
      type: MediaType.ANIME,
      sourceId: sourceInfo.id,
      sourceName: sourceInfo.name,
      providerId: providerId,
      title: MediaTitle(
        english: seriesTitle,
        romaji: seriesTitle,
      ),
      cover: coverUrl.startsWith('http') ? coverUrl : '$_baseUrl$coverUrl',
      description: description,
      isAdult: true,
      genres: const ['Hentai'],
    );
  }

  // ──────────────────────────── Episodes ───────────────────────────

  @override
  Future<List<UnifiedEpisode>> getEpisodes(String animeId) async {
    final log = _log.child('getEpisodes');
    if (_episodesCache.containsKey(animeId)) {
      return _episodesCache[animeId]!;
    }

    await _ensureSession();

    // Fetch the watch page to discover sibling episode links
    final url = '$_baseUrl/hentai/$animeId';
    final res = await _client
        .get(Uri.parse(url), headers: _browserHeaders())
        .timeout(const Duration(seconds: 12));

    if (res.statusCode != 200) return [];

    // Collect all unique /hentai/{slug} links that share the same series prefix
    final seriesBase = animeId.replaceAll(RegExp(r'-\d+$'), '');
    final linkPattern = RegExp(
      r'href="https://hstream\.moe/hentai/(' +
          RegExp.escape(seriesBase) +
          r'(?:-\d+)?)"',
    );

    final slugs = <String>{};
    for (final m in linkPattern.allMatches(res.body)) {
      final slug = m.group(1);
      if (slug != null) slugs.add(slug);
    }

    // Ensure the current page slug is included
    slugs.add(animeId);

    // Sort naturally by trailing episode number
    final sorted = slugs.toList()
      ..sort((a, b) {
        final na = int.tryParse(a.split('-').last) ?? 0;
        final nb = int.tryParse(b.split('-').last) ?? 0;
        return na.compareTo(nb);
      });

    final episodes = <UnifiedEpisode>[];
    for (var i = 0; i < sorted.length; i++) {
      final slug = sorted[i];
      final epNum = int.tryParse(slug.split('-').last) ?? (i + 1);
      episodes.add(UnifiedEpisode(
        id: slug,
        number: epNum.toDouble(),
        title: 'Episode $epNum',
      ));
    }

    _episodesCache[animeId] = episodes;
    log.i('Episodes for $animeId → ${episodes.length}');
    return episodes;
  }

  // ──────────────────────────── Servers ────────────────────────────

  @override
  Future<List<VideoServer>> getServers(String episodeId) async {
    // Single server — resolved at source-extraction time
    return const [
      VideoServer(
        id: 'hstream-dash',
        name: 'Hstream CDN',
        type: ServerType.raw,
      ),
    ];
  }

  // ──────────────────────────── Sources ────────────────────────────

  @override
  Future<List<VideoStream>> getSources(
      String episodeId, VideoServer server) async {
    final log = _log.child('getSources');

    await _ensureSession();

    // 1. Fetch the watch page to get the e_id hidden field
    final watchUrl = '$_baseUrl/hentai/$episodeId';
    final pageRes = await _client
        .get(Uri.parse(watchUrl), headers: _browserHeaders())
        .timeout(const Duration(seconds: 12));

    if (pageRes.statusCode != 200) {
      log.w('Watch page returned ${pageRes.statusCode}');
      return [];
    }

    // Refresh cookies from watch page
    final watchCookies = pageRes.headers['set-cookie'];
    if (watchCookies != null) {
      _cookieHeader = watchCookies
          .split(RegExp(r',(?=[A-Za-z_])'))
          .map((c) => c.split(';').first.trim())
          .join('; ');
    }

    // Extract e_id
    final eidMatch =
        RegExp(r'e_id"[^>]+value="([^"]+)"').firstMatch(pageRes.body);
    if (eidMatch == null) {
      log.w('Could not find e_id on watch page');
      return [];
    }
    final eid = eidMatch.group(1)!;

    // Extract XSRF-TOKEN from cookies
    final xsrfMatch =
        RegExp(r'XSRF-TOKEN=([^;]+)').firstMatch(_cookieHeader ?? '');
    final xsrfToken =
        xsrfMatch != null ? Uri.decodeComponent(xsrfMatch.group(1)!) : '';

    // 2. Call the player API
    final apiRes = await _client.post(
      Uri.parse('$_baseUrl/player/api'),
      headers: {
        'Content-Type': 'application/json',
        'Referer': watchUrl,
        'X-Requested-With': 'XMLHttpRequest',
        'X-Xsrf-Token': xsrfToken,
        'Cookie': _cookieHeader ?? '',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      },
      body: jsonEncode({'episode_id': eid}),
    ).timeout(const Duration(seconds: 15));

    if (apiRes.statusCode != 200) {
      log.w('Player API returned ${apiRes.statusCode}');
      return [];
    }

    final data = jsonDecode(apiRes.body) as Map<String, dynamic>;
    final streamUrl = data['stream_url'] as String? ?? '';
    final domains = (data['stream_domains'] as List<dynamic>?) ?? [];
    final asiaDomains = (data['asia_stream_domains'] as List<dynamic>?) ?? [];

    if (streamUrl.isEmpty || domains.isEmpty) {
      log.w('Player API returned empty stream data');
      return [];
    }

    // 3. Build DASH manifest URLs for each quality on the first domain
    final primaryDomain = domains.first as String;
    final streams = <VideoStream>[];

    for (final quality in ['1080', '720']) {
      final manifestUrl =
          '$primaryDomain/$streamUrl/$quality/manifest.mpd';
      streams.add(VideoStream(
        url: manifestUrl,
        quality: '${quality}p',
        headers: const {'Referer': 'https://hstream.moe/'},
      ));
    }

    // Add Asia CDN fallback if available
    if (asiaDomains.isNotEmpty) {
      final asiaDomain = asiaDomains.first as String;
      streams.add(VideoStream(
        url: '$asiaDomain/$streamUrl/720/manifest.mpd',
        quality: '720p (Asia CDN)',
        headers: const {'Referer': 'https://hstream.moe/'},
      ));
    }

    // Add subtitle tracks if available
    final extraSubs = data['extra_subtitles'];
    if (extraSubs is Map && extraSubs.isNotEmpty) {
      final subsForFirstStream = <SubtitleTrack>[];
      // English subtitles
      subsForFirstStream.add(SubtitleTrack(
        url: '$primaryDomain/$streamUrl/eng.ass',
        language: 'English',
      ));
      for (final lang in extraSubs.keys) {
        if (lang != 'en') {
          subsForFirstStream.add(SubtitleTrack(
            url: '$primaryDomain/$streamUrl/autotrans/$lang.ass',
            language: lang.toString().toUpperCase(),
          ));
        }
      }
      // Attach subtitles to the first stream
      if (streams.isNotEmpty && subsForFirstStream.isNotEmpty) {
        streams[0] = streams[0].copyWith(subtitles: subsForFirstStream);
      }
    }

    log.i('Resolved ${streams.length} streams for $episodeId');
    return streams;
  }
}
