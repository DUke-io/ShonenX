import 'package:shonenx/core/utils/app_logger.dart';

/// Defines security policies and permission sandboxing scopes for third-party extensions
/// loaded via the extension runtime bridge.
class ExtensionSecurityPolicy {
  static final _log = AppLogger.scope('ExtensionSecurityPolicy');

  /// Whitelisted domains that extensions are permitted to query.
  static const Set<String> allowedDomains = {
    'myanimelist.net',
    'anilist.co',
    'kitsu.io',
    'mangadex.org',
    'gogoanime.tel',
    'animepahe.ru',
    'hianime.to',
  };

  /// Validates whether an extension's network request URL complies with security policies.
  static bool validateRequestUrl(String urlString) {
    try {
      final uri = Uri.parse(urlString);
      final host = uri.host.toLowerCase();

      // Allow if host matches whitelist or is a recognized subdomain
      final isAllowed = allowedDomains.any((domain) => host == domain || host.endsWith('.$domain'));
      if (!isAllowed) {
        _log.w('Security Policy: Blocked unauthorized network request to domain: $host');
      }
      return isAllowed;
    } catch (e) {
      _log.w('Security Policy: Failed to parse URL: $urlString');
      return false;
    }
  }

  /// Enforces resource limits and execution sandboxing guardrails.
  static Duration get executionTimeout => const Duration(seconds: 15);
}
