import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';

/// Cache entry with expiration timestamp.
class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry(this.data, Duration ttl) : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Service providing resilient, rate-limited access to TVMaze API (api.tvmaze.com)
/// with in-memory TTL caching and automatic Kitsu fallback.
/// Specializes in Western cartoons, 2000s Gen Z classics (Ben 10, Generator Rex,
/// Teen Titans, Avatar, Regular Show, etc.), and animated television series.
class TvMazeService {
  static const String _baseUrl = 'https://api.tvmaze.com';
  static final _log = AppLogger.scope('TvMazeService');
  static final http.Client _client = http.Client();

  // ─── In-Memory TTL Caches ───
  static final Map<String, _CacheEntry<List<UnifiedMedia>>> _searchCache = {};
  static final Map<String, _CacheEntry<UnifiedMedia>> _detailsCache = {};
  static final Map<String, _CacheEntry<List<UnifiedEpisode>>> _episodesCache = {};

  // ─── Rate Limiter State ───
  // TVMaze limit: 20 req / 10s per IP (~2 req/s).
  // We pace requests to at least 300ms apart and queue bursts.
  static const Duration _minRequestInterval = Duration(milliseconds: 320);
  static DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  static Completer<void>? _rateLimitQueue;

  /// Executes an HTTP request through the rate-limiter with automatic 429 backoff retry.
  static Future<http.Response> _rateLimitedGet(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      // Serialize access and enforce spacing
      while (_rateLimitQueue != null) {
        await _rateLimitQueue!.future;
      }

      final completer = Completer<void>();
      _rateLimitQueue = completer;

      try {
        final now = DateTime.now();
        final elapsed = now.difference(_lastRequestTime);
        if (elapsed < _minRequestInterval) {
          final waitDuration = _minRequestInterval - elapsed;
          await Future.delayed(waitDuration);
        }
        _lastRequestTime = DateTime.now();
      } finally {
        _rateLimitQueue = null;
        completer.complete();
      }

      try {
        final response = await _client.get(
          uri,
          headers: headers ??
              {
                'User-Agent': 'KuroX-Client/2.1 (TVMazeService)',
                'Accept': 'application/json',
              },
        ).timeout(timeout);

        if (response.statusCode == 429) {
          _log.w('TVMaze returned HTTP 429 (Rate Limited) on attempt $attempt');
          if (attempt < maxRetries) {
            // Read Retry-After header or backoff exponentially
            final retryHeader = response.headers['retry-after'];
            final retrySec = (retryHeader != null ? int.tryParse(retryHeader) : null) ??
                (attempt + 1) * 2;
            _log.i('Backing off for $retrySec seconds before retrying TVMaze...');
            await Future.delayed(Duration(seconds: retrySec));
            continue;
          }
        }

        return response;
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    throw Exception('Failed to fetch from TVMaze after $maxRetries retries');
  }

  /// Searches TVMaze for animated shows matching [query].
  /// Uses in-memory cache and automatically falls back to Kitsu on failure.
  static Future<List<UnifiedMedia>> searchShows(
    String query, {
    MediaType mediaType = MediaType.ANIME,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];

    // Check in-memory cache first
    final cached = _searchCache[cleanQuery];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    try {
      final uri = Uri.parse('$_baseUrl/search/shows?q=${Uri.encodeComponent(cleanQuery)}');
      _log.i('Searching TVMaze shows: $uri');

      final response = await _rateLimitedGet(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          final List<UnifiedMedia> results = [];
          for (final item in data) {
            if (item is! Map<String, dynamic>) continue;
            final show = item['show'] as Map<String, dynamic>?;
            if (show == null) continue;

            final media = _mapShowToMedia(show, mediaType: mediaType);
            if (media != null) {
              results.add(media);
            }
          }

          if (results.isNotEmpty) {
            _searchCache[cleanQuery] = _CacheEntry(results, const Duration(hours: 1));
            _log.i('TVMaze found ${results.length} shows for "$cleanQuery"');
            return results;
          }
        }
      }

      // If TVMaze returned 0 items or HTTP error, try fallback
      _log.i('TVMaze returned empty/error for "$cleanQuery", executing Kitsu fallback...');
      final fallbackResults = await _fallbackSearchKitsu(cleanQuery, mediaType);
      if (fallbackResults.isNotEmpty) {
        _searchCache[cleanQuery] = _CacheEntry(fallbackResults, const Duration(hours: 1));
        return fallbackResults;
      }

      // If cached stale results exist, return them
      if (cached != null) return cached.data;
      return [];
    } catch (e, st) {
      _log.w('TVMaze search failed for "$cleanQuery": $e, trying fallback...', [st]);
      final fallbackResults = await _fallbackSearchKitsu(cleanQuery, mediaType);
      if (fallbackResults.isNotEmpty) return fallbackResults;
      if (cached != null) return cached.data;
      return [];
    }
  }

  /// Fetches show details including embedded episodes and cast.
  static Future<UnifiedMedia?> getShowDetails(String showId) async {
    final numericId = showId.replaceAll('tvm_', '').trim();
    if (numericId.isEmpty) return null;

    final cached = _detailsCache[numericId];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    try {
      final uri = Uri.parse('$_baseUrl/shows/$numericId?embed[]=episodes&embed[]=cast');
      _log.i('Fetching TVMaze show details: $uri');

      final response = await _rateLimitedGet(uri);

      if (response.statusCode == 200) {
        final show = jsonDecode(response.body);
        if (show is Map<String, dynamic>) {
          final media = _mapShowToMedia(show, includeEmbedded: true);
          if (media != null) {
            _detailsCache[numericId] = _CacheEntry(media, const Duration(hours: 24));
            return media;
          }
        }
      }

      if (cached != null) return cached.data;
      return null;
    } catch (e, st) {
      _log.e('Failed to fetch TVMaze show $showId: $e', [st]);
      if (cached != null) return cached.data;
      return null;
    }
  }

  /// Fetches episodes for a show from TVMaze.
  static Future<List<UnifiedEpisode>> getShowEpisodes(String showId) async {
    final numericId = showId.replaceAll('tvm_', '').trim();
    if (numericId.isEmpty) return [];

    final cached = _episodesCache[numericId];
    if (cached != null && !cached.isExpired) {
      return cached.data;
    }

    try {
      final uri = Uri.parse('$_baseUrl/shows/$numericId/episodes');
      _log.i('Fetching TVMaze episodes: $uri');

      final response = await _rateLimitedGet(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          final List<UnifiedEpisode> episodes = [];
          for (int i = 0; i < data.length; i++) {
            final ep = data[i];
            if (ep is! Map<String, dynamic>) continue;

            final numVal = (ep['number'] as num?)?.toDouble() ?? (i + 1).toDouble();
            final seasonVal = ep['season'] as int?;
            final nameVal = ep['name']?.toString() ?? 'Episode $numVal';
            final imageMap = ep['image'] as Map<String, dynamic>?;
            final thumb = imageMap?['original']?.toString() ?? imageMap?['medium']?.toString();
            final airDate = ep['airdate']?.toString();

            episodes.add(
              UnifiedEpisode(
                id: 'tvm_ep_${ep['id'] ?? i}',
                number: numVal,
                season: seasonVal,
                title: nameVal,
                thumbnailUrl: thumb,
                airDate: airDate,
                uploadDate: ep['airstamp']?.toString(),
              ),
            );
          }

          _episodesCache[numericId] = _CacheEntry(episodes, const Duration(hours: 24));
          return episodes;
        }
      }

      if (cached != null) return cached.data;
      return [];
    } catch (e, st) {
      _log.e('Failed to fetch TVMaze episodes for $showId: $e', [st]);
      if (cached != null) return cached.data;
      return [];
    }
  }

  /// Secondary fallback search using Kitsu API.
  static Future<List<UnifiedMedia>> _fallbackSearchKitsu(
    String query,
    MediaType mediaType,
  ) async {
    try {
      final uri = Uri.parse(
        'https://kitsu.io/api/edge/anime?filter[text]=${Uri.encodeComponent(query)}&page[limit]=10',
      );
      _log.i('Querying Kitsu fallback: $uri');

      final response = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.api+json',
          'User-Agent': 'KuroX-Client/2.1 (FallbackSearch)',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return [];

      final body = jsonDecode(response.body);
      final data = body['data'] as List?;
      if (data == null || data.isEmpty) return [];

      final List<UnifiedMedia> results = [];
      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final attrs = item['attributes'] as Map?;
        if (attrs == null) continue;

        final title = attrs['canonicalTitle']?.toString() ??
            attrs['titles']?['en']?.toString() ??
            'Unknown';
        final poster = attrs['posterImage']?['original']?.toString() ??
            attrs['posterImage']?['medium']?.toString();
        final banner = attrs['coverImage']?['original']?.toString() ?? poster;
        final synopsis = attrs['synopsis']?.toString();
        final episodeCount = attrs['episodeCount'] as int?;
        final ratingStr = attrs['averageRating']?.toString();
        final score = double.tryParse(ratingStr ?? '');

        results.add(
          UnifiedMedia(
            id: 'kitsu_$id',
            providerId: 'kitsu_$id',
            type: mediaType,
            format: 'Animation',
            title: MediaTitle(english: title, romaji: title),
            cover: poster,
            banner: banner,
            description: synopsis,
            score: score,
            episodes: episodeCount,
          ),
        );
      }

      _log.i('Kitsu fallback found ${results.length} shows for "$query"');
      return results;
    } catch (e) {
      _log.w('Kitsu fallback search failed: $e');
      return [];
    }
  }

  /// Maps a TVMaze show JSON map to [UnifiedMedia].
  static UnifiedMedia? _mapShowToMedia(
    Map<String, dynamic> show, {
    bool includeEmbedded = false,
    MediaType mediaType = MediaType.ANIME,
  }) {
    final id = show['id']?.toString();
    final name = show['name']?.toString();
    if (id == null || name == null || name.isEmpty) return null;

    final imageMap = show['image'] as Map<String, dynamic>?;
    final cover = imageMap?['original']?.toString() ?? imageMap?['medium']?.toString();

    final ratingMap = show['rating'] as Map<String, dynamic>?;
    final ratingNum = (ratingMap?['average'] as num?)?.toDouble();
    // Normalize TVMaze 1-10 rating to KuroX's 100-point scale
    final score = ratingNum != null ? (ratingNum * 10) : null;

    final genres = (show['genres'] as List?)
            ?.map((g) => g.toString())
            .where((g) => g.isNotEmpty)
            .toList() ??
        [];

    final premiered = show['premiered']?.toString();
    final year = (premiered != null && premiered.length >= 4)
        ? int.tryParse(premiered.substring(0, 4))
        : null;

    final rawSummary = show['summary']?.toString() ?? '';
    final summary = _cleanHtml(rawSummary);

    final status = show['status']?.toString();
    final typeStr = show['type']?.toString();

    List<MediaCharacter> characters = [];
    int? episodeCount;

    if (includeEmbedded) {
      final embedded = show['_embedded'] as Map<String, dynamic>?;
      if (embedded != null) {
        // Parse cast
        final castList = embedded['cast'] as List?;
        if (castList != null) {
          for (final c in castList) {
            if (c is! Map<String, dynamic>) continue;
            final person = c['person'] as Map<String, dynamic>?;
            final character = c['character'] as Map<String, dynamic>?;

            final charName = character?['name']?.toString() ?? person?['name']?.toString();
            if (charName == null || charName.isEmpty) continue;

            final charImg = (character?['image'] as Map<String, dynamic>?)?['medium']?.toString() ??
                (person?['image'] as Map<String, dynamic>?)?['medium']?.toString();

            final actorImg = (person?['image'] as Map<String, dynamic>?)?['medium']?.toString();

            characters.add(
              MediaCharacter(
                id: character?['id']?.toString() ?? person?['id']?.toString() ?? charName,
                name: charName,
                role: 'Voice Actor',
                image: charImg,
                voiceActorName: person?['name']?.toString(),
                voiceActorImage: actorImg,
              ),
            );
          }
        }

        // Count episodes
        final epList = embedded['episodes'] as List?;
        if (epList != null) {
          episodeCount = epList.length;
        }
      }
    }

    final network = (show['network'] as Map<String, dynamic>?)?['name']?.toString() ??
        (show['webChannel'] as Map<String, dynamic>?)?['name']?.toString();

    return UnifiedMedia(
      id: 'tvm_$id',
      providerId: 'tvm_$id',
      type: mediaType,
      format: typeStr ?? 'Animation',
      title: MediaTitle(english: name, romaji: name),
      cover: cover,
      banner: cover,
      description: summary,
      score: score,
      genres: genres,
      status: status,
      year: year,
      duration: (show['averageRuntime'] as num?)?.toInt() ?? (show['runtime'] as num?)?.toInt(),
      studios: network != null ? [network] : const [],
      episodes: episodeCount,
      characters: characters,
    );
  }

  /// Removes HTML tags from TVMaze synopsis descriptions.
  static String _cleanHtml(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
