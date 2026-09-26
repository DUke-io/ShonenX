import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/debrid/domain/models/debrid_config.dart';
import 'package:shonenx/features/debrid/domain/models/torrent_release.dart';
import 'package:shonenx/features/debrid/services/animetosho_scraper.dart';
import 'package:shonenx/features/debrid/services/nyaa_scraper.dart';
import 'package:shonenx/features/debrid/services/real_debrid_service.dart';
import 'package:shonenx/features/debrid/services/torbox_service.dart';
import 'package:shonenx/features/debrid/services/alldebrid_service.dart';
import 'package:shonenx/shared/models/unified_episode.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/models/video_stream.dart';

final debridConfigProvider =
    NotifierProvider<DebridConfigNotifier, DebridConfig>(
      DebridConfigNotifier.new,
    );

class DebridConfigNotifier extends Notifier<DebridConfig> {
  static const _prefKey = 'kurox_debrid_config';
  final _log = AppLogger.scope('DebridConfigNotifier');

  @override
  DebridConfig build() {
    _loadFromPrefs();
    return const DebridConfig();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null && json.isNotEmpty) {
        state = DebridConfig.fromJson(json);
      }
    } catch (e) {
      _log.e('Failed to load debrid config from prefs', e);
    }
  }

  Future<void> saveConfig(DebridConfig config) async {
    state = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, config.toJson());
    } catch (e) {
      _log.e('Failed to save debrid config', e);
    }
  }

  Future<void> toggleEnabled(bool enabled) async {
    await saveConfig(state.copyWith(isEnabled: enabled));
  }

  Future<void> setProvider(DebridProvider provider) async {
    await saveConfig(state.copyWith(provider: provider));
  }

  Future<void> setApiKey(String key) async {
    await saveConfig(state.copyWith(apiKey: key.trim()));
  }

  Future<void> setResolution(PreferredResolution res) async {
    await saveConfig(state.copyWith(preferredResolution: res));
  }
}

final debridAccountInfoProvider =
    FutureProvider.autoDispose<DebridAccountInfo?>((ref) async {
      final config = ref.watch(debridConfigProvider);
      if (!config.isEnabled || config.apiKey.isEmpty) return null;

      try {
        switch (config.provider) {
          case DebridProvider.realDebrid:
            return await RealDebridService.verifyAccount(config.apiKey);
          case DebridProvider.torbox:
            return await TorboxService.verifyAccount(config.apiKey);
          case DebridProvider.allDebrid:
            return await AllDebridService.verifyAccount(config.apiKey);
        }
      } catch (_) {
        return null;
      }
    });

class DebridStreamResolver {
  final Ref ref;
  static final _log = AppLogger.scope('DebridStreamResolver');

  DebridStreamResolver(this.ref);

  /// Searches AnimeTosho and Nyaa for torrent releases matching the anime & episode.
  Future<List<TorrentRelease>> searchReleases({
    required UnifiedMedia media,
    required UnifiedEpisode episode,
  }) async {
    final config = ref.read(debridConfigProvider);
    if (!config.isEnabled || config.apiKey.isEmpty) return [];

    final cleanTitle = media.title.english ?? media.title.romaji ?? media.title.availableTitle;
    final epNum = episode.number.toInt();

    // 1. Scrape AnimeTosho
    List<TorrentRelease> releases = await AnimeToshoScraper.search(
      query: cleanTitle,
      anilistId: media.idMal ?? media.id,
      episodeNumber: epNum,
    );

    // 2. Fallback to Nyaa if AnimeTosho returns nothing
    if (releases.isEmpty) {
      releases = await NyaaScraper.search(
        query: cleanTitle,
        episodeNumber: epNum,
      );
    }

    if (releases.isEmpty) return [];

    // 3. If Real-Debrid, check instant availability
    if (config.provider == DebridProvider.realDebrid && config.autoSelectCached) {
      try {
        final hashes = releases.map((r) => r.infoHash).where((h) => h.isNotEmpty).toList();
        final availability = await RealDebridService.checkInstantAvailability(
          config.apiKey,
          hashes,
        );

        releases = releases.map((r) {
          final isCached = availability[r.infoHash.toLowerCase()] ?? false;
          return r.copyWith(isCachedOnDebrid: isCached);
        }).toList();

        // Sort cached releases to top
        releases.sort((a, b) {
          if (a.isCachedOnDebrid && !b.isCachedOnDebrid) return -1;
          if (!a.isCachedOnDebrid && b.isCachedOnDebrid) return 1;
          return b.seeders.compareTo(a.seeders);
        });
      } catch (e) {
        _log.w('Could not check instant availability: $e');
      }
    }

    return releases;
  }

  /// Resolves an unrestricted high-speed CDN direct stream from a chosen release.
  Future<VideoStream?> resolveStream(
    TorrentRelease release, {
    int? episodeNumber,
  }) async {
    final config = ref.read(debridConfigProvider);
    if (!config.isEnabled || config.apiKey.isEmpty) return null;

    String? directUrl;
    switch (config.provider) {
      case DebridProvider.realDebrid:
        directUrl = await RealDebridService.resolveMagnetStream(
          config.apiKey,
          release.magnet,
          episodeNumber: episodeNumber,
        );
        break;
      case DebridProvider.torbox:
        directUrl = await TorboxService.resolveMagnetStream(
          config.apiKey,
          release.magnet,
          episodeNumber: episodeNumber,
        );
        break;
      case DebridProvider.allDebrid:
        directUrl = await AllDebridService.resolveMagnetStream(
          config.apiKey,
          release.magnet,
          episodeNumber: episodeNumber,
        );
        break;
    }

    if (directUrl == null || directUrl.isEmpty) return null;

    final providerName = config.provider.displayName;
    final qualityLabel = '⚡ $providerName Raw ${release.resolution}';

    return VideoStream(
      url: directUrl,
      quality: qualityLabel,
      size: release.formattedSize,
      headers: {
        'User-Agent': 'KuroX-MediaEngine/2.1',
      },
    );
  }
}

final debridStreamResolverProvider = Provider<DebridStreamResolver>((ref) {
  return DebridStreamResolver(ref);
});
