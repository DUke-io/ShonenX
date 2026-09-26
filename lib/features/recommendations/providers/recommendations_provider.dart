import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shonenx/features/discovery/providers/discovery_feed_provider.dart';
import 'package:shonenx/features/history/domain/models/watch_history_entry.dart';
import 'package:shonenx/features/library/domain/models/library_entry.dart';
import 'package:shonenx/features/recommendations/data/liked_anime_repository.dart';
import 'package:shonenx/features/recommendations/domain/models/liked_anime.dart';
import 'package:shonenx/features/recommendations/domain/models/recommended_anime.dart';
import 'package:shonenx/features/recommendations/domain/models/user_taste_profile.dart';
import 'package:shonenx/features/recommendations/engine/recommendation_engine.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_category.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/providers/content_prefs_provider.dart';
import 'package:shonenx/shared/providers/database_provider.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Liked Anime Repository & Notifier (Explicit User Likes)
// ─────────────────────────────────────────────────────────────────────────────

final likedAnimeRepositoryProvider = Provider<LikedAnimeRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LikedAnimeRepository(prefs);
});

class LikedAnimeNotifier extends Notifier<Map<String, LikedAnime>> {
  late LikedAnimeRepository _repo;

  @override
  Map<String, LikedAnime> build() {
    _repo = ref.watch(likedAnimeRepositoryProvider);
    return _repo.loadAll();
  }

  bool isLiked(String id) {
    return state.containsKey(id);
  }

  Future<bool> toggleLike(UnifiedMedia media) async {
    final nowLiked = await _repo.toggle(media);
    state = _repo.loadAll();
    ref.invalidate(userTasteProfileProvider);
    ref.invalidate(recommendedAnimeFeedProvider);
    return nowLiked;
  }

  Future<void> addLike(UnifiedMedia media) async {
    final item = LikedAnime.fromUnifiedMedia(media);
    await _repo.add(item);
    state = _repo.loadAll();
    ref.invalidate(userTasteProfileProvider);
    ref.invalidate(recommendedAnimeFeedProvider);
  }

  Future<void> removeLike(String id) async {
    await _repo.remove(id);
    state = _repo.loadAll();
    ref.invalidate(userTasteProfileProvider);
    ref.invalidate(recommendedAnimeFeedProvider);
  }
}

final likedAnimeProvider =
    NotifierProvider<LikedAnimeNotifier, Map<String, LikedAnime>>(
      LikedAnimeNotifier.new,
    );

// ─────────────────────────────────────────────────────────────────────────────
//  User Taste Profile Builder (Multi-Signal)
//
//  Signal Sources:
//    1. Liked Anime         (explicit, +4.0 per genre, +2.0 per tag)
//    2. Library Entries      (completed +3.5, watching +2.5, planning +2.0, dropped -4.0)
//    3. Watch History        (implicit binge detection, quick-drop penalty, studio tracking)
//
//  This works entirely offline — no AniList/MAL account needed.
// ─────────────────────────────────────────────────────────────────────────────

final userTasteProfileProvider = FutureProvider<UserTasteProfile>((ref) async {
  final likedMap = ref.watch(likedAnimeProvider);
  final isar = ref.watch(databaseProvider);

  final genreAffinities = <String, double>{};
  final tagAffinities = <String, double>{};
  final studioAffinities = <String, double>{};
  final seedAnime = <UnifiedMedia>[];
  final excludedIds = <String>{};

  int likedCount = 0;
  int completedCount = 0;
  int watchingCount = 0;
  int planningCount = 0;
  int droppedCount = 0;
  int bingeWatchedCount = 0;
  int quickDroppedCount = 0;
  double totalWatchedMinutes = 0.0;

  // ── Signal 1: Process Liked Anime (+4.0 genre weight, +2.0 tag weight) ──
  for (final liked in likedMap.values) {
    likedCount++;
    excludedIds.add(liked.id);
    final media = liked.toUnifiedMedia();
    seedAnime.add(media);

    for (final g in liked.genres) {
      genreAffinities[g] = (genreAffinities[g] ?? 0.0) + 4.0;
    }
    for (final t in liked.tags) {
      tagAffinities[t] = (tagAffinities[t] ?? 0.0) + 2.0;
    }
  }

  // ── Signal 2: Process Local Isar Library Entries ────────────────────────
  try {
    final libraryEntries = await isar.libraryEntrys.where().findAll();
    for (final entry in libraryEntries) {
      final status = entry.status?.toLowerCase() ?? '';
      final id = entry.providerId;
      if (id.isNotEmpty) {
        // Exclude watched, watching, or dropped from recommendations
        if (status == 'completed' ||
            status == 'watching' ||
            status == 'dropped') {
          excludedIds.add(id);
        }
      }

      double weight = 0.0;
      if (status == 'completed') {
        completedCount++;
        weight = 3.5;
        // Also treat completed as potential seed
        seedAnime.add(
          UnifiedMedia(
            id: entry.providerId,
            type: MediaType.ANIME,
            title: MediaTitle(english: entry.title, romaji: entry.title),
            cover: entry.cover,
            format: entry.format,
            score: entry.score,
          ),
        );
      } else if (status == 'watching') {
        watchingCount++;
        weight = 2.5;
      } else if (status == 'planning') {
        planningCount++;
        weight = 2.0;
      } else if (status == 'dropped') {
        droppedCount++;
        weight = -4.0; // Penalty
      }

      // Apply genre weights from library entries that have genres
      if (weight != 0.0 && entry.genres != null) {
        for (final g in entry.genres!) {
          genreAffinities[g] = (genreAffinities[g] ?? 0.0) + weight;
        }
      }
    }
  } catch (_) {}

  // ── Signal 3: Implicit Watch History Analysis ──────────────────────────
  //
  // We mine watch progress data to detect:
  //   • Binge-watching patterns → strong positive signal
  //   • Quick drops (< 1 episode or < 5 minutes) → negative signal
  //   • Episode completion rates → engagement quality
  //
  try {
    final allWatchEntries =
        await isar.watchHistoryEntrys.where().sortByLastUpdatedDesc().findAll();

    // Group entries by anime ID to analyze per-anime behavior
    final watchByAnime = <String, List<WatchHistoryEntry>>{};
    for (final entry in allWatchEntries) {
      watchByAnime.putIfAbsent(entry.animeId, () => []).add(entry);
    }

    for (final animeEntry in watchByAnime.entries) {
      final animeId = animeEntry.key;
      final episodes = animeEntry.value;
      if (episodes.isEmpty) continue;

      final firstEp = episodes.last; // Oldest (sorted desc, so last = first watched)
      final totalEps = firstEp.totalEpisodes ?? 0;

      // Calculate total minutes watched for this anime
      double animeMinutes = 0.0;
      int fullyWatchedEps = 0;
      for (final ep in episodes) {
        final mins = ep.positionInMilliseconds / 60000.0;
        animeMinutes += mins;
        totalWatchedMinutes += mins;

        // Consider an episode "fully watched" if > 80% of duration consumed
        if (ep.durationInMilliseconds > 0 &&
            ep.positionInMilliseconds / ep.durationInMilliseconds >= 0.80) {
          fullyWatchedEps++;
        }
      }

      // ── Binge Detection ────────────────────────────────────────────
      // If the user watched 5+ episodes within a 48-hour window, that's a binge.
      // We approximate by checking if there are 5+ episodes sorted within
      // 2 days of each other.
      bool isBinge = false;
      if (episodes.length >= 5) {
        final sortedByDate = List<WatchHistoryEntry>.from(episodes)
          ..sort((a, b) => a.lastUpdated.compareTo(b.lastUpdated));
        for (int i = 0; i <= sortedByDate.length - 5; i++) {
          final span = sortedByDate[i + 4]
              .lastUpdated
              .difference(sortedByDate[i].lastUpdated);
          if (span.inHours <= 48) {
            isBinge = true;
            break;
          }
        }
      }

      // ── Quick Drop Detection ───────────────────────────────────────
      // If the user only watched 1 episode and less than 5 minutes total,
      // this is a strong dislike signal.
      final isQuickDrop =
          episodes.length <= 1 && animeMinutes < 5.0 && totalEps > 1;

      // ── Build affinities from the first episode's metadata ─────────
      // WatchHistoryEntry doesn't store genres directly, but we can
      // look them up from the library or liked list. If not found, we
      // rely on the anime being enriched later by the candidate fetcher.
      //
      // For now, track engagement level per anime ID for the seed system:
      if (!excludedIds.contains(animeId)) {
        if (isBinge) {
          bingeWatchedCount++;
          // Binge-watched anime become high-quality seeds
          seedAnime.add(
            UnifiedMedia(
              id: animeId,
              type: MediaType.ANIME,
              title: MediaTitle(
                english: firstEp.animeTitle,
                romaji: firstEp.animeTitle,
              ),
              cover: firstEp.cover,
            ),
          );
        }
      }

      if (isQuickDrop) {
        quickDroppedCount++;
        // Quick drops don't contribute genre penalties here because
        // we may not know the genres. The library entry 'dropped' status
        // already handles that. But we track the count for diagnostics.
      }

      // ── High engagement: if user watched > 60% of episodes ─────────
      if (totalEps > 0 && fullyWatchedEps / totalEps >= 0.6) {
        // This anime was heavily watched — treat it like a completed entry
        if (!excludedIds.contains(animeId) &&
            !seedAnime.any((s) => s.id == animeId)) {
          seedAnime.add(
            UnifiedMedia(
              id: animeId,
              type: MediaType.ANIME,
              title: MediaTitle(
                english: firstEp.animeTitle,
                romaji: firstEp.animeTitle,
              ),
              cover: firstEp.cover,
            ),
          );
        }
        excludedIds.add(animeId);
      }
    }
  } catch (_) {}

  return UserTasteProfile(
    genreAffinities: genreAffinities,
    tagAffinities: tagAffinities,
    studioAffinities: studioAffinities,
    seedAnime: seedAnime,
    excludedIds: excludedIds,
    likedCount: likedCount,
    completedCount: completedCount,
    watchingCount: watchingCount,
    planningCount: planningCount,
    droppedCount: droppedCount,
    bingeWatchedCount: bingeWatchedCount,
    quickDroppedCount: quickDroppedCount,
    totalWatchedMinutes: totalWatchedMinutes,
  );
});

// ─────────────────────────────────────────────────────────────────────────────
//  Recommendation Engine Provider
// ─────────────────────────────────────────────────────────────────────────────

final recommendationEngineProvider = Provider<RecommendationEngine>((ref) {
  return const RecommendationEngine();
});

// ─────────────────────────────────────────────────────────────────────────────
//  Recommended Anime Feed Provider
//
//  Candidate sources:
//    1. Direct recommendations from seed anime (AniList/Kitsu recommendation edges)
//    2. Genre-based discovery from the user's top 3 positive genres
//    3. Top-rated fallback for quality padding
//    4. Trending items as a cold-start fallback when profile has no signals
// ─────────────────────────────────────────────────────────────────────────────

final recommendedAnimeFeedProvider =
    FutureProvider.family<List<RecommendedAnime>, MediaType>((
      ref,
      mediaType,
    ) async {
      final profile = await ref.watch(userTasteProfileProvider.future);
      final tracker = ref.watch(metadataSourceProvider);
      final adultMode = ref.watch(contentPrefsProvider).adultContentMode;
      final engine = ref.watch(recommendationEngineProvider);

      // ── Cold Start: No signals → return trending items ──────────────
      if (!profile.hasAnySignals) {
        try {
          final trending = await tracker.getCategoryItems(
            TrackerCategory.trending,
            type: mediaType,
            adultMode: adultMode,
            cacheDuration: const Duration(hours: 6),
          );
          return trending.items
              .map(
                (m) => RecommendedAnime(
                  media: m,
                  matchScore: (m.score ?? 8.0),
                  reason: 'Trending recommendation to get you started',
                ),
              )
              .toList();
        } catch (_) {
          return const [];
        }
      }

      final candidates = <UnifiedMedia>[];
      final seedReasons = <String, String>{};

      // ── 1. Expand Direct Seed Recommendations ──────────────────────
      // Limit seeds to top 15 by recency to avoid overwhelming the API
      final topSeeds = profile.seedAnime.take(15).toList();
      for (final seed in topSeeds) {
        final recs = seed.recommendations;
        if (recs != null && recs.isNotEmpty) {
          for (final rec in recs) {
            if (rec.id.isNotEmpty && !profile.excludedIds.contains(rec.id)) {
              candidates.add(rec);
              seedReasons[rec.id] =
                  'Because you liked ${seed.title.availableTitle}';
            }
          }
        }
      }

      // ── 2. Genre-Based Discovery ───────────────────────────────────
      // Use top 4 genres (increased from 3 for broader coverage)
      final topGenres = profile.topPositiveGenres.take(4).toList();
      for (final genre in topGenres) {
        try {
          final genreItems = await ref.watch(
            genreFeedProvider((type: mediaType, genre: genre)).future,
          );
          for (final item in genreItems) {
            if (!profile.excludedIds.contains(item.id)) {
              candidates.add(item);
            }
          }
        } catch (_) {}
      }

      // ── 3. Top Rated Quality Padding ───────────────────────────────
      try {
        final topRated = await tracker.getCategoryItems(
          TrackerCategory.topRated,
          type: mediaType,
          adultMode: adultMode,
          cacheDuration: const Duration(hours: 12),
        );
        for (final item in topRated.items) {
          if (!profile.excludedIds.contains(item.id)) {
            candidates.add(item);
          }
        }
      } catch (_) {}

      // ── 4. Trending Items for Diversity ────────────────────────────
      // Mix in some trending items to prevent the feed from becoming stale
      try {
        final trending = await tracker.getCategoryItems(
          TrackerCategory.trending,
          type: mediaType,
          adultMode: adultMode,
          cacheDuration: const Duration(hours: 6),
        );
        for (final item in trending.items) {
          if (!profile.excludedIds.contains(item.id)) {
            candidates.add(item);
          }
        }
      } catch (_) {}

      // ── 5. Rank, deduplicate, and assign reasons ───────────────────
      final ranked = engine.rankCandidates(
        profile: profile,
        candidates: candidates,
        seedReasons: seedReasons,
      );

      // Shuffle items with similar scores for feed freshness
      return _shuffleSimilarScores(ranked);
    });

/// Convenience provider that unwraps [RecommendedAnime] to [UnifiedMedia].
final recommendedMediaFeedProvider =
    FutureProvider.family<List<UnifiedMedia>, MediaType>((
      ref,
      mediaType,
    ) async {
      final recommended = await ref.watch(
        recommendedAnimeFeedProvider(mediaType).future,
      );
      return recommended.map((r) => r.media).toList();
    });

// ─────────────────────────────────────────────────────────────────────────────
//  Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Adds subtle randomization among items with very similar scores
/// so the feed doesn't show the exact same order every time.
List<RecommendedAnime> _shuffleSimilarScores(List<RecommendedAnime> list) {
  if (list.length <= 2) return list;

  final result = <RecommendedAnime>[];
  final rng = Random();
  var i = 0;

  while (i < list.length) {
    // Find the range of items within ±2.0 score of the current item
    var j = i + 1;
    while (j < list.length &&
        (list[i].matchScore - list[j].matchScore).abs() <= 2.0) {
      j++;
    }

    // Shuffle this cluster of similar-score items
    final cluster = list.sublist(i, j).toList()..shuffle(rng);
    result.addAll(cluster);
    i = j;
  }

  return result;
}
