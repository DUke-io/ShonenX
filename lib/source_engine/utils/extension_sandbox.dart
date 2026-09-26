import 'dart:async';
import 'package:shonenx/core/utils/app_logger.dart';

class ExtensionSandboxException implements Exception {
  final String message;
  final String? sourceId;
  const ExtensionSandboxException(this.message, {this.sourceId});

  @override
  String toString() => 'ExtensionSandboxException: $message (Source: ${sourceId ?? "unknown"})';
}

/// Guards external Javascript runtime execution against infinite loops,
/// memory exhaustion, and slow third-party extension scripts.
class ExtensionSandbox {
  static final _log = AppLogger.scope('ExtensionSandbox');

  static const Duration defaultTimeout = Duration(seconds: 15);

  // Circuit breaker state: sourceId -> failure count
  static final Map<String, int> _failureCounts = {};
  static final Map<String, DateTime> _circuitOpenUntil = {};

  /// Runs an extension action safely with strict timeout and circuit breaker protection.
  static Future<T> run<T>({
    required String sourceId,
    required String actionName,
    required Future<T> Function() action,
    Duration timeout = defaultTimeout,
  }) async {
    // 1. Check circuit breaker
    final openUntil = _circuitOpenUntil[sourceId];
    if (openUntil != null && DateTime.now().isBefore(openUntil)) {
      _log.w('Circuit open for source $sourceId ($actionName rejected to save UI isolate)');
      throw ExtensionSandboxException(
        'Extension $sourceId is temporarily paused due to repeated crashes. Will retry in ${openUntil.difference(DateTime.now()).inSeconds}s.',
        sourceId: sourceId,
      );
    }

    try {
      // 2. Execute with strict timeout
      final result = await action().timeout(
        timeout,
        onTimeout: () {
          _recordFailure(sourceId);
          _log.e('Extension timeout on $sourceId ($actionName after ${timeout.inSeconds}s)');
          throw ExtensionSandboxException(
            'Extension $sourceId timed out during $actionName (${timeout.inSeconds}s limit reached)',
            sourceId: sourceId,
          );
        },
      );

      // Reset failure count on success
      _failureCounts[sourceId] = 0;
      return result;
    } catch (e, st) {
      if (e is! ExtensionSandboxException) {
        _recordFailure(sourceId);
        _log.e('Extension error on $sourceId ($actionName)', e, st);
      }
      rethrow;
    }
  }

  static void _recordFailure(String sourceId) {
    final count = (_failureCounts[sourceId] ?? 0) + 1;
    _failureCounts[sourceId] = count;

    if (count >= 5) {
      // Trip circuit breaker for 60 seconds
      _circuitOpenUntil[sourceId] = DateTime.now().add(const Duration(seconds: 60));
      _log.w('Tripped circuit breaker for source $sourceId after 5 consecutive failures');
    }
  }

  static void resetCircuit(String sourceId) {
    _failureCounts.remove(sourceId);
    _circuitOpenUntil.remove(sourceId);
  }
}
