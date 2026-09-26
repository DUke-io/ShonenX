import 'package:shonenx/features/recommendations/domain/models/recommended_anime.dart';
import 'package:shonenx/features/recommendations/domain/models/user_taste_profile.dart';
import 'package:shonenx/shared/models/unified_media.dart';

/// Multi-signal recommendation engine that ranks candidate anime/manga based
/// on the user's local taste profile (likes, library, watch history).
///
/// Scoring pipeline:
///   1. Direct seed bonus ("Because you watched X")
///   2. Genre affinity matching (positive + negative penalties)
///   3. Tag affinity matching (themes, demographics)
///   4. Studio affinity bonus
///   5. Community quality multiplier (public rating)
///   6. Recency bonus (newer content gets a small lift)
///   7. Franchise deduplication (avoid recommending sequels)
class RecommendationEngine {
  const RecommendationEngine();

  /// Scores, deduplicates, and ranks candidate anime based on the user's
  /// taste profile. Returns a sorted list of [RecommendedAnime] with
  /// human-readable reasons.
  List<RecommendedAnime> rankCandidates({
    required UserTasteProfile profile,
    required List<UnifiedMedia> candidates,
    Map<String, String>? seedReasons,
  }) {
    if (candidates.isEmpty) return const [];

    final excluded = profile.excludedIds;
    final scoredList = <RecommendedAnime>[];
    final seenIds = <String>{};
    final seenTitles = <String>{}; // Franchise deduplication

    for (final candidate in candidates) {
      if (candidate.id.isEmpty) continue;
      // Filter out anime the user already liked, completed, is watching, or dropped
      if (excluded.contains(candidate.id)) continue;
      if (seenIds.contains(candidate.id)) continue;
      seenIds.add(candidate.id);

      // Franchise deduplication: skip sequels/spin-offs with very similar titles
      final normalizedTitle = _normalizeTitle(candidate.title.availableTitle);
      if (seenTitles.contains(normalizedTitle)) continue;
      seenTitles.add(normalizedTitle);

      final breakdown = <String, double>{};
      double score = 0.0;
      final matchingPositiveGenres = <String>[];
      final candidateGenres = candidate.genres ?? const [];
      final candidateTags = candidate.tags ?? const [];
      final candidateStudios = candidate.studios ?? const [];

      // ─── 1. Direct Seed Recommendation Link ─────────────────────────
      final seedReason = seedReasons?[candidate.id];
      final isDirectSeed = seedReason != null;
      if (isDirectSeed) {
        const seedBonus = 25.0;
        score += seedBonus;
        breakdown['Seed Match'] = seedBonus;
      }

      // ─── 2. Genre Affinity Scoring ──────────────────────────────────
      double genreScore = 0.0;
      for (final genre in candidateGenres) {
        final affinity = profile.genreAffinities[genre] ?? 0.0;
        if (affinity > 0) {
          genreScore += affinity.clamp(0.0, 10.0);
          matchingPositiveGenres.add(genre);
        } else if (affinity < 0) {
          genreScore += affinity.clamp(-15.0, 0.0);
        }
      }
      if (genreScore != 0) {
        score += genreScore;
        breakdown['Genre Affinity'] = genreScore;
      }

      // ─── 3. Tag / Theme Affinity Scoring ────────────────────────────
      double tagScore = 0.0;
      for (final tag in candidateTags) {
        final tagName = tag.name;
        final affinity = profile.tagAffinities[tagName] ?? 0.0;
        tagScore += affinity.clamp(-5.0, 5.0);
      }
      if (tagScore != 0) {
        score += tagScore;
        breakdown['Theme Affinity'] = tagScore;
      }

      // ─── 4. Studio Affinity Bonus ───────────────────────────────────
      double studioScore = 0.0;
      for (final studio in candidateStudios) {
        final affinity = profile.studioAffinities[studio] ?? 0.0;
        studioScore += affinity.clamp(0.0, 5.0);
      }
      if (studioScore > 0) {
        score += studioScore;
        breakdown['Studio Bonus'] = studioScore;
      }

      // ─── 5. Community Quality Multiplier ────────────────────────────
      final rawScore = candidate.score ?? 7.0;
      // Scale: an 8.5-rated anime gets ~3.4, a 6.0-rated gets ~2.4
      final qualityBonus = rawScore * 0.4;
      score += qualityBonus;
      breakdown['Quality'] = qualityBonus;

      // ─── 6. Popularity Signal ───────────────────────────────────────
      final popularity = candidate.popularity ?? 0;
      if (popularity > 50000) {
        const popBonus = 1.5;
        score += popBonus;
        breakdown['Popularity'] = popBonus;
      } else if (popularity > 10000) {
        const popBonus = 0.8;
        score += popBonus;
        breakdown['Popularity'] = popBonus;
      }

      // ─── 7. Recency Bonus ──────────────────────────────────────────
      final year = candidate.year;
      if (year != null && year >= DateTime.now().year - 2) {
        const recencyBonus = 1.0;
        score += recencyBonus;
        breakdown['Recent Release'] = recencyBonus;
      }

      // If the penalty pushed score below 0 and it's not a direct seed, skip
      if (score <= 0 && !isDirectSeed) continue;

      // ─── Build Recommendation Reason ───────────────────────────────
      String reason;
      String? seedTitle;
      if (seedReason != null) {
        reason = seedReason;
        // Extract seed title from "Because you liked X" pattern
        seedTitle = seedReason.replaceFirst('Because you liked ', '');
      } else if (matchingPositiveGenres.isNotEmpty) {
        final topGenres = matchingPositiveGenres.take(2).join(' & ');
        if (profile.signalStrength >= 0.5) {
          reason = 'Top pick for your taste in $topGenres';
        } else {
          reason = 'Matches your interest in $topGenres';
        }
      } else if (studioScore > 0 && candidateStudios.isNotEmpty) {
        reason = 'From a studio you enjoy: ${candidateStudios.first}';
      } else {
        reason = 'Recommended based on your library activity';
      }

      scoredList.add(
        RecommendedAnime(
          media: candidate,
          matchScore: score,
          reason: reason,
          matchingGenres: matchingPositiveGenres,
          isDirectSeed: isDirectSeed,
          seedTitle: seedTitle,
          scoreBreakdown: breakdown,
        ),
      );
    }

    // Sort descending by calculated match score
    scoredList.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return scoredList;
  }

  /// Normalizes a title for franchise deduplication.
  /// Strips season numbers, "Part 2", "2nd Season", etc.
  /// Example: "Attack on Titan Season 2" → "attack on titan"
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\s*(season|part|cour)\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+(st|nd|rd|th)\s+season', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[:\-–]\s*'), ' ')
        .replaceAll(RegExp(r'\s*(ii|iii|iv|v|vi)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
