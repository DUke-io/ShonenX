import 'dart:developer';

import 'package:shonenx/core/network/auth/authenticator.dart';
import 'package:shonenx/features/discovery/domain/models/search_filter_options.dart';
import 'package:shonenx/features/library/domain/models/library_entry.dart';
import 'package:shonenx/features/tracking/domain/models/tracked_list_item.dart';
import 'package:shonenx/features/tracking/domain/models/tracked_status.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_category.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_filter_options.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_profile.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';
import 'package:shonenx/features/tracking/engine/remote_tracker.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/providers/content_prefs_provider.dart';
import 'package:shonenx/source_engine/models/paginated_result.dart';
import 'package:shonenx/source_engine/models/tracker_search_result.dart';

/// A resilient wrapper around [RemoteTracker] that provides automatic,
/// seamless failover to a community fallback tracker (e.g., Kitsu)
/// whenever the primary tracker encounters an outage, HTTP 403/500,
/// rate limit, or network failure.
class ResilientRemoteTracker implements RemoteTracker {
  final RemoteTracker primary;
  final RemoteTracker fallback;

  const ResilientRemoteTracker({
    required this.primary,
    required this.fallback,
  });

  @override
  TrackerType get type => primary.type;

  @override
  Authenticator get authenticator => primary.authenticator;

  @override
  Future<bool> get isAuthenticated => primary.isAuthenticated;

  @override
  List<MediaType> get supportedMediaTypes => primary.supportedMediaTypes;

  @override
  bool supportsMediaType(MediaType mediaType) =>
      primary.supportsMediaType(mediaType);

  @override
  List<TrackerCategory> get supportedCategories => primary.supportedCategories;

  @override
  Future<TrackerProfile> fetchProfile() => primary.fetchProfile();

  @override
  Future<TrackerFilterOptions> fetchFilterOptions([MediaType? type]) async {
    try {
      final opts = await primary.fetchFilterOptions(type);
      if (opts.genres.isNotEmpty || opts.tags.isNotEmpty) return opts;
      return await fallback.fetchFilterOptions(type);
    } catch (e) {
      log(
        'fetchFilterOptions failed on ${primary.type.displayName}, using fallback: $e',
        name: 'ResilientRemoteTracker',
      );
      return await fallback.fetchFilterOptions(type);
    }
  }

  @override
  Future<List<String>> fetchGenres() async {
    try {
      final genres = await primary.fetchGenres();
      if (genres.isNotEmpty) return genres;
      return await fallback.fetchGenres();
    } catch (e) {
      log(
        'fetchGenres failed on ${primary.type.displayName}, using fallback: $e',
        name: 'ResilientRemoteTracker',
      );
      return await fallback.fetchGenres();
    }
  }

  @override
  Future<List<String>> fetchTags() async {
    try {
      final tags = await primary.fetchTags();
      if (tags.isNotEmpty) return tags;
      return await fallback.fetchTags();
    } catch (e) {
      log(
        'fetchTags failed on ${primary.type.displayName}, using fallback: $e',
        name: 'ResilientRemoteTracker',
      );
      return await fallback.fetchTags();
    }
  }

  @override
  Future<PaginatedResult<UnifiedMedia>> getCategoryItems(
    TrackerCategory category, {
    int page = 1,
    MediaType type = MediaType.ANIME,
    Duration? cacheDuration,
    AdultContentMode adultMode = AdultContentMode.safe,
  }) async {
    try {
      final result = await primary.getCategoryItems(
        category,
        page: page,
        type: type,
        cacheDuration: cacheDuration,
        adultMode: adultMode,
      );

      // If primary returned items, return them
      if (result.items.isNotEmpty) return result;

      // If page 1 had 0 items for trending/popular, try fallback
      if (page == 1 &&
          (category == TrackerCategory.trending ||
              category == TrackerCategory.popular)) {
        log(
          'Primary ${primary.type.displayName} returned 0 items for $category, querying fallback ${fallback.type.displayName}',
          name: 'ResilientRemoteTracker',
        );
        return await fallback.getCategoryItems(
          category,
          page: page,
          type: type,
          cacheDuration: cacheDuration,
          adultMode: adultMode,
        );
      }

      return result;
    } catch (e, st) {
      log(
        'Outage/Failure on ${primary.type.displayName} getCategoryItems($category), falling back to ${fallback.type.displayName}: $e',
        name: 'ResilientRemoteTracker',
        error: e,
        stackTrace: st,
      );
      return await fallback.getCategoryItems(
        category,
        page: page,
        type: type,
        cacheDuration: cacheDuration,
        adultMode: adultMode,
      );
    }
  }

  @override
  Future<PaginatedResult<UnifiedMedia>> getTrending({
    int page = 1,
    MediaType type = MediaType.ANIME,
    Duration? cacheDuration,
    AdultContentMode adultMode = AdultContentMode.safe,
  }) => getCategoryItems(
    TrackerCategory.trending,
    page: page,
    type: type,
    cacheDuration: cacheDuration,
    adultMode: adultMode,
  );

  @override
  Future<List<TrackerSearchResult>> searchMedia(
    String query, {
    required MediaType type,
  }) async {
    try {
      final results = await primary.searchMedia(query, type: type);
      if (results.isNotEmpty) return results;
      return await fallback.searchMedia(query, type: type);
    } catch (e) {
      log(
        'searchMedia failed on ${primary.type.displayName}, using fallback: $e',
        name: 'ResilientRemoteTracker',
      );
      return await fallback.searchMedia(query, type: type);
    }
  }

  @override
  Future<PaginatedResult<UnifiedMedia>> search(
    String query, {
    int page = 1,
    required MediaType type,
    List<String>? genres,
    List<String>? tags,
    SearchSort sort = SearchSort.popularity,
    SearchStatusFilter status = SearchStatusFilter.all,
    SearchFormatFilter format = SearchFormatFilter.all,
    Duration? cacheDuration,
    AdultContentMode adultMode = AdultContentMode.safe,
  }) async {
    try {
      final result = await primary.search(
        query,
        page: page,
        type: type,
        genres: genres,
        tags: tags,
        sort: sort,
        status: status,
        format: format,
        cacheDuration: cacheDuration,
        adultMode: adultMode,
      );

      if (result.items.isNotEmpty) return result;
      return await fallback.search(
        query,
        page: page,
        type: type,
        genres: genres,
        tags: tags,
        sort: sort,
        status: status,
        format: format,
        cacheDuration: cacheDuration,
        adultMode: adultMode,
      );
    } catch (e, st) {
      log(
        'search failed on ${primary.type.displayName}, falling back to ${fallback.type.displayName}: $e',
        name: 'ResilientRemoteTracker',
        error: e,
        stackTrace: st,
      );
      return await fallback.search(
        query,
        page: page,
        type: type,
        genres: genres,
        tags: tags,
        sort: sort,
        status: status,
        format: format,
        cacheDuration: cacheDuration,
        adultMode: adultMode,
      );
    }
  }

  @override
  Future<UnifiedMedia> getDetails(String providerId, MediaType type) async {
    try {
      return await primary.getDetails(providerId, type);
    } catch (e) {
      log(
        'getDetails failed on ${primary.type.displayName}, trying fallback: $e',
        name: 'ResilientRemoteTracker',
      );
      return await fallback.getDetails(providerId, type);
    }
  }

  @override
  Future<PaginatedResult<MediaCharacter>> getCharacters(
    String providerId, {
    int page = 1,
    int perPage = 25,
    MediaType type = MediaType.ANIME,
  }) async {
    try {
      final result = await primary.getCharacters(
        providerId,
        page: page,
        perPage: perPage,
        type: type,
      );
      if (result.items.isNotEmpty) return result;
      return await fallback.getCharacters(
        providerId,
        page: page,
        perPage: perPage,
        type: type,
      );
    } catch (_) {
      return await fallback.getCharacters(
        providerId,
        page: page,
        perPage: perPage,
        type: type,
      );
    }
  }

  @override
  Future<MediaCharacter?> getCharacterDetails(String characterId) async {
    try {
      final char = await primary.getCharacterDetails(characterId);
      if (char != null) return char;
      return await fallback.getCharacterDetails(characterId);
    } catch (_) {
      return await fallback.getCharacterDetails(characterId);
    }
  }

  @override
  Future<void> updateListItem({
    required String trackingId,
    required UnifiedMedia media,
    TrackedStatus? status,
    double? progress,
    double? score,
  }) => primary.updateListItem(
    trackingId: trackingId,
    media: media,
    status: status,
    progress: progress,
    score: score,
  );

  @override
  Future<List<LibraryEntry>> fetchUserLibrary({
    TrackedStatus status = TrackedStatus.watching,
    MediaType mediaType = MediaType.ANIME,
    int page = 1,
  }) => primary.fetchUserLibrary(
    status: status,
    mediaType: mediaType,
    page: page,
  );

  @override
  Future<TrackedListItem?> fetchUserListItem({
    required String mediaId,
    required MediaType mediaType,
  }) => primary.fetchUserListItem(
    mediaId: mediaId,
    mediaType: mediaType,
  );

  @override
  Future<void> removeEntry({
    required String trackingId,
    required MediaType mediaType,
  }) => primary.removeEntry(
    trackingId: trackingId,
    mediaType: mediaType,
  );
}
