import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/video_server.dart';
import 'package:shonenx/shared/models/video_stream.dart';
import 'package:shonenx/source_engine/models/chapter_page.dart';
import 'package:shonenx/source_engine/providers/anime_source.dart';
import 'package:shonenx/source_engine/providers/manga_source.dart';

class PrecacheData {
  final List<VideoServer> servers;
  final List<VideoStream> streams;
  final DateTime cachedAt;

  const PrecacheData({
    required this.servers,
    required this.streams,
    required this.cachedAt,
  });
}

class PrecacheService {
  static final _log = AppLogger.scope('PrecacheService');

  // In-memory cache of next episode stream metadata: episodeId -> PrecacheData
  final Map<String, PrecacheData> _cachedEpisodeStreams = {};

  // In-memory cache of next chapter pages: chapterId -> List<ChapterPage>
  final Map<String, List<ChapterPage>> _cachedChapterPages = {};

  final Set<String> _inFlightRequests = {};

  PrecacheData? getCachedEpisode(String episodeId) =>
      _cachedEpisodeStreams[episodeId];

  List<ChapterPage>? getCachedPages(String chapterId) =>
      _cachedChapterPages[chapterId];

  /// Silently pre-fetches the next episode's server and stream links in the background.
  Future<void> precacheNextEpisode({
    required AnimeSource source,
    required UnifiedEpisode nextEpisode,
  }) async {
    final epId = nextEpisode.id;
    if (_cachedEpisodeStreams.containsKey(epId) || _inFlightRequests.contains(epId)) {
      return;
    }

    _inFlightRequests.add(epId);
    _log.i('Pre-caching metadata for next episode ${nextEpisode.number} ($epId)...');

    try {
      final servers = await source.getServers(epId);
      if (servers.isEmpty) return;

      final server = servers.first;
      final streams = await source.getSources(epId, server);

      if (streams.isNotEmpty) {
        _cachedEpisodeStreams[epId] = PrecacheData(
          servers: servers,
          streams: streams,
          cachedAt: DateTime.now(),
        );
        _log.i(
          'Pre-cache complete for episode ${nextEpisode.number} (${streams.length} streams ready)',
        );
      }
    } catch (e) {
      _log.w('Pre-cache error for next episode ${nextEpisode.number}: $e');
    } finally {
      _inFlightRequests.remove(epId);
    }
  }

  /// Silently pre-fetches the next chapter's pages and warms image caches.
  Future<void> precacheNextChapter({
    required MangaSource source,
    required String chapterId,
    BuildContext? context,
  }) async {
    if (_cachedChapterPages.containsKey(chapterId) ||
        _inFlightRequests.contains(chapterId)) {
      return;
    }

    _inFlightRequests.add(chapterId);
    _log.i('Pre-caching pages for next chapter ($chapterId)...');

    try {
      final pages = await source.getPages(chapterId);
      if (pages.isNotEmpty) {
        _cachedChapterPages[chapterId] = pages;
        _log.i('Pre-cached ${pages.length} page URLs for next chapter');

        // Prime the image cache for the first 5 pages
        if (context != null && context.mounted) {
          final pagesToWarm = pages.take(5);
          for (final page in pagesToWarm) {
            try {
              precacheImage(
                CachedNetworkImageProvider(page.url, headers: page.headers),
                context,
              );
            } catch (_) {}
          }
          _log.i('Primed image cache for first 5 pages of next chapter');
        }
      }
    } catch (e) {
      _log.w('Pre-cache error for chapter $chapterId: $e');
    } finally {
      _inFlightRequests.remove(chapterId);
    }
  }

  void clear() {
    _cachedEpisodeStreams.clear();
    _cachedChapterPages.clear();
    _inFlightRequests.clear();
  }
}

final precacheServiceProvider = Provider<PrecacheService>((ref) {
  final service = PrecacheService();
  return service;
});
