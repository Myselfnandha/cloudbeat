import 'package:flutter/foundation.dart';

/// Centralized, high-efficiency application logging utility for CloudBeat.
class AppLogger {
  static bool enabled = true;

  /// Trace method execution entry with module, method name and optional arguments.
  static void trace(String identifier, [dynamic details, dynamic extra]) {
    if (!enabled) return;
    final tag = identifier.startsWith('[') ? identifier : '[$identifier]';
    if (extra != null) {
      debugPrint('$tag $details $extra');
    } else if (details != null) {
      debugPrint('$tag $details');
    } else {
      debugPrint(tag);
    }
  }

  /// Informational debug message.
  static void d(String tag, String message) {
    if (!enabled) return;
    debugPrint('[CloudBeat:$tag] $message');
  }

  /// Error log with optional exception and stack trace.
  static void e(String tag, String message, [Object? error, StackTrace? stack]) {
    debugPrint('[CloudBeat:$tag:ERROR] $message ${error != null ? '($error)' : ''}');
    if (stack != null) {
      debugPrint('[CloudBeat:$tag:STACK] $stack');
    }
  }
}
