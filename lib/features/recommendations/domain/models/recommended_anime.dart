import 'package:shonenx/shared/models/unified_media.dart';

/// The confidence tier of a recommendation, used for visual treatment in the UI.
enum RecommendationTier {
  /// 90%+ match — "Perfect for you"
  perfect,

  /// 70–89% — "Great match"
  great,

  /// 50–69% — "You might enjoy"
  good,

  /// Below 50% — "Worth a look"
  discover,
}

/// A single recommendation with its scoring breakdown and human-readable
/// explanation of why it was recommended.
class RecommendedAnime {
  final UnifiedMedia media;
  final double matchScore;
  final String reason;
  final List<String> matchingGenres;
  final bool isDirectSeed;

  /// Optional: the title of the seed anime that originated this recommendation.
  final String? seedTitle;

  /// Breakdown of how the score was calculated (for debug / transparency).
  final Map<String, double> scoreBreakdown;

  const RecommendedAnime({
    required this.media,
    required this.matchScore,
    required this.reason,
    this.matchingGenres = const [],
    this.isDirectSeed = false,
    this.seedTitle,
    this.scoreBreakdown = const {},
  });

  /// Normalized match percentage (0–100) for display.
  double get matchPercentage => (matchScore / _maxPossibleScore * 100).clamp(0, 100);

  /// The maximum theoretical score an item can achieve.
  /// Used to normalize matchScore into a percentage.
  static const double _maxPossibleScore = 60.0;

  /// Which visual tier this recommendation falls into.
  RecommendationTier get tier {
    final pct = matchPercentage;
    if (pct >= 90) return RecommendationTier.perfect;
    if (pct >= 70) return RecommendationTier.great;
    if (pct >= 50) return RecommendationTier.good;
    return RecommendationTier.discover;
  }

  /// A short human-readable label for the tier.
  String get tierLabel {
    switch (tier) {
      case RecommendationTier.perfect:
        return 'Perfect Match';
      case RecommendationTier.great:
        return 'Great Match';
      case RecommendationTier.good:
        return 'Good Match';
      case RecommendationTier.discover:
        return 'Worth a Look';
    }
  }
}
