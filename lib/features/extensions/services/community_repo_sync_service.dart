import 'dart:convert';
import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    as bridge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/features/extensions/providers/extension_service_provider.dart';
import 'package:shonenx/features/extensions/providers/extensions_provider.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';
import 'package:shonenx/source_engine/source_registry.dart';

class CommunityRepoSyncService {
  static const String _primaryUrl =
      'https://raw.githubusercontent.com/Zcross091/KuroX/main/kurox_repository.json';
  static const String _fallbackUrl =
      'https://raw.githubusercontent.com/Zcross091/KuroX/community-sources/kurox_repository.json';
  static const String _cacheKey = 'kurox_community_repo_manifest_v1';
  static const String _lastSyncKey = 'kurox_community_repo_last_sync';

  static final _log = AppLogger.scope('CommunityRepoSyncService');

  /// Runs automatically on app launch / bridge initialization.
  static Future<int> syncOnStartup(dynamic ref) async {
    final log = _log.child('syncOnStartup');
    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final lastSyncMs = prefs.getInt(_lastSyncKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Only perform automatic remote background check at most once every 6 hours
      final shouldFetchRemote = (now - lastSyncMs) > 6 * 3600 * 1000;

      if (!Get.isRegistered<bridge.ExtensionManager>()) {
        log.d('ExtensionManager not yet registered; skipping startup sync.');
        return 0;
      }

      final ExtensionAdapter adapter = ref.read(extensionAdapterProvider);
      final existingRepos = adapter.getAllRepos();

      // If user has 0 repositories, always fetch immediately
      if (existingRepos.isEmpty || shouldFetchRemote) {
        log.i('Triggering community repository sync...');
        return await syncNow(ref);
      } else {
        log.d('Community repositories up to date. Existing count: ${existingRepos.length}');
        return 0;
      }
    } catch (e, st) {
      log.w('Background community sync error: $e', e, st);
      return 0;
    }
  }

  /// Forces an immediate sync from remote GitHub manifest or local cache.
  static Future<int> syncNow(dynamic ref) async {
    final log = _log.child('syncNow');

    if (!Get.isRegistered<bridge.ExtensionManager>()) {
      log.w('ExtensionManager is not registered; cannot sync repos.');
      return 0;
    }

    try {
      final SharedPreferences prefs = ref.read(sharedPreferencesProvider);
      final ExtensionAdapter adapter = ref.read(extensionAdapterProvider);

    Map<String, dynamic>? manifest;

    // 1. Attempt fetching from primary URL
    try {
      log.d('Fetching remote manifest from: $_primaryUrl');
      final res = await http.get(
        Uri.parse(_primaryUrl),
        headers: {'User-Agent': 'KuroX-App'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        manifest = jsonDecode(res.body) as Map<String, dynamic>?;
        await prefs.setString(_cacheKey, res.body);
        await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
        log.s('Successfully fetched and cached remote manifest');
      }
    } catch (e) {
      log.w('Failed to fetch primary manifest: $e');
    }

    // 2. Fallback to community-sources branch if primary failed
    if (manifest == null) {
      try {
        log.d('Trying fallback manifest: $_fallbackUrl');
        final res = await http.get(
          Uri.parse(_fallbackUrl),
          headers: {'User-Agent': 'KuroX-App'},
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode == 200) {
          manifest = jsonDecode(res.body) as Map<String, dynamic>?;
          await prefs.setString(_cacheKey, res.body);
          log.s('Successfully fetched fallback manifest');
        }
      } catch (e) {
        log.w('Fallback manifest fetch failed: $e');
      }
    }

    // 3. Fallback to local cache
    if (manifest == null) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          manifest = jsonDecode(cached) as Map<String, dynamic>?;
          log.i('Using cached community repository manifest');
        } catch (_) {}
      }
    }

    if (manifest == null) {
      log.e('No manifest available to sync.');
      return 0;
    }

    final bundledList = manifest['bundledRepositories'] as List<dynamic>? ?? [];
    if (bundledList.isEmpty) return 0;

    final existingUrls = adapter
        .getAllRepos()
        .map((r) => r.url.toLowerCase().trim())
        .toSet();

    int addedCount = 0;

    for (final item in bundledList) {
      if (item is! Map) continue;
      final url = item['url']?.toString().trim();
      final engine = item['engine']?.toString().toLowerCase().trim() ?? 'aniyomi';
      final types = (item['types'] as List<dynamic>?)
              ?.map((t) => t.toString().toLowerCase())
              .toList() ??
          ['anime'];

      if (url == null || url.isEmpty) continue;

      // Check if already registered
      final isAlreadyAdded = existingUrls.contains(url.toLowerCase());
      if (isAlreadyAdded) continue;

      bool addedAny = false;
      try {
        if (types.contains('anime')) {
          final ok = await adapter.addRepo(url, engine, bridge.ItemType.anime);
          if (ok) addedAny = true;
        }
        if (types.contains('manga') ||
            types.contains('manhwa') ||
            types.contains('manhua') ||
            types.contains('webtoons')) {
          final ok = await adapter.addRepo(url, engine, bridge.ItemType.manga);
          if (ok) addedAny = true;
        }
        if (types.contains('novel')) {
          final ok = await adapter.addRepo(url, engine, bridge.ItemType.novel);
          if (ok) addedAny = true;
        }

        if (addedAny) {
          existingUrls.add(url.toLowerCase());
          addedCount++;
          log.s('Added community repo: ${item['name']} ($engine)');
        }
      } catch (e) {
        log.w('Failed adding repo $url: $e');
      }
    }

    // Invalidate providers to refresh UI
    ref.invalidate(activeExtReposProvider);
    ref.invalidate(availableAnimeSourcesProvider);
    ref.invalidate(availableMangaSourcesProvider);
    ref.invalidate(availableNovelSourcesProvider);

    log.i('Community repo sync completed. Added $addedCount new repos.');
    return addedCount;
    } catch (e, st) {
      log.e('Community repo sync failed: $e', e, st);
      return 0;
    }
  }
}
