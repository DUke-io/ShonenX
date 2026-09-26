import 'package:shonenx/shared/models/unified_media.dart';

/// Represents a user's taste profile built from local signals (watch history,
/// library state, likes) without requiring any external tracker account.
///
/// Genre/tag affinities are accumulated numeric weights:
///   - Positive values indicate preference
///   - Negative values indicate dislike (e.g. from dropped anime)
class UserTasteProfile {
  final Map<String, double> genreAffinities;
  final Map<String, double> tagAffinities;
  final Map<String, double> studioAffinities;
  final List<UnifiedMedia> seedAnime;
  final Set<String> excludedIds;

  // Signal counts for diagnostic and UI display
  final int likedCount;
  final int completedCount;
  final int watchingCount;
  final int planningCount;
  final int droppedCount;

  // Implicit behavioral signals from watch history
  final int bingeWatchedCount;
  final int quickDroppedCount;
  final double totalWatchedMinutes;

  const UserTasteProfile({
    this.genreAffinities = const {},
    this.tagAffinities = const {},
    this.studioAffinities = const {},
    this.seedAnime = const [],
    this.excludedIds = const {},
    this.likedCount = 0,
    this.completedCount = 0,
    this.watchingCount = 0,
    this.planningCount = 0,
    this.droppedCount = 0,
    this.bingeWatchedCount = 0,
    this.quickDroppedCount = 0,
    this.totalWatchedMinutes = 0.0,
  });

  /// Whether the user has produced any meaningful recommendation signals.
  bool get hasAnySignals =>
      likedCount > 0 ||
      completedCount > 0 ||
      watchingCount > 0 ||
      planningCount > 0 ||
      droppedCount > 0 ||
      bingeWatchedCount > 0;

  /// Returns genres sorted by descending affinity (strongest preferences first).
  List<String> get topPositiveGenres {
    final entries = genreAffinities.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  /// Returns genres the user actively avoids (dropped anime genres).
  List<String> get topNegativeGenres {
    final entries = genreAffinities.entries
        .where((e) => e.value < 0)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries.map((e) => e.key).toList();
  }

  /// Returns studios the user has shown the most interest in.
  List<String> get topStudios {
    final entries = studioAffinities.entries
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).take(5).toList();
  }

  /// Signal strength indicator for the UI (0.0 = no data, 1.0 = rich profile).
  double get signalStrength {
    int signals = 0;
    if (likedCount > 0) signals += likedCount.clamp(0, 5);
    if (completedCount > 0) signals += completedCount.clamp(0, 10);
    if (watchingCount > 0) signals += watchingCount.clamp(0, 3);
    if (bingeWatchedCount > 0) signals += bingeWatchedCount.clamp(0, 5);
    // Normalize to 0.0–1.0 range (20 signals = fully enriched profile)
    return (signals / 20.0).clamp(0.0, 1.0);
  }
}
