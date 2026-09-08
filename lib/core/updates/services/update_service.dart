import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shonenx/core/updates/models/github_release.dart';
import 'package:shonenx/core/utils/app_logger.dart';
import 'package:shonenx/core/utils/env.dart';
import 'package:shonenx/shared/providers/storage_provider.dart';

class UpdatePreferences {
  final bool includePrerelease;
  final bool autoCheckOnStartup;
  final int? lastSeenReleaseId;
  final int? lastDismissedReleaseId;

  const UpdatePreferences({
    this.includePrerelease = false,
    this.autoCheckOnStartup = true,
    this.lastSeenReleaseId,
    this.lastDismissedReleaseId,
  });

  UpdatePreferences copyWith({
    bool? includePrerelease,
    bool? autoCheckOnStartup,
    int? lastSeenReleaseId,
    int? lastDismissedReleaseId,
    bool clearDismissed = false,
  }) {
    return UpdatePreferences(
      includePrerelease: includePrerelease ?? this.includePrerelease,
      autoCheckOnStartup: autoCheckOnStartup ?? this.autoCheckOnStartup,
      lastSeenReleaseId: lastSeenReleaseId ?? this.lastSeenReleaseId,
      lastDismissedReleaseId: clearDismissed
          ? null
          : (lastDismissedReleaseId ?? this.lastDismissedReleaseId),
    );
  }
}

class UpdatePrefsNotifier extends Notifier<UpdatePreferences> {
  static const _keyIncludePrerelease = 'update_include_prerelease';
  static const _keyAutoCheck = 'update_auto_check_startup';
  static const _keyLastSeenId = 'update_last_seen_release_id';
  static const _keyLastDismissedId = 'update_last_dismissed_release_id';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  UpdatePreferences build() {
    return UpdatePreferences(
      includePrerelease: _prefs.getBool(_keyIncludePrerelease) ?? false,
      autoCheckOnStartup: _prefs.getBool(_keyAutoCheck) ?? true,
      lastSeenReleaseId: _prefs.getInt(_keyLastSeenId),
      lastDismissedReleaseId: _prefs.getInt(_keyLastDismissedId),
    );
  }

  Future<void> setIncludePrerelease(bool value) async {
    await _prefs.setBool(_keyIncludePrerelease, value);
    state = state.copyWith(includePrerelease: value, clearDismissed: true);
  }

  Future<void> setAutoCheckOnStartup(bool value) async {
    await _prefs.setBool(_keyAutoCheck, value);
    state = state.copyWith(autoCheckOnStartup: value);
  }

  Future<void> setLastSeenReleaseId(int id) async {
    await _prefs.setInt(_keyLastSeenId, id);
    state = state.copyWith(lastSeenReleaseId: id);
  }

  Future<void> setLastDismissedReleaseId(int id) async {
    await _prefs.setInt(_keyLastDismissedId, id);
    state = state.copyWith(lastDismissedReleaseId: id);
  }
}

final updatePrefsProvider = NotifierProvider<UpdatePrefsNotifier, UpdatePreferences>(
  UpdatePrefsNotifier.new,
);

class UpdateService {
  final Ref _ref;
  final _log = AppLogger.scope('UpdateService');

  UpdateService(this._ref);

  Future<GitHubRelease?> checkForUpdate({bool force = false}) async {
    final repo = Env.RELEASE_REPO.trim();
    if (repo.isEmpty) {
      _log.w('Env.RELEASE_REPO is not configured.');
      return null;
    }

    final prefs = _ref.read(updatePrefsProvider);
    final apiUrl = 'https://api.github.com/repos/$repo/releases';

    _log.i('Checking for updates from $apiUrl (includePrerelease: ${prefs.includePrerelease})...');

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'KuroX-App',
        },
      );

      if (response.statusCode != 200) {
        _log.w('Failed to fetch releases. Status code: ${response.statusCode}');
        return null;
      }

      final List<dynamic> data = jsonDecode(response.body);
      final releases = data
          .map((item) => GitHubRelease.fromJson(item as Map<String, dynamic>))
          .where((r) => !r.draft)
          .where((r) => prefs.includePrerelease || !r.prerelease)
          .toList();

      if (releases.isEmpty) {
        _log.i('No suitable releases found on GitHub.');
        return null;
      }

      // Sort releases by published date descending (newest first)
      releases.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      final latestRelease = releases.first;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      _log.i('Current version: $currentVersion, Latest release tag: ${latestRelease.tagName} (id: ${latestRelease.id})');

      // Compare versions
      final cmp = _compareVersions(latestRelease.tagName, currentVersion);
      if (cmp > 0) {
        // Tag version is strictly newer than current installed version
        if (!force && latestRelease.id == prefs.lastDismissedReleaseId) {
          _log.i('Release ${latestRelease.tagName} was previously dismissed.');
          return null;
        }
        return latestRelease;
      } else {
        // Current installed version is equal to or newer than the latest release.
        // If the user is on a test version (e.g. pre-release or newer build), do NOT ping.
        _log.i('Current version ($currentVersion) is up to date or newer than latest release (${latestRelease.tagName}).');
        if (prefs.lastSeenReleaseId != latestRelease.id) {
          await _ref.read(updatePrefsProvider.notifier).setLastSeenReleaseId(latestRelease.id);
        }
      }
    } catch (e, st) {
      _log.e('Error while checking for updates', e, st);
    }

    return null;
  }

  int _compareVersions(String tag, String currentVersion) {
    final cleanTag = tag.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final cleanCurrent = currentVersion.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');

    // Extract build numbers (+number) if present
    final tagBuildIndex = cleanTag.indexOf('+');
    final currentBuildIndex = cleanCurrent.indexOf('+');

    final tagNoBuild = tagBuildIndex != -1 ? cleanTag.substring(0, tagBuildIndex) : cleanTag;
    final currentNoBuild = currentBuildIndex != -1 ? cleanCurrent.substring(0, currentBuildIndex) : cleanCurrent;

    final tagBuildStr = tagBuildIndex != -1 ? cleanTag.substring(tagBuildIndex + 1) : '';
    final currentBuildStr = currentBuildIndex != -1 ? cleanCurrent.substring(currentBuildIndex + 1) : '';

    final tagParts = tagNoBuild.split('-');
    final currentParts = currentNoBuild.split('-');

    final tagNums = tagParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final currentNums = currentParts[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final a = i < tagNums.length ? tagNums[i] : 0;
      final b = i < currentNums.length ? currentNums[i] : 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }

    // Main major.minor.patch versions are equal. Check pre-release identifiers.
    final tagPre = tagParts.length > 1 ? tagParts.sublist(1).join('-') : '';
    final currentPre = currentParts.length > 1 ? currentParts.sublist(1).join('-') : '';

    // If one is pre-release and one is final:
    // If the remote release is NOT pre-release and local IS pre-release of the same version:
    // e.g. local is 2.1.5-alpha.1 and remote is 2.1.5 -> remote is final release, so remote is newer (1)
    if (tagPre.isEmpty && currentPre.isNotEmpty) return 1;
    // If remote is pre-release but local is final:
    // e.g. local is 2.1.5 and remote is 2.1.5-alpha.1 -> local is newer (-1)
    if (tagPre.isNotEmpty && currentPre.isEmpty) return -1;

    if (tagPre.isNotEmpty && currentPre.isNotEmpty) {
      final tagSegments = tagPre.split('.');
      final currentSegments = currentPre.split('.');
      final len = tagSegments.length > currentSegments.length ? tagSegments.length : currentSegments.length;
      for (var i = 0; i < len; i++) {
        final segA = i < tagSegments.length ? tagSegments[i] : '';
        final segB = i < currentSegments.length ? currentSegments[i] : '';
        final numA = int.tryParse(segA);
        final numB = int.tryParse(segB);
        if (numA != null && numB != null) {
          if (numA > numB) return 1;
          if (numA < numB) return -1;
        } else {
          final cmp = segA.compareTo(segB);
          if (cmp != 0) return cmp;
        }
      }
    }

    // Check build number (+number) if versions and pre-releases are identical
    final tagBuild = int.tryParse(tagBuildStr) ?? 0;
    final currentBuild = int.tryParse(currentBuildStr) ?? 0;
    if (tagBuild > currentBuild) return 1;
    if (tagBuild < currentBuild) return -1;

    return 0;
  }

  Future<List<GitHubRelease>> fetchAllReleases() async {
    final repo = Env.RELEASE_REPO.trim();
    if (repo.isEmpty) return [];
    final apiUrl = 'https://api.github.com/repos/$repo/releases';
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'ShonenX-App',
        },
      );
      if (response.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(response.body);
      final releases = data
          .map((item) => GitHubRelease.fromJson(item as Map<String, dynamic>))
          .where((r) => !r.draft)
          .toList();
      releases.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return releases;
    } catch (e, st) {
      _log.e('Error fetching all releases', e, st);
      return [];
    }
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService(ref);
});

final releasesListProvider = FutureProvider<List<GitHubRelease>>((ref) async {
  final service = ref.watch(updateServiceProvider);
  return service.fetchAllReleases();
});

