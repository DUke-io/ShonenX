import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';

/// Service providing access to the free TVMaze API (api.tvmaze.com).
/// Specializes in Western cartoons, 2000s Gen Z classics (Ben 10, Generator Rex,
/// Teen Titans, Avatar, Regular Show, etc.), and animated television series.
class TvMazeService {
  static const String _baseUrl = 'https://api.tvmaze.com';
  static final _log = AppLogger.scope('TvMazeService');
  static final http.Client _client = http.Client();

  /// Searches TVMaze for animated shows matching [query].
  static Future<List<UnifiedMedia>> searchShows(
    String query, {
    MediaType mediaType = MediaType.ANIME,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/search/shows?q=${Uri.encodeComponent(cleanQuery)}');
      _log.i('Searching TVMaze shows: $uri');

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'KuroX-Client/2.1 (TVMazeService)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _log.w('TVMaze returned HTTP ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      if (data is! List) return [];

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

      _log.i('TVMaze found ${results.length} shows for "$cleanQuery"');
      return results;
    } catch (e, st) {
      _log.w('TVMaze search failed for "$cleanQuery": $e', [st]);
      return [];
    }
  }

  /// Fetches show details including embedded episodes and cast.
  static Future<UnifiedMedia?> getShowDetails(String showId) async {
    final numericId = showId.replaceAll('tvm_', '').trim();
    if (numericId.isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/shows/$numericId?embed[]=episodes&embed[]=cast');
      _log.i('Fetching TVMaze show details: $uri');

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'KuroX-Client/2.1 (TVMazeService)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _log.w('TVMaze details returned HTTP ${response.statusCode}');
        return null;
      }

      final show = jsonDecode(response.body);
      if (show is! Map<String, dynamic>) return null;

      return _mapShowToMedia(show, includeEmbedded: true);
    } catch (e, st) {
      _log.e('Failed to fetch TVMaze show $showId: $e', [st]);
      return null;
    }
  }

  /// Fetches episodes for a show from TVMaze.
  static Future<List<UnifiedEpisode>> getShowEpisodes(String showId) async {
    final numericId = showId.replaceAll('tvm_', '').trim();
    if (numericId.isEmpty) return [];

    try {
      final uri = Uri.parse('$_baseUrl/shows/$numericId/episodes');
      _log.i('Fetching TVMaze episodes: $uri');

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'KuroX-Client/2.1 (TVMazeService)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _log.w('TVMaze episodes returned HTTP ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      if (data is! List) return [];

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

      return episodes;
    } catch (e, st) {
      _log.e('Failed to fetch TVMaze episodes for $showId: $e', [st]);
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
