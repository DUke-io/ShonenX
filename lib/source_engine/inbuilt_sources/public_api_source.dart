import 'dart:async';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:shonenx/source_engine/inbuilt_sources/hianime_source.dart';
import 'package:shonenx/source_engine/inbuilt_sources/raretoon_source.dart';
import 'package:shonenx/source_engine/models/source_info.dart';
import 'package:shonenx/source_engine/models/source_setting.dart';
import 'package:shonenx/source_engine/providers/anime_source.dart';

/// Unified Public API Source merging Japanese Anime and Western Cartoons
/// into a single, high-performance, stable unit.
///
/// Features:
/// - Fast Anime streaming & multi-season tracking (HiAnime backend).
/// - Cartoon & Animated Classics with Hindi + English Dual Audio (RareToon backend).
/// - Deduplicated search & interleaved trending with no broken banners.
/// - Unified playback and stream resolution.
class PublicApiSource implements AnimeSource {
  final HiAnimeSource _anime = HiAnimeSource();
  final RareToonSource _cartoon = RareToonSource();
  final ScopedLogger _log = AppLogger.scope('PublicApiSource');

  // In-memory caches for rapid responses
  final Map<String, List<UnifiedMedia>> _searchCache = {};
  final Map<String, List<UnifiedMedia>> _trendingCache = {};

  @override
  SourceInfo get sourceInfo => SourceInfo(
        id: 'inbuilt_hianime',
        name: 'Public API',
        type: SourceType.inbuilt,
        mediaType: MediaType.ANIME,
        iconUrl: null,
        baseUrl: 'https://hianime.at',
        lang: 'all',
      );

  @override
  Future<List<SourceSetting>> getSettingsSchema() async {
    final animeSettings = await _anime.getSettingsSchema();
    final cartoonSettings = await _cartoon.getSettingsSchema();
    return [...animeSettings, ...cartoonSettings];
  }

  @override
  Future<List<String>> getFilterGenres() async {
    final a = await _anime.getFilterGenres();
    final c = await _cartoon.getFilterGenres();
    return {...a, ...c}.toList();
  }

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
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return getTrending(page: page);
    }

    final cacheKey = '$cleanQuery:$page';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    final isCartoon = _isCartoonQuery(cleanQuery);

    try {
      final animeFuture = _anime
          .search(cleanQuery, type, page: page, isAdult: isAdult, sort: sort, genres: genres, tags: tags)
          .catchError((_) => <UnifiedMedia>[]);
      final cartoonFuture = _cartoon
          .search(cleanQuery, type, page: page, isAdult: isAdult, sort: sort, genres: genres, tags: tags)
          .catchError((_) => <UnifiedMedia>[]);

      final results = await Future.wait([animeFuture, cartoonFuture]);
      final animeList = results[0];
      final cartoonList = results[1];

      final List<UnifiedMedia> merged = [];
      final Set<String> seen = {};

      void addShows(List<UnifiedMedia> list) {
        for (final item in list) {
          final titleKey = _normalizeKey(item.title.english ?? item.title.romaji ?? item.id);
          if (seen.contains(titleKey)) continue;
          seen.add(titleKey);

          merged.add(
            item.copyWith(
              sourceId: sourceInfo.id,
              sourceName: sourceInfo.name,
            ),
          );
        }
      }

      if (isCartoon) {
        addShows(cartoonList);
        addShows(animeList);
      } else {
        addShows(animeList);
        addShows(cartoonList);
      }

      if (merged.isNotEmpty) {
        _searchCache[cacheKey] = merged;
      }
      return merged;
    } catch (e, st) {
      _log.e('Search error in PublicApiSource for "$query": $e', [st]);
      return [];
    }
  }

  @override
  Future<List<UnifiedMedia>> getTrending({int page = 1}) async {
    final cacheKey = 'trending:$page';
    if (_trendingCache.containsKey(cacheKey)) {
      return _trendingCache[cacheKey]!;
    }

    try {
      final animeFuture = _anime.getTrending(page: page).catchError((_) => <UnifiedMedia>[]);
      final cartoonFuture = _cartoon.getTrending(page: page).catchError((_) => <UnifiedMedia>[]);

      final results = await Future.wait([animeFuture, cartoonFuture]);
      final animeTrending = results[0];
      final cartoonTrending = results[1];

      final List<UnifiedMedia> combined = [];
      final Set<String> seen = {};

      void addItem(UnifiedMedia m) {
        final key = _normalizeKey(m.title.english ?? m.title.romaji ?? m.id);
        if (seen.contains(key)) return;
        seen.add(key);
        combined.add(
          m.copyWith(
            sourceId: sourceInfo.id,
            sourceName: sourceInfo.name,
          ),
        );
      }

      // Smoothly interleave 2 anime, 1 cartoon
      int aIdx = 0;
      int cIdx = 0;
      while (aIdx < animeTrending.length || cIdx < cartoonTrending.length) {
        if (aIdx < animeTrending.length) addItem(animeTrending[aIdx++]);
        if (aIdx < animeTrending.length) addItem(animeTrending[aIdx++]);
        if (cIdx < cartoonTrending.length) addItem(cartoonTrending[cIdx++]);
      }

      if (combined.isNotEmpty) {
        _trendingCache[cacheKey] = combined;
      }
      return combined;
    } catch (e, st) {
      _log.e('Failed to fetch unified trending in PublicApiSource: $e', [st]);
      return _anime.getTrending(page: page);
    }
  }

  @override
  Future<UnifiedMedia> getDetails(String providerId, MediaType type) async {
    if (_isCartoonId(providerId)) {
      final details = await _cartoon.getDetails(providerId, type);
      return details.copyWith(
        sourceId: sourceInfo.id,
        sourceName: sourceInfo.name,
      );
    }
    final details = await _anime.getDetails(providerId, type);
    return details.copyWith(
      sourceId: sourceInfo.id,
      sourceName: sourceInfo.name,
    );
  }

  @override
  Future<List<UnifiedEpisode>> getEpisodes(String animeId) async {
    if (_isCartoonId(animeId)) {
      return await _cartoon.getEpisodes(animeId);
    }
    return await _anime.getEpisodes(animeId);
  }

  @override
  Future<List<VideoServer>> getServers(String episodeId) async {
    if (_isCartoonId(episodeId)) {
      return await _cartoon.getServers(episodeId);
    }
    return await _anime.getServers(episodeId);
  }

  @override
  Future<List<VideoStream>> getSources(String episodeId, VideoServer server) async {
    if (_isCartoonId(episodeId) || server.id.startsWith('raretoon') || server.id.startsWith('rt_')) {
      return await _cartoon.getSources(episodeId, server);
    }
    return await _anime.getSources(episodeId, server);
  }

  bool _isCartoonId(String id) {
    final lower = id.toLowerCase();
    return lower.startsWith('rt_') ||
        lower.contains('toonworld') ||
        lower.contains('raretoon') ||
        lower.contains('rareanime') ||
        (lower.startsWith('http') && !lower.contains('hianime') && !lower.contains('aniwatch'));
  }

  bool _isCartoonQuery(String q) {
    final lower = q.toLowerCase();
    const keywords = [
      'ben 10', 'ben10', 'generator rex', 'teen titans', 'avatar', 'airbender',
      'regular show', 'adventure time', 'courage', 'danny phantom', 'samurai jack',
      'dexter', 'powerpuff', 'ed, edd', 'grim adventures', 'johnny bravo',
      'spider-man', 'spiderman', 'batman', 'superman', 'justice league',
      'tom and jerry', 'looney tunes', 'scooby', 'phineas', 'gravity falls',
      'doraemon', 'shinchan', 'shin chan', 'cartoon', 'hindi', 'multi audio',
      'dual audio', 'oggy', 'chhota bheem', 'roll no 21', 'beyblade'
    ];
    return keywords.any((k) => lower.contains(k));
  }

  String _normalizeKey(String t) {
    return t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
